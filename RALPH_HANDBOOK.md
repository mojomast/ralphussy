# Ralph Mode for OpenCode - Handoff Document

## Overview

Ralph is an autonomous AI coding loop agent for OpenCode. It iteratively runs OpenCode with the same prompt until completion, allowing unsupervised coding tasks to complete automatically.

## What Was Accomplished

### 1. Fresh Context + Handoff System (NEW)

Ralph now uses a **fresh context model** to prevent context window bloat and ensure best code quality.

#### Fresh Context Model

Each Ralph instance starts with a clean context window. Knowledge from previous work comes only from:
1. The `handoff.md` file (written by previous Ralph)
2. The `devplan.md` file (tracks all tasks)
3. Git history and current file contents

This prevents context pollution and ensures best code quality.

#### Handoff System

After each task, Ralph creates a `handoff.md` file for the next Ralph:

```markdown
# Ralph Handoff

**Created**: 2026-01-20T12:00:00Z
**DevPlan**: ./devplan.md

## Just Completed
- [task name]

## Next Task
- [next task from devplan]

## Context & Notes
[Important notes for next Ralph]

## Important Files Modified
- file1.ts
- file2.py

## Current DevPlan Status
```
- [✅] Task 1
- [ ] Task 2 (next)
```

## Instructions for Next Ralph
1. Read this handoff to understand context
2. Read the devplan at: $devfile
3. Work on the next task
4. Create new handoff when done
5. Output <promise>COMPLETE</promise> when task is done
```

#### Handoff Functions

| Function | Purpose |
|----------|---------|
| `create_handoff()` | Creates handoff.md with context for next Ralph |
| `read_handoff()` | Reads existing handoff content |
| `has_handoff()` | Checks if handoff exists |
| `archive_handoff()` | Archives old handoffs to `~/.ralph/handoffs/` |

#### Updated Agent Prompt

The Ralph agent prompt now includes:

```
You are Ralph, an autonomous coding agent with FRESH CONTEXT for each task.

## CRITICAL: Fresh Context Model
You start each task with a clean context window to ensure best code quality.
Your knowledge of previous work comes ONLY from:
1. The handoff.md file (written by previous Ralph)
2. The devplan.md file (tracks all tasks)
3. Git history and file contents

## Your Workflow
1. FIRST: Read handoff.md if it exists - this contains context from previous Ralph
2. Read devplan.md to find your current task (first `- [ ]` item)
3. Complete the task thoroughly with high-quality code
4. Update devplan.md: change `- [ ]` to `- [✅]` for completed task
5. Create/update handoff.md for the NEXT Ralph with:
   - What you just completed
   - Important context for next task
   - Any issues or notes
6. Output `<promise>COMPLETE</promise>` when YOUR task is done
```

### 2. OpenCode Command Files

**Location:** `~/.config/opencode/commands/` and `.opencode/commands/`

Created command files for Ralph functionality:
- `ralph.md` - Main command to start autonomous loop
- `ralph-status.md` - Check loop status
- `ralph-stop.md` - Stop running loop
- `ralph-context.md` - Add guidance mid-loop
- `ralph-clear.md` - Clear pending context
- `ralph-help.md` - Show help

These commands are globally available in any directory.

### 3. Slash Commands Plugin

**Location:** `opencode-ralph-slash/`

Built a TypeScript plugin that provides:
- Ralph agent tools (`ralph`, `ralphStatus`, `ralphStop`, etc.)
- Agent-specific chat parameters (temperature 0.1, topP 0.95)
- System prompt transformation for Ralph mode

**Build:**
```bash
cd opencode-ralph-slash
npm install && npm run build
```

Output: `dist/index.js` (8KB compiled plugin)

### 4. Ralph CLI Script

**Location:** `~/.local/bin/ralph` and `/home/mojo/projects/opencode2/ralph`

Fixed and adapted the Ralph autonomous loop script to work with OpenCode.

