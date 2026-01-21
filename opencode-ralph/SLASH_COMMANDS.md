# Ralph Agent Mode Configuration for OpenCode

## Installation

### 1. Install Ralph Script

```bash
# Copy Ralph script to PATH
cp /home/mojo/projects/opencode2/opencode-ralph/ralph-integrated ~/.local/bin/ralph
chmod +x ~/.local/bin/ralph

# Source Ralph commands (add to ~/.bashrc or ~/.bash_profile)
echo "source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh" >> ~/.bashrc
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### 2. Configure OpenCode Agent

Create or update `opencode.json` in your project:

```json
{
  "agents": {
    "ralph": {
      "name": "Ralph",
      "description": "Autonomous loop agent - iterates until task completion",
      "command": "ralph",
      "temperature": 0.1,
      "systemPrompt": "You are Ralph, an autonomous coding agent. You work iteratively on tasks, outputting <promise>COMPLETE</promise> when done."
    }
  }
}
```

### 3. Enable Slash Commands

Ralph slash commands work by sourcing the commands file. In OpenCode's terminal:

```bash
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

Or add to your shell profile for permanent enablement.

## Usage in OpenCode

### Starting Ralph Mode

```
/ralph Build a REST API for todos with CRUD operations and tests.
        Output <promise>COMPLETE</promise> when all tests pass.
```

### Monitoring

```
/ralph-status   (or /rs)
```

### Controlling

```
/ralph-stop     (or /rq)  - Stop running loop
/ralph-context  (or /rc)  - Add context mid-loop
/ralph-clear    (or /rx)  - Clear pending context
/ralph-help     (or /rh)  - Show help
```

### With Options

```
/ralph "Your task" --max-iterations 20 --completion-promise DONE
```

## Slash Command Reference

| Command | Alias | Description |
|---------|-------|-------------|
| `/ralph` | `/r` | Start autonomous loop |
| `/ralph-status` | `/rs` | Check current status |
| `/ralph-stop` | `/rq` | Stop running loop |
| `/ralph-context` | `/rc` | Add context to next iteration |
| `/ralph-clear` | `/rx` | Clear pending context |
| `/ralph-help` | `/rh` | Show help |

## Configuration Options

### Environment Variables

```bash
# Default max iterations
export RALPH_MAX_ITERATIONS=100

# Default completion promise
export RALPH_COMPLETION_PROMISE="COMPLETE"

# State directory
export RALPH_DIR=".ralph"
```

### OpenCode Config

```json
{
  "ralph": {
    "maxIterations": 100,
    "completionPromise": "COMPLETE",
    "temperature": 0.1,
    "autoCommit": true
  }
}
```

## Writing Effective Prompts

### Good Prompt Structure

```
[TASK DESCRIPTION]
[REQUIREMENTS]
[SUCCESS CRITERIA]

Output <promise>COMPLETE</promise> when [specific conditions met].
```

### Example Prompt

```
Build a REST API for managing todos with:

## Requirements
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- Unit tests for each endpoint

## Success Criteria
- All endpoints return correct status codes
- All tests pass (>90% coverage)
- Proper error handling

Run tests after each change.
Output <promise>COMPLETE</promise> when all tests pass.
```

### Tips

1. **Be Specific**: Clear requirements and success criteria
2. **Include Verification**: How to verify completion
3. **Set Limits**: Prevent runaway loops with `--max-iterations`
4. **Use Progress Files**: Track iteration-by-iteration
5. **Inject Context**: Guide struggling agents

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
    └── iteration_002.log
```

## Troubleshooting

### Command Not Found

Ensure Ralph is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Slash Commands Not Working

Source the commands file:

```bash
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### Agent Appears Stuck

Add context to guide it:

```
/ralph-context Try a different approach: focus on the core functionality first
```

### Check Status

```
/ralph-status
```

## Advanced Usage

### Multiple Concurrent Loops

Run Ralph in separate directories:

```bash
cd /project/api && ralph "Build API" &
cd /project/web && ralph "Build UI" &
```

### Custom Completion Signals

```bash
/ralph "Your task" --completion-promise "DONE"
```

Then in your prompt: `Output <promise>DONE</promise> when complete.`

### Integration with CI/CD

```bash
#!/bin/bash
# CI/CD script using Ralph

ralph "Fix all linting errors. Output <promise>LINT_CLEAN</promise> when eslint passes." --max-iterations 10

if [ $? -eq 0 ]; then
    echo "✅ Linting passed"
    exit 0
else
    echo "❌ Linting failed after max iterations"
    exit 1
fi
```

## Examples

### Example 1: Create File

```
/ralph Create greeting.txt with "Hello, Ralph!" on line 1.
        Output <promise>COMPLETE</promise> when done.
```

### Example 2: Build Feature

```
/ralph Implement user authentication with JWT.
        Include login, logout, and registration endpoints.
        Output <promise>AUTH_READY</promise> when all endpoints work.
```

### Example 3: Refactor Code

```
/ralph Refactor the utils module:
        1. Extract pure functions
        2. Add JSDoc comments
        3. Write unit tests
        
All existing tests must pass.
Output <promise>REFACTORED</promise> when complete.
```

### Example 4: Add Tests

```
/ralph Add unit tests for src/api/users.ts.
        Cover all CRUD operations.
        Output <promise>TESTED</promise> when coverage > 90%.
```

## See Also

- [Ralph README](/home/mojo/projects/opencode2/opencode-ralph/README.md)
- [Prompt Examples](/home/mojo/projects/opencode2/opencode-ralph/examples/prompts.md)
- [OpenCode Documentation](/docs)