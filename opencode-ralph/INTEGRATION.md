# Ralph Agent Mode - Integration Guide

This guide explains how to integrate Ralph agent mode directly into OpenCode.

## Installation

### Method 1: npm Package (Recommended)

```bash
# Install the package
npm install @opencode-ai/ralph

# Or for development
git clone https://github.com/anomalyco/opencode-ralph
cd opencode-ralph
npm install
npm run build
```

### Method 2: From Source

```bash
# Clone OpenCode and add Ralph
git clone https://github.com/anomalyco/opencode
cd opencode
# Copy Ralph files to plugins directory
```

## Configuration

### Basic Configuration

Add to your `opencode.json`:

```json
{
  "plugins": [
    "@opencode-ai/ralph"
  ]
}
```

### Advanced Configuration

```json
{
  "plugins": [
    "@opencode-ai/ralph"
  ],
  "ralph": {
    "maxIterations": 100,
    "completionPromise": "COMPLETE",
    "autoCommit": true,
    "staleTimeout": 3600,
    "verbose": false,
    "progressFile": ".ralph/progress.md",
    "historyFile": ".ralph/history.json"
  },
  "agents": {
    "ralph": {
      "description": "Autonomous loop agent",
      "temperature": 0.1,
      "topP": 0.95,
      "systemPrompt": "You are Ralph, an autonomous coding agent that iterates until task completion."
    }
  }
}
```

## Usage

### Starting Ralph Mode

#### CLI

```bash
# Simple task
opencode run --agent ralph "Create a hello.txt file"

# With options
opencode run --agent ralph "Build a REST API" \
  --max-iterations 20 \
  --model claude-sonnet-4-20250514
```

#### Interactive

```
> /ralph "Build a todo API with CRUD operations"
```

### Available Tools

When Ralph mode is active, these tools are available:

- `ralphStart` - Start autonomous loop
- `ralphStatus` - Check current status
- `ralphStop` - Stop the loop
- `ralphAddContext` - Add guidance mid-loop
- `ralphClearContext` - Clear pending context
- `ralphConfig` - Configure settings

### Monitoring

#### Check Status

```bash
# CLI
ralph --status

# In OpenCode
ralphStatus
```

#### View Progress

```bash
# View progress file
cat .ralph/progress.md

# View history
cat .ralph/history.json
```

## Architecture

### Plugin Structure

```
@opencode-ai/ralph/
├── src/
│   ├── index.ts       # Core Ralph agent implementation
│   ├── plugin.ts      # OpenCode plugin integration
│   └── cli.ts         # CLI interface
├── dist/              # Compiled JavaScript
├── examples/          # Example configurations
└── package.json
```

### State Management

Ralph maintains state in `.ralph/` directory:

```
.ralph/
├── state.json         # Current loop state
├── history.json       # Iteration history
├── progress.md        # Progress log
├── context.md         # Pending context
└── logs/
    ├── iteration_001.log
    ├── iteration_002.log
    └── ...
```

### Loop Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Ralph Loop Cycle                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. User provides task prompt                           │
│                    ↓                                    │
│  2. OpenCode processes task                             │
│                    ↓                                    │
│  3. Check for completion promise                        │
│                    ↓                                    │
│  4. If not complete:                                    │
│     - Record iteration                                  │
│     - Detect struggles                                  │
│     - Check context                                     │
│     - Repeat with same prompt                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Customization

### Custom Completion Promises

```json
{
  "ralph": {
    "completionPromise": "DONE"
  }
}
```

Prompt usage:
```
Build the feature. Output <promise>DONE</promise> when complete.
```

### Custom System Prompts

```json
{
  "agents": {
    "ralph": {
      "systemPrompt": "You are Ralph. You prefer TypeScript over JavaScript. You always write tests."
    }
  }
}
```

### Hook Integration

Ralph integrates with OpenCode hooks:

- `config` - Load Ralph configuration
- `tool` - Register Ralph tools
- `chat.message` - Handle Ralph chat messages
- `chat.params` - Customize LLM parameters
- `experimental.chat.system.transform` - Add Ralph system prompt

## Best Practices

### Writing Prompts

1. **Be Specific**
   ```
   ❌ "Build a todo API"
   ✅ "Build a REST API for todos with CRUD endpoints and tests"
   ```

2. **Include Verification**
   ```
   ❌ "Make the code better"
   ✅ "Refactor auth.ts. All tests must pass. Output <promise>DONE</promise> when complete."
   ```

3. **Set Clear Criteria**
   ```
   ✅ "Output <promise>COMPLETE</promise> when all tests pass and coverage > 90%"
   ```

### Managing Iterations

- Set `maxIterations` to prevent runaway loops
- Monitor with `ralph --status`
- Use `ralph --add-context` to guide stuck agents
- Review `.ralph/progress.md` for patterns

### Troubleshooting

#### Agent Not Completing

1. Check if completion promise is correct
2. Verify requirements are achievable
3. Add more specific guidance
4. Break into smaller tasks

#### Poor Code Quality

1. Add specific quality requirements
2. Mention frameworks and patterns
3. Require tests and coverage
4. Specify code style guidelines

#### Too Slow

1. Reduce task scope
2. Use faster model
3. Limit max iterations
4. Add intermediate checkpoints

## API Reference

### Plugin Options

```typescript
interface RalphConfig {
  maxIterations: number;      // Default: 100
  completionPromise: string;  // Default: "COMPLETE"
  autoCommit: boolean;        // Default: true
  staleTimeout: number;       // Default: 3600
  verbose: boolean;           // Default: false
  progressFile: string;       // Default: ".ralph/progress.md"
  historyFile: string;        // Default: ".ralph/history.json"
}
```

### Tool Definitions

#### ralphStart

```typescript
{
  task: string,              // Task description
  maxIterations?: number,    // Override config
  completionPromise?: string, // Override config
  model?: string,            // AI model
  options?: {
    verbose?: boolean,
    autoCommit?: boolean,
    progressFile?: string,
    historyFile?: string
  }
}
```

#### ralphStatus

Returns current loop status and history.

#### ralphStop

Stops the running loop.

#### ralphAddContext

```typescript
{
  context: string  // Guidance for next iteration
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Add tests
5. Submit pull request

## License

MIT License - see LICENSE file for details.

## Support

- GitHub Issues: Report bugs and feature requests
- Discussions: Share use cases and get help
- Wiki: Community-contributed guides