**Key Features:**
- Runs OpenCode in JSON format mode for script integration
- Iterates until `<promise>COMPLETE</promise>` is detected
- Tracks iteration history in `~/.ralph/history.json`
- Logs progress to `~/.ralph/progress.md`
- Struggle detection when no file modifications occur
- Context injection between iterations
- **Fresh context mode** - clean context per task
- **Handoff system** - passes context between Ralph instances
- **DevPlan integration** - Works through devplan.md tasks iteratively
- **Task batching** - automatically groups simple tasks together
- **DevPlan auto-formatting** - converts various formats to standard
- **Stalled task detection** - Automatically detects and marks blocked tasks
- **Blocker tracking** - Records and displays blockers with 🚫 emoji
- **Documentation updates** - Auto-updates docs/progress.md with progress
- **API indicators** - Shows request/response status

**Usage:**
```bash
ralph "Your task. Output <promise>COMPLETE</promise> when done."
ralph "Build a REST API" --max-iterations 20
ralph --status
ralph --add-context "Focus on authentication first"
```

**DevPlan Usage:**
```bash
ralph --devplan ./devplan.md                    # Work through devplan tasks
ralph --devplan-summary                         # Show devplan progress summary
ralph --reset-task "Task name" --devplan ./devplan.md  # Reset stalled task
```

### 5. Task Batching (NEW)

Simple tasks are automatically batched together to reduce API calls:

```bash
# Task batching configuration
export SIMPLE_TASK_THRESHOLD=2  # 1=only trivial, 2=simple (default), 3=off
```

**What gets batched:**
- Short tasks (less than 50 characters)
- Tasks starting with: update, fix, rename, add comment, remove, delete, change, set, toggle
- Maximum 3 tasks per batch

### 6. DevPlan Auto-Formatting (NEW)

Ralph automatically converts various task list formats to the standard format:

| Original Format | Converted To |
|-----------------|--------------|
| `- task name` | `- [ ] task name` |
| `- [x] task name` (GitHub style) | `- [✅] task name` |
| `- [X] task name` | `- [✅] task name` |
| `* task name` (bullets) | `- [ ] task name` |
| `1. task name` (numbered) | `- [ ] task name` |

A backup is created at `devplan.md.bak` before formatting.

### 7. OpenCode Configuration

**Location:** `~/.config/opencode/opencode.jsonc`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "ralph": {
      "description": "Autonomous loop agent - iterates until task completion",
      "prompt": "You are Ralph, an autonomous coding agent with FRESH CONTEXT for each task.\n\n## CRITICAL: Fresh Context Model\nYou start each task with a clean context window...\n\n## Your Workflow\n1. FIRST: Read handoff.md if it exists...\n2. Read devplan.md to find your current task...\n3. Complete the task thoroughly...\n4. Update devplan.md: change `- [ ]` to `- [✅]`...\n5. Create/update handoff.md for the NEXT Ralph...\n6. Output `<promise>COMPLETE</promise>` when YOUR task is done...",
      "temperature": 0.1,
      "topP": 0.95
    }
  }
}
```

### 8. Ralph State Directory

**Location:** `~/.ralph/`

State files maintained by Ralph:
- `state.json` - Current loop state
- `history.json` - Iteration history and metrics
- `progress.md` - Progress log
- `context.md` - Pending context for next iteration
- `handoffs/` - Archived handoff files (NEW)
- `logs/iteration_*.log` - Detailed logs for each iteration
- `blockers.txt` - Active blockers for devplan tasks

### 9. DevPlan Integration

Ralph can work through tasks in a devplan.md file iteratively.

**DevPlan Format:**
```markdown
### Phase 1: Setup

- [ ] Create project structure
- [ ] Initialize git repo

### Phase 2: Core Features

