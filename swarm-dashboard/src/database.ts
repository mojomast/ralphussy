import Database from 'better-sqlite3';
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

export class SwarmDatabase {
  private db: Database.Database;

  constructor(dbPath: string) {
    const absolutePath = path.resolve(dbPath);
    if (!fs.existsSync(absolutePath)) {
      throw new Error(`Database not found: ${absolutePath}`);
    }
    this.db = new Database(absolutePath, { readonly: true, fileMustExist: true });
  }

  close(): void {
    this.db.close();
  }

  getCurrentRun(): SwarmRun | null {
    const stmt = this.db.prepare(`
      SELECT * FROM swarm_runs 
      WHERE status = 'running' 
      ORDER BY started_at DESC 
      LIMIT 1
    `);
    return stmt.get() as SwarmRun | null;
  }

  getWorkersByRun(runId: string): Worker[] {
    const stmt = this.db.prepare(`
      SELECT * FROM workers 
      WHERE run_id = ? 
      ORDER BY worker_num
    `);
    return stmt.all(runId) as Worker[];
  }

  getTasksByRun(runId: string): Task[] {
    const stmt = this.db.prepare(`
      SELECT * FROM tasks 
      WHERE run_id = ? 
      ORDER BY priority, id
    `);
    return stmt.all(runId) as Task[];
  }

  getTaskById(taskId: number): Task | null {
    const stmt = this.db.prepare('SELECT * FROM tasks WHERE id = ?');
    return stmt.get(taskId) as Task | null;
  }

  getTaskCostsByRun(runId: string): TaskCost[] {
    const stmt = this.db.prepare(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC
    `);
    return stmt.all(runId) as TaskCost[];
  }

  getRecentTaskCosts(runId: string, limit: number = 20): TaskCost[] {
    const stmt = this.db.prepare(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC 
      LIMIT ?
    `);
    return stmt.all(runId, limit) as TaskCost[];
  }

  getRecentRuns(limit: number = 10): SwarmRun[] {
    const stmt = this.db.prepare(`
      SELECT * FROM swarm_runs 
      ORDER BY started_at DESC 
      LIMIT ?
    `);
    return stmt.all(limit) as SwarmRun[];
  }

  getFileLocksByRun(runId: string): { pattern: string; worker_id: number; acquired_at: string }[] {
    const stmt = this.db.prepare(`
      SELECT pattern, worker_id, acquired_at 
      FROM file_locks 
      WHERE run_id = ? 
      ORDER BY acquired_at DESC
    `);
    return stmt.all(runId) as { pattern: string; worker_id: number; acquired_at: string }[];
  }

  getTaskStats(runId: string): {
    pending: number;
    in_progress: number;
    completed: number;
    failed: number;
  } {
    const stmt = this.db.prepare(`
      SELECT 
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed
      FROM tasks 
      WHERE run_id = ?
    `);
    return stmt.get(runId) as {
      pending: number;
      in_progress: number;
      completed: number;
      failed: number;
    };
  }

  getTotalCosts(runId: string): {
    total_cost: number;
    total_prompt_tokens: number;
    total_completion_tokens: number;
  } {
    const stmt = this.db.prepare(`
      SELECT 
        COALESCE(SUM(cost), 0) as total_cost,
        COALESCE(SUM(prompt_tokens), 0) as total_prompt_tokens,
        COALESCE(SUM(completion_tokens), 0) as total_completion_tokens
      FROM task_costs 
      WHERE run_id = ?
    `);
    return stmt.get(runId) as {
      total_cost: number;
      total_prompt_tokens: number;
      total_completion_tokens: number;
    };
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
