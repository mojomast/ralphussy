# Ralph - Autonomous AI Coding Loop for OpenCode

Ralph is an implementation of the **Ralph Wiggum** autonomous coding methodology for OpenCode. It runs OpenCode in a continuous loop with real-time feedback, allowing it to work on tasks unsupervised until completion.

## What is Ralph?

Ralph is based on the observation that AI coding agents can achieve remarkable results when given the same prompt repeatedly. The key insight is:

> The AI doesn't talk to itself. It sees the same prompt each time, but the files have changed from previous iterations.

This creates a feedback loop where the AI iteratively improves its work until success.

## Features

- **Fresh Context Mode**: Each task starts with a clean context window for best code quality
- **Handoff System**: Automatic handoff.md files pass context between Ralph instances
- **Real-time Output**: Watch tool calls, API responses, and progress as they happen
- **Provider/Model Selection**: Choose which AI model to use
- **DevPlan Mode**: Work through development plan tasks iteratively
- **Task Batching**: Simple tasks are automatically batched together (max 3)
- **Auto-DevPlan Formatting**: Automatically converts various task formats to standard format
- **Token Tracking**: Monitor usage and costs per iteration
- **Auto-completion**: Detect when tasks are done via `<promise>TAG</promise>`
- **Stall Detection**: Automatically detects and marks stalled tasks with [🔄]

## Fresh Context + Handoff System

Ralph now uses a **fresh context model** to prevent context window bloat and ensure best code quality.

