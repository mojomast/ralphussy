Ralph TUI Handoff
=================

**Updated**: 2026-01-21
**Previous**: swarmhandoff.md (Swarm implementation)

What I delivered
----------------
An upgraded Terminal User Interface (TUI) for Ralph that treats the swarm as a first-class, controllable system.

The big change is that the chat pane is no longer only a thin wrapper around `ralph2`. It now defaults to an **orchestration agent** that can:

- Answer questions about the swarm (run status, workers, tasks, heartbeats, cost).
- Modify the project `devplan.md` (add detours, refine tasks, re-scope work).
- Force swarm to re-queue work when a user notices a worker is stuck or behaving badly.

Core Features
-------------
- **Chat Terminal Pane**
  - Two modes:
    - `orchestrator` (default): an OpenCode-backed agent that uses swarm DB context + `devplan.md` to answer questions and control swarm.
    - `ralph`: sends prompts to `ralph2` for the classic Ralph loop.
  - Command history (Up/Down) and command auto-complete (Tab).

- **Worker Status Pane**: Real-time display of swarm worker activity (worker num, status, task, branch, heartbeat).
- **Progress Dashboard Pane**: Task stats + progress bar + total cost (if reported by provider).
- **File Browser Pane**
  - Live refresh via file watching (when `watchfiles` is available).
  - Syntax-highlighted preview for common file types.

Swarm Control From Chat
----------------------
The chat supports swarm control primitives directly:

- Start swarm: `/swarm [N]`
- Status: `/swarm status [RUN_ID]`
- Logs: `/swarm logs [RUN_ID] [--worker N] [--lines N]`
- Stop: `/swarm stop [RUN_ID]`
- Cleanup: `/swarm cleanup [RUN_ID]`
- Inspect: `/swarm inspect [RUN_ID]`

Worker recovery:

- `/reiterate <worker_num> [run_id]`
- `/swarm reiterate [RUN_ID] --worker <N>`

Under the hood, reiteration resets the worker record, releases locks, and re-queues the worker's current task.

Settings Menu
-------------
There is now a TUI settings modal to configure:

- **Swarm model/provider** (used by swarm analyzer + workers)
- **Orchestration agent model/provider** (used by the chat default agent)
- Defaults like worker count, refresh interval, artifacts collection, auto-merge, file watching, and theme.

Settings are persisted to:

- `~/.ralph/tui_settings.json`

Cost Tracking
-------------
Swarm now records per-task cost/token stats (best-effort, depends on provider reporting) in the swarm DB.

- DB table: `task_costs`
- Progress pane shows run total cost.

Important files (quick map)
---------------------------
- TUI launcher: `ralph-tui` (top-level) or `ralph-refactor/ralph-tui`
- TUI application: `ralph-refactor/tui/ralph_tui.py`
- TUI dependencies: `ralph-refactor/tui/requirements.txt`
- Swarm DB schema + helpers: `ralph-refactor/lib/swarm_db.sh`
- Swarm worker cost recording: `ralph-refactor/lib/swarm_worker.sh`
- Swarm reiterate CLI: `ralph-refactor/ralph-swarm`
- Updated docs: `ralph-refactor/README.md`

How to run
----------
```bash
./ralph-tui
```

Inside the TUI
--------------
Recommended flow:

1. `/new <project>`
2. Edit `devplan.md` (or ask the orchestrator to refine it)
3. `/swarm 4`
4. If a worker stalls: `/reiterate 2`

---
*This handoff documents the upgraded Ralph TUI with swarm-aware orchestration, settings, and recovery controls.*
