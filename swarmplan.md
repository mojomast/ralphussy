# Ralph Swarm Implementation Plan

## Overview

Implement a swarm architecture for ralph2 that enables multiple parallel ralph instances to work on tasks without file conflicts. The system uses a **Central Orchestrator** pattern with **SQLite** for coordination and **LLM-based file prediction** for task analysis.

---

## Architecture Summary

```
                      ┌─────────────────────────────┐
                      │      ralph-swarm CLI        │
                      │   (Orchestrator Entry)      │
                      └──────────────┬──────────────┘
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         │                           │                           │
         ▼                           ▼                           ▼
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│  Task Analyzer  │       │    Scheduler    │       │ Progress Monitor│
│  (LLM + Parse)  │       │  (Dispatcher)   │       │  (Aggregator)   │
└────────┬────────┘       └────────┬────────┘       └────────┬────────┘
         │                         │                         │
         └─────────────────────────┼─────────────────────────┘
                                   │
                      ┌────────────┴────────────┐
                      │    SQLite Database      │
                      │    ~/.ralph/swarm.db    │
                      └────────────┬────────────┘
                                   │
         ┌────────────┬────────────┼────────────┬────────────┐
         │            │            │            │            │
         ▼            ▼            ▼            ▼            ▼
    ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
    │Worker 1 │  │Worker 2 │  │Worker 3 │  │Worker 4 │  │Worker N │
    │(Branch) │  │(Branch) │  │(Branch) │  │(Branch) │  │(Branch) │
    └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘
         │            │            │            │            │
         └────────────┴────────────┴────────────┴────────────┘
                                   │
                      ┌────────────┴────────────┐
                      │    Git Repository       │
                      │  (per-worker branches)  │
                      └─────────────────────────┘
```

---

## Supported Modes

### Mode 1: Devplan Swarm
```bash
ralph-swarm --devplan ./devplan.md --workers 4
```
- Parses existing devplan.md
- Analyzes each task for file scope
- Distributes tasks to workers in parallel

### Mode 2: Prompt Decomposition Swarm  
```bash
ralph-swarm "Build a REST API with auth, rate limiting, and tests" --workers 3
```
- Uses LLM to decompose prompt into parallel sub-tasks
- Creates internal task list
- Distributes to workers

---

## Implementation Phases

---

### Phase 1: Database Layer
**Files**: `ralph-refactor/lib/swarm_db.sh`

#### Tasks
- [x] Create SQLite schema initialization function
- [x] Implement task CRUD operations (add, claim, complete, fail)
- [x] Implement worker registration and heartbeat
- [x] Implement file lock acquire/release with conflict detection
- [x] Implement run history tracking
- [x] Add WAL mode for concurrent access
- [x] Create database migration helper for schema updates

**Status**: ✅ Complete - Database layer implemented with full CRUD, worker management, and file locking

#### Schema
```sql
-- Core tables
CREATE TABLE IF NOT EXISTS swarm_runs (
    id INTEGER PRIMARY KEY,
    run_id TEXT UNIQUE NOT NULL,
    status TEXT DEFAULT 'running',
    source_type TEXT,              -- 'devplan' or 'prompt'
    source_path TEXT,              -- devplan path or null
    source_prompt TEXT,            -- original prompt or null
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
    status TEXT DEFAULT 'pending',
    worker_id INTEGER,
    priority INTEGER DEFAULT 0,
    estimated_files TEXT,          -- JSON array
    actual_files TEXT,             -- JSON array (post-completion)
    devplan_line INTEGER,          -- For devplan mode: line to update
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
```

#### Functions to Implement
```bash
swarm_db_init()                    # Initialize database and schema
swarm_db_start_run()               # Create new swarm run, return run_id
swarm_db_end_run()                 # Mark run complete
swarm_db_add_task()                # Insert task into queue
swarm_db_claim_task()              # Atomically claim next available task
swarm_db_complete_task()           # Mark task done, record actual files
swarm_db_fail_task()               # Mark task failed with error
swarm_db_register_worker()         # Register worker, return worker_id
swarm_db_worker_heartbeat()        # Update heartbeat timestamp
swarm_db_worker_status()           # Get worker status
swarm_db_acquire_locks()           # Lock file patterns for worker
swarm_db_release_locks()           # Release worker's locks
swarm_db_check_conflicts()         # Check if files conflict with locks
swarm_db_get_run_status()          # Get aggregate run statistics
swarm_db_cleanup_stale_workers()   # Detect and clean up dead workers
```

