# Ralphussy

**The Autonomous AI Coding Toolbelt**

Ralphussy is a comprehensive distribution of the "Ralph" autonomous agent tooling, evolved into a powerful suite for AI-assisted software engineering. It includes a robust CLI loop agent, a terminal user interface (TUI), and a swarm runner for parallel task execution.

## ✨ Recent Improvements (2026-01-27)

**New: Options Menu & Configuration System:**
- ✅ **Options Menu** (`o` key) - Full settings UI with 5 tabbed sections
- ✅ **Provider/Model Selection** - Support for anthropic, openai, openrouter, ollama
- ✅ **Granular DevPlan Models** - Configure models per pipeline stage (interview/design/devplan/phase/handoff)
- ✅ **Config Persistence** - Settings saved to `~/.ralph/config.json`
- ✅ **Mode Selection** - Switch between ralph, devplan, and swarm modes
- ✅ **Configurable Settings** - Timeouts, poll interval, agent count, and more

**NEW: Major TUI Upgrades - Mouse Support & Visual Enhancements:**
- ✅ **Mouse Support** (`brrrrrrrr`!) - Enabled full mouse interaction (clicks, hover, scroll)
- ✅ **Modern Color Scheme** - GitHub Dark theme with consistent palette
- ✅ **ASCII Art Title** - Animated RALPH logo in header
- ✅ **Help System** - Press `?` for comprehensive keyboard shortcuts
- ✅ **Visual Enhancements** - Better borders, emojis, and color coding
- ✅ **Hover States** - Interactive feedback on all elements
- ✅ **Animated Spinners** - Loading states with rotating characters
- ✅ **Enhanced Modals** - All modals use new color scheme

## Previous Improvements (2026-01-24)

**15 Critical and Performance Fixes Implemented:**
- ✅ Fixed stall detection with duration-based accuracy
- ✅ Improved completion promise detection (case-insensitive, space-tolerant)
- ✅ Fixed JSON extraction to get latest messages reliably
- ✅ Prevented monitor process leaks with control files
- ✅ Added cross-platform devplan sync (fsync fallback)
- ✅ Automatic file rotation for history, logs, and handoffs
- ✅ Early model validation to prevent wasted execution
- ✅ SQLite performance optimizations for high concurrency
- ✅ Improved tool detection across all provider formats

See [IMPLEMENTATION_COMPLETED.md](IMPLEMENTATION_COMPLETED.md) for detailed documentation.

**New (2026-01-24): Completed remaining optimizations**
- ✅ Task batching look-ahead optimization (removes O(n^2) scans on large devplans)
- ✅ Removed duplicated OpenCode execution logic (shared helper used by loop + devplan)

## 📦 What's Included

This repository contains a self-contained distribution of the Ralph tooling:

*   **`ralph2`**: The primary CLI entry point for the autonomous loop agent. It runs the refactored, stable core of Ralph.
*   **`ralph-tui`**: A beautiful Textual-based Terminal User Interface for managing Ralph sessions, monitoring progress, and interacting with the agent.
*   **`ralph-swarm`**: (Located in `ralph-refactor/ralph-swarm`) A multi-worker system capable of executing tasks from a `devplan.md` in parallel using git worktrees.
*   **OpenCode Plugins**: Optional integrations for OpenCode (slash commands and plugins).

## 🚀 Quick Start

### Prerequisites

