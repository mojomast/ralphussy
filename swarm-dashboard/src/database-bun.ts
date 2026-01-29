import Database from 'bun:sqlite';
import path from 'path';
import fs from 'fs';

export interface Worker {
  id: number;
  run_id: string;
  worker_num: number;
  pid: number;
  branch_name: string;
  status: string;
  current_task_id: number | null;
  locked_files: string;
  work_dir: string;
  started_at: string;
  last_heartbeat: string;
}

export interface Task {
  id: number;
  run_id: string;
  task_text: string;
  task_hash: string;
  status: string;
  worker_id: number | null;
  priority: number;
  estimated_files: string;
  actual_files: string;
  devplan_line: number | null;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  error_message: string | null;
  stall_count: number;
}

export interface SwarmRun {
  run_id: string;
  status: string;
  source_type: string;
  source_path: string | null;
  source_hash: string;
  source_prompt: string;
  worker_count: number;
  total_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  started_at: string;
  completed_at: string | null;
}

export interface TaskCost {
  run_id: string;
  task_id: number;
  prompt_tokens: number;
  completion_tokens: number;
  cost: number;
  created_at: string;
}

async function readLastLines(filePath: string, maxLines: number, maxBytes: number = 64 * 1024): Promise<string[]> {
  try {
    const stats = await fs.promises.stat(filePath);
    const size = stats.size;
    if (size === 0) return [];

    const handle = await fs.promises.open(filePath, 'r');
    try {
      const readSize = Math.min(size, maxBytes);
      const buffer = Buffer.alloc(readSize);
      const position = size - readSize;

      await handle.read(buffer, 0, readSize, position);

      let content = buffer.toString('utf-8');
      // If we didn't read the whole file and the first line is partial, discard it
      if (position > 0) {
        const firstNewLine = content.indexOf('\n');
        if (firstNewLine !== -1) {
          content = content.substring(firstNewLine + 1);
        }
      }

      const lines = content.split('\n')
        .map(l => l.trim())
        .filter(l => l.length > 0)
        .reverse(); // Newest first

      return lines.slice(0, maxLines);
    } finally {
      await handle.close();
    }
  } catch (error) {
    return [];
  }
}

export class SwarmDatabase {
  private db: Database;

  constructor(dbPath: string) {
    const absolutePath = path.resolve(dbPath);
    if (!fs.existsSync(absolutePath)) {
      throw new Error(`Database not found: ${absolutePath}`);
    }
    this.db = new Database(absolutePath, { readonly: true });
  }

  close(): void {
    this.db.close();
  }

  getCurrentRun(): SwarmRun | null {
    const run = this.db.query(`
      SELECT * FROM swarm_runs 
      WHERE status = 'running' 
      ORDER BY started_at DESC 
      LIMIT 1
    `).get() as SwarmRun | undefined;
    return run || null;
  }

  getWorkersByRun(runId: string): Worker[] {
    return this.db.query(`
      SELECT * FROM workers 
      WHERE run_id = ? 
      ORDER BY worker_num
    `).all(runId) as Worker[];
  }

  getTasksByRun(runId: string): Task[] {
    return this.db.query(`
      SELECT * FROM tasks 
      WHERE run_id = ? 
      ORDER BY priority, id
    `).all(runId) as Task[];
  }

  getTaskById(taskId: number): Task | null {
    const task = this.db.query('SELECT * FROM tasks WHERE id = ?').get(taskId) as Task | undefined;
    return task || null;
  }

  getTaskCostsByRun(runId: string): TaskCost[] {
    return this.db.query(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC
    `).all(runId) as TaskCost[];
  }

  getRecentTaskCosts(runId: string, limit: number = 20): TaskCost[] {
    return this.db.query(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC 
      LIMIT ?
    `).all(runId, limit) as TaskCost[];
  }