---

### Phase 2: Task Analyzer
**Files**: `ralph-refactor/lib/swarm_analyzer.sh`

#### Tasks
- [x] Implement devplan parser to extract tasks with line numbers
- [x] Implement LLM-based file prediction prompt
- [x] Implement prompt decomposition for non-devplan mode
- [x] Add caching for file predictions
- [x] Handle special cases (documentation, tests, config files)

#### Functions to Implement
- [x] parse_devplan_tasks()              # Extract tasks from devplan.md
- [x] analyze_task_files()               # Use LLM to predict affected files
- [x] compose_prompt()                 # Break single prompt into subtasks
- [x] build_file_prediction_prompt()     # Create LLM prompt for file analysis
- [x] extract_files_from_response()      # Parse LLM response for file patterns
- [x] validate_file_patterns()           # Check patterns against actual codebase

**Status**: ✅ Complete - Task analyzer implemented with devplan parsing, LLM file prediction, and prompt decomposition

#### LLM Prompt for File Prediction
```markdown
You are analyzing a coding task to predict which files will be modified.

Task: "{task_text}"

Codebase structure:
{tree output or key directories}

Respond with ONLY a JSON array of file patterns that this task is likely to modify.
Use glob patterns where appropriate (e.g., "src/auth/*", "tests/**/*.test.ts").

Examples:
- Single file: ["src/utils/helper.ts"]
- Directory: ["src/auth/*"]
- Multiple patterns: ["src/api/routes/*", "tests/api/*", "README.md"]

Respond with JSON array only, no explanation:
```

#### LLM Prompt for Prompt Decomposition
```markdown
You are breaking down a development task into parallelizable subtasks.

Main task: "{prompt}"

Rules:
1. Each subtask should be independently completable
2. Minimize file overlap between subtasks
3. Group related changes together
4. Prioritize foundation tasks first (they get lower priority numbers = run first)

Respond with a JSON array of objects:
[
  {"task": "description", "priority": 1, "estimated_files": ["pattern1", "pattern2"]},
  {"task": "description", "priority": 2, "estimated_files": ["pattern3"]}
]

Lower priority numbers run before higher ones (1 runs before 2).
Tasks with the same priority can run in parallel.
```

---

### Phase 3: Git Branch Manager
**Files**: `ralph-refactor/lib/swarm_git.sh`

#### Tasks
- [x] Create worker branch creation function
- [x] Implement branch cleanup on worker stop
- [x] Implement merge orchestration
- [x] Handle merge conflicts gracefully
- [x] Add branch naming convention with run_id

#### Functions to Implement
- [x] swarm_git_create_worker_branch()   # Create branch: swarm/{run_id}/worker-{n}
- [x] swarm_git_switch_to_branch()       # Checkout worker branch
- [x] swarm_git_commit_work()            # Commit completed task work
- [x] swarm_git_merge_worker_branches()  # Merge all worker branches to main
- [x] swarm_git_cleanup_branches()       # Delete swarm branches after merge
- [x] swarm_git_handle_conflict()        # Interactive or auto conflict resolution
- [x] swarm_git_get_modified_files()     # Get files modified in current branch

**Status**: ✅ Complete - Git branch management fully implemented

#### Branch Strategy
```
main
├── swarm/20260121_143022/worker-1
├── swarm/20260121_143022/worker-2
├── swarm/20260121_143022/worker-3
└── swarm/20260121_143022/worker-4
```

---

### Phase 4: Worker Manager
**Files**: `ralph-refactor/lib/swarm_worker.sh`

#### Tasks
- [x] Implement worker spawn function
- [x] Implement worker main loop (poll -> execute -> report)
- [x] Add heartbeat background process
- [x] Implement graceful shutdown handling
- [x] Add worker isolation (separate devplan, handoff files)
- [x] Implement stale worker detection and cleanup

