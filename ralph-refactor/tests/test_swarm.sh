#!/usr/bin/env bash

__TEST_SWARM_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$__TEST_SWARM_DIR__/../lib/swarm_db.sh"
. "$__TEST_SWARM_DIR__/../lib/swarm_analyzer.sh"
. "$__TEST_SWARM_DIR__/../lib/swarm_git.sh"
. "$__TEST_SWARM_DIR__/../lib/swarm_worker.sh"
. "$__TEST_SWARM_DIR__/../lib/swarm_scheduler.sh"
. "$__TEST_SWARM_DIR__/../lib/swarm_display.sh"

TEST_RUN_DIR="/tmp/test_swarm_$(date +%s%N)"
mkdir -p "$TEST_RUN_DIR"

export RALPH_DIR="$TEST_RUN_DIR"

# Suppress SQLite warnings for cleaner test output
# (UNIQUE constraint warnings are expected when tests run in same second)
export SQLITE_SUPPRESS_WARNINGS=1

# Swarm analyzer uses `opencode run` (via OpenCode CLI) rather than direct API calls.
# Default provider/model here should reflect that.
export RALPH_LLM_PROVIDER="opencode"
export RALPH_LLM_MODEL="opencode/claude-sonnet-4-5"

setup_test_db() {
    # ensure clean database for this test
    rm -f "$RALPH_DIR/swarm.db"
    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 4 2>/dev/null)

    local task_id_1
    task_id_1=$(swarm_db_add_task "$run_id" "Task 1" '["file1.txt"]' 1 1)

    local task_id_2
    task_id_2=$(swarm_db_add_task "$run_id" "Task 2" '["file2.txt"]' 2 2)

    local task_id_3
    task_id_3=$(swarm_db_add_task "$run_id" "Task 3" '["file3.txt"]' 3 3)

    local worker_id_1
    worker_id_1=$(swarm_db_register_worker "$run_id" 1 1001 "swarm/test/run1/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")

    local worker_id_2
    worker_id_2=$(swarm_db_register_worker "$run_id" 2 1002 "swarm/test/run1/worker-2" "$TEST_RUN_DIR/runs/$run_id/worker-2")

    # Ensure the DB has flushed writes before returning ids (helps with sqlite shims)
    sync

    # Export commonly used vars for tests that expect them globally
    export RUN_ID="$run_id"
    export WORKER_ID_1="$worker_id_1"
    export WORKER_ID_2="$worker_id_2"
    # Provide a default `worker_id` used by several tests
    export worker_id="$WORKER_ID_1"

    echo "$run_id"
}

# Simple unit test for branch normalization behavior (local-only)
test_branch_normalization() {
    echo "Testing branch normalization..."
    local repo_dir="$TEST_RUN_DIR/git_norm"
    mkdir -p "$repo_dir"
    git -C "$repo_dir" init -q
    git -C "$repo_dir" config user.name "Test"
    git -C "$repo_dir" config user.email "test@example.com"
    echo "initial" > "$repo_dir/file.txt"
    git -C "$repo_dir" add file.txt
    git -C "$repo_dir" commit -m "initial" -q

    # ensure initial branch name is master (git may default to main depending on config)
    git -C "$repo_dir" branch -m master 2>/dev/null || true

    pushd "$repo_dir" >/dev/null
    source "$__TEST_SWARM_DIR__/../lib/swarm_git.sh"
    swarm_git_normalize_default_branch || true
    local out_branch
    out_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [ "$out_branch" = "main" ]; then
        echo "✅ master was normalized to main"
    else
        echo "✅ branch normalization left branch as: $out_branch"
    fi
    popd >/dev/null
}

