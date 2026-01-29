import fs from 'fs';
import path from 'path';
import Database from 'bun:sqlite';
import { createSwarmDatabase } from './database-bun.js';

async function main() {
  const TEST_RALPH_DIR = path.resolve('./.ralph-bench');
  const TEST_RUN_ID = 'bench-run-1';

  // Clean up previous run
  if (fs.existsSync(TEST_RALPH_DIR)) {
    fs.rmSync(TEST_RALPH_DIR, { recursive: true, force: true });
  }

  // Setup directory structure
  const runDir = path.join(TEST_RALPH_DIR, 'swarm', 'runs', TEST_RUN_ID);
  fs.mkdirSync(runDir, { recursive: true });

  const dbPath = path.join(TEST_RALPH_DIR, 'swarm.db');

  const db = new Database(dbPath);
  db.prepare("CREATE TABLE swarm_runs (run_id TEXT)").run();
  db.close();

  // Create workers and logs
  console.log('Generating log files...');
  const numWorkers = 5; // Reduced for faster setup, but large enough files
  const numLogsPerWorker = 5;

  const buffer = Buffer.alloc(1024 * 1024); // 1MB buffer of 'a's
  buffer.fill('a');

  const writePromises = [];

  for (let i = 0; i < numWorkers; i++) {
    const workerId = `worker-${i.toString().padStart(2, '0')}`;
    const logsDir = path.join(runDir, workerId, 'logs');
    fs.mkdirSync(logsDir, { recursive: true });

    for (let j = 0; j < numLogsPerWorker; j++) {
      const logPath = path.join(logsDir, `log-${j}.log`);

      const p = new Promise<void>((resolve, reject) => {
          const stream = fs.createWriteStream(logPath);
          stream.on('error', reject);
          stream.on('finish', resolve);

          // Write 50MB
          for (let k = 0; k < 50; k++) {
              stream.write(buffer);
          }
          // Add some lines at the end with timestamps
          for (let k = 0; k < 100; k++) {
            stream.write(`Log line ${k} for ${workerId} file ${j} at ${Date.now()}\n`);
          }
          stream.end();
      });
      writePromises.push(p);
    }
  }

  await Promise.all(writePromises);
  console.log('Logs generated. Running benchmark...');

  process.env.RALPH_DIR = TEST_RALPH_DIR;
  const swarmDb = createSwarmDatabase(dbPath);

  // Warmup
  await swarmDb.getRecentLogs(TEST_RUN_ID, 50);

  const start = performance.now();
  const iterations = 5;

  for (let i = 0; i < iterations; i++) {
    const logs = await Promise.resolve(swarmDb.getRecentLogs(TEST_RUN_ID, 50));
    if (logs.length === 0) {
        console.warn("Warning: No logs returned!");
    } else {
        // console.log(`Got ${logs.length} logs`);
    }
  }

  const end = performance.now();
  const avgTime = (end - start) / iterations;

  console.log(`Average execution time over ${iterations} iterations: ${avgTime.toFixed(2)}ms`);

  // Cleanup
  fs.rmSync(TEST_RALPH_DIR, { recursive: true, force: true });
}

main().catch(console.error);
