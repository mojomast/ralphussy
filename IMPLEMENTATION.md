# Ralph Implementation Summary

## Overview

This repository contains a complete implementation of **Ralph**, an autonomous AI coding loop methodology for OpenCode. Ralph enables developers to run OpenCode in continuous loops, allowing it to work on complex tasks unsupervised until completion.

## What is Ralph?

Ralph is based on the **Ralph Wiggum** technique, named after the character from The Simpsons who famously says "I didn't do it" while clearly having done it. The methodology works by:

1. **Same Prompt, Repeated**: The AI receives the same prompt each iteration
2. **File-based Memory**: Files and git history serve as memory (not model context)
3. **Self-Correction**: AI sees previous work and test results, enabling fixes
4. **Persistence**: Tasks can run for hours/days until completion
5. **Autonomy**: No human intervention required between iterations

## Key Files

### Core Implementation

- **ralph** - Main bash CLI implementation for Linux/macOS
- **ralph.ps1** - PowerShell implementation for Windows
- **ralph.config** - Configuration file for customization

### Installation & Testing

- **install.sh** - Bash installation script
- **install.ps1** - PowerShell installation script for Windows
- **test.sh** - Comprehensive test suite
- **completion.bash** - Bash completion script

### Documentation

- **README.md** - Complete documentation
- **examples/rest-api-project.md** - Step-by-step tutorial
- **examples/prompts.md** - Collection of example prompts

## Quick Start

### Installation

```bash
# Option 1: Download directly
curl -fsSL https://raw.githubusercontent.com/anomalyco/opencode/main/ralph -o ralph
chmod +x ralph
sudo mv ralph /usr/local/bin/

# Option 2: Clone and install
git clone https://github.com/anomalyco/opencode
cd opencode
./install.sh

# Option 3: From source
./ralph --help
```

### Basic Usage

```bash
# Simple task
ralph "Create a hello.txt file with 'Hello World'. Output <promise>COMPLETE</promise> when done."

# Complex task with iterations
ralph "Build a REST API with CRUD endpoints and tests. Output <promise>COMPLETE</promise> when all tests pass." --max-iterations 20

# From prompt file
ralph --prompt-file task.txt

# Monitor progress
ralph --status

# Add guidance mid-loop
ralph --add-context "Focus on the authentication module first"
```

## Features

### Core Features

- **Autonomous Loop**: Runs OpenCode repeatedly until completion
- **State Persistence**: Maintains state across iterations
- **Progress Tracking**: Detailed logs and progress reports
- **Struggle Detection**: Identifies when agent gets stuck
- **Context Injection**: Guide agents mid-loop without stopping
- **Multi-platform**: Works on Linux, macOS, and Windows

### Monitoring & Control

- **Status Dashboard**: Real-time loop status (`ralph --status`)
- **Iteration History**: Track all iterations with timing and tools
- **Progress Log**: Append-only progress documentation
- **Context Management**: Add hints for next iteration
- **Struggle Indicators**: Automatic detection of stuck agents

### Advanced Features

- **Custom Completion Promises**: Define what "done" looks like
- **Model Selection**: Choose specific AI models
- **Max Iterations**: Safety limits for runaway loops
- **Verbose Mode**: Detailed output for debugging
- **Configuration Files**: Customizable behavior

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Ralph Loop Cycle                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Send prompt to OpenCode                                 │
│                    ↓                                        │
│  2. OpenCode works on task, modifies files                  │
│                    ↓                                        │
│  3. Ralph checks for completion promise                     │
│                    ↓                                        │
│  4. If not complete: repeat with same prompt                │
│     If complete: stop and report success                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Architecture

### State Files (`~/.ralph/`)

- **state.json** - Current loop state and iteration count
- **history.json** - All iteration history with metrics
- **progress.md** - Append-only progress log
- **context.md** - Pending context for next iteration
- **logs/iteration_*.log** - Detailed logs for each iteration

### Key Components

1. **Loop Engine**: Handles iteration logic and completion checking
2. **State Manager**: Persists and retrieves loop state
3. **Context Manager**: Handles mid-loop context injection
4. **Progress Tracker**: Records all activity and metrics
5. **Struggle Detector**: Identifies when agent needs help

## Writing Effective Prompts

### ✅ Good Prompt Structure

```
[Task Description]
[Requirements]
[Success Criteria]
[Verification Steps]
Output <promise>COMPLETE</promise> when [specific conditions].
```

### Example Prompt

```
Build a REST API for todos with:
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- Unit tests for each endpoint

Run tests after each change.
Output <promise>COMPLETE</promise> when all tests pass.
```

### Tips for Success