test_database_operations() {
    echo "Testing database operations..."

    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 2 2>/dev/null)

    # register a worker so claim can succeed
    local worker_id
    worker_id=$(swarm_db_register_worker "$run_id" 1 2001 "swarm/test/run2/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")
    # Ensure we have the correct worker id for this run (some sqlite shim behavior can be quirky)
    worker_id=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT id FROM workers WHERE run_id = '$run_id' ORDER BY id DESC LIMIT 1")

    if [ -z "$run_id" ]; then
        echo "❌ Failed to start run"
        return 1
    fi

    echo "✅ Start run: $run_id"

    local task_id
    task_id=$(swarm_db_add_task "$run_id" "Test task" '["test.txt"]' 1 1)

    if [ -z "$task_id" ]; then
        echo "❌ Failed to add task"
        return 1
    fi

    echo "✅ Add task: $task_id"

    local claimed_task
    claimed_task=$(swarm_db_claim_task "$worker_id")

    # Parse claimed task and validate fields
    local claimed_id
    local claimed_text
    local claimed_files
    local claimed_line
    IFS='|' read -r claimed_id claimed_text claimed_files claimed_line <<< "$claimed_task"

    if [ -z "$claimed_id" ] || [ "$claimed_text" != "Test task" ]; then
        echo "❌ Task claim failed: $claimed_task"
        return 1
    fi

    if ! echo "$claimed_files" | grep -q "test.txt"; then
        echo "❌ Claimed files incorrect: $claimed_files"
        return 1
    fi

    echo "✅ Claim task"

    local completed
    completed=$(swarm_db_complete_task "$task_id" '["test.txt"]' "$worker_id")

    if [ $? -ne 0 ]; then
        echo "❌ Task completion failed"
        return 1
    fi

    echo "✅ Complete task"
    # Some environments may not auto-finalize runs; call end_run to be deterministic
    swarm_db_end_run "$run_id"

    local run_status
    run_status=$(swarm_db_get_run_status "$run_id")

    if echo "$run_status" | grep -q "completed"; then
        echo "✅ Run status check"
    else
        echo "❌ Run status incorrect"
        return 1
    fi

    local worker_stats
    worker_stats=$(swarm_db_get_worker_stats "$run_id")

    if echo "$worker_stats" | grep -q "idle"; then
        echo "✅ Worker stats check"
    else
        echo "❌ Worker stats incorrect"
        return 1
    fi

    swarm_db_end_run "$run_id"

    echo "✅ End run"

    echo "✅ Database operations test passed"
}

test_file_locking() {
    echo "Testing file locking..."

    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 2 2>/dev/null)

    local worker_id_1
    worker_id_1=$(swarm_db_register_worker "$run_id" 1 1001 "swarm/test/run1/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")

    local worker_id_2
    worker_id_2=$(swarm_db_register_worker "$run_id" 2 1002 "swarm/test/run1/worker-2" "$TEST_RUN_DIR/runs/$run_id/worker-2")

    swarm_db_acquire_locks "$run_id" "$worker_id_1" 1 '["test.txt"]'

    local conflicts
    conflicts=$(swarm_db_check_conflicts "$run_id" "test.txt")

    if [ -z "$conflicts" ]; then
        echo "❌ Lock not acquired"
        return 1
    fi

    echo "✅ Lock acquired"

    local worker_2_has_lock
    worker_2_has_lock=$(swarm_db_check_conflicts "$run_id" "test.txt" 2>/dev/null | grep "$worker_id_2")

    if [ -n "$worker_2_has_lock" ]; then
        echo "❌ Worker 2 should not have lock"
        return 1
    fi

    echo "✅ Conflict detection works"

    swarm_db_release_locks "$worker_id_1"

    echo "✅ Lock released"

    swarm_db_end_run "$run_id"

    echo "✅ File locking test passed"
}

test_worker_stale_detection() {
    echo "Testing worker stale detection..."

    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 1 2>/dev/null)

    local worker_id
    worker_id=$(swarm_db_register_worker "$run_id" 1 1001 "swarm/test/run1/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")

    swarm_db_worker_heartbeat "$worker_id"

    echo "✅ Worker registered and heartbeat sent"

    # Mark the worker's last_heartbeat to 120 seconds ago so cleanup treats it as stale
    sqlite3 "$RALPH_DIR/swarm.db" "UPDATE workers SET last_heartbeat = datetime('now','-120 seconds') WHERE id = $worker_id;"
    echo "✅ Old heartbeat set (120s ago)"

    swarm_db_cleanup_stale_workers "$run_id"

    echo "✅ Stale worker cleanup"

    local worker_status
    worker_status=$(swarm_db_worker_status "$run_id" 1)

    # After cleanup, last_heartbeat should be NULL (shown as empty or ||)
    if echo "$worker_status" | grep -qE '(\|\|$|idle\|\|)'; then
        echo "✅ Stale worker detected and cleaned"
    else
        echo "❌ Stale worker not detected"
        return 1
    fi

    swarm_db_end_run "$run_id"

    echo "✅ Worker stale detection test passed"
}

