#!/usr/bin/env bash

__SWARM_DB_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# swarms depend on sqlite3, but some environments (including CI containers)
# don't have the sqlite3 CLI installed.
#
# Provide a minimal wrapper that prefers the system sqlite3 binary and falls
# back to a tiny python-based shim at ralph-refactor/tools/sqlite3.
sqlite3() {
    local sys_sqlite3
    sys_sqlite3=$(type -P sqlite3 2>/dev/null || true)
    if [ -n "$sys_sqlite3" ]; then
        "$sys_sqlite3" "$@"
        return $?
    fi

    local shim="$__SWARM_DB_DIR__/../tools/sqlite3"
    if [ -x "$shim" ]; then
        "$shim" "$@"
        return $?
    fi

    echo "sqlite3: command not found (and shim missing at $shim)" 1>&2
    return 127
}

swarm_db_init() {
    local db_path="$RALPH_DIR/swarm.db"
    mkdir -p "$(dirname "$db_path")"
    local dir

    for dir in "$RALPH_DIR/swarm/runs"; do
        mkdir -p "$dir"
    done

    # sqlite3 prints the new journal mode for PRAGMA journal_mode=WAL on some
    # builds; silence init output to keep tests clean.
     sqlite3 "$db_path" >/dev/null <<'EOF'
   PRAGMA journal_mode=WAL;
   PRAGMA synchronous=NORMAL;
   PRAGMA foreign_keys=ON;
   PRAGMA busy_timeout=120000;        # INCREASED: 120 seconds (was 30)
   PRAGMA wal_autocheckpoint=1000;
   
   # Additional performance optimizations for high concurrency
   PRAGMA cache_size=-64000;          # 64MB cache (negative = KB)
   PRAGMA temp_store=MEMORY;          # Use RAM for temp tables
   PRAGMA mmap_size=268435456;        # 256MB memory-mapped I/O
   PRAGMA page_size=4096;             # Larger page size for better perf

CREATE TABLE IF NOT EXISTS swarm_runs (
    id INTEGER PRIMARY KEY,
    run_id TEXT UNIQUE NOT NULL,
    status TEXT DEFAULT 'running',
    source_type TEXT,
    source_path TEXT,
    source_hash TEXT,
    source_prompt TEXT,
    worker_count INTEGER,
    total_tasks INTEGER DEFAULT 0,
    completed_tasks INTEGER DEFAULT 0,
    failed_tasks INTEGER DEFAULT 0,
    started_at TEXT,
    completed_at TEXT
);

CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY,
    run_id TEXT NOT NULL,
    task_text TEXT NOT NULL,
    task_hash TEXT,
    status TEXT DEFAULT 'pending',
    worker_id INTEGER,
    priority INTEGER DEFAULT 0,
    estimated_files TEXT,
    actual_files TEXT,
    devplan_line INTEGER,
    created_at TEXT,
    started_at TEXT,
    completed_at TEXT,
    error_message TEXT,
    stall_count INTEGER DEFAULT 0,
    FOREIGN KEY (run_id) REFERENCES swarm_runs(run_id)
);

