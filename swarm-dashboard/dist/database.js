import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
export class SwarmDatabase {
    db;
    getCurrentRunStmt;
    constructor(dbPath) {
        const absolutePath = path.resolve(dbPath);
        if (!fs.existsSync(absolutePath)) {
            throw new Error(`Database not found: ${absolutePath}`);
        }
        this.db = new Database(absolutePath, { readonly: true, fileMustExist: true });
        this.getCurrentRunStmt = this.db.prepare(`
      SELECT * FROM swarm_runs 
      WHERE status = 'running' 
      ORDER BY started_at DESC 
      LIMIT 1
    `);
    }
    close() {
        this.db.close();
    }
    getCurrentRun() {
        return this.getCurrentRunStmt.get();
    }
    getWorkersByRun(runId) {
        const stmt = this.db.prepare(`
      SELECT * FROM workers 
      WHERE run_id = ? 
      ORDER BY worker_num
    `);
        return stmt.all(runId);
    }
    getTasksByRun(runId) {
        const stmt = this.db.prepare(`
      SELECT * FROM tasks 
      WHERE run_id = ? 
      ORDER BY priority, id
    `);
        return stmt.all(runId);
    }
    getTaskById(taskId) {
        const stmt = this.db.prepare('SELECT * FROM tasks WHERE id = ?');
        return stmt.get(taskId);
    }
    getTaskCostsByRun(runId) {
        const stmt = this.db.prepare(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC
    `);
        return stmt.all(runId);
    }
    getRecentTaskCosts(runId, limit = 20) {
        const stmt = this.db.prepare(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC 
      LIMIT ?
    `);
        return stmt.all(runId, limit);
    }
    getRecentRuns(limit = 10) {
        const stmt = this.db.prepare(`
      SELECT * FROM swarm_runs 
      ORDER BY started_at DESC 
      LIMIT ?
    `);
        return stmt.all(limit);
    }
    getFileLocksByRun(runId) {
        const stmt = this.db.prepare(`
      SELECT pattern, worker_id, acquired_at 
      FROM file_locks 
      WHERE run_id = ? 
      ORDER BY acquired_at DESC
    `);
        return stmt.all(runId);
    }
    getTaskStats(runId) {
        const stmt = this.db.prepare(`
      SELECT 
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed
      FROM tasks 
      WHERE run_id = ?
    `);
        return stmt.get(runId);
    }
    getTotalCosts(runId) {
        const stmt = this.db.prepare(`
      SELECT 
        COALESCE(SUM(cost), 0) as total_cost,
        COALESCE(SUM(prompt_tokens), 0) as total_prompt_tokens,
        COALESCE(SUM(completion_tokens), 0) as total_completion_tokens
      FROM task_costs 
      WHERE run_id = ?
    `);
        return stmt.get(runId);
    }
}
export function getSwarmDatabasePath() {
    const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', 'projects', '.ralph');
    return path.join(ralphDir, 'swarm.db');
}
export function createSwarmDatabase(dbPath) {
    const path = dbPath || getSwarmDatabasePath();
    return new SwarmDatabase(path);
}
//# sourceMappingURL=database.js.map