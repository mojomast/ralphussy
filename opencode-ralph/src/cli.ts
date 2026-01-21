#!/usr/bin/env node

import { spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

interface RalphOptions {
  prompt: string;
  maxIterations: number;
  completionPromise: string;
  model: string | null;
  verbose: boolean;
  attach: string | null;
}

class RalphCLI {
  private stateDir: string;
  private progressFile: string;
  private historyFile: string;

  constructor() {
    this.stateDir = '.ralph';
    this.progressFile = path.join(this.stateDir, 'progress.md');
    this.historyFile = path.join(this.stateDir, 'history.json');
  }

  async run(options: RalphOptions): Promise<void> {
    console.log('🚀 Starting Ralph autonomous loop...\n');
    console.log(`📝 Prompt: ${options.prompt.substring(0, 100)}...`);
    console.log(`🔄 Max iterations: ${options.maxIterations}`);
    console.log(`✅ Completion promise: ${options.completionPromise}\n`);

    this.ensureStateDir();
    this.initState(options.prompt, options.completionPromise, options.maxIterations);

    let iteration = 0;
    let success = false;

    while (iteration < options.maxIterations) {
      iteration++;
      console.log(`\n🔄 Iteration ${iteration}/${options.maxIterations}`);

      try {
        const result = await this.runIteration(options, iteration);
        
        if (result.success) {
          success = true;
          console.log('\n✅ Ralph completed successfully!');
          break;
        }

        if (result.struggle) {
          console.log('\n⚠️  Struggle detected - no recent file changes');
        }

        this.logProgress(iteration, result.duration, result.tools);
        this.appendHistory(iteration, result.duration, result.tools, result.success);

      } catch (error) {
        console.error(`❌ Iteration ${iteration} failed:`, error);
      }
    }

    if (!success) {
      console.log(`\n⚠️  Reached max iterations (${options.maxIterations})`);
    }

    this.printSummary(iteration, success);
  }

  private async runIteration(options: RalphOptions, iteration: number): Promise<{
    success: boolean;
    struggle: boolean;
    duration: number;
    tools: string[];
  }> {
    const startTime = Date.now();
    
    // Build command
    const cmd = ['run'];
    if (options.model) {
      cmd.push('--model', options.model);
    }
    if (options.attach) {
      cmd.push('--attach', options.attach);
    }

    // Get context if exists
    let prompt = options.prompt;
    const contextFile = path.join(this.stateDir, 'context.md');
    if (fs.existsSync(contextFile)) {
      const context = fs.readFileSync(contextFile, 'utf-8').trim();
      if (context) {
        prompt = `${options.prompt}\n\nAdditional context:\n${context}`;
        fs.unlinkSync(contextFile);
      }
    }

    // Run OpenCode
    const output = await this.runOpenCode(cmd, prompt);
    const duration = Date.now() - startTime;

    // Extract tools
    const tools = this.extractTools(output);

    // Check completion
    const success = output.includes(`<promise>${options.completionPromise}</promise>`);

    // Detect struggle
    const struggle = this.detectStruggle();

    return { success, struggle, duration, tools };
  }

  private async runOpenCode(args: string[], prompt: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const proc = spawn('opencode', [...args], {
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env }
      });

      let stdout = '';
      let stderr = '';

      proc.stdout.on('data', (data) => {
        const text = data.toString();
        stdout += text;
        process.stdout.write(text);
      });

      proc.stderr.on('data', (data) => {
        stderr += data.toString();
        process.stderr.write(data);
      });

      proc.stdin.write(prompt);
      proc.stdin.end();

      proc.on('close', (code) => {
        if (code === 0) {
          resolve(stdout);
        } else {
          resolve(`Error: Process exited with code ${code}\n${stderr}`);
        }
      });

      proc.on('error', reject);
    });
  }

  private extractTools(output: string): string[] {
    const tools: string[] = [];
    const patterns = ['Read', 'Write', 'Edit', 'Bash', 'grep', 'glob', 'task', 'webfetch'];
    
    for (const tool of patterns) {
      if (output.includes(tool)) {
        tools.push(tool);
      }
    }
    
    return tools;
  }

  private detectStruggle(): boolean {
    if (!fs.existsSync(this.historyFile)) return false;

    try {
      const history = JSON.parse(fs.readFileSync(this.historyFile, 'utf-8'));
      if (history.length < 3) return false;

      const recent = history.slice(-3);
      return !recent.some((h: any) => 
        h.tools?.some((t: string) => ['Write', 'Edit', 'Bash'].includes(t))
      );
    } catch {
      return false;
    }
  }

  private ensureStateDir(): void {
    fs.mkdirSync(this.stateDir, { recursive: true });
  }

  private initState(prompt: string, completionPromise: string, maxIterations: number): void {
    const state = {
      status: 'running',
      iteration: 0,
      prompt,
      startTime: new Date().toISOString(),
      lastActivity: new Date().toISOString(),
      context: '',
      maxIterations,
      completionPromise
    };
    fs.writeFileSync(
      path.join(this.stateDir, 'state.json'),
      JSON.stringify(state, null, 2)
    );

    fs.writeFileSync(
      path.join(this.stateDir, 'progress.md'),
      `# Ralph Progress Log\n\nStarted: ${new Date().toISOString()}\n\n`
    );

    fs.writeFileSync(
      this.historyFile,
      JSON.stringify({ iterations: [], totalTime: 0 }, null, 2)
    );
  }

  private logProgress(iteration: number, duration: number, tools: string[]): void {
    const log = `\n## Iteration ${iteration} - ${new Date().toISOString()}\n` +
      `- Duration: ${duration}ms\n` +
      `- Tools: ${tools.join(', ') || 'none'}\n`;
    
    fs.appendFileSync(this.progressFile, log);
  }

  private appendHistory(iteration: number, duration: number, tools: string[], success: boolean): void {
    const history = JSON.parse(fs.readFileSync(this.historyFile, 'utf-8'));
    history.iterations.push({
      iteration,
      timestamp: new Date().toISOString(),
      duration,
      tools,
      success
    });
    history.totalTime = history.iterations.reduce((sum: number, h: any) => sum + h.duration, 0);
    fs.writeFileSync(this.historyFile, JSON.stringify(history, null, 2));
  }

  private printSummary(iteration: number, success: boolean): void {
    console.log('\n═══════════════════════════════════════════');
    console.log('           Ralph Summary                   ');
    console.log('═══════════════════════════════════════════');
    console.log(`Status:      ${success ? '✅ Completed' : '⚠️  Max iterations'}`);
    console.log(`Iterations:  ${iteration}`);
    
    if (fs.existsSync(this.historyFile)) {
      const history = JSON.parse(fs.readFileSync(this.historyFile, 'utf-8'));
      const totalTime = Math.round(history.totalTime / 1000);
      console.log(`Total time:  ${totalTime}s`);
      console.log(`Log file:    ${this.progressFile}`);
    }
    
    console.log('═══════════════════════════════════════════\n');
  }

  async status(): Promise<void> {
    if (!fs.existsSync(path.join(this.stateDir, 'state.json'))) {
      console.log('🔄 No active Ralph loop');
      return;
    }

    const state = JSON.parse(fs.readFileSync(path.join(this.stateDir, 'state.json'), 'utf-8'));
    const history = fs.existsSync(this.historyFile) 
      ? JSON.parse(fs.readFileSync(this.historyFile, 'utf-8'))
      : { iterations: [] };

    console.log('╔═══════════════════════════════════════════════════╗');
    console.log('║              Ralph Status                          ║');
    console.log('╚═══════════════════════════════════════════════════╝');
    console.log('');
    console.log('🔄 ACTIVE LOOP');
    console.log(`   Iteration:    ${state.iteration} / ${state.maxIterations}`);
    
    if (state.startTime) {
      const elapsed = Math.floor((Date.now() - new Date(state.startTime).getTime()) / 1000);
      const minutes = Math.floor(elapsed / 60);
      const seconds = elapsed % 60;
      console.log(`   Elapsed:      ${minutes}m ${seconds}s`);
    }
    
    console.log(`   Promise:      ${state.completionPromise}`);
    console.log(`   Prompt:       ${state.prompt?.substring(0, 50)}...`);
    console.log('');

    if (history.iterations?.length > 0) {
      console.log('📊 HISTORY');
      history.iterations.slice(-5).forEach((h: any) => {
        console.log(`   🔄 #${h.iteration}: ${Math.round(h.duration / 1000)}s | ${h.tools?.join(' ') || 'none'}`);
      });
      console.log('');
    }

    if (fs.existsSync(path.join(this.stateDir, 'context.md'))) {
      console.log('📝 PENDING CONTEXT');
      const context = fs.readFileSync(path.join(this.stateDir, 'context.md'), 'utf-8');
      console.log(context.substring(0, 200));
    }
  }

  async addContext(context: string): Promise<void> {
    this.ensureStateDir();
    const contextFile = path.join(this.stateDir, 'context.md');
    fs.appendFileSync(contextFile, context + '\n');
    console.log('✅ Context added for next iteration');
  }

  async clearContext(): Promise<void> {
    const contextFile = path.join(this.stateDir, 'context.md');
    if (fs.existsSync(contextFile)) {
      fs.unlinkSync(contextFile);
    }
    console.log('✅ Context cleared');
  }
}