### How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Ralph #1      │────▶│   Ralph #2      │────▶│   Ralph #3      │
│                 │     │                 │     │                 │
│ • Fresh context │     │ • Fresh context │     │ • Fresh context │
│ • Read handoff  │     │ • Read handoff  │     │ • Read handoff  │
│ • Do Task 1     │     │ • Do Task 2     │     │ • Do Task 3     │
│ • Write handoff │     │ • Write handoff │     │ • Write handoff │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                      │                      │
         ▼                      ▼                      ▼
    handoff.md             handoff.md             handoff.md
    (for #2)               (for #3)               (for #4)
```

### Handoff File

After each task, Ralph creates a `handoff.md` file:

```markdown
# Ralph Handoff

**Created**: 2026-01-20T12:00:00Z
**DevPlan**: ./devplan.md

## Just Completed
- [completed task description]

## Next Task
- [next pending task]

## Context & Notes
[Important context for next Ralph]

## Important Files Modified
- file1.ts
- file2.py

## Instructions for Next Ralph
1. Read this handoff
2. Work on next task
3. Create new handoff when done
```

### Task Batching

Simple tasks (renames, small fixes, etc.) are automatically batched together:
- Maximum 3 tasks per batch
- Reduces API calls for trivial changes
- Tasks estimated as "simple" based on length and keywords

## Installation

### System-wide Install

```bash
# Install to ~/bin (already in PATH)
cp ralph ~/bin/ralph
chmod +x ~/bin/ralph

# Or to /usr/local/bin
sudo cp ralph /usr/local/bin/
sudo chmod +x /usr/local/bin/ralph

# Verify
ralph --help
```

### From Source

```bash
git clone https://github.com/anomalyco/opencode
cd opencode
./ralph --help
```

## Prerequisites

- **OpenCode** installed and in PATH
- **jq** for JSON processing (`sudo apt install jq` or `brew install jq`)
- **bash** 4.0+

## Quick Start

```bash
# Simple task
ralph "Create hello.txt with 'Hello World'. Output <promise>COMPLETE</promise> when done."

# With specific model
ralph "Build a REST API" --model zai-coding-plan/glm-4.7-flash

# Work on devplan tasks
ralph --devplan ./devplan.md --max-iterations 10
```

## Real-Time Output

Ralph shows what's happening as it happens:

```
[RALPH]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[RALPH]📊 Progress: 1/5 complete (20%) | Pending: 4
[RALPH]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📤 API REQUEST
   Provider: default
   Model: default
   Task: Create hello.txt

⏳ Waiting for API response...
📥 API RESPONSE received (15s)

🔧 Write    tmp/hello.txt
🔧 Read     tmp/hello.txt
💭 Verifying file contents...

[RALPH] ----------------------------------------
[RALPH] Provider/Model: opencode/default | Tokens: 123→456 (total: 579) | Cost: $0.01 | Duration: 15s
[RALPH] Tools used: Write Read
[RALPH] ----------------------------------------

📋 Handoff created: ./handoff.md
✅ Task completed: Create hello.txt
```

## Usage

### Basic Commands

```bash
# Simple task
ralph "Create a file. Output <promise>COMPLETE</promise> when done."

# From file
ralph --prompt-file task.txt

# With max iterations
ralph "Build something" --max-iterations 20
```

### Provider & Model Selection

```bash
# List available models
ralph --list-models

# List providers
ralph --list-providers

# Use specific provider and model
ralph "Your task" --provider opencode --model claude-sonnet-4-20250514
```

### DevPlan Mode

Work through tasks in a development plan file iteratively:

```bash
# Work on devplan.md tasks (default location)
ralph --devplan ./devplan.md

# With specific model
ralph --devplan ./devplan.md --model zai-coding-plan/glm-4.7-flash

# Limit number of tasks
ralph --devplan ./devplan.md --max-iterations 5
```

DevPlan format (devplan.md):
```markdown
### Phase 1: Setup

- [ ] Create project structure
- [ ] Initialize git repo
- [ ] Set up configuration

### Phase 2: Core Features

- [ ] Implement main functionality
- [ ] Add unit tests
```

Ralph will mark tasks as in-progress (⏳) and complete (✅) as it works.

### DevPlan Auto-Formatting

Ralph automatically converts various task formats to the standard format:

| Original | Converted To |
|----------|--------------|
| `- task name` | `- [ ] task name` |
| `- [x] task name` | `- [✅] task name` |
| `* task name` | `- [ ] task name` |
| `1. task name` | `- [ ] task name` |

A backup is created before formatting.

### Monitoring & Control

```bash
# Check status of active loop
ralph --status

# Add context/hints for next iteration
ralph --add-context "Focus on the auth module first"

# Clear pending context
ralph --clear-context
```

### Advanced Options

```bash
# Custom completion promise
ralph "Your task" --completion-promise "DONE"

# Verbose output (more details)
ralph "Your task" --verbose

# Set environment variables
export MODEL="claude-sonnet-4-20250514"
export MAX_ITERATIONS=50

# Task batching threshold (1=only trivial, 2=simple, 3=all)
export SIMPLE_TASK_THRESHOLD=2

# Handoff file location
export HANDOFF_FILE="./handoff.md"
```

## Writing Good Prompts

### ✅ Good Prompts

```
Build a REST API with:
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- Unit tests for each endpoint

Run tests after changes. Output <promise>COMPLETE</promise> when all tests pass.
```

```
Refactor auth.ts to:
1. Extract validation into separate functions
2. Add error handling for network failures
3. Ensure all existing tests still pass

Output <promise>DONE</promise> when refactored and tests pass.
```

### ❌ Bad Prompts

```
Build a todo API
```

```
Make the code better
```

## State Files

Ralph maintains state in `~/.ralph/`:

- `state.json` - Current loop state
- `history.json` - Iteration history and metrics
- `progress.md` - Append-only progress log
- `context.md` - Pending context for next iteration
- `handoffs/` - Archived handoff files
- `logs/iteration_*.log` - Detailed logs for each iteration
- `blockers.txt` - Active blockers for devplan tasks

## When to Use Ralph

**Good for:**
- Tasks with automatic verification (tests, linters)
- Well-defined tasks with clear completion criteria
- Greenfield projects where you can walk away
- Working through development plans
- Iterative refinement

**Not good for:**
- Tasks requiring human judgment
- One-shot operations
- Unclear success criteria
- Production debugging

## Architecture

```
ralph/
├── ralph              # Main CLI script
├── ralph.config       # Configuration file
└── README.md          # This file

~/.ralph/
├── state.json         # Current loop state
├── history.json       # Iteration history
├── progress.md        # Progress log
├── context.md         # Pending context
├── handoffs/          # Archived handoffs
│   └── handoff_*.md
└── logs/
    ├── iteration_001.log
    ├── iteration_002.log
    └── ...

./handoff.md           # Current handoff (project directory)
./devplan.md           # Development plan (project directory)
```

## Environment Variables

```bash
export MAX_ITERATIONS=50          # Maximum iterations
export COMPLETION_PROMISE="DONE"  # Completion tag
export VERBOSE=true               # Verbose output
export MODEL="claude-sonnet-4"    # Default model
export RALPH_DIR="$HOME/.ralph"   # State directory
export HANDOFF_FILE="./handoff.md" # Handoff file path
export SIMPLE_TASK_THRESHOLD=2    # Task batching threshold
```

## Troubleshooting

### "jq: command not found"

```bash
sudo apt install jq    # Ubuntu/Debian
brew install jq        # macOS
```

### OpenCode not found

```bash
curl -fsSL https://opencode.ai/install | bash
```

### Agent appears stuck

```bash
ralph --add-context "Try looking at the utils/parser.ts file"
```

### Task marked with [🔄] (needs review)

```bash
# View the handoff to see what happened
cat handoff.md

# Reset the task to try again
ralph --reset-task "Task name" --devplan ./devplan.md

# Or manually edit devplan.md: change [🔄] back to [ ]
```

## Examples

### Example 1: Create a File

```bash
ralph "Create greeting.txt with 'Hello, Ralph!'. Output <promise>COMPLETE</promise> when the file exists and contains the correct text."
```

### Example 2: Build a Python Project

```bash
ralph "Create a Flask app with:
- routes for /, /about, /contact
- proper error handling
- unit tests for each route
- requirements.txt

Run tests after changes. Output <promise>COMPLETE</promise> when all tests pass."
```

### Example 3: Work Through DevPlan

```bash
ralph --devplan ./devplan.md --max-iterations 10
```

### Example 4: Use Specific Model

```bash
ralph "Build a REST API" --provider anthropic --model claude-sonnet-4-20250514
```

### Example 5: Monitor Progress

```bash
# From another terminal
ralph --status              # Check loop status
ralph --devplan-summary     # Show devplan progress
cat handoff.md              # Read current handoff
```

## Learn More

- [Original Ralph Wiggum technique by Geoffrey Huntley](https://ghuntley.com/ralph/)
- [OpenCode Documentation](https://opencode.ai/docs)

## License

MIT License
