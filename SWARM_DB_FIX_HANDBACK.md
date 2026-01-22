# Swarm Database Schema Fix - Handback

**Date**: 2026-01-22
**Issue**: Database schema mismatch causing swarm runs to fail silently

## Problem Summary

When starting a new swarm run, the `swarm_db_start_run()` function failed to create entries in the `swarm_runs` table. This caused:

1. TUI progress display showing stale data from old runs (project 2 instead of project 3)
2. Task IDs continuing to increment across projects instead of resetting
3. Workers appearing to die immediately (scheduler couldn't find active workers)
4. No visual feedback that the swarm was running

## Root Cause Analysis

### Database Schema Mismatch
- Code expected `source_hash` column in `swarm_runs` table
- Existing database was created with older schema missing this column
- `CREATE TABLE IF NOT EXISTS` doesn't update existing tables

### Silent Error Handling
- Python sqlite3 shim (`tools/sqlite3`) caught exceptions and silently continued
- INSERT failures were invisible to users
- Run ID was still generated and tasks added, but run record missing

## Solution Implemented

### 1. Database Migration (`swarm_db.sh`)
Added migration logic after table creation:

```bash
# Migration: Add missing columns to existing tables
sqlite3 "$db_path" "ALTER TABLE swarm_runs ADD COLUMN source_hash TEXT;" 2>/dev/null || true
sqlite3 "$db_path" "ALTER TABLE tasks ADD COLUMN task_hash TEXT;" 2>/dev/null || true
```

### 2. Fixed Error Logging (`tools/sqlite3`)
Changed error handling to log to stderr instead of silently continuing:

```python
except sqlite3.Error as e2:
    err_str = str(e2).lower()
    if 'already exists' not in err_str and 'duplicate column' not in err_str:
        print(f"sqlite3 error: {e2}", file=sys.stderr)
        print(f"  statement: {stmt[:100]}...", file=sys.stderr)
    continue
```

## Files Modified

| File | Change |
|------|--------|
| `ralph-refactor/lib/swarm_db.sh` | Added migration logic for schema upgrades |
| `ralph-refactor/tools/sqlite3` | Fixed error handling to log instead of silently swallow |

## Database State After Fix

### Tables Now Have All Expected Columns

**swarm_runs**:
- id, run_id, status, source_type, source_path, source_hash, source_prompt
- worker_count, total_tasks, completed_tasks, failed_tasks, started_at, completed_at

**tasks**:
- id, run_id, task_text, task_hash, status, worker_id, priority
- estimated_files, actual_files, devplan_line
- created_at, started_at, completed_at, error_message, stall_count

## Verification Steps

```bash
# Check sqlite3 is installed
which sqlite3 && sqlite3 --version

# Verify schema
sqlite3 ~/.ralph/swarm.db "PRAGMA table_info(swarm_runs);"
sqlite3 ~/.ralph/swarm.db "PRAGMA table_info(tasks);"

# Test run registration
sqlite3 ~/.ralph/swarm.db "INSERT INTO swarm_runs (run_id, status, source_type, source_path, source_hash, worker_count, started_at) VALUES ('TEST123', 'running', 'devplan', '/test.md', 'hash', 4, datetime('now'));"

# Clean up orphaned runs (if any exist from the bug)
rm -rf ~/.ralph/swarm/runs/20260122_*
```

## Impact

- **Positive**: New swarm runs now properly register in database
- **Positive**: TUI progress displays correct run data
- **Positive**: Future schema changes will automatically migrate
- **Note**: Old orphaned runs (20260122_*) remain in tasks table but not in swarm_runs

## Future Recommendations

1. Add schema version tracking to `swarm_config` table
2. Create proper migration framework with version numbers
3. Consider using SQLite's ALTER TABLE for all schema changes
4. Test schema changes on existing databases before deployment
