import Database from 'bun:sqlite';
import path from 'path';
import fs from 'fs';
async function readLastLines(filePath, maxLines, maxBytes = 64 * 1024) {
    try {
        const stats = await fs.promises.stat(filePath);
        const size = stats.size;
        if (size === 0)
            return [];
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
        }
        finally {
            await handle.close();
        }
    }
    catch (error) {
        return [];
    }
}
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
    getRunById(runId) {
        const run = this.db.query(`
      SELECT * FROM swarm_runs 
      WHERE run_id = ?
    `).get(runId);
        return run || null;
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
    async getRecentLogs(runId, limit = 20) {
        const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', 'projects', '.ralph');
        const runDir = path.join(ralphDir, 'swarm', 'runs', runId);
        const logs = [];
        try {
            const entries = await fs.promises.readdir(runDir, { withFileTypes: true });
            const workerDirs = entries.filter(dirent => dirent.isDirectory() && dirent.name.startsWith('worker-'));
            let lineCounter = 0;
            for (const workerDir of workerDirs) {
                const logsDir = path.join(runDir, workerDir.name, 'logs');
                try {
                    await fs.promises.access(logsDir);
                }
                catch {
                    continue;
                }
                const logFiles = await fs.promises.readdir(logsDir);
                const logFilesWithStats = await Promise.all(logFiles
                    .filter(file => file.endsWith('.log'))
                    .map(async (file) => {
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
    const ralphDir = process.env.RALPH_DIR || path.join(process.env.HOME || '', 'projects', '.ralph');
    return path.join(ralphDir, 'swarm.db');
}
export function createSwarmDatabase(dbPath) {
    const path = dbPath || getSwarmDatabasePath();
    return new SwarmDatabase(path);
}
//# sourceMappingURL=database-bun.js.map