CREATE TABLE IF NOT EXISTS workers (
    id INTEGER PRIMARY KEY,
    run_id TEXT NOT NULL,
    worker_num INTEGER NOT NULL,
    pid INTEGER,
    branch_name TEXT,
    status TEXT DEFAULT 'idle',
    current_task_id INTEGER,
    locked_files TEXT,
    work_dir TEXT,
    started_at TEXT,
    last_heartbeat TEXT,
    FOREIGN KEY (run_id) REFERENCES swarm_runs(run_id),
    FOREIGN KEY (current_task_id) REFERENCES tasks(id)
);

 CREATE TABLE IF NOT EXISTS file_locks (
    id INTEGER PRIMARY KEY,
    run_id TEXT NOT NULL,
    pattern TEXT NOT NULL,
    worker_id INTEGER NOT NULL,
    task_id INTEGER NOT NULL,
    acquired_at TEXT,
    UNIQUE(run_id, pattern),
    FOREIGN KEY (worker_id) REFERENCES workers(id),
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

 CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(run_id, status);
 CREATE INDEX IF NOT EXISTS idx_workers_status ON workers(run_id, status);
 CREATE INDEX IF NOT EXISTS idx_file_locks_worker ON file_locks(worker_id);

 -- Prevent multiple workers from claiming same task
 CREATE UNIQUE INDEX IF NOT EXISTS idx_task_in_progress 
   ON tasks(id) 
   WHERE status = 'in_progress';

 -- Performance indexes for faster queries
 CREATE INDEX IF NOT EXISTS idx_tasks_hash ON tasks(task_hash);
 CREATE INDEX IF NOT EXISTS idx_completed_tasks_source ON completed_tasks(source_hash, task_hash);
 CREATE INDEX IF NOT EXISTS idx_workers_run_status ON workers(run_id, status);
 CREATE INDEX IF NOT EXISTS idx_tasks_run_status_priority ON tasks(run_id, status, priority);

 -- Optional cost tracking for OpenCode runs (best-effort; some providers may not report cost).
 CREATE TABLE IF NOT EXISTS task_costs (
     id INTEGER PRIMARY KEY,
     run_id TEXT NOT NULL,
     task_id INTEGER NOT NULL,
     prompt_tokens INTEGER DEFAULT 0,
     completion_tokens INTEGER DEFAULT 0,
     cost REAL DEFAULT 0,
     created_at TEXT,
     FOREIGN KEY (run_id) REFERENCES swarm_runs(run_id),
     FOREIGN KEY (task_id) REFERENCES tasks(id)
 );

  CREATE INDEX IF NOT EXISTS idx_task_costs_run_id ON task_costs(run_id);
  CREATE INDEX IF NOT EXISTS idx_task_costs_task_id ON task_costs(task_id);

  -- System configuration table for swarm limits
  CREATE TABLE IF NOT EXISTS swarm_config (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at TEXT
  );

  -- Worker registry for tracking all active workers system-wide
  CREATE TABLE IF NOT EXISTS worker_registry (
      id INTEGER PRIMARY KEY,
      worker_id INTEGER NOT NULL,
      run_id TEXT NOT NULL,
      worker_num INTEGER NOT NULL,
      pid INTEGER NOT NULL,
      started_at TEXT,
      last_heartbeat TEXT,
      FOREIGN KEY (worker_id) REFERENCES workers(id)
  );

  CREATE INDEX IF NOT EXISTS idx_worker_registry_pid ON worker_registry(pid);
  CREATE INDEX IF NOT EXISTS idx_worker_registry_run_id ON worker_registry(run_id);
  CREATE INDEX IF NOT EXISTS idx_worker_registry_active ON worker_registry(last_heartbeat);

  -- Completed tasks tracking for cross-run resume functionality
  -- Stores hashes of tasks that have been successfully completed
  CREATE TABLE IF NOT EXISTS completed_tasks (
      id INTEGER PRIMARY KEY,
      task_hash TEXT UNIQUE NOT NULL,
      task_text TEXT,
      source_hash TEXT,
      completed_at TEXT,
      run_id TEXT
  );

   CREATE INDEX IF NOT EXISTS idx_completed_tasks_hash ON completed_tasks(task_hash);
   CREATE INDEX IF NOT EXISTS idx_completed_tasks_source ON completed_tasks(source_hash);
EOF

    # Migration: Add missing columns to existing tables (for schema upgrades)
    # These ALTER TABLE statements are safe even if columns already exist
    sqlite3 "$db_path" "ALTER TABLE swarm_runs ADD COLUMN source_hash TEXT;" 2>/dev/null || true
    sqlite3 "$db_path" "ALTER TABLE tasks ADD COLUMN task_hash TEXT;" 2>/dev/null || true

    # Set default configuration values
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_max_workers', '${SWARM_MAX_WORKERS:-8}', datetime('now'));"
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_spawn_delay', '${SWARM_SPAWN_DELAY:-1}', datetime('now'));"
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_max_total_workers', '${SWARM_MAX_TOTAL_WORKERS:-16}', datetime('now'));"
    # Resource limits disabled by default (0 = no limit) to prevent fork errors
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_max_processes_per_worker', '${SWARM_MAX_PROCESSES_PER_WORKER:-0}', datetime('now'));"
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_max_memory_mb', '${SWARM_MAX_MEMORY_MB:-0}', datetime('now'));"
    sqlite3 "$db_path" "INSERT OR IGNORE INTO swarm_config (key, value, updated_at) VALUES ('swarm_max_cpu_seconds', '${SWARM_MAX_CPU_SECONDS:-0}', datetime('now'));"

    echo "Database initialized at: $db_path"
}

swarm_db_record_task_cost() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local task_id="$2"
    local prompt_tokens="${3:-0}"
    local completion_tokens="${4:-0}"
    local cost="${5:-0}"

    # Keep this best-effort; cost reporting varies by provider/model.
    sqlite3 "$db_path" <<EOF
