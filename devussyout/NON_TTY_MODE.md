# Non-TTY Interview Mode

## Problem Overview

The original interview system used blocking `input()` calls in an infinite loop:

```python
while not manager.is_complete:
    user_input = input("> ")  # BLOCKS HERE
    response = await manager.chat(user_input)
    print(response)
```

**Why this fails in OpenTUI:**

1. **OpenTUI is not a real TTY**
   - `sys.stdin.isatty()` returns `False`
   - There's no terminal to block on

2. **Ownership mismatch**
   - The CLI owns the interaction loop and blocks forever
   - OpenTUI needs to own the loop - it calls the program once per message
   - The program must return after each response

3. **No state persistence**
   - Each OpenTUI message is a new invocation
   - Without persistence, the interview restarts every time

## Solution Architecture

### Dual-Mode System

The refactored system detects the environment and routes accordingly:

```python
is_tty = sys.stdin.isatty()

if is_tty:
    # TTY mode - original blocking loop (no change)
    await run_tty_mode(config, args)
else:
    # Non-TTY mode - message-driven state machine
    await run_non_tty_mode(config, args)
```

### Non-TTY Mode Components

1. **SessionManager** (`src/interview/session_manager.py`)
   - Persists interview state to disk (`~/.ralph/sessions/`)
   - Tracks active session
   - Loads/saves state between invocations
   - No loops, no blocking

2. **State Persistence**
   ```python
   SessionState:
       - session_id
       - project_name
       - current_stage
       - is_complete
       - last_response
       - message_count
       - config_dict
   ```

3. **Message Flow**
   ```
   User sends message → OpenTUI
                      ↓
   OpenTUI invokes: python interview_cli.py
                      ↓
   CLI detects non-TTY mode
                      ↓
   SessionManager loads state
                      ↓
   Process one message
                      ↓
   Save state to disk
                      ↓
   Print response
                      ↓
   Program EXITS (returns control to OpenTUI)
   ```

## Usage

### TTY Mode (Traditional Terminal)

```bash
# Works exactly as before
python interview_cli.py

# Assistant: What would you like to build?
> I want to create a REST API
# (continues in blocking loop)
```

### Non-TTY Mode (OpenTUI / Pipes)

```bash
# First call - creates session
echo "I want to create a REST API" | python interview_cli.py

# Output:
# Great! Let's start by gathering some details...
# (program exits)

# Second call - resumes session
echo "Python with FastAPI" | python interview_cli.py

# Output:
# [Resumed session session_1234567890]
# Excellent choice! What will your API do?
# (program exits)

# Continue...
echo "User authentication and profiles" | python interview_cli.py
```

### Commands

Available in non-TTY mode:
- `/status` - Show session status
- `/help` - Show available commands
- `/done` - Complete current stage
- `/back` - Go back to previous stage
- `/quit` - End session

### Force Mode Override

```bash
# Force TTY mode (for debugging)
python interview_cli.py --force-tty

# Force non-TTY mode (for testing)
python interview_cli.py --force-non-tty
```

## OpenTUI Integration

OpenTUI automatically works with this system:

1. User types message in OpenTUI chat
2. OpenTUI invokes: `python interview_cli.py` with message via stdin
3. Program detects non-TTY mode (stdin is not a TTY)
4. SessionManager loads active session or creates new one
5. Message is processed
6. State is saved
7. Response is printed to stdout
8. Program exits
9. OpenTUI displays the response
10. Repeat for next message

**No special configuration needed** - it just works!

## Session Management

### Session Files

Located in `~/.ralph/sessions/`:
- `session_{timestamp}.json` - Serialized session state
- `active_session.txt` - Points to currently active session

### Session Lifecycle

```
No session → Create new → Process messages → Complete → Clear active marker
                ↓
        Auto-resume on next invocation
```

### Manual Session Management

```bash
# View session directory
ls ~/.ralph/sessions/

# Clear stuck session
rm ~/.ralph/sessions/active_session.txt

# View session state
cat ~/.ralph/sessions/session_*.json
```

## Key Differences from TTY Mode

| Aspect | TTY Mode | Non-TTY Mode |
|--------|----------|--------------|
| Input | Blocking `input()` | Read once from stdin |
| Loop | Infinite while loop | No loop - one message |
| Streaming | Supported | Disabled |
| State | In-memory only | Persisted to disk |
| Lifecycle | Runs until complete | One invocation per message |
| Session | Single continuous session | Restored each time |

## Implementation Details

### Environment Detection

```python
is_tty = sys.stdin.isatty()
```

This returns:
- `True` - Real terminal (Terminal.app, iTerm, gnome-terminal)
- `False` - Pipe, file redirect, OpenTUI, background process

### No TTY Emulation

We do **NOT**:
- Attempt to create a pseudo-TTY
- Use curses or termios
- Require raw mode
- Handle keypresses directly

We **DO**:
- Read stdin once (non-blocking)
- Process the message
- Print to stdout
- Exit immediately

### OpenCode Integration

The LLM calls remain **completely unchanged**:

```python
# This still works in both modes
response = await manager.chat(user_input)
```

OpenCode subprocess calls work fine because they don't depend on stdin being a TTY.

## Testing

### Test in Terminal (TTY mode)

```bash
python interview_cli.py
```

Should work exactly as before with blocking loop.

### Test in Non-TTY mode

```bash
# Simulate OpenTUI
echo "I want to build a web app" | python interview_cli.py

# Simulate second message
echo "Python and React" | python interview_cli.py

# Check status
echo "/status" | python interview_cli.py

# End session
echo "/quit" | python interview_cli.py
```

### Test with OpenTUI

Simply use the interview from within OpenTUI - it will automatically detect the environment and use non-TTY mode.

## Troubleshooting

### Session stuck?

```bash
rm ~/.ralph/sessions/active_session.txt
```

### Want to see what mode is being used?

Add debug output:

```python
if is_tty:
    print("[Running in TTY mode]", file=sys.stderr)
else:
    print("[Running in non-TTY mode]", file=sys.stderr)
```

### Force a specific mode for testing

```bash
python interview_cli.py --force-tty
python interview_cli.py --force-non-tty
```

## Summary

**What changed:**
- Added TTY detection: `sys.stdin.isatty()`
- Created SessionManager for state persistence
- Split into two execution paths: TTY and non-TTY
- Non-TTY mode: no loops, one message per invocation, disk-backed state

**What stayed the same:**
- All LLM integration (OpenCode calls)
- Interview logic and stages
- Output format and artifacts
- TTY behavior for terminal users

**Result:**
- Works in real terminals (no change)
- Works in OpenTUI (new capability)
- Same final output (devplan, artifacts)
- Clean, maintainable separation of concerns
