# Ralph Refactor Handoff

## Project State
We have significantly refactored the Ralph TUI (`ralph-refactor/tui/ralph_tui.py`) to improve the user experience and visibility into swarm operations. The backend logic for the swarm remains largely in shell scripts (`ralph-refactor/lib/`), but the TUI is now a robust Python Textual application.

## Recent Changes

### 1. System Log Pane (LogPane)
Added a new non-interactive **System Log pane** (left column) that shows swarm/agent process details:
- Task starts, completions, and failures with visual flair
- Tool calls with arguments
- File edits and command executions
- Process spawn/exit events

**Visual Flair for Task Status:**
- `✅` - Task completed successfully
- `❌` - Task failed (shows error message)
- `⏳` - Task appears stuck
- `→` - Task currently in progress
- `◇` - Tool call
- `◆` - File edit
- `★` - Command execution

The LogPane keeps the main chat console less noisy by moving system-level details to a dedicated pane.

### 2. Enhanced Worker Status Display
Fixed the worker pane to properly show what workers are currently working on:
- Workers now display their current task with status indicators
- "idle" workers show in yellow
- "working" workers show in green with `●` indicator
- "error" workers show in red with `!` indicator
- "stuck" workers show in yellow with `⏳` indicator

The worker table now shows: ID | Status | Current Task | Branch | RunID

### 3. TUI Layout Changes
Modified the grid layout to accommodate the new LogPane:
- **3-column layout**: LogPane (left) | ChatPane (center) | WorkerPane (right)
- **2-row layout**: Top row for active work, bottom row for progress/file browser

### 4. Resume/Progress Persistence
Added comprehensive progress saving and resumption:
- **Database schema updates**: Added `source_hash` and `task_hash` columns
- **Completed tasks tracking**: New `completed_tasks` table for cross-run persistence
- **CLI support**: `--resume RUN_ID` flag to continue interrupted runs
- **TUI support**: `/resume RUN_ID` and `/swarm resume RUN_ID` commands
- **Auto-detection**: System detects when same devplan is run again and prompts to resume

### 5. Swarm Containment
Added resource limits and controls to prevent runaway swarms:
- `SWARM_MAX_WORKERS=8` - Max workers per run
- `SWARM_SPAWN_DELAY=1` - Delay between worker spawns
- `SWARM_MAX_TOTAL_WORKERS=16` - System-wide worker limit
- `--emergency-stop` - Kill all workers immediately
- `/emergency-stop` - TUI command for emergency stop
- Process resource limits (ulimit) applied per worker

## Key Files
*   `ralph-refactor/tui/ralph_tui.py`: The main TUI application. Contains all screen definitions (Chat, Workers, Files, Settings, LogPane) and the main event loop.
*   `ralph-refactor/lib/swarm_db.sh`: The shell-based SQLite wrapper with resume and tracking functions.
*   `ralph-refactor/lib/swarm_worker.sh`: The worker agent logic with resource limits.
*   `ralph-refactor/ralph-swarm`: Main swarm orchestrator with `--resume` and `--emergency-stop` support.

## Known Issues / TODOs
*   **Performance:** `refresh_status_async` polls the DB every 2 seconds. For very large task histories, fetching all tasks to check for status changes might become slow. Consider adding a `last_updated` filter or limiting the query if performance degrades.
*   **Editor:** The `FileEditorScreen` is basic. It lacks syntax highlighting *editing* (though it has highlighting for *viewing* if `TextArea` supports it sufficiently) and advanced features like search/replace.
*   **Shell Integration:** The TUI currently relies on `subprocess` to call `ralph` shell scripts. Ensure the path resolution in `ralph_tui.py` (specifically `RALPH_REFACTOR_DIR`) stays aligned with the actual directory structure.
*   **Stuck Detection:** The stuck detection (`⏳`) is visual-only based on worker state. Consider adding actual timeout detection in the backend.

## How to Run
1.  Ensure you are in the `ralph-refactor` directory.
2.  Run the TUI:
    ```bash
    python3 tui/ralph_tui.py
    ```
3.  Inside the TUI, use `/help` to see commands. Use `/swarm start ...` to kick off a run.

## New Commands
```bash
# Resume a previous run
./ralph-swarm --resume 20260122_143015
/swarm resume 20260122_143015

# Emergency stop all workers
./ralph-swarm --emergency-stop
/emergency-stop

# View system statistics
/system
```