- [ ] Implement main functionality
- [ ] Add unit tests
```

**Task States:**
| State | Marker | Meaning |
|-------|--------|---------|
| Pending | `[ ]` | Not started |
| In Progress | `[⏳]` | Currently working |
| Complete | `[✅]` | Done successfully |
| Needs Review | `[🔄]` | Stalled/blocked |

**How Ralph Handles DevPlan:**
1. Reads handoff.md if exists (NEW)
2. Reads next pending task from devplan.md
3. Marks task as [⏳] in progress (NEW: may batch simple tasks)
4. Runs OpenCode with task as prompt (NEW: includes fresh context instructions)
5. Marks complete with [✅] or stalled with [🔄]
6. Creates handoff.md for next Ralph (NEW)
7. Continues to next task automatically
8. Updates documentation at `docs/progress.md`

### 10. Stalled Task Detection

Ralph automatically detects when tasks are stuck and marks them for review.

**Stall Indicators:**
- No file modifications (Write/Edit) after Bash command
- Error messages in output ("cannot", "error", "failed", "not found")
- Commands that timeout
- No completion promise

**Detection Logic:**
Requires 2+ indicators to mark as stalled.

**When Stall Detected:**
- Task marked with `[🔄]` (needs review)
- Recorded in `~/.ralph/blockers.txt`
- Logged to `docs/progress.md`
- Displayed with `ralph --status`
- Skipped - Ralph continues with next task
- Handoff created noting the stall (NEW)

### 11. Blocker Tracking

**Blocker Emoji:** 🚫

Ralph detects and records blockers during task execution:

**Detected Blockers:**
- Command not found errors
- Permission denied
- Missing dependencies
- Cannot proceed messages
- Any "blocked" or "failed" language

**Blocker Files:**
- `~/.ralph/blockers.txt` - Active blockers log
- `docs/progress.md` - Full progress with blockers

**View Blockers:**
```bash
ralph --status              # Shows active blockers
ralph --devplan-summary     # Shows blockers for devplan tasks
```

### 12. Documentation Updates

Ralph automatically updates documentation:

**Files Updated:**
- `~/.ralph/progress.md` - Iteration progress log
- `docs/progress.md` - Full project progress (if exists)

**Logged Events:**
- ✅ Task completed
- 📋 Handoff created (NEW)
- 🔄 Task stalled
- 🚫 Blocker detected
- ⚠️ Task incomplete

**Custom Docs Path:**
```bash
DOCS_PATH="./PROJECT/docs/status.md" ralph --devplan ./devplan.md
```

## Architecture

### Main Ralph Loop

```
┌─────────────────────────────────────────────────────────────┐
│                     Ralph Loop Cycle                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. User provides task prompt with <promise>TAG</promise>    │
│                          ↓                                   │
│  2. Check for handoff.md (read context if exists)           │
│                          ↓                                   │
│  3. Ralph runs: opencode run --format json "prompt"         │
│                          ↓                                   │
│  4. Parse JSON output, extract text and tools used          │
│                          ↓                                   │
│  5. Check for <promise>TAG</promise> in output              │
│                          ↓                                   │
│  6. If found → Success                                      │
│     - Create handoff.md (NEW)                               │
│     - Return                                                │
│     If not found → Continue to next iteration               │
│     - Record iteration in history.json                      │
│     - Check for struggle (no file changes)                  │
│     - Detect blockers and stalled tasks                     │
│     - Update documentation                                  │
│     - Read context.md for guidance                          │
│     - Repeat with same prompt                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### DevPlan Mode Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Ralph DevPlan Cycle                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Read handoff.md if exists (NEW)                         │
│                          ↓                                   │
│  2. Read next pending task from devplan.md                  │
│                          ↓                                   │
│  3. Check if task is simple enough to batch (NEW)           │
│     - If yes: batch up to 3 simple tasks                    │
│     - If no: single task                                    │
│                          ↓                                   │
│  4. Mark task(s) as [⏳] in progress                        │
│                          ↓                                   │
│  5. Run OpenCode with task(s) as prompt                     │
│     (NEW: includes fresh context instructions)              │
│                          ↓                                   │
│  6. Check result:                                           │
│     - Complete? → Mark [✅], create handoff, next task      │
│     - Stalled? → Mark [🔄], record blocker, next task       │
│     - Incomplete? → Continue (retry or add context)         │
│                          ↓                                   │
│  7. Update: progress.md, docs/progress.md, blockers.txt     │
│  8. Archive old handoff, create new handoff (NEW)           │
│                          ↓                                   │
│  9. Repeat until all tasks complete or max iterations       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Fresh Context Flow

