# Ralph Refactor Workspace

This folder contains a refactor-friendly copy of the root `ralph` script.

Goals:
- Keep the main entrypoint smaller and easier to edit.
- Isolate the Unicode-heavy / fast-changing sections (like the live monitor) into separate modules.
- Reduce the chance that a partial edit or encoding hiccup corrupts the entire script.

Files:
- `ralph-refactor/ralph` - Refactor candidate entrypoint (sources modules from `ralph-refactor/lib/`).
- `ralph-refactor/ralph.orig` - Snapshot of the copied script before refactoring.
- `ralph2` - Thin wrapper that runs `ralph-refactor/ralph` (use this to test the refactor without touching `./ralph`).
- `ralph-refactor/lib/core.sh` - Stable core plumbing (config, logging, state, blockers, docs, handoffs).
- `ralph-refactor/lib/monitor.sh` - Live monitor implementation.
- `ralph-refactor/lib/json.sh` - JSON extraction helpers (jq/fallback parsing).
- `ralph-refactor/lib/devplan.sh` - Devplan parsing + task execution helpers.

Background usage (detach/attach):

```bash
# Start a run in the background (prints run id + log path)
ralph2 --detach --devplan /home/mojo/projects/ralph1/devplan.md

# Follow the current run logs (Ctrl+C detaches without stopping it)
ralph2 --attach

# Stop the current run
ralph2 --stop

# List known runs
ralph2 --runs
```

Optional bash integration (prompt flair + helper functions):

```bash
# One-time: source the helper (put this in ~/.bashrc if you like)
source /home/mojo/projects/opencode2/ralph-refactor/ralph-bashrc.sh

# Optional prompt flair (example):
# If you already have a custom PS1, splice $(ralph_prompt_segment) in wherever you want.
export PS1='\u@\h:\w $(ralph_prompt_segment)\$ '

# Convenience helpers
ralph_attach
ralph_stop
ralph_runs
ralph_status
```

To syntax-check:

```bash
bash -n ralph-refactor/ralph
bash -n ralph2
bash -n ralph-refactor/lib/core.sh
bash -n ralph-refactor/lib/monitor.sh
bash -n ralph-refactor/lib/json.sh
bash -n ralph-refactor/lib/devplan.sh
```

Swarm CLI
---------

The `ralph-refactor/ralph-swarm` script provides a small CLI to run a parallel
"swarm" over a devplan file or a decomposed prompt. It uses the OpenCode CLI
(`opencode run --format json`) for analysis and for worker runs. Basic usage:

1. Analyze a devplan (no network calls):

```bash
./ralph-refactor/ralph-swarm --analyze ralph-refactor/tests/devplan_complex.md
```

2. Run the swarm against a devplan (example using GitHub Copilot / Gemini):

```bash
RALPH_DIR=/tmp/ralph_swarm_run \
RALPH_LLM_PROVIDER=github-copilot \
RALPH_LLM_MODEL=github-copilot/gemini-3-flash-preview \
./ralph-refactor/ralph-swarm --devplan ralph-refactor/tests/devplan_complex.md --workers 4 --timeout 3600
```

- `RALPH_DIR` points at state/log/run artifacts (default: `~/.ralph`).
- `RALPH_LLM_PROVIDER` and `RALPH_LLM_MODEL` are forwarded to `opencode run`.
- Ensure `opencode` is installed and configured to use the provider/model you
  select (see OpenCode docs).

3. Helpful runtime commands (use the same `RALPH_DIR`):

```bash
# show status
RALPH_DIR=/tmp/ralph_swarm_run ./ralph-refactor/ralph-swarm --status

# tail aggregated logs
RALPH_DIR=/tmp/ralph_swarm_run ./ralph-refactor/ralph-swarm --logs --lines 200

# stop run
RALPH_DIR=/tmp/ralph_swarm_run ./ralph-refactor/ralph-swarm --stop
```

Environment toggles:
- `SWARM_AUTO_MERGE=true` (auto-merge worker branches at the end)
- `SWARM_PUSH_AFTER_MERGE=true` (push merged main branch to origin)

Note: Worker execution runs `opencode run` inside isolated git worktrees created
per worker. The LLM must perform repository edits and commit them (or produce
patches) for merges to be meaningful.

Ralph TUI
---------

The `ralph-tui` script launches a full-screen Terminal User Interface for Ralph.
It provides a visual IDE-like experience with multiple panes:

- **Chat Terminal**: Interact with Ralph via commands and prompts
- **Worker Status**: Monitor swarm worker activity in real-time
- **Progress Dashboard**: Track task completion with progress bars
- **File Browser**: Explore project files and artifacts

### Quick Start

```bash
# Launch the TUI (automatically sets up Python dependencies on first run)
./ralph-tui

# Or just setup without launching
./ralph-tui --setup

# Clean and reinstall dependencies
./ralph-tui --clean && ./ralph-tui --setup
```

### Project Management

The TUI uses a project-based workflow. Projects are stored in `~/.ralph/projects/`:

```
~/.ralph/projects/<project-name>/
├── src/          # Source code
├── docs/         # Documentation
├── artifacts/    # Swarm run artifacts
├── output/       # Ralph output files
└── devplan.md    # Development plan
```

### TUI Commands

Inside the TUI, use these commands in the chat terminal:

```
/new <name>      Create a new project
/open <name>     Open an existing project
/projects        List all projects
/devplan [file]  Run Ralph in devplan mode
/mode <name>     Switch chat mode (orchestrator|ralph)
/settings        Open settings menu

/swarm [N]        Start swarm with N workers (default from settings)
/swarm status     Show swarm status (reads from db / CLI)
/swarm logs ...   Tail swarm logs (supports same args as ralph-swarm)
/swarm stop       Stop a swarm run
/swarm inspect    Inspect latest run
/swarm cleanup    Cleanup latest run
/swarm reiterate  Force a worker to re-queue current task

/reiterate N     Convenience alias for /swarm reiterate --worker N
/report [RUN_ID] Export a markdown report to project output/

/sessions        List active subprocess sessions
/focus <PID>     Focus a session (used by /stop)
/status          Show current status
/stop            Stop current Ralph run
/logs            Show recent logs
/help            Show help
```

### Keyboard Shortcuts

- `Ctrl+N` - New project
- `Ctrl+O` - Open project
- `Ctrl+R` - Run swarm
- `Ctrl+S` - Stop swarm
- `Ctrl+,` - Settings
- `Ctrl+T` - Toggle theme
- `F1` - Help
- `F5` - Refresh status
- `Q` - Quit

### Dependencies

The TUI requires Python 3.9+ and uses:
- `textual` - Modern TUI framework
- `rich` - Rich text rendering
- `watchfiles` - File change monitoring

Dependencies are automatically installed in a virtual environment at
`ralph-refactor/tui/.venv/` on first launch.

### Orchestrator Chat

By default the chat pane is in `orchestrator` mode. The orchestrator is a small
agent that can:

- Answer questions about the active swarm run (workers, tasks, locks, logs)
- Suggest corrective actions if a worker is stuck
- Update `devplan.md` (add detours, reorder tasks, refine steps)
- Trigger `--reiterate` when the user reports a broken worker

The orchestrator runs via `opencode run` and uses the model/provider you choose
in the TUI settings.
