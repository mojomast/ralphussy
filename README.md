# Ralphussy

**The Autonomous AI Coding Toolbelt**

Ralphussy is a comprehensive distribution of the "Ralph" autonomous agent tooling, evolved into a powerful suite for AI-assisted software engineering. It includes a robust CLI loop agent, a terminal user interface (TUI), and a swarm runner for parallel task execution.

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

 ### Running a Swarm

To execute multiple tasks in parallel:

```bash
# Run 2 workers against a local devplan.md (default)
RALPH_LLM_PROVIDER=zai-coding-plan RALPH_LLM_MODEL=glm-4.7 ./ralph-refactor/ralph-swarm --devplan ./devplan.md

# Run with 4 workers
./ralph-refactor/ralph-swarm --devplan ./devplan.md --workers 4

# Resume a previous run
./ralph-refactor/ralph-swarm --resume <RUN_ID>

# Show live output with token counting
SWARM_OUTPUT_MODE=live ./ralph-refactor/ralph-swarm --devplan ./devplan.md
```

*Note: Swarm mode creates temporary git worktrees to isolate worker contexts.*

**Recent Swarm Improvements:**
- ✅ Fixed token aggregation bug (was showing 0 tokens incorrectly)
- ✅ Added model validation against enabled-models.json
- ✅ Improved database locking with retry logic and WAL mode
- ✅ Added timeout protection for long-running tasks (increased to 10 min)
- ✅ Automatic cleanup of orphaned processes
- ✅ Resume functionality for interrupted runs
- ✅ **NEW:** Commit-aware resume - workers check for existing git commits and skip completed work
- ✅ **NEW:** Fixed display encoding in status output - now shows formatted, human-readable task lists
- ✅ **NEW:** Default model is `zai-coding-plan/glm-4.7` (no longer broken free model)

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
./ralph2 --devplan devplan.md
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

## 📂 Project Structure

*   `ralph2`: CLI wrapper script.
*   `ralph-tui`: TUI launcher script.
*   `ralph-refactor/`: The core implementation.
    *   `ralph`: The actual bash script logic.
    *   `lib/`: Modular libraries for the agent (monitoring, JSON handling, etc.).
    *   `tui/`: Python source code for the TUI.
*   `opencode-ralph*/`: Plugins for integrating Ralph directly into OpenCode.

## 🤝 Contributing

This is a distribution of the Ralph tooling ecosystem. Changes to the core logic should be made in `ralph-refactor/`.

## 📜 License

[MIT](LICENSE)