  getRecentRuns(limit: number = 10): SwarmRun[] {
    return this.db.query(`
      SELECT * FROM swarm_runs 
      ORDER BY started_at DESC 
      LIMIT ?
    `).all(limit) as SwarmRun[];
  }

  getRunById(runId: string): SwarmRun | null {
    const run = this.db.query(`
      SELECT * FROM swarm_runs 
      WHERE run_id = ?
    `).get(runId) as SwarmRun | undefined;
    return run || null;
  }

  getFileLocksByRun(runId: string): { pattern: string; worker_id: number; acquired_at: string }[] {
    return this.db.query(`
      SELECT pattern, worker_id, acquired_at 
      FROM file_locks 
      WHERE run_id = ? 
      ORDER BY acquired_at DESC
    `).all(runId) as { pattern: string; worker_id: number; acquired_at: string }[];
  }

  getTaskStats(runId: string): {
    pending: number;
    in_progress: number;
    completed: number;
    failed: number;
  } {
    const stats = this.db.query(`
      SELECT 
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed
      FROM tasks 
      WHERE run_id = ?
    `).get(runId) as { pending: number; in_progress: number; completed: number; failed: number };
    return stats;
  }

  getTotalCosts(runId: string): {
    total_cost: number;
    total_prompt_tokens: number;
    total_completion_tokens: number;
  } {
    const costs = this.db.query(`
      SELECT 
        COALESCE(SUM(cost), 0) as total_cost,
        COALESCE(SUM(prompt_tokens), 0) as total_prompt_tokens,
        COALESCE(SUM(completion_tokens), 0) as total_completion_tokens
      FROM task_costs 
      WHERE run_id = ?
    `).get(runId) as {
      total_cost: number;
      total_prompt_tokens: number;
      total_completion_tokens: number;
    };
    return costs;
  }

  async getRecentLogs(runId: string, limit: number = 20): Promise<Array<{ worker_num: string; log_line: string; timestamp: number }>> {
    const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', 'projects', '.ralph');
    const runDir = path.join(ralphDir, 'swarm', 'runs', runId);
    const logs: Array<{ worker_num: string; log_line: string; timestamp: number }> = [];

    try {
      const entries = await fs.promises.readdir(runDir, { withFileTypes: true });
      const workerDirs = entries.filter(dirent => dirent.isDirectory() && dirent.name.startsWith('worker-'));

      let lineCounter = 0;

      for (const workerDir of workerDirs) {
        const logsDir = path.join(runDir, workerDir.name, 'logs');
        try {
          await fs.promises.access(logsDir);
        } catch {
          continue;
        }

        const logFiles = await fs.promises.readdir(logsDir);
        const logFilesWithStats = await Promise.all(logFiles
          .filter(file => file.endsWith('.log'))
          .map(async file => {
             const stats = await fs.promises.stat(path.join(logsDir, file));
             return { file, mtimeMs: stats.mtimeMs };
          }));

        logFilesWithStats.sort((a, b) => b.mtimeMs - a.mtimeMs);

        for (const { file, mtimeMs } of logFilesWithStats) {
          const logPath = path.join(logsDir, file);
          
          const lines = await readLastLines(logPath, limit * 2);
          for (const line of lines) {
            logs.push({
              worker_num: workerDir.name.replace('worker-', ''),
              log_line: line,
              timestamp: mtimeMs - (lineCounter * 1000)
            });
            lineCounter++;
            if (logs.length >= limit * 2) break;
          }
          if (logs.length >= limit * 2) break;
        }
        if (logs.length >= limit * 2) break;
      }

      logs.sort((a, b) => b.timestamp - a.timestamp);
      return logs.slice(0, limit);
    } catch (error) {
      return [];
    }
  }
}

export function getSwarmDatabasePath(): string {
  const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', 'projects', '.ralph');
  return path.join(ralphDir, 'swarm.db');
}

export function createSwarmDatabase(dbPath?: string): SwarmDatabase {
  const path = dbPath || getSwarmDatabasePath();
  return new SwarmDatabase(path);
}
