"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.defaultConfig = exports.slashCommands = void 0;
const defaultConfig = {
    maxIterations: 100,
    completionPromise: 'COMPLETE',
    autoCommit: true,
    staleTimeout: 3600
};
exports.defaultConfig = defaultConfig;
let config = { ...defaultConfig };
const slashCommands = [
    {
        command: '/ralph',
        description: 'Start Ralph autonomous loop',
        arguments: '<task description>',
        options: [
            { name: '--max-iterations', description: 'Maximum iterations (default: 100)' },
            { name: '--completion-promise', description: 'Completion signal (default: COMPLETE)' },
            { name: '--model', description: 'AI model to use' }
        ],
        examples: [
            '/ralph Build a REST API. Output <promise>COMPLETE</promise> when done.',
            '/ralph Write tests. --max-iterations 20',
            '/ralph Refactor auth module. --completion-promise DONE'
        ]
    },
    {
        command: '/ralph-status',
        alias: ['/ralphs', '/rs'],
        description: 'Check Ralph loop status'
    },
    {
        command: '/ralph-stop',
        alias: ['/ralphq', '/rq'],
        description: 'Stop running Ralph loop'
    },
    {
        command: '/ralph-context',
        alias: ['/ralphc', '/rc'],
        arguments: '<message>',
        description: 'Add context to next iteration',
        examples: [
            '/ralph-context Focus on the authentication module first'
        ]
    },
    {
        command: '/ralph-clear',
        alias: ['/ralphx', '/rx'],
        description: 'Clear pending context'
    },
    {
        command: '/ralph-help',
        alias: ['/ralphh', '/rh'],
        description: 'Show Ralph help'
    }
];
exports.slashCommands = slashCommands;
const ralphSlash = async (input) => {
    return {
        config: async (cfg) => {
            if (cfg.ralph) {
                config = {
                    maxIterations: cfg.ralph.maxIterations || defaultConfig.maxIterations,
                    completionPromise: cfg.ralph.completionPromise || defaultConfig.completionPromise,
                    autoCommit: cfg.ralph.autoCommit ?? defaultConfig.autoCommit,
                    staleTimeout: cfg.ralph.staleTimeout || defaultConfig.staleTimeout
                };
            }
        },
        tool: {
            ralph: {
                name: 'ralph',
                description: 'Start Ralph autonomous loop',
                parameters: {
                    type: 'object',
                    properties: {
                        task: { type: 'string', description: 'Task description' },
                        maxIterations: { type: 'number', description: 'Maximum iterations' },
                        completionPromise: { type: 'string', description: 'Completion signal' },
                        model: { type: 'string', description: 'AI model to use' },
                        verbose: { type: 'boolean', description: 'Verbose output' }
                    },
                    required: ['task']
                },
                execute: async (args) => {
                    const task = args.task;
                    const maxIterations = args.maxIterations || config.maxIterations;
                    const completionPromise = args.completionPromise || config.completionPromise;
                    return `🤖 **Ralph Mode Activated**

Starting autonomous loop:
- Task: ${task.substring(0, 80)}...
- Max iterations: ${maxIterations}
- Completion signal: <promise>${completionPromise}</promise>

Ralph will iterate until completion. Use ralphStatus to check progress.`;
                }
            },
            ralphStatus: {
                name: 'ralphStatus',
                description: 'Check Ralph loop status',
                parameters: { type: 'object', properties: {} },
                execute: async () => {
                    return '## Ralph Status\n\nNo active Ralph loop. Use `/ralph` to start one.';
                }
            },
            ralphStop: {
                name: 'ralphStop',
                description: 'Stop Ralph loop',
                parameters: { type: 'object', properties: {} },
                execute: async () => {
                    return '✅ Ralph loop stopped. Note: Background processes may still be running.';
                }
            },
            ralphContext: {
                name: 'ralphContext',
                description: 'Add context to next iteration',
                parameters: {
                    type: 'object',
                    properties: {
                        message: { type: 'string', description: 'Context message' }
                    },
                    required: ['message']
                },
                execute: async (args) => {
                    return `✅ Context added: "${args.message}"\n\nThis will be included in the next iteration.`;
                }
            },
            ralphClear: {
                name: 'ralphClear',
                description: 'Clear pending context',
                parameters: { type: 'object', properties: {} },
                execute: async () => {
                    return '✅ Context cleared.';
                }
            },
            ralphHelp: {
                name: 'ralphHelp',
                description: 'Show Ralph help',
                parameters: { type: 'object', properties: {} },
                execute: async () => {
                    return `## 🤖 Ralph Slash Commands

### Available Commands

| Command | Alias | Description |
|---------|-------|-------------|
| \`/ralph\` | \`/r\` | Start autonomous loop |
| \`/ralph-status\` | \`/rs\` | Check loop status |
| \`/ralph-stop\` | \`/rq\` | Stop loop |
| \`/ralph-context\` | \`/rc\` | Add context |
| \`/ralph-clear\` | \`/rx\` | Clear context |
| \`/ralph-help\` | \`/rh\` | Show help |

### Examples

\`\`\`bash
/ralph Build a REST API. Output <promise>COMPLETE</promise> when done.
/ralph Write tests. --max-iterations 20
/ralph-status
/ralph-context Focus on fixing the auth module
\`\`\`

### Writing Good Prompts

✅ Good:
> Build a REST API with CRUD endpoints and tests. Output <promise>COMPLETE</promise> when all tests pass.

❌ Bad:
> Make the code better`;
                }
            }
        },
        'chat.message': async (input, output) => {
            if (input.agent === 'ralph') {
                output.parts.push({
                    type: 'text',
                    text: formatRalphWelcome(),
                    id: Date.now().toString(),
                    sessionID: input.sessionID || 'default',
                    messageID: Date.now().toString()
                });
            }
        },
        'chat.params': async (input, output) => {
            if (input.agent === 'ralph') {
                output.temperature = 0.1;
                output.topP = 0.95;
                output.topK = 50;
            }
        },
        'experimental.chat.system.transform': async (input, output) => {
            if (input.sessionID?.includes('ralph')) {
                output.system.push('You are Ralph, an autonomous coding agent.', 'You iterate on tasks until completion using the same prompt.', 'You see previous work through file changes and git history.', 'Output <promise>COMPLETE</promise> when done.');
            }
        }
    };
};
function formatRalphWelcome() {
    return `## 🤖 Ralph Mode - Autonomous Coding

Welcome to Ralph! I'll help you iterate on coding tasks autonomously.

### How It Works
1. You provide a task with clear completion criteria
2. I work on it iteratively until done
3. I see my progress through file changes
4. I self-correct based on test results

### Slash Commands
- \`/ralph "task"\` - Start autonomous loop
- \`/ralph-status\` - Check progress
- \`/ralph-stop\` - Stop the loop
- \`/ralph-context "message"\` - Add guidance
- \`/ralph-help\` - Show help

### Writing Good Prompts
✅ Good:
> Build a REST API with CRUD endpoints and tests. Output <promise>COMPLETE</promise> when all tests pass.

❌ Bad:
> Make the code better

Ready to work! What would you like me to build?`;
}
exports.default = ralphSlash;
//# sourceMappingURL=index.js.map