INSERT INTO task_costs (
    run_id, task_id, prompt_tokens, completion_tokens, cost, created_at
) VALUES (
    '$run_id', $task_id, $prompt_tokens, $completion_tokens, $cost, datetime('now')
);
EOF
}

swarm_db_get_total_cost() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" "SELECT COALESCE(SUM(cost), 0) FROM task_costs WHERE run_id = '$run_id';"
}

swarm_db_force_reiterate_worker() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local worker_num="$2"

    if [ -z "$run_id" ] || [ -z "$worker_num" ]; then
        echo "Usage: swarm_db_force_reiterate_worker <run_id> <worker_num>" 1>&2
        return 1
    fi

    local worker_id
    worker_id=$(sqlite3 "$db_path" "SELECT id FROM workers WHERE run_id = '$run_id' AND worker_num = $worker_num ORDER BY id DESC LIMIT 1;")
    if [ -z "$worker_id" ] || [ "$worker_id" = "NULL" ]; then
        echo "Worker $worker_num not found for run $run_id" 1>&2
        return 1
    fi

    local current_task_id
    current_task_id=$(sqlite3 "$db_path" "SELECT current_task_id FROM workers WHERE id = $worker_id;")

    # Release locks for the worker record.
    swarm_db_release_locks "$worker_id" >/dev/null 2>&1 || true

    # Re-queue current task if any.
    if [ -n "$current_task_id" ] && [ "$current_task_id" != "NULL" ]; then
        sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'pending',
    worker_id = NULL,
    started_at = NULL,
    stall_count = stall_count + 1,
    error_message = COALESCE(error_message, '')
WHERE id = $current_task_id AND run_id = '$run_id';

COMMIT;
EOF
    fi

    sqlite3 "$db_path" <<EOF
UPDATE workers
SET status = 'idle',
    current_task_id = NULL,
    last_heartbeat = NULL
WHERE id = $worker_id;
EOF

    echo "$worker_id"
}

swarm_db_start_run() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_type="$1"
    local source_path="$2"
    local source_hash="$3"
    local source_prompt="$4"
    local worker_count="$5"

    local run_id
    run_id=$(date +%Y%m%d_%H%M%S)

    sqlite3 "$db_path" <<EOF
INSERT INTO swarm_runs (
    run_id, status, source_type, source_path, source_hash, source_prompt,
    worker_count, total_tasks, started_at
) VALUES (
    '$run_id', 'running', '$source_type', '$source_path', '$source_hash', '$source_prompt',
    $worker_count, 0, datetime('now')
);
EOF

    # echo run_id without additional newlines so callers receive a clean token
    printf "%s" "$run_id"
}

swarm_db_end_run() {
    local run_id="$1"

    sqlite3 "$RALPH_DIR/swarm.db" <<EOF
UPDATE swarm_runs
SET status = 'completed',
    completed_at = datetime('now')
WHERE run_id = '$run_id';
EOF

    echo "Run $run_id marked as completed"
}

swarm_db_add_task() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local task_text="$2"
    local estimated_files="$3"
    local devplan_line="$4"
    local priority="${5:-0}"

    # Calculate task hash for deduplication
    local task_hash
    task_hash=$(printf '%s' "$task_text" | sha256sum | cut -d' ' -f1)

    # Check if this exact task already exists in completed_tasks
    local already_completed
    already_completed=$(swarm_db_is_task_completed "$task_hash")
    
    if [ "$already_completed" = "yes" ]; then
        echo "Task already completed in previous run, skipping: $task_text" >&2
        # Return a special marker instead of task_id
        echo "SKIPPED"
        return 0
    fi

    # Insert task with hash
    local task_id
    task_id=$(sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;
INSERT INTO tasks (
    run_id, task_text, task_hash, status, priority, estimated_files, devplan_line, created_at
) VALUES (
    '$run_id', '$task_text', '$task_hash', 'pending', $priority, '$estimated_files', $devplan_line, datetime('now')
);
-- Recalculate total_tasks to avoid relying on incremental updates
UPDATE swarm_runs
SET total_tasks = (SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id')
WHERE run_id = '$run_id';
SELECT id FROM tasks WHERE run_id = '$run_id' ORDER BY id DESC LIMIT 1;
COMMIT;
EOF
)

    echo "$task_id"
}

