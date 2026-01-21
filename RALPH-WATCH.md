# Ralph Watch - Real-time Activity Monitor

Monitor ralph/opencode sessions in real-time without breaking ralph's functionality.

## Usage

**Auto-detect latest log:**
```bash
ralph-watch
```

**Watch specific log file:**
```bash
ralph-watch /home/mojo/.local/share/opencode/log/2026-01-20T234856.log
```

## What It Shows

- 🟢 **Session Start/Finish** - When ralph starts and completes tasks
- 🟣 **Step Progress** - Major processing steps with token counts
- 🔧 **Tool Usage** - When opencode uses tools (Read, Write, Edit, Bash, etc.)
- 📂 **File Operations** - When files are opened/modified by LSP
- 🔴 **Errors** - Any errors or failures detected
- 🎯 **LLM Streaming** - When the model is actively streaming responses

## Features

- ✅ Non-invasive - Only reads logs, doesn't interfere with ralph
- ✅ Auto-detects latest opencode log file
- ✅ Color-coded output for easy reading
- ✅ Filters out noisy "message.updated" entries
- ✅ Shows tool usage with emoji icons
- ✅ Displays token counts and costs
- ✅ Clean exit with summary (Ctrl+C)

## Examples

```bash
# While ralph is running, in another terminal:
cd ~/projects/ralph1
ralph-watch

# Or watch from anywhere:
ralph-watch

# Stop watching with Ctrl+C
```

## How It Works

1. Uses `tail -f` to follow the opencode log file in real-time
2. Parses JSON log entries as they arrive
3. Filters and formats important events
4. Displays human-readable output

## Installation

The script is already installed at `/home/mojo/projects/opencode2/ralph-watch` and is executable.

To use from anywhere, add to PATH:

```bash
# Option 1: Add to PATH
echo 'export PATH="$PATH:/home/mojo/projects/opencode2"' >> ~/.bashrc
source ~/.bashrc

# Option 2: Create symlink (already attempted)
sudo ln -s /home/mojo/projects/opencode2/ralph-watch /usr/local/bin/ralph-watch

# Option 3: Copy to bin
cp /home/mojo/projects/opencode2/ralph-watch ~/.local/bin/
```

## No Risk to Ralph

This script is completely read-only:
- ✅ Never modifies files
- ✅ Never sends API requests
- ✅ Never interferes with ralph's operation
- ✅ Just watches the log file that opencode already writes

It's safe to run while ralph is working!