#### Functions to Implement
- [x] spawn_worker()                     # Fork and start worker process
- [x] worker_main_loop()                 # Main worker execution loop
- [x] worker_poll_for_task()             # Check DB for assigned task
- [x] worker_execute_task()              # Run ralph2 on the task
- [x] worker_report_completion()         # Report back to orchestrator
- [x] worker_start_heartbeat()           # Background heartbeat thread
- [x] worker_stop_heartbeat()            # Stop heartbeat
- [x] worker_cleanup()                   # Graceful shutdown
- [x] worker_create_isolated_devplan()   # Create single-task devplan for worker

**Status**: ✅ Complete - Worker manager fully implemented

#### Worker Directory Structure
```
~/.ralph/swarm/run_20260121_143022/
├── swarm.db
├── master_devplan.md              # Original (read-only during run)
├── worker-1/
│   ├── devplan.md                 # Single-task devplan
│   ├── handoff.md
│   ├── state.json
│   └── logs/
├── worker-2/
│   ├── devplan.md
│   ├── handoff.md
│   └── ...
└── merged_results.md              # Final merged output
```

---

### Phase 5: Scheduler
**Files**: `ralph-refactor/lib/swarm_scheduler.sh`

#### Tasks
- [x] Implement main scheduling loop
- [x] Add priority-based task ordering
- [x] Implement file conflict checking before assignment
- [x] Add dynamic worker scaling (optional)
- [x] Implement task reassignment for failed/stale tasks

#### Functions to Implement
- [x] scheduler_main_loop()              # Main dispatch loop
- [x] scheduler_get_next_task()          # Find next assignable task
- [x] scheduler_check_file_conflicts()   # Verify no lock conflicts
- [x] scheduler_assign_task()            # Assign task to worker
- [x] scheduler_handle_completion()      # Process completed task
- [x] scheduler_handle_failure()         # Process failed task
- [x] scheduler_rebalance()              # Reassign stuck tasks
- [x] scheduler_all_complete()           # Check if run is done

**Status**: ✅ Complete - Scheduler fully implemented

#### Scheduling Algorithm
```
WHILE NOT all_tasks_complete AND NOT timeout:
    FOR each pending_task ordered by priority:
        available_workers = get_idle_workers()
        
        IF available_workers is empty:
            CONTINUE
            
        FOR each worker in available_workers:
            IF NOT has_file_conflicts(task.estimated_files, get_locked_files()):
                assign_task(task, worker)
                acquire_locks(worker, task.estimated_files)
                BREAK
    
    # Check for stale workers (no heartbeat > 60s)
    stale_workers = find_stale_workers()
    FOR each stale in stale_workers:
        release_locks(stale)
        mark_worker_dead(stale)
        reassign_task(stale.current_task)
    
    SLEEP(1 second)
```

---

### Phase 6: Orchestrator CLI
**Files**: `ralph-refactor/ralph-swarm`

#### Tasks
- [x] Implement CLI argument parsing
- [x] Implement devplan mode initialization
- [x] Implement prompt decomposition mode
- [x] Add real-time progress display
- [x] Implement graceful shutdown (Ctrl+C)
- [x] Add --status, --stop, --logs commands
- [x] Implement final devplan update (sync completed tasks back)
- [x] Add cost/token aggregation across workers

#### CLI Interface
- [x] Devplan mode: `ralph-swarm --devplan ./devplan.md --workers 4`
- [x] Prompt mode: `ralph-swarm "Build a REST API with auth" --workers 3`
- [x] Common options: `--provider`, `--timeout`, `--max-retries`, `--verbose`
- [x] Control commands: `--status`, `--stop`, `--kill`, `--logs`
- [x] Analysis mode: `ralph-swarm --devplan ./devplan.md --analyze-only`

**Status**: ✅ Complete - Orchestrator CLI fully implemented

