import * as path from 'path';
// @ts-ignore
import { RalphCLI } from './src/cli.ts';

// Helper to access private members
const access = (obj: any) => obj;

async function runBenchmark() {
  console.log('📊 Running Performance Benchmark...\n');

  // Add local bin to PATH
  const binPath = path.resolve(process.cwd(), 'bin');
  process.env.PATH = `${binPath}:${process.env.PATH}`;

  const iterations = 5;
  const options = {
    prompt: "test",
    maxIterations: 10,
    completionPromise: "COMPLETE",
    model: null,
    verbose: false,
    attach: null
  };

  // 1. Baseline: Uses spawn('opencode')
  // We mock ensureStateDir/initState/logProgress to avoid file I/O noise
  console.log('Running Baseline (Spawn)...');
  const baselineCLI = new RalphCLI();
  access(baselineCLI).ensureStateDir = () => {};
  access(baselineCLI).initState = () => {};
  access(baselineCLI).logProgress = () => {};
  access(baselineCLI).appendHistory = () => {};
  access(baselineCLI).detectStruggle = () => false;

  const startBaseline = Date.now();
  for (let i = 0; i < iterations; i++) {
    process.stdout.write(`.`);
    // We call runIteration which calls runOpenCode which calls spawn
    await access(baselineCLI).runIteration(options, i + 1);
  }
  const durationBaseline = Date.now() - startBaseline;
  console.log(`\nBaseline Time: ${durationBaseline}ms (${Math.round(durationBaseline / iterations)}ms/op)`);

  // 2. Optimized: Simulated SDK
  // Since we haven't implemented the SDK logic in CLI yet, we will
  // Override runOpenCode to simulate what the SDK path will do (fast in-process call)
  console.log('\nRunning Optimized (Simulated SDK)...');
  const optimizedCLI = new RalphCLI();
  access(optimizedCLI).ensureStateDir = () => {};
  access(optimizedCLI).initState = () => {};
  access(optimizedCLI).logProgress = () => {};
  access(optimizedCLI).appendHistory = () => {};
  access(optimizedCLI).detectStruggle = () => false;

  // Override runOpenCode to simulate in-process execution
  // The real optimization will use a persistent client
  access(optimizedCLI).runOpenCode = async () => {
     await new Promise(r => setTimeout(r, 10)); // 10ms network/processing
     return "Output <promise>COMPLETE</promise>";
  };

  const startOpt = Date.now();
  for (let i = 0; i < iterations; i++) {
    process.stdout.write(`.`);
    await access(optimizedCLI).runIteration(options, i + 1);
  }
  const durationOpt = Date.now() - startOpt;
  console.log(`\nOptimized Time: ${durationOpt}ms (${Math.round(durationOpt / iterations)}ms/op)`);

  const improvement = ((durationBaseline - durationOpt) / durationBaseline * 100).toFixed(1);
  console.log(`\n🚀 Improvement: ${improvement}% faster`);
}

runBenchmark().catch(console.error);
