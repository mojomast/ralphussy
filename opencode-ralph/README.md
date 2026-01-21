# Ralph Agent Plugin for OpenCode

Ralph autonomous loop agent mode for OpenCode.

## Installation

```bash
# In your OpenCode project
npm install @opencode-ai/ralph

# Or for development
git clone https://github.com/anomalyco/opencode-ralph
cd opencode-ralph
npm install
npm run build
```

## Usage

Add Ralph to your `opencode.json`:

```json
{
  "plugins": [
    "@opencode-ai/ralph"
  ]
}
```

Or use the CLI:

```bash
opencode run --agent ralph "Build a REST API with tests"
```

## Features

- **Autonomous Loop**: Runs OpenCode repeatedly with the same prompt
- **State Persistence**: Maintains state across iterations
- **Progress Tracking**: Detailed logs and progress reports
- **Struggle Detection**: Automatic detection of stuck agents
- **Context Injection**: Guide agents mid-loop without stopping

## Configuration

```json
{
  "ralph": {
    "maxIterations": 100,
    "completionPromise": "COMPLETE",
    "autoCommit": true,
    "staleTimeout": 3600,
    "progressFile": ".ralph/progress.md",
    "historyFile": ".ralph/history.json"
  }
}
```

## Commands

### Start Ralph Loop

```bash
ralph "Your task here. Output <promise>COMPLETE</promise> when done."
```

### Check Status

```bash
ralph --status
```

### Add Context

```bash
ralph --add-context "Focus on fixing the auth module"
```

### Clear Context

```bash
ralph --clear-context
```

## Writing Prompts

### Good Prompt Structure

```
[Task Description]
[Requirements]
[Success Criteria]
Output <promise>COMPLETE</promise> when [specific conditions].
```

### Example

```
Build a REST API for todos with:
- CRUD endpoints (GET, POST, PUT, DELETE)
- Input validation
- Unit tests for each endpoint

Run tests after each change.
Output <promise>COMPLETE</promise> when all tests pass.
```

## API

### Plugin Interface

```typescript
import { Plugin, PluginInput, Hooks } from '@opencode-ai/plugin';

const ralph: Plugin = async (input: PluginInput): Promise<Hooks> => {
  return {
    tool: {
      // Ralph tools
    },
    'chat.message': async (input, output) => {
      // Handle Ralph messages
    },
  };
};

export default ralph;
```

## License

MIT