#### Main Orchestrator Flow
```bash
main() {
    parse_args "$@"
    init_swarm_db
    
    if [ -n "$DEVPLAN" ]; then
        # Devplan mode
        tasks=$(parse_devplan_tasks "$DEVPLAN")
    else
        # Prompt mode
        tasks=$(decompose_prompt "$PROMPT")
    fi
    
    run_id=$(swarm_db_start_run)
    
    # Analyze all tasks for file predictions
    for task in tasks; do
        files=$(analyze_task_files "$task")
        swarm_db_add_task "$run_id" "$task" "$files"
    done
    
    # Spawn workers
    for i in $(seq 1 $WORKER_COUNT); do
        spawn_worker "$run_id" "$i"
    done
    
    # Run scheduler until complete
    scheduler_main_loop "$run_id"
    
    # Merge branches
    swarm_git_merge_worker_branches "$run_id"
    
    # Update original devplan with results
    if [ -n "$DEVPLAN" ]; then
        sync_results_to_devplan "$DEVPLAN" "$run_id"
    fi
    
    swarm_db_end_run "$run_id"
    show_final_summary "$run_id"
}
```

---

### Phase 7: Progress Display
**Files**: `ralph-refactor/lib/swarm_display.sh`

#### Tasks
- [x] Implement real-time dashboard
- [x] Add per-worker status display
- [x] Add progress bar
- [x] Show file lock status
- [x] Aggregate cost/token tracking
- [x] Add log aggregation view

#### Display Format
```
╔══════════════════════════════════════════════════════════════════╗
║                      RALPH SWARM                                 ║
║  Run: 20260121_143022  │  Mode: devplan  │  Workers: 4/4 active  ║
╠══════════════════════════════════════════════════════════════════╣
║  Progress: ████████████████░░░░  │  8/12 tasks  (66%)            ║
╠══════════════════════════════════════════════════════════════════╣
║  Worker 1 [BUSY]  Task: "Implement auth"     Files: src/auth/*   ║
║  Worker 2 [BUSY]  Task: "Add rate limiting"  Files: src/api/*    ║
║  Worker 3 [IDLE]  Waiting (conflict: src/auth/*)                 ║
║  Worker 4 [BUSY]  Task: "Update docs"        Files: docs/*       ║
╠══════════════════════════════════════════════════════════════════╣
║  Completed: 6  │  In Progress: 3  │  Failed: 0                   ║
║  Elapsed: 12m 34s │  Est. remaining: 8m │  Cost: $2.45           ║
╚══════════════════════════════════════════════════════════════════╝
```

**Status**: ✅ Complete - Progress display fully implemented

---

### Phase 8: Integration with Existing Ralph
**Files**: `ralph-refactor/ralph` (modify), `ralph-refactor/lib/core.sh` (modify)

#### Tasks
- [x] Add `--swarm-worker` mode flag to ralph
- [x] Add swarm-specific config variables to core.sh
- [x] Ensure ralph can read worker-specific RALPH_DIR
- [x] Add worker-id to logging output
- [x] Support `--isolated` flag for worker isolation

#### Changes to ralph
```bash
# New flag handling in main()
--swarm-worker)
    SWARM_WORKER_MODE=true
    SWARM_WORKER_ID="$2"
    SWARM_RUN_ID="$3"
    RALPH_DIR="$HOME/.ralph/swarm/$SWARM_RUN_ID/worker-$SWARM_WORKER_ID"
    shift 3
    ;;
```

**Status**: ✅ Complete - Integration with ralph fully implemented

---

### Phase 9: Testing & Edge Cases
**Files**: `ralph-refactor/tests/test_swarm.sh` (create)

#### Tasks
- [ ] Add unit tests for database operations
- [ ] Add unit tests for file conflict detection
- [ ] Add integration test: 2 workers, no conflicts
- [ ] Add integration test: file conflict resolution
- [ ] Add integration test: worker crash recovery
- [ ] Add integration test: prompt decomposition mode
- [ ] Add test for stale worker detection
- [ ] Add test for branch merge conflicts

#### Test Scenarios
1. **Happy path**: 4 tasks, 2 workers, no file overlap -> parallel completion
2. **File conflict**: 2 tasks touching same file -> serial execution
3. **Worker crash**: Kill worker mid-task -> task reassigned
4. **Stale heartbeat**: Worker hangs -> detected and cleaned up
5. **Branch conflict**: Two workers modify same file unexpectedly -> merge conflict handling
6. **All tasks fail**: Proper error reporting and cleanup
7. **Single task**: Swarm with 1 task behaves like regular ralph

**Status**: ⏳ Pending - Testing framework to be implemented