swarm_db_claim_task() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"

    local task_id
    local task_text
    local estimated_files
    local devplan_line

    local max_retries=20
    local retry_delay=0.1
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        task_id=$(sqlite3 "$db_path" <<EOF 2>/dev/null
BEGIN IMMEDIATE TRANSACTION;

UPDATE tasks
SET status = 'in_progress',
    worker_id = $worker_id,
    started_at = datetime('now')
WHERE id IN (
    SELECT id FROM tasks
    WHERE run_id = (SELECT run_id FROM workers WHERE id = $worker_id)
    AND status = 'pending'
    ORDER BY priority ASC, id ASC
    LIMIT 1
)
RETURNING id;

COMMIT;
EOF
)

        local exit_code=$?
        
        # If claim succeeded, verify we actually got the task
        if [ $exit_code -eq 0 ] && [ -n "$task_id" ]; then
            # VERIFICATION: Check that WE are the worker assigned to this task
            local assigned_worker
            assigned_worker=$(sqlite3 "$db_path" "SELECT worker_id FROM tasks WHERE id = $task_id AND status = 'in_progress';")
            
            if [ "$assigned_worker" = "$worker_id" ]; then
                # Success! We own this task
                break
            else
                # Race condition: another worker grabbed it between our update and verify
                echo "[RACE] Worker $worker_id lost race for task $task_id to worker $assigned_worker" >&2
                task_id=""
            fi
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            sleep $retry_delay
            retry_delay=$(awk "BEGIN {print $retry_delay * 1.5}")  # Exponential backoff
        fi
    done

    if [ -z "$task_id" ]; then
        # No pending tasks available after retries
        echo ""
        return 0
    fi

    # Fetch task details
    task_text=$(sqlite3 "$db_path" "SELECT task_text FROM tasks WHERE id = $task_id")
    estimated_files=$(sqlite3 "$db_path" "SELECT estimated_files FROM tasks WHERE id = $task_id")
    devplan_line=$(sqlite3 "$db_path" "SELECT devplan_line FROM tasks WHERE id = $task_id")

    echo "$task_id|$task_text|$estimated_files|$devplan_line"
}

swarm_db_complete_task() {
    local db_path="$RALPH_DIR/swarm.db"
    local task_id="$1"
    local actual_files="$2"
    local worker_id="$3"

    # Get task info before marking complete
    local task_text task_hash run_id source_hash
    task_text=$(sqlite3 "$db_path" "SELECT task_text FROM tasks WHERE id = $task_id;")
    run_id=$(sqlite3 "$db_path" "SELECT run_id FROM tasks WHERE id = $task_id;")
    source_hash=$(sqlite3 "$db_path" "SELECT source_hash FROM swarm_runs WHERE run_id = '$run_id';")

    # Generate task hash for deduplication
    task_hash=$(printf '%s' "$task_text" | sha256sum | cut -d' ' -f1)

    sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'completed',
    completed_at = datetime('now'),
    actual_files = '$actual_files',
    task_hash = '$task_hash'
WHERE id = $task_id AND worker_id = $worker_id;

UPDATE swarm_runs
SET completed_tasks = completed_tasks + 1
WHERE run_id = (SELECT run_id FROM tasks WHERE id = $task_id);

-- Record in completed_tasks table for cross-run resume
INSERT OR IGNORE INTO completed_tasks (task_hash, task_text, source_hash, completed_at, run_id)
VALUES ('$task_hash', '$task_text', '$source_hash', datetime('now'), '$run_id');

COMMIT;
EOF

    echo "Task $task_id completed"
    swarm_db_maybe_finalize_run "$task_id"
    swarm_db_finalize_if_no_pending_tasks "$task_id"
}

# Fallback finalization: mark run completed when no remaining non-completed tasks exist
swarm_db_finalize_if_no_pending_tasks() {
    local db_path="$RALPH_DIR/swarm.db"
    local task_id="$1"

    local remaining
    remaining=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = (SELECT run_id FROM tasks WHERE id = $task_id) AND status != 'completed';")

    if [ "$remaining" = "0" ] || [ "$remaining" = "0|" ]; then
        sqlite3 "$db_path" <<EOF
UPDATE swarm_runs
SET status = 'completed', completed_at = datetime('now')
WHERE run_id = (SELECT run_id FROM tasks WHERE id = $task_id);
EOF
    fi
}

# After completing a task, if completed_tasks == total_tasks mark run completed
swarm_db_maybe_finalize_run() {
    local db_path="$RALPH_DIR/swarm.db"
    local task_id="$1"

    sqlite3 "$db_path" <<EOF
UPDATE swarm_runs
SET status = 'completed', completed_at = datetime('now')
WHERE run_id = (SELECT run_id FROM tasks WHERE id = $task_id)
  AND completed_tasks >= total_tasks;
EOF

}

