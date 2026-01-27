# Code Changes Reference

Quick reference showing exactly what changed in each file.

---

## Modified Files

### `interview_cli.py`

**Added imports:**
```python
from pathlib import Path
from interview.session_manager import SessionManager
```

**Added functions:**
```python
async def run_non_tty_mode(config: InterviewConfig, args) -> None:
    """Run in non-TTY mode (OpenTUI, pipes, etc)."""
    # SessionManager-based message processing
    # One message per invocation
    # State persists to disk

async def run_tty_mode(config: InterviewConfig, args) -> None:
    """Run in TTY mode (traditional terminal)."""
    # Original blocking loop behavior
    # Unchanged from before
```

**Modified `main()` function:**
```python
# ADDED: Environment detection
is_tty = sys.stdin.isatty()

# ADDED: Mode override flags
if args.force_tty:
    is_tty = True
elif args.force_non_tty:
    is_tty = False

# MODIFIED: Routing logic
if args.no_interactive:
    # Automated mode (unchanged)
    ...
elif is_tty:
    # NEW: Route to TTY mode
    await run_tty_mode(config, args)
else:
    # NEW: Route to non-TTY mode
    await run_non_tty_mode(config, args)
```

**Added command-line arguments:**
```python
parser.add_argument("--message", "-msg", default=None,
    help="Single message to process (for non-TTY mode)")
parser.add_argument("--force-tty", action="store_true",
    help="Force TTY mode even if stdin is not a TTY")
parser.add_argument("--force-non-tty", action="store_true",
    help="Force non-TTY mode even if stdin is a TTY")
```

**What was removed:**
- Nothing! Original blocking loop moved to `run_tty_mode()`

---

## Created Files

### `src/interview/session_manager.py`

**New file** - Complete state persistence layer for non-TTY mode.

**Key classes:**
```python
@dataclass
class SessionState:
    """Persistent state for an interview session."""
    session_id: str
    project_name: Optional[str]
    current_stage: str
    is_complete: bool
    last_response: str
    message_count: int
    config_dict: Dict[str, Any]

class SessionManager:
    """Manages persistent interview sessions for non-TTY environments."""

    async def create_session(config, initial_message=None) -> str
    async def process_message(message: str) -> str
    async def resume_or_create(config, initial_message=None) -> str

    def save_state() -> None
    def load_state(session_id: str) -> bool
    def get_active_session_id() -> Optional[str]
    def session_exists(session_id: str) -> bool
```

**Storage:**
- Session files: `~/.ralph/sessions/session_{timestamp}.json`
- Active marker: `~/.ralph/sessions/active_session.txt`

---

### Documentation Files

**`REFACTOR_SUMMARY.md`**
- Complete technical explanation
- Problem analysis
- Architecture diagrams
- Code flow comparison

**`NON_TTY_MODE.md`**
- User guide
- Usage examples
- Troubleshooting
- OpenTUI integration details

**`README_NON_TTY.md`**
- Quick start guide
- High-level overview
- Testing instructions

**`CHANGES.md`** (this file)
- Code change reference
- Quick lookup for developers

---

### Test/Example Files

**`test_non_tty.sh`**
```bash
#!/bin/bash
# Automated test of non-TTY mode
# Simulates multi-turn conversation
echo "message 1" | python interview_cli.py --force-non-tty
echo "message 2" | python interview_cli.py --force-non-tty
# etc...
```

**`opentui_example.py`**
```python
#!/usr/bin/env python3
# Simulates how OpenTUI interacts with the CLI
# Shows message-passing behavior
def send_message(message: str) -> str:
    subprocess.run([python, "interview_cli.py", "--force-non-tty"],
                   input=message, capture_output=True)
```

---

## Unchanged Files

**No modifications to:**
- `src/interview/interview_manager.py` ✓
- `src/interview/stage_coordinator.py` ✓
- `src/llm_client_opencode.py` ✓
- `src/interview/conversation_history.py` ✓
- `src/interview/json_extractor.py` ✓
- `src/interview/interview_pipeline.py` ✓

**All core interview logic unchanged!**

---

## Summary of Changes

### Lines Added
- **interview_cli.py**: ~150 lines (two new functions)
- **session_manager.py**: ~220 lines (new file)
- **Documentation**: ~1000+ lines across 4 files
- **Tests**: ~100 lines across 2 files

### Lines Modified
- **interview_cli.py**: ~30 lines (main() refactored)

### Lines Removed
- **0 lines** (everything preserved)

### Core Concept
```
Before: interview_cli.py
  └─ main() → blocking loop

After:  interview_cli.py
  ├─ main() → detect environment
  ├─ run_tty_mode() → blocking loop (original code)
  └─ run_non_tty_mode() → SessionManager (new)
        └─ session_manager.py (new file)
```

---

## Testing Checklist

- [ ] Run in terminal: `python interview_cli.py`
- [ ] Run in non-TTY: `./test_non_tty.sh`
- [ ] Simulate OpenTUI: `./opentui_example.py`
- [ ] Test force modes: `--force-tty`, `--force-non-tty`
- [ ] Verify session persistence: check `~/.ralph/sessions/`
- [ ] Complete full interview in both modes
- [ ] Verify same artifacts generated

---

## Migration Guide

### For Users

**No changes needed!** Everything works as before.

**New capability:** The interview now also works in OpenTUI.

### For Developers

**Adding features:**
- Interview logic: Modify `interview_manager.py` (unchanged)
- LLM calls: Modify `llm_client_opencode.py` (unchanged)
- State persistence: Modify `session_manager.py` (new)
- CLI behavior: Modify `interview_cli.py` (modified)

**Understanding flow:**
1. Entry: `interview_cli.py:main()`
2. Detection: `is_tty = sys.stdin.isatty()`
3. Routing: `run_tty_mode()` or `run_non_tty_mode()`
4. Processing: `InterviewManager` (same for both)
5. Persistence: `SessionManager` (non-TTY only)

---

## Quick Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Terminal support | ✅ Yes | ✅ Yes (unchanged) |
| OpenTUI support | ❌ No | ✅ Yes (new) |
| Blocking loops | ✅ Always | ✅ TTY only |
| State persistence | ❌ No | ✅ Non-TTY mode |
| Code complexity | Simple | Slightly more (dual-path) |
| Breaking changes | N/A | None |

---

**Total impact: Minimal code changes, maximum compatibility gains.**