```
Ralph #1                      Ralph #2                      Ralph #3
   │                             │                             │
   ├─▶ Read handoff.md (none)    │                             │
   ├─▶ Do Task 1                 │                             │
   ├─▶ Mark [✅]                 │                             │
   ├─▶ Create handoff.md ────────┼────────────────────────────▶│
   │                             │                             │
   │                             ├─▶ Read handoff.md           │
   │                             ├─▶ Do Task 2                 │
   │                             ├─▶ Mark [✅]                 │
   │                             ├─▶ Create handoff.md ────────┼─▶
   │                             │                             │
   │                             │                             ├─▶ Read handoff.md
   │                             │                             ├─▶ Do Task 3
   │                             │                             └─▶ ...
```

## How Ralph Works

### The Key Insight

Ralph is based on the observation that AI coding agents achieve remarkable results when given the same prompt repeatedly. The key insight:

> The AI doesn't talk to itself. It sees the same prompt each time, but the files have changed from previous iterations.

This creates a feedback loop where the AI iteratively improves its work until success.

### Fresh Context Model (NEW)

The fresh context model is a key enhancement:

1. **Problem**: Long-running AI sessions accumulate context, leading to:
   - Degraded code quality
   - Incoherent responses
   - Confusion about what was already done

2. **Solution**: Each task gets a fresh start:
   - Context is passed via handoff.md (text file, not context window)
   - Ralph only sees what's in handoff.md + devplan.md + files
   - Task completion is immediate, not delayed by context issues

3. **Benefits**:
   - Best code quality per task
   - No context window bloat
   - Explicit knowledge transfer between sessions
   - Audit trail of all work done

### Writing Good Prompts

✅ **Good:**
```
Build a REST API with:
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- Unit tests for each endpoint

Run tests after each change.
Output <promise>COMPLETE</promise> when all tests pass.
```

❌ **Bad:**
```
Build a todo API
```

### Prompt Structure

```
[TASK DESCRIPTION]
[REQUIREMENTS]
[SUCCESS CRITERIA]

Output <promise>TAG</promise> when [specific conditions met].
```

## Commands Reference

### Starting Ralph

```bash
# Basic usage
ralph "Create a hello.txt file. Output <promise>COMPLETE</promise> when done."

# With options
ralph "Build a REST API with tests" --max-iterations 20
ralph "Refactor auth module" --completion-promise DONE

# DevPlan mode
ralph --devplan ./devplan.md
ralph --devplan ./devplan.md --max-iterations 50
```

### DevPlan Commands

```bash
ralph --devplan ./devplan.md              # Work through devplan tasks
ralph --devplan-summary                    # Show devplan task summary
ralph --reset-task "Task name" --devplan ./devplan.md  # Reset stalled task
```

### Monitoring & Control

```bash
# Check status (from another terminal)
ralph --status

# Add guidance mid-loop
ralph --add-context "Focus on the authentication module first"

# Clear pending context
ralph --clear-context

# Read current handoff (NEW)
cat handoff.md
```

### Ralph Slash Commands (in OpenCode TUI)

```
/ralph "Task description"     - Start autonomous loop
/ralph-status                 - Check loop status
/ralph-stop                   - Stop running loop
/ralph-context "message"      - Add context
/ralph-clear                  - Clear context
/ralph-help                   - Show help
```

## File Locations Summary

| Item | Location |
|------|----------|
| Ralph CLI | `/usr/local/bin/ralph` or `~/.local/bin/ralph` |
| Ralph script (project) | `/home/mojo/projects/opencode2/ralph` |
| Slash commands plugin | `opencode-ralph-slash/dist/index.js` |
| OpenCode commands | `~/.config/opencode/commands/*.md` |
| OpenCode config | `~/.config/opencode/opencode.jsonc` |
| Ralph state | `~/.ralph/` |
| Current handoff | `./handoff.md` (project directory) |
| Archived handoffs | `~/.ralph/handoffs/` |
| Progress docs | `docs/progress.md` (or custom) |