swarm_db_fail_task() {
    local db_path="$RALPH_DIR/swarm.db"
    local task_id="$1"
    local worker_id="$2"
    local error_message="$3"

    sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'failed',
    completed_at = datetime('now'),
    error_message = '$error_message'
WHERE id = $task_id AND worker_id = $worker_id;

UPDATE swarm_runs
SET failed_tasks = failed_tasks + 1
WHERE run_id = (SELECT run_id FROM tasks WHERE id = $task_id);

COMMIT;
EOF

    echo "Task $task_id failed: $error_message"
}

swarm_db_register_worker() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local worker_num="$2"
    local pid="$3"
    local branch_name="$4"
    local work_dir="$5"

    local worker_id
    worker_id=$(sqlite3 "$db_path" <<EOF
INSERT INTO workers (
    run_id, worker_num, pid, branch_name, status, work_dir, started_at
) VALUES (
    '$run_id', $worker_num, $pid, '$branch_name', 'idle', '$work_dir', datetime('now')
);

SELECT last_insert_rowid();
EOF
)

    echo "$worker_id"
}

swarm_db_update_worker_pid() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"
    local pid="$2"

    sqlite3 "$db_path" <<EOF
UPDATE workers
SET pid = $pid
WHERE id = $worker_id;
EOF
}

swarm_db_worker_heartbeat() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"

    sqlite3 "$db_path" <<EOF
UPDATE workers
SET last_heartbeat = datetime('now')
WHERE id = $worker_id;
EOF

    echo "Heartbeat sent for worker $worker_id"
}

swarm_db_worker_status() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local worker_num="$2"

    sqlite3 "$db_path" <<EOF
SELECT id, pid, branch_name, status, current_task_id, locked_files, work_dir, started_at, last_heartbeat
FROM workers
WHERE run_id = '$run_id' AND worker_num = $worker_num;
EOF
}

swarm_db_get_run_status() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT status, total_tasks, completed_tasks, failed_tasks,
       datetime(started_at) as started_at,
       datetime(completed_at) as completed_at
FROM swarm_runs
WHERE run_id = '$run_id';
EOF
}

swarm_db_get_worker_stats() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT status, COUNT(*) as count
FROM workers
WHERE run_id = '$run_id'
GROUP BY status;
EOF
}

swarm_db_acquire_locks() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local worker_id="$2"
    local task_id="$3"

    shift 3
    local patterns=("$@")

    local lock_id
    lock_id=$(sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

EOF
)

    for pattern in "${patterns[@]}"; do
        local pattern_clean=$(echo "$pattern" | sed "s/'//g")

        # If caller passed a JSON array like ["a","b"], split into elements
        if echo "$pattern_clean" | grep -qE '^\[.*\]$'; then
            # remove brackets
            local inner=${pattern_clean#\[}
            inner=${inner%\]}
            # split by comma
            IFS=',' read -ra parts <<< "$inner"
            for p in "${parts[@]}"; do
                # trim whitespace and quotes
                p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//')
                sqlite3 "$db_path" <<EOF
INSERT OR IGNORE INTO file_locks (run_id, pattern, worker_id, task_id, acquired_at)
VALUES ('$run_id', '$p', $worker_id, $task_id, datetime('now'));
EOF
            done
        else
            sqlite3 "$db_path" <<EOF
INSERT OR IGNORE INTO file_locks (run_id, pattern, worker_id, task_id, acquired_at)
VALUES ('$run_id', '$pattern_clean', $worker_id, $task_id, datetime('now'));
EOF
        fi
    done

    sqlite3 "$db_path" "COMMIT;"
    echo "Acquired locks for worker $worker_id"
}

swarm_db_release_locks() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"

    sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

DELETE FROM file_locks WHERE worker_id = $worker_id;

COMMIT;
EOF

    echo "Released locks for worker $worker_id"
}

swarm_db_check_conflicts() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local file_pattern="$2"

    # Accept both raw pattern or JSON array element
    local pattern_clean=$(echo "$file_pattern" | sed "s/'//g" | sed 's/^"//;s/"$//')

    sqlite3 "$db_path" <<EOF
SELECT worker_id, task_id, pattern
FROM file_locks
WHERE run_id = '$run_id' AND pattern = '$pattern_clean';
EOF
}

swarm_db_get_locked_files() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT DISTINCT pattern, worker_id
FROM file_locks
WHERE run_id = '$run_id';
EOF
}