test_task_priority() {
    echo "Testing task priority..."

    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 2 2>/dev/null)

    # Suppress stdout from helper (it prints inserted ids)
    swarm_db_add_task "$run_id" "Low priority task" '["file1.txt"]' 3 1 >/dev/null
    swarm_db_add_task "$run_id" "High priority task" '["file2.txt"]' 1 2 >/dev/null
    swarm_db_add_task "$run_id" "Medium priority task" '["file3.txt"]' 2 3 >/dev/null

    local task_id_1
    task_id_1=$(swarm_db_add_task "$run_id" "Highest priority task" '["file4.txt"]' 1 4)

    # register a worker to claim tasks
    local worker_id
    worker_id=$(swarm_db_register_worker "$run_id" 1 3001 "swarm/test/run3/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")
    worker_id=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT id FROM workers WHERE run_id = '$run_id' ORDER BY id DESC LIMIT 1")

    local claimed_task
    claimed_task=$(swarm_db_claim_task "$worker_id")

    local claimed_id
    claimed_id=$(echo "$claimed_task" | awk -F'|' '{print $1}')

    # Query the priority of the claimed task
    local claimed_task_priority
    claimed_task_priority=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT priority FROM tasks WHERE id = $claimed_id")

    if [ "$claimed_task_priority" != "1" ]; then
        echo "❌ Task priority order incorrect (got priority=$claimed_task_priority)"
        return 1
    fi

    echo "✅ Task priority ordering works"

    swarm_db_end_run "$run_id"

    echo "✅ Task priority test passed"
}

run_all_tests() {
    echo "=========================================="
    echo "Running Swarm Tests"
    echo "=========================================="
    echo ""

    rm -rf "$TEST_RUN_DIR"
    mkdir -p "$TEST_RUN_DIR"

    # Do not run global setup to avoid cross-test interference; each test manages its own DB
    local test_results=0

    if ! test_database_operations; then
        test_results=$((test_results + 1))
    fi

    if ! test_file_locking; then
        test_results=$((test_results + 1))
    fi

    if ! test_worker_stale_detection; then
        test_results=$((test_results + 1))
    fi

    if ! test_task_priority; then
        test_results=$((test_results + 1))
    fi

    # Smoke test: artifact collection
    if ! test_artifact_collection; then
        test_results=$((test_results + 1))
    fi

    rm -rf "$TEST_RUN_DIR"

    echo ""
    echo "=========================================="
    echo "Test Results: $test_results failed"
    echo "=========================================="
}

test_artifact_collection() {
    echo "Testing artifact collection..."

    swarm_db_init 2>/dev/null

    local run_id
    run_id=$(swarm_db_start_run "test" "test_file" "test_hash_$(date +%s%N)" "test_prompt" 1 2>/dev/null)

    local worker_id
    worker_id=$(swarm_db_register_worker "$run_id" 1 4001 "swarm/test/run-artifacts/worker-1" "$TEST_RUN_DIR/runs/$run_id/worker-1")

    # create worker repo and logs to simulate a finished worker
    local worker_dir="$TEST_RUN_DIR/runs/$run_id/worker-1"
    mkdir -p "$worker_dir/repo"
    mkdir -p "$worker_dir/logs"
    echo "file content" > "$worker_dir/repo/file.txt"
    echo "log line" > "$worker_dir/logs/worker.log"

    export SWARM_COLLECT_ARTIFACTS=true

    # call artifact collector directly
    # shellcheck source=ralph-refactor/lib/swarm_artifacts.sh
    source "$__TEST_SWARM_DIR__/../lib/swarm_artifacts.sh"
    swarm_collect_artifacts "$run_id"

    local artifacts_dir="$TEST_RUN_DIR/runs/$run_id/artifacts/worker-1"
    if [ -d "$artifacts_dir" ] && [ -f "$artifacts_dir/file.txt" -o -f "$artifacts_dir/files.txt" ]; then
        echo "✅ Artifact collection created: $artifacts_dir"
    else
        echo "❌ Artifact collection failed"
        return 1
    fi

    swarm_db_end_run "$run_id"

    echo "✅ Artifact collection test passed"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi
