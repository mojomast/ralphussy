# Swarm Dashboard 2

A React-based OpenTUI dashboard for monitoring Ralph AI swarm operations. This is the successor to the original `swarm-dashboard` with improved scrolling, dynamic sizing, and detail views.

## Features

- **Mouse Support**: Click to interact with options menu, switch tabs, and cycle values (BETA)
- **Options Menu**: Full configuration UI for providers, models, and settings (press `o`)
- **DevPlan Generation**: Built-in wizard to generate development plans from requirements (press `d`)
- **Full Scrolling Support**: Scroll through all content - per-pane or global dashboard scrolling
- **Dynamic Sizing**: Panes grow based on content size, ensuring all tasks/logs are accessible
- **Detail Views**: View full task or worker details in an overlay panel
- **Live Updates**: Auto-refreshes based on configurable poll interval
- **Keyboard Navigation**: Full keyboard control for pane switching, scrolling, and selection
- **Focus Indicators**: Visual indicators show which pane is currently focused
- **Config Persistence**: Settings saved to `~/.ralph/config.json`

## Quick Start

```bash
# From the repository root
chmod +x run-swarm-dashboard2.sh   # One-time setup
./run-swarm-dashboard2.sh

# Alternative: run directly with Bun
bun swarm-dashboard2/src/index.ts
```

## Keyboard Controls

### Main Actions
| Key | Action |
|-----|--------|
| `o` | Open Options Menu (providers, models, settings) - **Mouse-enabled!** |
| `d` | Show DevPlan Interactive Interview instructions |
| `s` | Start a new swarm run |
| `e` | Emergency stop (kill all workers) |
| `a` | Attach/inspect running swarm |
| `v` | View/select historical runs |
| `V` | Clear selection, return to current run |
| `t` | Filter Ralph Live by task |
| `r` | Manual refresh |
| `?` | Show help modal with all keybindings |
| `q` / `Ctrl+C` | Quit dashboard |

### Navigation
| Key | Action |
|-----|--------|
| `Tab` | Cycle focused pane (tasks -> actions -> workers -> ralph -> console) |
| `Up` / `Down` | Scroll focused pane by one line |
| `PageUp` / `PageDown` | Scroll focused pane by 10 lines |
| `Shift+Up` / `Shift+Down` | Scroll entire dashboard (global scroll) |
| `Enter` / `Space` | Open detail view for selected task or worker |
| `Escape` | Close detail view or modal |

### Options Menu Navigation
| Key/Mouse | Action |
|-----------|--------|
| `←` / `→` or `H` / `L` | Switch between sections |
| `↑` / `↓` | Navigate fields within section |
| `Enter` / `Space` | Cycle through values |
| `Escape` | Close and save |
| **Mouse Click** | **Click tabs to switch sections** |
| **Mouse Click** | **Click fields to focus and cycle values** |
| **Mouse Click Outside** | **Click outside modal to close** |

## Options Menu

Press `o` to open the Options Menu with 5 configurable sections:

### MODE
Select operation mode:
- **RALPH** - Single agent autonomous coding
- **DEVPLAN** - Generate development plans from requirements
- **SWARM** - Multi-agent parallel task execution

### SWARM
Configure swarm settings:
- Provider (anthropic, openai, openrouter, ollama)
- Model selection
- Agent count (1-10)

### RALPH
Configure ralph settings:
- Provider
- Model selection

### DEVPLAN
Granular model selection for each pipeline stage:
- Interview model
- Design model
- DevPlan model
- Phase model
- Handoff model

### SETTINGS
General configuration:
- Command timeout (60-600s)
- LLM timeout (30-300s)
- Poll interval (1-30s)
- Auto-refresh (ON/OFF)
- Show costs (ON/OFF)
- Debug mode (ON/OFF)
- Max log lines (100-1000)

## Configuration

Settings are persisted to `~/.ralph/config.json`:

```json
{
  "mode": "swarm",
  "swarmModel": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
  "ralphModel": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
  "devplanModels": {
    "interview": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
    "design": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
    "devplan": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
    "phase": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" },
    "handoff": { "provider": "anthropic", "model": "claude-sonnet-4-20250514" }
  },
  "swarmAgentCount": 4,
  "commandTimeout": 300,
  "llmTimeout": 120,
  "pollInterval": 5,
  "autoRefresh": true,
  "showCosts": true,
  "maxLogLines": 200,
  "debugMode": false
}
```

## Supported Providers