swarm_db_cleanup_stale_workers() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local threshold_seconds=60

    local stale_workers
    stale_workers=$(sqlite3 "$db_path" <<EOF
SELECT id FROM workers
WHERE run_id = '$run_id'
AND (last_heartbeat IS NULL OR datetime(last_heartbeat) < datetime('now', '-$threshold_seconds seconds'))
AND status != 'completed';
EOF
)

    if [ -z "$stale_workers" ]; then
        echo "No stale workers found"
        return 0
    fi

    local old_ifs="$IFS"
    IFS='|' read -ra worker_ids <<< "$stale_workers"
    IFS="$old_ifs"

    for worker_id in "${worker_ids[@]}"; do
        local current_task_id
        current_task_id=$(sqlite3 "$db_path" "SELECT current_task_id FROM workers WHERE id = $worker_id")

        # Release any locks held by worker
        echo "Releasing locks for stale worker $worker_id..."
        swarm_db_release_locks "$worker_id"

        if [ -n "$current_task_id" ] && [ "$current_task_id" != "NULL" ]; then
            local task_id
            task_id=$current_task_id
            echo "Resetting task $task_id to pending state..."
            sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'pending',
    worker_id = NULL,
    started_at = NULL,
    stall_count = stall_count + 1
WHERE id = $task_id AND run_id = (SELECT run_id FROM workers WHERE id = $worker_id);

COMMIT;
EOF
        fi

        # Reset worker record
        sqlite3 "$db_path" <<EOF
UPDATE workers
SET status = 'idle',
    current_task_id = NULL,
    last_heartbeat = NULL
WHERE id = $worker_id;
EOF
    done

    echo "Cleaned up stale workers"
}

swarm_db_list_workers() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT id, worker_num, pid, branch_name, status, current_task_id,
       datetime(started_at) as started_at,
       datetime(last_heartbeat) as last_heartbeat
FROM workers
WHERE run_id = '$run_id'
ORDER BY worker_num;
EOF
}

swarm_db_get_pending_tasks() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT id, task_text, priority, estimated_files, devplan_line
FROM tasks
WHERE run_id = '$run_id' AND status = 'pending'
ORDER BY priority ASC, id ASC;
EOF
}

swarm_db_get_task_count_by_status() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT status, COUNT(*) as count
FROM tasks
WHERE run_id = '$run_id'
GROUP BY status;
EOF
}

swarm_db_get_config() {
    local db_path="$RALPH_DIR/swarm.db"
    local key="$1"

    sqlite3 "$db_path" "SELECT value FROM swarm_config WHERE key = '$key';" 2>/dev/null || echo ""
}

swarm_db_set_config() {
    local db_path="$RALPH_DIR/swarm.db"
    local key="$1"
    local value="$2"

    sqlite3 "$db_path" "UPDATE swarm_config SET value = '$value', updated_at = datetime('now') WHERE key = '$key';"
}

swarm_db_register_worker_global() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"
    local run_id="$2"
    local worker_num="$3"
    local pid="$4"

    local registry_id
    registry_id=$(sqlite3 "$db_path" <<EOF
INSERT INTO worker_registry (
    worker_id, run_id, worker_num, pid, started_at, last_heartbeat
) VALUES (
    $worker_id, '$run_id', $worker_num, $pid, datetime('now'), datetime('now')
);
SELECT last_insert_rowid();
EOF
)

    echo "$registry_id"
}

swarm_db_unregister_worker() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"

    sqlite3 "$db_path" "DELETE FROM worker_registry WHERE worker_id = $worker_id;"
}

swarm_db_get_active_worker_count() {
    local db_path="$RALPH_DIR/swarm.db"

    local count
    count=$(sqlite3 "$db_path" <<EOF
SELECT COUNT(*) FROM worker_registry
WHERE last_heartbeat >= datetime('now', '-60 seconds');
EOF
)

    echo "${count:-0}"
}

swarm_db_get_all_active_workers() {
    local db_path="$RALPH_DIR/swarm.db"

    sqlite3 "$db_path" <<EOF
SELECT wr.*, w.status as worker_status
FROM worker_registry wr
JOIN workers w ON wr.worker_id = w.id
WHERE wr.last_heartbeat >= datetime('now', '-60 seconds')
ORDER BY wr.started_at;
EOF
}

swarm_db_heartbeat_worker_global() {
    local db_path="$RALPH_DIR/swarm.db"
    local worker_id="$1"

    sqlite3 "$db_path" "UPDATE worker_registry SET last_heartbeat = datetime('now') WHERE worker_id = $worker_id;"
}