1. **Be Specific**: Clear requirements and success criteria
2. **Include Verification**: How to verify completion
3. **Set Iteration Limits**: Prevent runaway loops
4. **Use Progress Files**: Track iteration-by-iteration progress
5. **Inject Context**: Guide struggling agents

## Use Cases

### ✅ Good For

- Building new features with tests
- Refactoring codebases
- Creating documentation
- Setting up Docker/infrastructure
- Writing test suites
- Any task with clear success criteria

### ❌ Not Good For

- Tasks requiring human judgment
- One-shot operations
- Unclear success criteria
- Production debugging

## Integration

### OpenCode Server Mode

For faster performance, run OpenCode server:

```bash
# Terminal 1: Start OpenCode server
opencode serve

# Terminal 2: Run Ralph (configure to use server)
ralph "Your task"
```

### Configuration

Edit `ralph.config` or use environment variables:

```bash
export MAX_ITERATIONS=50
export COMPLETION_PROMISE="DONE"
export VERBOSE=true
export MODEL="claude-sonnet-4-20250514"
```

## Testing

Run the test suite:

```bash
# Run all tests
./test.sh

# Test specific script
RALPH_SCRIPT=/usr/local/bin/ralph ./test.sh

# Test with verbose output
./test.sh --verbose
```

## Troubleshooting

### Common Issues

**"jq: command not found"**
```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq
```

**"opencode: command not found"**
```bash
curl -fsSL https://opencode.ai/install | bash
```

**Agent appears stuck**
```bash
# Check status
ralph --status

# Add guidance
ralph --add-context "Try looking at the utils/parser.ts file"
```

### Debug Mode

```bash
# Verbose output
ralph "Your task" --verbose

# Check logs
cat ~/.ralph/logs/iteration_*.log

# Check progress
cat ~/.ralph/progress.md
```

## Examples

### Example 1: Simple File Creation

```bash
ralph "Create a greeting.txt file with 'Hello, Ralph!'. Output <promise>COMPLETE</promise> when the file exists and contains the correct text."
```

### Example 2: REST API Development

```bash
ralph "Build a REST API for managing todos. Include CRUD operations, input validation, and unit tests. Output <promise>COMPLETE</promise> when all tests pass." --max-iterations 25
```

### Example 3: Code Refactoring

```bash
ralph "Refactor the authentication module to use the singleton pattern. Add proper error handling and logging. Ensure all existing tests still pass. Output <promise>DONE</promise> when complete." --max-iterations 15
```

## Advanced Usage

### Custom Completion Promises

```bash
ralph "Your task" --completion-promise "DONE"
```

### Specific Models

```bash
ralph "Your task" --model "claude-sonnet-4-20250514"
```

### Batch Processing

```bash
# Process multiple prompts
for prompt in $(cat prompts.txt); do
    ralph "$prompt" --max-iterations 10
done
```

### Parallel Loops

```bash
# Run multiple independent Ralph loops
ralph "Task A" --prompt-file task-a.txt &
ralph "Task B" --prompt-file task-b.txt &
wait
```

## Performance Tips

1. **Use OpenCode Server Mode**: Reduces cold boot time
2. **Set Reasonable Limits**: Prevents infinite loops
3. **Monitor Progress**: Catch issues early
4. **Optimize Prompts**: Clear requirements speed up iteration
5. **Use Context Wisely**: Guide without micromanaging

## Security Considerations

- **Never commit secrets**: Ralph can expose credentials in logs
- **Use .gitignore**: Exclude sensitive files
- **Review output**: Always verify generated code
- **Limit permissions**: Run with minimal required access
- **Audit logs**: Regularly review iteration history

## Contributing

Contributions are welcome! Areas for improvement:

- **Additional agents**: Support for Claude Code, Codex, etc.
- **Platform-specific optimizations**: Better Windows support
- **Enhanced monitoring**: Integration with observability tools
- **Template library**: Collection of proven prompts
- **Plugins**: Integration with CI/CD, project management

## License

MIT License - see LICENSE file for details.

## Resources

- [Original Ralph Wiggum Technique](https://ghuntley.com/ralph/)
- [OpenCode Documentation](/docs)
- [Ralph Wiggum for OpenCode (Th0rgal)](https://github.com/Th0rgal/opencode-ralph-wiggum)
- [Minimal Ralph Implementation](https://github.com/iannuttall/ralph)

## Support

- **Issues**: Report bugs and request features
- **Discussions**: Share use cases and tips
- **Wiki**: Community-contributed guides

## Version History

- **v1.0.0**: Initial implementation
  - Core loop functionality
  - State persistence
  - Progress tracking
  - Context injection
  - Struggle detection
  - Multi-platform support (Linux, macOS, Windows)

---

**Built with ❤️ for the open source community**

*Ralph: Because sometimes you need to let the AI work while you sleep.*