## Configuration

### Environment Variables

```bash
# Max iterations
export MAX_ITERATIONS=50

# Completion promise text
export COMPLETION_PROMISE="DONE"

# Verbose mode
export VERBOSE=true

# Model to use
export MODEL="opencode/claude-opus-4-5"

# State directory
export RALPH_DIR="$HOME/.ralph"

# DevPlan file
export DEVPATH="./devplan.md"

# Handoff file (NEW)
export HANDOFF_FILE="./handoff.md"

# Task batching threshold (NEW)
# 1=only trivial, 2=simple (default), 3=off
export SIMPLE_TASK_THRESHOLD=2

# Documentation path
export DOCS_PATH="./docs/progress.md"
```

### OpenCode Config (`~/.config/opencode/opencode.jsonc`)

```json
{
  "agent": {
    "ralph": {
      "description": "Autonomous loop agent",
      "prompt": "You are Ralph, an autonomous coding agent with FRESH CONTEXT...",
      "temperature": 0.1,
      "topP": 0.95
    }
  }
}
```

## Troubleshooting

### "Agent appears to be struggling"

**Cause:** No file modifications in recent iterations.

**Solution:** Add context:
```bash
ralph --add-context "Try a different approach: focus on core functionality first"
```

### "Task marked for review (stalled)"

**Cause:** Ralph detected the task was stuck (errors, timeouts, no progress).

**Solution:**
```bash
# View handoff to understand what happened
cat handoff.md

# View blockers
ralph --status

# Check what went wrong in progress log
cat ~/.ralph/progress.md

# Reset the task to try again
ralph --reset-task "Task name" --devplan ./devplan.md

# Or manually edit devplan.md: change [🔄] back to [ ]
```

### Task shows "Blocked" with 🚫

**Cause:** Ralph detected a blocker (command not found, permission denied, etc.).

**Solution:**
```bash
# View blocker details
ralph --status

# Check handoff for context
cat handoff.md

# Fix the issue (install dependency, fix permissions, etc.)

# Reset the task
ralph --reset-task "Task name" --devplan ./devplan.md
```

### No handoff.md after task

**Cause:** Task might have failed before handoff creation.

**Solution:** Check:
- `~/.ralph/progress.md` for error logs
- `~/.ralph/logs/` for detailed iteration logs
- The task might have been in a non-devplan run

### Task batching not working

**Cause:** Tasks might be too complex to batch.

**Solution:**
```bash
# Check task complexity threshold
export SIMPLE_TASK_THRESHOLD=2  # Increase to batch more tasks

# Or manually batch tasks in devplan.md:
# - [ ] Simple task 1
# - [ ] Simple task 2
# - [ ] Simple task 3
```

### OpenCode model not found

**Cause:** Invalid model name in config or MODEL variable.

**Solution:** Use available models:
```bash
opencode models
# Then use a valid model name
```

### Command not found

**Cause:** `ralph` not in PATH.

**Solution:** Ensure `~/.local/bin` is in PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
# Add to ~/.bashrc for persistence
```

## When to Use Ralph

**Good for:**
- Tasks with automatic verification (tests, linters, type checking)
- Well-defined tasks with clear completion criteria
- Greenfield projects where you can walk away
- Iterative refinement (getting tests to pass)
- Working through devplan.md task lists
- Long-running projects (fresh context prevents degradation)

**Not good for:**
- Tasks requiring human judgment
- One-shot operations
- Unclear success criteria
- Production debugging

## Examples

### Example 1: Create a Simple File

```bash
ralph "Create a file called greeting.txt with 'Hello, Ralph!' on line 1. Output <promise>COMPLETE</promise> when the file exists and contains the correct text."
```

### Example 2: Build a Python Project

```bash
ralph "Create a Python Flask app with:
- routes for /, /about, /contact
- proper error handling
- unit tests for each route
- requirements.txt

