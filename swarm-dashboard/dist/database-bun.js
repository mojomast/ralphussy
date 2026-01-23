import Database from 'bun:sqlite';
import path from 'path';
import fs from 'fs';
export class SwarmDatabase {
    db;
    constructor(dbPath) {
        const absolutePath = path.resolve(dbPath);
        if (!fs.existsSync(absolutePath)) {
            throw new Error(`Database not found: ${absolutePath}`);
        }
        this.db = new Database(absolutePath, { readonly: true });
    }
    close() {
        this.db.close();
    }
    getCurrentRun() {
        const run = this.db.query(`
      SELECT * FROM swarm_runs 
      WHERE status = 'running' 
      ORDER BY started_at DESC 
      LIMIT 1
    `).get();
        return run || null;
    }
    getWorkersByRun(runId) {
        return this.db.query(`
      SELECT * FROM workers 
      WHERE run_id = ? 
      ORDER BY worker_num
    `).all(runId);
    }
    getTasksByRun(runId) {
        return this.db.query(`
      SELECT * FROM tasks 
      WHERE run_id = ? 
      ORDER BY priority, id
    `).all(runId);
    }
    getTaskById(taskId) {
        const task = this.db.query('SELECT * FROM tasks WHERE id = ?').get(taskId);
        return task || null;
    }
    getTaskCostsByRun(runId) {
        return this.db.query(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC
    `).all(runId);
    }
    getRecentTaskCosts(runId, limit = 20) {
        return this.db.query(`
      SELECT * FROM task_costs 
      WHERE run_id = ? 
      ORDER BY created_at DESC 
      LIMIT ?
    `).all(runId, limit);
    }
    getRecentRuns(limit = 10) {
        return this.db.query(`
      SELECT * FROM swarm_runs 
      ORDER BY started_at DESC 
      LIMIT ?
    `).all(limit);
    }
    getFileLocksByRun(runId) {
        return this.db.query(`
      SELECT pattern, worker_id, acquired_at 
      FROM file_locks 
      WHERE run_id = ? 
      ORDER BY acquired_at DESC
    `).all(runId);
    }
    getTaskStats(runId) {
        const stats = this.db.query(`
      SELECT 
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed
      FROM tasks 
      WHERE run_id = ?
    `).get(runId);
        return stats;
    }
    getTotalCosts(runId) {
        const costs = this.db.query(`
      SELECT 
        COALESCE(SUM(cost), 0) as total_cost,
        COALESCE(SUM(prompt_tokens), 0) as total_prompt_tokens,
        COALESCE(SUM(completion_tokens), 0) as total_completion_tokens
      FROM task_costs 
      WHERE run_id = ?
    `).get(runId);
        return costs;
    }
    getRecentLogs(runId, limit = 20) {
        const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', '.ralph');
        const runDir = path.join(ralphDir, 'swarm', 'runs', runId);
        const logs = [];
        try {
            const workerDirs = fs.readdirSync(runDir, { withFileTypes: true })
                .filter(dirent => dirent.isDirectory() && dirent.name.startsWith('worker-'));
            const now = Date.now();
            let lineCounter = 0;
            for (const workerDir of workerDirs) {
                const logsDir = path.join(runDir, workerDir.name, 'logs');
                if (!fs.existsSync(logsDir))
                    continue;
                const logFiles = fs.readdirSync(logsDir)
                    .filter(file => file.endsWith('.log'))
                    .sort((a, b) => {
                    const statA = fs.statSync(path.join(logsDir, a));
                    const statB = fs.statSync(path.join(logsDir, b));
                    return statB.mtimeMs - statA.mtimeMs;
                });
                for (const logFile of logFiles) {
                    const logPath = path.join(logsDir, logFile);
                    const stats = fs.statSync(logPath);
                    const lines = fs.readFileSync(logPath, 'utf-8').split('\n').reverse().filter(line => line.trim());
                    for (const line of lines) {
                        logs.push({
                            worker_num: workerDir.name.replace('worker-', ''),
                            log_line: line,
                            timestamp: stats.mtimeMs - (lineCounter * 1000)
                        });
                        lineCounter++;
                        if (logs.length >= limit * 2)
                            break;
                    }
                    if (logs.length >= limit * 2)
                        break;
                }
                if (logs.length >= limit * 2)
                    break;
            }
            logs.sort((a, b) => b.timestamp - a.timestamp);
            return logs.slice(0, limit);
        }
        catch (error) {
            return [];
        }
    }
}
export function getSwarmDatabasePath() {
    const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', '.ralph');
    return path.join(ralphDir, 'swarm.db');
}
export function createSwarmDatabase(dbPath) {
    const path = dbPath || getSwarmDatabasePath();
    return new SwarmDatabase(path);
}
//# sourceMappingURL=database-bun.js.map