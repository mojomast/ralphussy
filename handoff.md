Ralph TUI Handoff
=================

**Updated**: 2026-01-22
**Previous**: 2026-01-21

What I Delivered
----------------
An upgraded Terminal User Interface (TUI) for Ralph with:
1. **System Log Pane** - Non-interactive console for swarm/agent process details
2. **Enhanced Worker Display** - Workers now show what they're working on
3. **Resume/Persistence** - Progress saving across runs
4. **Swarm Containment** - Resource limits and emergency controls

Core Features
-------------

### System Log Pane (New)
Non-interactive console showing swarm/agent process details:

| Icon | Meaning |
|------|---------|
| `✅` | Task completed |
| `❌` | Task failed |
| `⏳` | Task stuck |
| `→` | Task in progress |
| `◇` | Tool call |
| `◆` | File edit |
| `★` | Command execution |
| `✓` | Success |
| `⚠` | Warning |

**Benefits:**
- Keeps main chat console less noisy
- Scrollable history of all system events
- Visual flair for status changes

### Enhanced Worker Status Display
Workers now properly display their current task:
- Status indicators: `●` (working), `!` (error), `⏳` (stuck)
- Current task text with truncation
- Branch and run ID shortening

### Resume/Persistence
Progress saving across runs:
- Devplan file hashing for identification
- Completed task tracking in `completed_tasks` table
- `--resume RUN_ID` CLI support
- `/resume RUN_ID` TUI command
- Auto-detection of existing runs

### Swarm Containment
Resource limits to prevent runaway agents:
- `SWARM_MAX_WORKERS=8` (per run)
- `SWARM_MAX_TOTAL_WORKERS=16` (system-wide)
- `SWARM_SPAWN_DELAY=1` (seconds between spawns)
- `--emergency-stop` to kill all workers
- Process limits (ulimit) per worker

Chat Terminal Pane
------------------
Two modes:
- `orchestrator` (default): OpenCode-backed agent with swarm DB context
- `ralph`: Classic Ralph loop via `ralph2`

Features:
- Command history (Up/Down)
- Auto-complete (Tab)
- `/mode` to switch between modes

Worker Status Pane
------------------
Real-time display:
- Worker ID
- Status (idle/working/error/stuck)
- **Current task** (fixed display issue)
- Branch name
- Run ID

Click a worker to view detailed logs.

Progress Dashboard Pane
-----------------------
- Task statistics (done/active/pending/failed)
- Progress bar
- Total cost (if reported)

System Log Pane
---------------
New left-most pane with:
- Task start/completion/failure events
- Tool calls and file edits
- Command executions
- Process spawn/exit events

Swarm Control From Chat
-----------------------
New commands:

```bash
# Resume a previous run
/resume 20260122_143015
/swarm resume 20260122_143015

# Emergency stop all workers
/emergency-stop

# System statistics
/system

# Existing commands still work:
/swarm [N]          # Start swarm with N workers
/swarm status       # Show run status
/swarm logs         # View logs
/swarm stop         # Stop run
/swarm cleanup      # Clean up run
/swarm inspect      # Inspect run
/reiterate N        # Re-queue worker N's task
```

Settings Menu
-------------
Configure via `/settings`:
- Swarm model/provider
- Orchestration model/provider
- Default worker count
- Refresh interval
- Artifacts collection
- Auto-merge
- Theme (paper/midnight)

Settings persisted to: `~/.ralph/tui_settings.json`

Important Files (Quick Map)
---------------------------
- TUI launcher: `ralph-tui` or `ralph-refactor/ralph-tui`
- TUI application: `ralph-refactor/tui/ralph_tui.py`
- TUI dependencies: `ralph-refactor/tui/requirements.txt`
- Swarm DB schema: `ralph-refactor/lib/swarm_db.sh`
- Swarm worker: `ralph-refactor/lib/swarm_worker.sh`
- Swarm orchestrator: `ralph-refactor/ralph-swarm`
- Configuration: `~/.ralph/ralph.config`

How to Run
----------
```bash
./ralph-tui
```

Inside the TUI
--------------
Recommended flow:

1. `/new <project>`
2. Edit `devplan.md` or ask orchestrator to refine it
3. `/swarm 4`
4. Monitor in System Log pane (left)
5. Watch worker progress in Worker pane (top-right)
6. If worker stuck: `/reiterate 2`
7. If runaway: `/emergency-stop`
8. To resume later: `/resume <run_id>`

---
*This handoff documents the upgraded Ralph TUI with system logging, enhanced worker display, progress persistence, and swarm containment.*