swarm_db_cleanup_stale_registry_entries() {
    local db_path="$RALPH_DIR/swarm.db"
    local threshold_seconds="${1:-120}"

    # Find stale entries (no heartbeat for threshold_seconds)
    local stale_entries
    stale_entries=$(sqlite3 "$db_path" <<EOF
SELECT id, worker_id FROM worker_registry
WHERE last_heartbeat < datetime('now', '-$threshold_seconds seconds');
EOF
)

    if [ -z "$stale_entries" ] || [ "$stale_entries" = "" ]; then
        return 0
    fi

    local old_ifs="$IFS"
    IFS='|' read -ra entries <<< "$stale_entries"
    IFS="$old_ifs"

    for entry in "${entries[@]}"; do
        local entry_id worker_id
        entry_id=$(echo "$entry" | cut -d'|' -f1)
        worker_id=$(echo "$entry" | cut -d'|' -f2)

        if [ -n "$entry_id" ]; then
            echo "Removing stale worker registry entry: $entry_id (worker $worker_id)"
            sqlite3 "$db_path" "DELETE FROM worker_registry WHERE id = $entry_id;"
        fi
    done
}

swarm_db_get_system_stats() {
    local db_path="$RALPH_DIR/swarm.db"

    sqlite3 "$db_path" <<EOF
SELECT
    (SELECT COUNT(*) FROM worker_registry WHERE last_heartbeat >= datetime('now', '-60 seconds')) as active_workers,
    (SELECT COUNT(*) FROM swarm_runs WHERE status = 'running') as running_runs,
    (SELECT COUNT(*) FROM tasks WHERE status = 'pending') as pending_tasks,
    (SELECT COUNT(*) FROM tasks WHERE status = 'in_progress') as active_tasks;
EOF
}

swarm_db_get_source_hash() {
    local db_path="$RALPH_DIR/swarm.db"
    local devplan_path="$1"

    if [ -f "$devplan_path" ]; then
        sha256sum "$devplan_path" 2>/dev/null | cut -d' ' -f1 || echo ""
    else
        echo ""
    fi
}

swarm_db_find_existing_run() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        echo ""
        return 1
    fi

    sqlite3 "$db_path" "SELECT run_id FROM swarm_runs WHERE source_hash = '$source_hash' AND status = 'running' ORDER BY id DESC LIMIT 1;"
}

swarm_db_get_run_by_source() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        echo ""
        return 1
    fi

    sqlite3 "$db_path" "SELECT run_id, status, completed_tasks, total_tasks FROM swarm_runs WHERE source_hash = '$source_hash' ORDER BY id DESC LIMIT 1;"
}

swarm_db_is_task_completed() {
    local db_path="$RALPH_DIR/swarm.db"
    local task_hash="$1"

    if [ -z "$task_hash" ]; then
        echo "no"
        return 1
    fi

    local result
    result=$(sqlite3 "$db_path" "SELECT 1 FROM completed_tasks WHERE task_hash = '$task_hash' LIMIT 1;")

    if [ -n "$result" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

swarm_db_get_completed_task_hashes() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        sqlite3 "$db_path" "SELECT task_hash FROM completed_tasks;"
    else
        sqlite3 "$db_path" "SELECT task_hash FROM completed_tasks WHERE source_hash = '$source_hash';"
    fi
}

swarm_db_get_incomplete_tasks() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" <<EOF
SELECT id, task_text, priority, estimated_files, devplan_line
FROM tasks
WHERE run_id = '$run_id' AND status IN ('pending', 'in_progress')
ORDER BY priority ASC, id ASC;
EOF
}

swarm_db_get_completed_task_count_for_source() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        echo "0"
        return 1
    fi

    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM completed_tasks WHERE source_hash = '$source_hash';")
    echo "${count:-0}"
}

swarm_db_get_total_tasks_for_source() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        echo "0"
        return 1
    fi

    local count
    count=$(sqlite3 "$db_path" "SELECT total_tasks FROM swarm_runs WHERE source_hash = '$source_hash' ORDER BY id DESC LIMIT 1;")
    echo "${count:-0}"
}

swarm_db_get_latest_run_for_source() {
    local db_path="$RALPH_DIR/swarm.db"
    local source_hash="$1"

    if [ -z "$source_hash" ]; then
        echo ""
        return 1
    fi

    sqlite3 "$db_path" "SELECT run_id FROM swarm_runs WHERE source_hash = '$source_hash' ORDER BY id DESC LIMIT 1;"
}