Run tests after changes. Output <promise>COMPLETE</promise> when all tests pass."
```

### Example 3: Refactoring Task

```bash
ralph "Refactor the authentication module:
1. Extract user validation into separate functions
2. Add proper error messages for all failure cases
3. Ensure all existing tests still pass
4. Add logging for security-relevant events

Output <promise>DONE</promise> when refactoring is complete."
```

### Example 4: DevPlan Mode

```bash
# Create devplan.md first
cat > devplan.md << 'EOF'
### Phase 1: Setup
- [ ] Initialize npm project
- [ ] Install dependencies

### Phase 2: Core
- [ ] Create main module
- [ ] Add unit tests

### Phase 3: Integration
- [ ] Create API endpoints
- [ ] Test end-to-end
EOF

# Run Ralph on devplan
ralph --devplan ./devplan.md

# Check progress
ralph --devplan-summary

# Read handoff to see current state
cat handoff.md
```

### Example 5: Handle Blocked Tasks

```bash
# During devplan run, task gets blocked
# Ralph marks it with [🔄] and continues

# Check handoff to understand context
cat handoff.md

# Check status to see blockers
ralph --status
# Output shows: 🚫 Blocked: Task name - "python: command not found"

# Fix the issue
sudo apt install python3

# Reset the blocked task
ralph --reset-task "Task name" --devplan ./devplan.md

# Continue
ralph --devplan ./devplan.md
```

### Example 6: Monitor Fresh Context Handoff

```bash
# Start a devplan run
ralph --devplan ./devplan.md &

# From another terminal, watch the handoff evolve
watch -n 1 "cat handoff.md"

# You'll see:
# - "Just Completed" update after each task
# - "Next Task" change to next pending item
# - "Context & Notes" accumulate important info
```

## Recent Improvements (January 2026)

1. **Fresh Context Model**
   - Each task starts with clean context window
   - Prevents context pollution and degradation
   - Ensures best code quality per task

2. **Handoff System**
   - Automatic handoff.md creation after each task
   - Archives old handoffs to `~/.ralph/handoffs/`
   - Explicit knowledge transfer between sessions

3. **Task Batching**
   - Simple tasks automatically batched together
   - Reduces API calls for trivial changes
   - Configurable threshold (`SIMPLE_TASK_THRESHOLD`)

4. **DevPlan Auto-Formatting**
   - Converts various formats to standard
   - Creates backup before formatting
   - Supports: `- task`, `- [x]`, `*`, `1.`

5. **API Indicators**
   - Shows `📤 API REQUEST` with details
   - Shows `⏳ Waiting for API response...`
   - Shows `📥 API RESPONSE received`

6. **Improved Prompts**
   - Agent prompt includes handoff instructions
   - DevPlan mode prompts include fresh context reminder
   - Quality standards emphasized

7. **Bug Fixes**
   - Fixed sed replacement commands (removed stray `^`)
   - Added `escape_sed_pattern()` for special characters
   - Fixed indentation handling for nested tasks

## Future Improvements

Potential enhancements that could be made:

1. **Server Mode Integration:** Use `opencode serve` for faster repeated calls
2. **Better Struggle Detection:** Analyze error patterns, not just tool usage
3. **Progress Indicators:** Show detailed progress during iterations
4. **Parallel Loops:** Run multiple Ralph instances in different directories
5. **Plugin Integration:** Use the slash commands plugin for in-TUI control
6. **Auto-retry Blockers:** Automatically retry tasks after fixing common blockers
7. **Handoff Diff:** Show what changed between handoffs
8. **Context Metrics:** Track context window usage

## References

- [OpenCode Commands Documentation](https://opencode.ai/docs/commands/)
- [OpenCode Configuration](https://opencode.ai/docs/config/)
- [Ralph Wiggum Methodology](https://ghuntley.com/ralph/)
- Original Ralph implementation: `ralph` script in this project
