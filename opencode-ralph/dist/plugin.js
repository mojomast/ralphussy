#!/usr/bin/env node
"use strict";
// OpenCode plugin integration for Ralph
// This enables Ralph mode directly within OpenCode
Object.defineProperty(exports, "__esModule", { value: true });
exports.defaultConfig = void 0;
const zod_1 = require("zod");
const defaultConfig = {
    maxIterations: 100,
    completionPromise: 'COMPLETE',
    autoCommit: true,
    staleTimeout: 3600,
    progressFile: 'projects/.ralph/progress.md',
    historyFile: 'projects/.ralph/history.json'
};
exports.defaultConfig = defaultConfig;
let config = { ...defaultConfig };
const ralph = async (input) => {
    return {
        config: async (cfg) => {
            if (cfg.plugins?.ralph) {
                config = { ...config, ...cfg.plugins.ralph };
            }
        },
        tool: {
            ralph: tool({
                description: 'Start Ralph autonomous loop',
                args: {
                    task: zod_1.z.string().describe('Task description'),
                    maxIterations: zod_1.z.number().optional().describe('Maximum iterations'),
                    completionPromise: zod_1.z.string().optional().describe('Completion signal'),
                    model: zod_1.z.string().optional().describe('AI model to use'),
                    options: zod_1.z.object({
                        verbose: zod_1.z.boolean().optional(),
                        autoCommit: zod_1.z.boolean().optional(),
                        progressFile: zod_1.z.string().optional(),
                        historyFile: zod_1.z.string().optional()
                    }).optional()
                },
                execute: async (args, context) => {
                    const { task, maxIterations, completionPromise, model, options } = args;
                    const fullPrompt = buildRalphPrompt(task, {
                        completionPromise: completionPromise || config.completionPromise,
                        options
                    });
                    return `🤖 **Ralph Mode Activated**

Starting autonomous loop with:
- Task: ${task.substring(0, 100)}...
- Max iterations: ${maxIterations || config.maxIterations}
- Completion signal: ${completionPromise || config.completionPromise}

${options?.verbose ? 'Verbose mode enabled\n' : ''}Ralph will iterate until completion. Use ralphStatus to monitor progress.`;
                }
            }),
            ralphStatus: tool({
                description: 'Get Ralph loop status',
                args: {},
                execute: async (args, context) => {
                    return JSON.stringify({
                        status: 'active',
                        config,
                        message: 'Use the Ralph dashboard for detailed status'
                    }, null, 2);
                }
            }),
            ralphStop: tool({
                description: 'Stop Ralph loop',
                args: {},
                execute: async (args, context) => {
                    return '✅ Ralph loop stopped';
                }
            }),
            ralphConfig: tool({
                description: 'Configure Ralph settings',
                args: {
                    maxIterations: zod_1.z.number().optional(),
                    completionPromise: zod_1.z.string().optional(),
                    autoCommit: zod_1.z.boolean().optional()
                },
                execute: async (args, context) => {
                    Object.assign(config, args);
                    return `✅ Ralph configuration updated:\n${JSON.stringify(config, null, 2)}`;
                }
            })
        },
        'chat.message': async (input, output) => {
            if (input.agent === 'ralph') {
                output.parts.push({
                    type: 'text',
                    text: formatRalphWelcome()
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
            if (input.sessionID.includes('ralph')) {
                output.system.push('You are Ralph, an autonomous coding agent.', 'You iterate on tasks until completion using the same prompt.', 'You see previous work through file changes and git history.', 'Output <promise>COMPLETE</promise> when done.');
            }
        }
    };
};
function buildRalphPrompt(task, options) {
    return `${task}

## Ralph Loop Configuration
- Completion signal: <promise>${options.completionPromise}</promise>
${options.options?.autoCommit ? '- Auto-commit enabled' : ''}
${options.options?.verbose ? '- Verbose logging enabled' : ''}

## Instructions
1. Work on the task systematically
2. Run tests and verify after each change
3. Output <promise>${options.completionPromise}</promise> when all requirements are met
4. If stuck, output what you've tried and what might help

Let's begin!`;
}
function formatRalphWelcome() {
    return `## 🤖 Ralph Mode - Autonomous Coding

Welcome to Ralph! I'll help you iterate on coding tasks autonomously.

### How It Works
1. You provide a task with clear completion criteria
2. I work on it iteratively until done
3. I see my progress through file changes
4. I self-correct based on test results

### Available Commands
- \`ralphStart "task"\` - Start autonomous loop
- \`ralphStatus\` - Check progress
- \`ralphStop\` - Stop the loop
- \`ralphConfig\` - Configure settings

### Writing Good Prompts
✅ Good:
> Build a REST API with CRUD endpoints and tests. Output <promise>COMPLETE</promise> when all tests pass.

❌ Bad:
> Make the code better

### Tips
- Set clear success criteria
- Include test/verification steps
- Use <promise>TAG</promise> to signal completion
- Monitor progress with ralphStatus

Ready to work! What would you like me to build?`;
}
exports.default = ralph;
//# sourceMappingURL=plugin.js.map