swarm_db_resume_run() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    # Check if run exists
    local status
    status=$(sqlite3 "$db_path" "SELECT status FROM swarm_runs WHERE run_id = '$run_id';")

    if [ -z "$status" ]; then
        echo "Run not found: $run_id"
        return 1
    fi

    if [ "$status" = "completed" ]; then
        echo "Run already completed: $run_id"
        return 1
    fi

    # Check for pending or in_progress tasks
    local resumable_tasks
    resumable_tasks=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status IN ('pending', 'in_progress');")

    if [ "$resumable_tasks" -eq 0 ]; then
        echo "Run has no remaining tasks: $run_id"
        return 1
    fi

    # Resume the run - CRITICAL: Don't reset started_at!
    sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

-- Reset workers (they're all dead after crash)
UPDATE workers 
SET status = 'stopped', 
    current_task_id = NULL, 
    last_heartbeat = NULL
WHERE run_id = '$run_id';

-- Release all locks from dead workers
DELETE FROM file_locks WHERE run_id = '$run_id';

-- Reset in_progress tasks ONLY if not already in completed_tasks
-- Use task_hash to check if work is actually done
UPDATE tasks 
SET status = 'pending', 
    worker_id = NULL, 
    started_at = NULL,
    stall_count = COALESCE(stall_count, 0) + 1
WHERE run_id = '$run_id' 
  AND status = 'in_progress'
  AND task_hash NOT IN (
    SELECT task_hash FROM completed_tasks WHERE task_hash IS NOT NULL
  );

-- Mark tasks as completed if they're in completed_tasks but status is wrong
-- This handles the case where DB update failed but task was actually done
UPDATE tasks t
SET status = 'completed',
    completed_at = (
      SELECT completed_at FROM completed_tasks ct 
      WHERE ct.task_hash = t.task_hash 
      LIMIT 1
    )
WHERE run_id = '$run_id'
  AND status = 'in_progress'
  AND task_hash IN (
    SELECT task_hash FROM completed_tasks WHERE task_hash IS NOT NULL
  );

-- Mark run as running again - KEEP ORIGINAL started_at for timeout calculations!
UPDATE swarm_runs 
SET status = 'running', 
    completed_at = NULL 
WHERE run_id = '$run_id';

COMMIT;
EOF

    echo "$run_id"
}

swarm_db_mark_run_interrupted() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    sqlite3 "$db_path" "UPDATE swarm_runs SET status = 'interrupted' WHERE run_id = '$run_id';"
}

swarm_db_resume_status() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    if [ -z "$run_id" ]; then
        echo "Error: run_id required"
        return 1
    fi

    sqlite3 "$db_path" <<EOF
SELECT
    sr.run_id,
    sr.status,
    sr.source_path,
    sr.total_tasks,
    sr.completed_tasks,
    sr.failed_tasks,
    (SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'pending') as pending,
    (SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'in_progress') as in_progress,
    datetime(sr.started_at) as started_at
FROM swarm_runs sr
WHERE sr.run_id = '$run_id';
EOF
}

# Retry failed tasks by resetting their status to pending
# Optionally filter by stall_count to only retry tasks that haven't failed too many times
swarm_db_retry_failed_tasks() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local max_retries="${2:-3}"  # Default max retries is 3

    if [ -z "$run_id" ]; then
        echo "Error: run_id required"
        return 1
    fi

    # Count how many failed tasks we're retrying
    local retry_count
    retry_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'failed' AND COALESCE(stall_count, 0) < $max_retries;")

    if [ "$retry_count" = "0" ]; then
        echo "No failed tasks eligible for retry (max_retries: $max_retries)"
        return 0
    fi

    sqlite3 "$db_path" <<EOF
BEGIN TRANSACTION;

-- Reset failed tasks to pending (only if under max retry limit)
UPDATE tasks
SET status = 'pending',
    worker_id = NULL,
    started_at = NULL,
    completed_at = NULL,
    stall_count = COALESCE(stall_count, 0) + 1
WHERE run_id = '$run_id' 
    AND status = 'failed'
    AND COALESCE(stall_count, 0) < $max_retries;

-- Update the run's failed_tasks count
UPDATE swarm_runs
SET failed_tasks = (SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'failed')
WHERE run_id = '$run_id';

COMMIT;
EOF

    echo "Retried $retry_count failed tasks"
}

# Get count of tasks that can be retried (failed but under max retry limit)
swarm_db_get_retryable_task_count() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"
    local max_retries="${2:-3}"

    sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'failed' AND COALESCE(stall_count, 0) < $max_retries;"
}