---

## File Summary

| File | Status | Description |
|------|--------|-------------|
| `ralph-refactor/ralph-swarm` | ✅ Complete | Main swarm orchestrator CLI |
| `ralph-refactor/lib/swarm_db.sh` | ✅ Complete | SQLite database operations |
| `ralph-refactor/lib/swarm_analyzer.sh` | ✅ Complete | Task analysis, file prediction, prompt decomposition |
| `ralph-refactor/lib/swarm_git.sh` | ✅ Complete | Git branch management |
| `ralph-refactor/lib/swarm_worker.sh` | ✅ Complete | Worker process management |
| `ralph-refactor/lib/swarm_scheduler.sh` | ✅ Complete | Task scheduling and dispatch |
| `ralph-refactor/lib/swarm_display.sh` | ✅ Complete | Progress display and monitoring |
| `ralph-refactor/lib/core.sh` | ⏳ Pending | Add swarm config variables |
| `ralph-refactor/ralph` | ✅ Complete | Add --swarm-worker mode |
| `ralph-refactor/tests/test_swarm.sh` | ⏳ Pending | Test suite |

---

## Dependencies

- **SQLite3**: For coordination database (`apt install sqlite3`)
- **jq**: For JSON parsing (already optional dependency)
- **Git**: For branch management (required)

---

## Configuration

Add to `ralph.config` or `ralph-refactor/lib/core.sh`:
```bash
# Swarm settings
SWARM_WORKER_COUNT=4
SWARM_HEARTBEAT_INTERVAL=10        # seconds
SWARM_STALE_THRESHOLD=60           # seconds before worker considered dead
SWARM_POLL_INTERVAL=1              # scheduler poll interval
SWARM_MAX_RETRIES=3                # max task retry attempts
SWARM_DB_PATH="$HOME/.ralph/swarm.db"
```

---

## Implementation Order (Recommended)

1. ✅ **Phase 1: Database Layer** - Foundation for everything (COMPLETE)
2. ✅ **Phase 3: Git Branch Manager** - Critical for isolation (COMPLETE)
3. ✅ **Phase 4: Worker Manager** - Can test with manual task assignment (COMPLETE)
4. ✅ **Phase 2: Task Analyzer** - Enables intelligent distribution (COMPLETE)
5. 🔄 **Phase 5: Scheduler** - Ties workers and tasks together (IN PROGRESS)
6. 📋 **Phase 6: Orchestrator CLI** - User-facing entry point
7. 📋 **Phase 7: Progress Display** - Polish and visibility
8. 📋 **Phase 8: Integration** - Connect to existing ralph
9. 📋 **Phase 9: Testing** - Verify all edge cases

---

## Rollback Plan

If swarm fails mid-run:
1. All work is on separate branches -> main branch unaffected
2. `ralph-swarm --status` shows current state
3. `ralph-swarm --stop` gracefully stops workers
4. Worker branches can be manually inspected/merged
5. `ralph-swarm --cleanup` removes swarm branches and temp files

---

## Success Metrics

- [ ] 4 workers can process 8 non-conflicting tasks in ~2x time of single task
- [ ] File conflicts are correctly detected and serialized
- [ ] Worker crashes are detected within 60s and tasks reassigned
- [ ] Branch merges succeed for non-conflicting work
- [ ] Original devplan.md is correctly updated with completion status
- [ ] Works with both devplan mode and prompt decomposition mode

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| SQLite write contention | Use WAL mode, short transactions, retry logic |
| Inaccurate file predictions | Post-completion validation, flag unexpected conflicts |
| Worker crashes | Heartbeat detection (60s), automatic task reassignment |
| Git merge conflicts | Per-worker branches, conflict detection before merge |
| LLM rate limits | Batch file predictions, caching, retry with backoff |
| Complex debugging | Per-worker logs, centralized status view, verbose mode |

---

## Open Questions

1. **File prediction caching**: Should we cache LLM predictions across runs for similar tasks?
2. **Dynamic scaling**: Should workers scale up/down based on task queue depth?
3. **Partial merge**: Should we merge completed worker branches incrementally or all at once?
4. **Conflict resolution**: Interactive prompts vs. automatic resolution for merge conflicts?