async function main() {
  const cli = new RalphCLI();
  
  const args = process.argv.slice(2);
  let prompt = '';
  let maxIterations = 100;
  let completionPromise = 'COMPLETE';
  let model: string | null = null;
  let verbose = false;
  let attach: string | null = null;
  let showStatus = false;
  let addContext = '';
  let clearContext = false;
  let showHelp = false;

  // Parse arguments
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    switch (arg) {
      case '--help':
      case '-h':
        showHelp = true;
        break;
      case '--status':
        showStatus = true;
        break;
      case '--add-context':
        addContext = args[++i] || '';
        break;
      case '--clear-context':
        clearContext = true;
        break;
      case '--max-iterations':
        maxIterations = parseInt(args[++i]) || 100;
        break;
      case '--completion-promise':
        completionPromise = args[++i] || 'COMPLETE';
        break;
      case '--model':
        model = args[++i] || null;
        break;
      case '--verbose':
      case '-v':
        verbose = true;
        break;
      case '--attach':
        attach = args[++i] || null;
        break;
      default:
        if (!arg.startsWith('--')) {
          prompt = arg;
        }
    }
  }

  if (showHelp) {
    console.log(`
🤖 Ralph - Autonomous AI Coding Loop for OpenCode

USAGE:
  ralph "<prompt>" [options]
  ralph --status
  ralph --add-context "<hint>"
  ralph --clear-context

OPTIONS:
  --max-iterations N       Stop after N iterations (default: 100)
  --completion-promise T   Text that signals completion (default: COMPLETE)
  --model MODEL            OpenCode model to use
  --verbose, -v            Show detailed output
  --attach URL             Attach to OpenCode server
  --status                 Show current loop status
  --add-context HINT       Add context for next iteration
  --clear-context          Clear pending context
  --help, -h               Show this help message

EXAMPLES:
  ralph "Create a hello.txt file. Output <promise>COMPLETE</promise> when done."
  ralph "Build a REST API with tests. Output <promise>COMPLETE</promise> when all tests pass." --max-iterations 20
  ralph --status
  ralph --add-context "Focus on fixing the auth module first"

For more information, visit: https://github.com/anomalyco/opencode
`);
    process.exit(0);
  }

  if (showStatus) {
    await cli.status();
    process.exit(0);
  }

  if (addContext) {
    await cli.addContext(addContext);
    process.exit(0);
  }

  if (clearContext) {
    await cli.clearContext();
    process.exit(0);
  }

  if (!prompt) {
    console.error('❌ No prompt provided. Use: ralph "<prompt>"');
    process.exit(1);
  }

  await cli.run({
    prompt,
    maxIterations,
    completionPromise,
    model,
    verbose,
    attach
  });
}

main().catch(console.error);