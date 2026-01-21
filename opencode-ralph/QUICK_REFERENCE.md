# Ralph Slash Commands for OpenCode - Quick Reference Card

## Available Slash Commands

| Command | Short | Description |
|---------|-------|-------------|
| `/ralph` | `/r` | Start autonomous loop |
| `/ralph-status` | `/rs` | Check current status |
| `/ralph-stop` | `/rq` | Stop running loop |
| `/ralph-context` | `/rc` | Add context to next iteration |
| `/ralph-clear` | `/rx` | Clear pending context |
| `/ralph-help` | `/rh` | Show this help |

## Quick Start in OpenCode

### 1. Enable Ralph Commands

```bash
# Source the commands (add to ~/.bashrc for persistence)
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### 2. Use in OpenCode Terminal

```
/ralph Build a REST API with CRUD operations.
        Output <promise>COMPLETE</promise> when all endpoints work.
```

### 3. Monitor Progress

```
/ralph-status
```

### 4. Control Running Loop

```
/ralph-context Focus on the authentication module first
/ralph-stop
```

## Usage Examples

### Example 1: Simple Task

```
/r Create a README.md with setup instructions.
   Output <promise>COMPLETE</promise> when the file exists.
```

### Example 2: Complex Task with Options

```
/ralph Build a todo API with:
       - Express.js backend
       - SQLite database
       - Unit tests
       
       Output <promise>COMPLETE</promise> when all tests pass.
       --max-iterations 20
```

### Example 3: Refactoring

```
/r Refactor the auth module to use TypeScript.
   Add proper error handling.
   Output <promise>DONE</promise> when refactoring complete.
   --completion-promise DONE
```

### Example 4: Adding Tests

```
/r Write unit tests for src/utils/date.ts.
   Cover all functions.
   Output <promise>TESTED</promise> when coverage > 90%.
```

## Writing Prompts

### Template

```
[TASK]
[REQUIREMENTS]
[SUCCESS CRITERIA]

Output <promise>COMPLETE</promise> when [conditions].
```

### Good Example

```
Build a REST API for managing users with:

Requirements:
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- JWT authentication

Success Criteria:
- All endpoints tested
- All tests pass
- Documentation complete

Output <promise>COMPLETE</promise> when all tests pass.
```

### Bad Example

```
❌ "Make the code better"
❌ "Fix the bugs"
❌ "Improve performance"
```

## Options

### --max-iterations N

```
/r "Your task" --max-iterations 50
```

Default: 100

### --completion-promise TAG

```
/r "Your task" --completion-promise DONE
```

Default: COMPLETE

## Monitoring

### Check Status

```
/rs
```

Shows:
- Current iteration
- Elapsed time
- Recent activity

### Add Context Mid-Loop

```
/rc Focus on fixing the authentication first
```

### Clear Context

```
/rx
```

## State Files

Ralph maintains state in `.ralph/`:

```
.ralph/
├── state.json       # Current loop state
├── history.json     # Iteration history
├── progress.md      # Progress log
├── context.md       # Pending context
└── logs/
    ├── iteration_001.log
    ├── iteration_002.log
    └── ...
```

## Troubleshooting

### Command Not Found

```bash
# Ensure Ralph is in PATH
export PATH="$HOME/.local/bin:$PATH"

# Re-source commands
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### Agent Appears Stuck

```bash
# Add guidance
/rc Try looking at the utils/parser.ts file first

# Or stop and restart with better prompt
/rq
/r "Your task with more specific requirements"
```

### Check What's Happening

```
/rs
cat .ralph/progress.md
cat .ralph/logs/iteration_*.log
```

## Advanced Usage

### Multiple Projects

```bash
# Project 1
cd /project/api && /r "Build API" &

# Project 2  
cd /project/web && /r "Build UI" &
```

### CI/CD Integration

```bash
#!/bin/bash
# Ralph in CI/CD

ralph "Fix all linting errors. Output <promise>LINT_CLEAN</promise> when eslint passes." \
  --max-iterations 10

if [ $? -eq 0 ]; then
    echo "✅ Linting passed"
    git add .
    git commit -m "Fix linting"
else
    echo "❌ Linting failed"
    exit 1
fi
```

### Custom Completion Signals

```
/r "Your task" --completion-promise "READY_FOR_REVIEW"
```

Then in your prompt:
```
Output <promise>READY_FOR_REVIEW</promise> when code is ready for review.
```

## Files

```
/home/mojo/projects/opencode2/opencode-ralph/
├── ralph-integrated        # Main Ralph script
├── ralph-commands.sh       # Slash command functions
├── slash-commands.sh       # Command definitions
├── setup-slash-commands.sh # Setup script
├── SLASH_COMMANDS.md       # Full documentation
└── README.md               # Plugin documentation
```

## See Also

- [Full Documentation](/home/mojo/projects/opencode2/opencode-ralph/SLASH_COMMANDS.md)
- [Prompt Examples](/home/mojo/projects/opencode2/opencode-ralph/examples/prompts.md)
- [OpenCode Docs](/docs)