| Provider | Models |
|----------|--------|
| `anthropic` | claude-sonnet-4-20250514, claude-opus-4-20250514, claude-3-5-haiku-20241022 |
| `openai` | gpt-4o, gpt-4o-mini, gpt-4-turbo, o1, o1-mini, o3-mini |
| `openrouter` | deepseek/deepseek-chat, deepseek/deepseek-reasoner, google/gemini-2.0-flash-001, meta-llama/llama-3.3-70b-instruct |
| `ollama` | llama3.2, qwen2.5-coder, deepseek-r1:14b, codellama |

## DevPlan Generation

Press `d` to view instructions for launching the **Interactive LLM Interview** for DevPlan generation.

### What You'll See

A modal displays with:
- **Exact command** to run the interactive interview (auto-detects your project)
- **Step-by-step instructions** for launching the interview
- **Feature overview** of what the interview covers
- **Output location** where devplan files will be saved

### How to Use

1. Press `d` in the TUI
2. Read the instructions in the modal
3. Press `Escape` to close the TUI
4. Run the command shown (example):
   ```bash
   cd ~/projects/ralphussy/devussy/devussy && \
   python3 -m src.cli interactive-design --llm-interview --streaming --repo-dir ~/projects/your-project
   ```

### Interactive Interview Features

The LLM-driven interview provides:
- **Natural conversation** - Chat with the LLM to gather requirements
- **Smart prompting** - Guided questions based on your project type
- **Technology recommendations** - Suggestions for frameworks and tools
- **Repo awareness** - Analyzes existing code if available
- **Slash commands**: `/help`, `/done`, `/quit`, `/settings`, etc.

### Interview Process

1. **Requirements Gathering** - Describe what you want to build
2. **Technology Selection** - Choose languages, frameworks, APIs
3. **Architecture Planning** - Define project structure and components
4. **Review & Refinement** - Clarify and adjust before generation
5. **Generation** - Creates design, devplan, phases, and handoff

### Output Files

Generated in `~/.ralph/devplans/{project_name}/`:
- `design.md` - Project design document
- `devplan.md` - Development plan with phases and steps
- `handoff.md` - Handoff prompt for agents

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

## Mouse Support (BETA)

The Options Menu now supports mouse interaction! This feature is in BETA and includes debugging to help troubleshoot any issues.

### Supported Mouse Actions

When the Options Menu is open (press `o`):
- **Click Tabs** - Switch between Mode, Swarm, Ralph, Devplan, Settings sections
- **Click Fields** - Focus and cycle through values (providers, models, settings)
- **Click Outside** - Close the modal and save settings
- **Scroll Wheel** - Scroll through long option lists (if supported by terminal)

### Verifying Mouse Support

1. Launch the TUI and check the **Ralph Live** pane (bottom right)
2. Look for: `[MOUSE] Mouse handler initialized - try clicking!`
3. If you see this message, mouse support is active
4. Open options with `o` and try clicking
5. Each click will be logged: `[MOUSE] mousedown at (x, y) - Options menu is open`

### Troubleshooting Mouse Issues

**Mouse events not logged:**
- Your terminal emulator may not support mouse events
- Try a different terminal (iTerm2, Alacritty, Kitty all work well)
- Check terminal settings for mouse mode support

**Mouse events logged but nothing happens:**
- The coordinate mapping may need adjustment
- Enable debug mode: Press `o`, go to Settings, toggle "Debug Mode" ON
- Report the coordinates you see when clicking on fields

**Terminal compatibility:**
- ✅ Works: iTerm2, Alacritty, Kitty, Warp, Hyper
- ⚠️ Limited: Terminal.app (macOS), GNOME Terminal
- ❌ Not supported: Basic TTY, some SSH sessions

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

### Mouse not working
1. Check Ralph Live pane for `[MOUSE] Mouse handler initialized`
2. If missing, check for error: `[MOUSE ERR] Failed to initialize`
3. Try a different terminal emulator
4. Report issue with terminal name and OS version

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
- `HANDOFF.md` - Development handoff documentation (for developers)

## For Developers

See **[HANDOFF.md](./HANDOFF.md)** for:
- Recent code changes and implementation details
- Testing procedures and verification steps
- Known issues and troubleshooting guides
- Technical debt and recommendations
- Debug logging reference

## Recent Updates

### January 27, 2026
- ✅ **Mouse Support Added** - Click to interact with options menu (BETA)
- ✅ **DevPlan Instructions** - Press 'D' for interactive interview guide
- ✅ **Enhanced Debugging** - Comprehensive logging for troubleshooting
- 📋 **Documentation** - Added HANDOFF.md with technical details

### Features in Development
- 🔄 Mouse support for task/worker selection
- 🔄 Click-to-focus for panes
- 🔄 Hover tooltips and visual feedback
- 🔄 Scroll wheel support for panes
