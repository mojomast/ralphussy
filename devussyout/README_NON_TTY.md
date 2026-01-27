# Non-TTY Interview Support

## Quick Start

The interview CLI now works in both terminals and non-TTY environments (like OpenTUI):

```bash
# Traditional terminal (unchanged)
python interview_cli.py

# OpenTUI / non-TTY mode (automatic)
echo "I want to build a REST API" | python interview_cli.py
```

**It just works!** The CLI automatically detects the environment and adapts.

---

## What Changed

### Before (Broken in OpenTUI)

```python
# Blocking infinite loop - won't work in OpenTUI
while not manager.is_complete:
    user_input = input("> ")  # BLOCKS FOREVER
    response = await manager.chat(user_input)
    print(response)
```

### After (Works Everywhere)

```python
# Detects environment and routes accordingly
is_tty = sys.stdin.isatty()

if is_tty:
    run_tty_mode()      # Original blocking loop
else:
    run_non_tty_mode()  # Message-driven state machine
```

---

## How It Works

### In OpenTUI

1. User types message
2. OpenTUI invokes: `python interview_cli.py`
3. CLI detects non-TTY mode
4. Loads session state from disk
5. Processes message
6. Saves updated state
7. Prints response
8. Exits (returns to OpenTUI)
9. Repeat

**No loops, no blocking, state persists across invocations.**

### In Terminal

Everything works exactly as before. No changes to user experience.

---

## Documentation

- **[REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)** - Technical deep dive
- **[NON_TTY_MODE.md](NON_TTY_MODE.md)** - User guide and examples
- **[test_non_tty.sh](test_non_tty.sh)** - Test script
- **[opentui_example.py](opentui_example.py)** - OpenTUI simulation

---

## Testing

### Quick Test

```bash
# Test non-TTY mode
./test_non_tty.sh

# Simulate OpenTUI
./opentui_example.py
```

### Manual Test

```bash
# First message
echo "Build a todo app" | python interview_cli.py

# Second message
echo "Python and FastAPI" | python interview_cli.py

# Check status
echo "/status" | python interview_cli.py

# Clean up
rm -rf ~/.ralph/sessions/
```

---

## Key Features

✅ **Dual-mode operation**: TTY and non-TTY
✅ **Automatic detection**: No configuration needed
✅ **Session persistence**: State saved to disk
✅ **Zero breaking changes**: Terminal users unaffected
✅ **Same output**: Identical devplan artifacts
✅ **Clean architecture**: Separate execution paths

---

## Architecture

```
Input → Detect TTY
         ├─ Yes → run_tty_mode() → Blocking loop
         └─ No  → run_non_tty_mode() → SessionManager
                                        ├─ Load state
                                        ├─ Process message
                                        ├─ Save state
                                        └─ Exit
```

---

## Files Changed

| File | Change |
|------|--------|
| `interview_cli.py` | Modified - added dual-mode routing |
| `src/interview/session_manager.py` | Created - state persistence |
| All other interview files | Unchanged |

---

## Summary

**Problem**: Interview used blocking `input()` loop → Failed in OpenTUI
**Solution**: Detect environment, use state machine for non-TTY
**Result**: Works in both terminals and OpenTUI with zero breaking changes

See [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md) for full technical details.
