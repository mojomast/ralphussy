# Swarm Dashboard 2

A React-based OpenTUI dashboard for monitoring Ralph AI swarm operations. This is the successor to the original `swarm-dashboard` with improved scrolling, dynamic sizing, and detail views.

## Features

- **Full Scrolling Support**: Scroll through all content - per-pane or global dashboard scrolling
- **Dynamic Sizing**: Panes grow based on content size, ensuring all tasks/logs are accessible
- **Detail Views**: View full task or worker details in an overlay panel
- **Live Updates**: Auto-refreshes every 2 seconds
- **Keyboard Navigation**: Full keyboard control for pane switching, scrolling, and selection
- **Focus Indicators**: Visual indicators show which pane is currently focused

## Quick Start

```bash
# From the repository root
chmod +x run-swarm-dashboard2.sh   # One-time setup
./run-swarm-dashboard2.sh

# Alternative: run directly with Bun
bun swarm-dashboard2/src/index.ts
```

## Keyboard Controls

### Navigation
| Key | Action |
|-----|--------|
| `Tab` | Cycle focused pane (tasks -> actions -> workers -> console) |
| `Up` / `Down` | Scroll focused pane by one line |
| `PageUp` / `PageDown` | Scroll focused pane by 10 lines |
| `Shift+Up` / `Shift+Down` | Scroll entire dashboard (global scroll) |
| `Shift+PageUp` / `Shift+PageDown` | Scroll entire dashboard by 10 lines |

### Actions
| Key | Action |
|-----|--------|
| `Enter` / `Space` | Open detail view for selected task or worker |
| `Escape` / `q` | Close detail view (when open) |
| `r` | Manual refresh |
| `q` / `Ctrl+C` | Quit dashboard |

## Display Panes

### Live Actions (30% width)
- Real-time activity stream from worker logs
- Shows worker number and log message
- Scrollable with up to 200 recent log entries

### Tasks (45% width)
- All tasks from the current swarm run
- Shows task ID, status, and description
- Color-coded by status:
  - Green: Completed
  - Blue: In Progress
  - Red: Failed
  - Gray: Pending/Unknown

### Resources (25% width, top)
- Resource summary (coming soon)
- Will show API costs, token usage, and statistics

### Workers (25% width, bottom)
- All workers in the current swarm run
- Shows worker number, status, and current task
- Color-coded status indicators

### Console Log (bottom)
- All console log entries (no limit)
- Shows worker number and message
- 120-character line width

## Detail Views

Press `Enter` or `Space` on a selected task or worker to open a detail overlay:

### Task Details
- Task ID, status, worker assignment
- Created/started/completed timestamps
- Full task text (multi-line)
- Result output (if completed)

### Worker Details
- Worker number and status
- Current task assignment
- Completed task count
- Start time and last activity

Press `Escape` or `q` to close the detail view.

## Database

The dashboard reads from Ralph swarm SQLite database:
- Default location: `~/.ralph/swarm.db`
- Override with `RALPH_DIR` environment variable
- The launcher auto-discovers the most active swarm database

## Troubleshooting

### Terminal appears garbled or stuck
1. Try `Ctrl+C` or press `q`
2. From another terminal run:
   ```bash
   tput rmcup || true
   stty echo || true
   reset
   ```

### TTY detection issues
For debugging or non-interactive environments:
```bash
ALLOW_NO_TTY=1 ./run-swarm-dashboard2.sh
```

### No active run displayed
Start a swarm run with Ralph, and the dashboard will automatically detect and display it.

## Architecture

```
swarm-dashboard2/
├── src/
│   ├── index.ts       - React + OpenTUI entry point
│   └── dashboard.ts   - Class-based version (reference)
└── README.md
```

## Technologies

- **React** - Component-based UI
- **OpenTUI** - Terminal UI framework (@opentui/react, @opentui/core)
- **Bun** - Runtime and bundler
- **SQLite** - Database (via swarm-dashboard compiled helper)

## Development

The dashboard runs directly from source files for fast iteration:

```bash
# Run from source (default)
./run-swarm-dashboard2.sh

# Force run from dist (if built)
RUN_DIST=1 ./run-swarm-dashboard2.sh
```

## Related

- `swarm-dashboard/` - Original dashboard implementation
- `run-swarm-dashboard2.sh` - Root launcher script
- `handoff.md` - Development handoff documentation
