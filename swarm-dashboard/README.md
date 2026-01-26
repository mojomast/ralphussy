# Swarm Dashboard

Real-time dashboards for monitoring Ralph AI swarm operations.

> **Note**: A newer React-based dashboard (`swarm-dashboard2`) is also available with improved scrolling and detail views. See `../swarm-dashboard2/README.md` or run `./run-swarm-dashboard2.sh` from the repository root.

## Features

- **Live Worker Monitoring**: View status of all swarm workers in real-time
- **Task Progress Tracking**: See pending, in-progress, completed, and failed tasks
- **Resource Usage**: Monitor API costs, token usage, and task statistics
- **Real-Time Updates**: Auto-refreshes every 2 seconds
- **Color-Coded Display**: Easy-to-read status indicators and progress information

## Prerequisites

- **Node.js** v18+ - Required for SQLite database access (better-sqlite3)
- SQLite database at `~/.ralph/swarm.db` (created by Ralph swarm)

Note: Bun is used for development but Node.js is required at runtime for database compatibility.

## Installation

1. Install dependencies:
```bash
cd swarm-dashboard
npm install
```

2. Build dashboard:
```bash
npm run build
```

## Usage

### Simple CLI Version (Recommended)

The simple version works in any terminal and displays formatted output:

```bash
./run-simple.sh
```

Or directly with Node.js:
```bash
node dist/simple.js
```

**Features**:
- Works in any terminal (no TUI dependencies)
- Color-coded output
- Automatic refresh every 2 seconds
- Ctrl+C to exit

### Full TUI Version

The full TUI version provides a rich interactive interface:

```bash
./run.sh
```

Or directly with Node.js:
```bash
node dist/index.js
```

**Keyboard Controls**:
- `r` - Refresh data immediately
- `q` - Quit dashboard
- `Ctrl+C` - Quit dashboard

**Note**: The TUI version requires a proper terminal emulator and may not work through opencode or remote connections.

## Display

Both versions show:

### Run Information
- Active run ID and status
- Worker count
- Progress percentage (completed/total tasks)

### Worker Status
- Worker number and current state
- Task being worked on (or idle)
- Status color coding: 
  - 🟡 Yellow - Idle/Pending
  - 🟢 Green - Working/In Progress
  - 🔵 Blue - Completed
  - 🔴 Red - Failed/Error
  - ⚫ Gray - Stopped

### Task List
- Recent tasks from current swarm run
- Task ID, status, and description
- Truncated long descriptions for readability

### Resource Summary
- **Total Cost**: Total API costs in USD
- **Prompt Tokens**: Total prompt tokens used
- **Completion Tokens**: Total completion tokens used
- **Task Statistics**: Count of pending, in-progress, completed, and failed tasks

## Database

The dashboard reads from Ralph swarm SQLite database:
- Location: `~/.ralph/swarm.db` (or via `RALPH_DIR` env var)
- Tables: `swarm_runs`, `workers`, `tasks`, `task_costs`, `file_locks`

The database is opened in read-only mode for safe concurrent access.

## Development

Build TypeScript:
```bash
npm run build
```

## Troubleshooting

### "Database not found" error
Ensure a swarm run has been executed with Ralph, which creates the database.

### No active run displayed
Start a swarm run with Ralph, and the dashboard will automatically detect and display it.

### TUI version shows black screen
- Use the simple CLI version instead: `./run-simple.sh`
- Ensure you're running in a proper terminal (not through opencode)
- Try increasing terminal window size
- Make sure terminal supports ANSI escape codes

### Terminal stuck after dashboard exit
- Try the simple CLI version instead
- Run `reset` command to restore terminal
- Check your terminal emulator settings

## Architecture

```
swarm-dashboard/
├── src/
│   ├── index.ts       - TUI dashboard entry point
│   ├── simple.ts      - Simple CLI dashboard
│   ├── dashboard.ts   - Main TUI dashboard UI
│   └── database.ts    - SQLite database layer
├── dist/             - Compiled JavaScript
├── run.sh           - TUI launcher script
├── run-simple.sh     - Simple CLI launcher script
├── package.json
├── tsconfig.json
└── README.md
```

## Technologies

- **OpenTUI** - Terminal UI framework (TUI version)
- **better-sqlite3** - SQLite database access
- **TypeScript** - Type-safe development
- **Node.js** - Production runtime for database compatibility
- **Bun** - Development runtime

## Quick Start

```bash
cd /home/mojo/projects/ralphussy/swarm-dashboard

# First time setup
npm install
npm run build

# Run the simple version (recommended)
./run-simple.sh

# Or run the full TUI version
./run.sh
```

The simple version works in any terminal and shows all the same information with color-coded output.
