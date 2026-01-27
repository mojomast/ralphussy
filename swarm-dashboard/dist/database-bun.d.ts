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
export declare class SwarmDatabase {
    private db;
    constructor(dbPath: string);
    close(): void;
    getCurrentRun(): SwarmRun | null;
    getWorkersByRun(runId: string): Worker[];
    getTasksByRun(runId: string): Task[];
    getTaskById(taskId: number): Task | null;
    getTaskCostsByRun(runId: string): TaskCost[];
    getRecentTaskCosts(runId: string, limit?: number): TaskCost[];
    getRecentRuns(limit?: number): SwarmRun[];
    getRunById(runId: string): SwarmRun | null;
    getFileLocksByRun(runId: string): {
        pattern: string;
        worker_id: number;
        acquired_at: string;
    }[];
    getTaskStats(runId: string): {
        pending: number;
        in_progress: number;
        completed: number;
        failed: number;
    };
    getTotalCosts(runId: string): {
        total_cost: number;
        total_prompt_tokens: number;
        total_completion_tokens: number;
    };
    getRecentLogs(runId: string, limit?: number): Array<{
        worker_num: string;
        log_line: string;
        timestamp: number;
    }>;
}
export declare function getSwarmDatabasePath(): string;
export declare function createSwarmDatabase(dbPath?: string): SwarmDatabase;
//# sourceMappingURL=database-bun.d.ts.map