*   **Linux/macOS** (Windows via WSL2)
*   **Bash** 4.0+
*   **Python 3.10+** (for TUI)
*   **[OpenCode CLI](https://github.com/anomalyco/opencode)** installed and configured on your `PATH`.
*   **`jq`** (recommended for JSON parsing)
*   **`git`**
*   **Node.js 18+** (for swarm dashboard and OpenCode plugins)

### Running the CLI Agent

The simplest way to use Ralph is via the CLI wrapper. This runs the agent in a loop until the task is complete.

```bash
# Run a simple task
./ralph2 "Create a python script to calculate fibonacci numbers"

# Run with a specific model
./ralph2 "Refactor the database layer" --model claude-3-5-sonnet-20241022

# Work on a devplan (iterates through tasks in devplan.md)
./ralph2 --devplan ./devplan.md
```

### Running the TUI

For a more immersive experience with real-time monitoring:

```bash
./ralph-tui
```

The TUI allows you to:
*   Chat with the agent.
*   View active swarm workers.
*   Manage your `devplan.md`.
*   Monitor tool usage and logs in real-time.

### Swarm Dashboard Setup

For real-time swarm monitoring with a powerful TUI:

```bash
# Run the dashboard (recommended)
./run-swarm-dashboard2.sh

# Or run directly with Bun
bun swarm-dashboard2/src/index.ts
```

**Dashboard Features:**
- **Options Menu** (`o`) - Configure providers, models, and settings
- **DevPlan Generation** (`d`) - Generate development plans from requirements
- **Start Run** (`s`) - Launch swarm with configurable worker count
- **Run History** (`v`) - View and switch between historical runs
- **Live Monitoring** - Real-time task progress, worker status, and logs

**Configuration** is saved to `~/.ralph/config.json` and includes:
- Operation mode (ralph/devplan/swarm)
- Provider and model selection for each component
- Swarm agent count, timeouts, and behavioral settings

See [swarm-dashboard2/README.md](swarm-dashboard2/README.md) for full documentation.

  ### Running a Swarm
 
 Ralphussy now runs swarms on **isolated projects** in `~/projects/`, keeping your devplan work separate from ralphussy itself.
 
 ```bash
 # Run swarm on a new project (creates ~/projects/my-project/)
 RALPH_LLM_PROVIDER=zai-coding-plan RALPH_LLM_MODEL=glm-4.7 ./ralph-refactor/ralph-swarm --devplan ./devplan.md --project my-project
 
 # Run with 4 workers
 ./ralph-refactor/ralph-swarm --devplan ./devplan.md --project my-project --workers 4
 
 # Interactive mode (prompts for project name, workers, etc.)
 ./ralph-refactor/ralph-swarm --interactive
 
 # Resume a previous run
 ./ralph-refactor/ralph-swarm --resume <RUN_ID>
 
 # Show live output with token counting
 SWARM_OUTPUT_MODE=live ./ralph-refactor/ralph-swarm --devplan ./devplan.md --project my-project
 ```
 
 *Note: Swarm creates independent git repos in `~/projects/PROJECT_NAME/` with worker worktrees for isolation.*

 **Recent Improvements:**
 - ✅ **Project Isolation** - Swarms now create independent repos in `~/projects/` instead of worktrees on ralphussy
 - ✅ **Artifact Extraction** - `swarm_extract_merged_artifacts()` extracts only changed files from completed swarm runs
 - ✅ **Project-Based Workflow** - Use `--project NAME` to organize swarms by project
 - ✅ Fixed token aggregation bug (was showing 0 tokens incorrectly)
 - ✅ Added model validation against enabled-models.json
 - ✅ Improved database locking with retry logic and WAL mode
 - ✅ Added timeout protection for long-running tasks (default: 3 min)
 - ✅ Automatic cleanup of orphaned processes
 - ✅ Resume functionality for interrupted runs

## 🛠️ Usage Guide

 ### The DevPlan Workflow
 
 Ralph shines when working with a `devplan.md`. Create a file named `devplan.md` in your project root:
 
 ```markdown
 # My Project Plan
 
 - [ ] Create basic project structure
 - [ ] Implement user authentication
 - [ ] Add unit tests for auth
 ```
 
 Then run Ralph pointing to this plan:
 
 ```bash
 # Single agent mode
 ./ralph2 --devplan devplan.md
 
 # Swarm mode on isolated project
 ./ralph-refactor/ralph-swarm --devplan devplan.md --project my-project
 ```
 
 Ralph will:
 1.  Read the first pending task.
 2.  Execute the task using OpenCode.
 3.  Mark the task as `[✅]` when complete.
 4.  Move to the next task automatically.
 5.  If a task stalls, it marks it with `[🔄]` for your review.

### Command Line Options

| Option | Description |
|--------|-------------|
| `--devplan <file>` | Path to your devplan (default: `./devplan.md`) |
| `--model <name>` | Specify the LLM model to use |
| `--provider <name>` | Specify the LLM provider (e.g., anthropic, openai) |
| `--max-iterations <N>` | Limit the number of loop iterations (default: 100) |
| `--status` | Show the status of the current/last run |
| `--detach` | Run Ralph in the background |
| `--attach` | Attach to a running background instance |
 | `--add-context "..."` | Inject a hint or correction into the running agent |
 | `--project <name>` | Create isolated project in ~/projects/ for swarm runs |
 
 ### Extracting Swarm Artifacts
 
 After a swarm run completes, extract the merged results:
 
 ```bash
  # List all swarm runs
  source ralph-refactor/lib/swarm_artifacts.sh
  export RALPH_DIR="$HOME/projects/.ralph"
  swarm_list_runs
 
 # Extract artifacts (only changes, not full project)
 swarm_extract_merged_artifacts "RUN_ID" "/home/mojo/projects"
 ```
 
 This creates:
 - `~/projects/swarm-RUN_ID/merged-repo/` - Merged code from all workers
 - `~/projects/swarm-RUN_ID/SWARM_SUMMARY.md` - Run report with task status
 
 See [SWARM_ARTIFACTS.md](SWARM_ARTIFACTS.md) for details.

### OpenCode Integration Setup

To integrate Ralph into OpenCode as a plugin:

```bash
# Install Ralph plugin
cd opencode-ralph
./install-integrated.sh

# Install slash commands
cd ../opencode-ralph-slash
npm install
npm run build

# Follow instructions in opencode-ralph/INTEGRATION.md
```

See [opencode-ralph/README.md](opencode-ralph/README.md) for detailed integration instructions.
 
 ## 📂 Project Structure

*   `ralph2`: CLI wrapper script.
*   `ralph-tui`: TUI launcher script.
*   `ralph-live`: Real-time CLI with streaming output.
*   `ralph.config`: Configuration file.
*   `ralph-refactor/`: The core implementation.
    *   `ralph`: The actual bash script logic.
    *   `ralph-swarm`: Parallel swarm execution.
    *   `lib/`: Modular libraries for the agent (monitoring, JSON handling, etc.).
    *   `tui/`: Python source code for the TUI.
*   `swarm-dashboard/`: Real-time swarm monitoring with TUI and CLI versions.
*   `opencode-ralph*/`: Plugins for integrating Ralph directly into OpenCode.

## 🤝 Contributing

This is a distribution of the Ralph tooling ecosystem. Changes to the core logic should be made in `ralph-refactor/`.

## 📜 License

[MIT](LICENSE)
