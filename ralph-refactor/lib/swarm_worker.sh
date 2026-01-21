#!/usr/bin/env bash

swarm_worker_create_isolated_devplan() {
    local run_id="$1"
    local worker_num="$2"
    local task_text="$3"
    local task_file="$4"

    local isolated_dir="$RALPH_DIR/swarm/runs/$run_id/worker-$worker_num"
    mkdir -p "$isolated_dir"

    local devplan_file="$isolated_dir/devplan.md"
    cat > "$devplan_file" <<EOF
# Swarm Isolated Task

## Task
$task_text

---
EOF

    echo "$devplan_file"
}

swarm_worker_spawn() {
    local run_id="$1"
    local worker_num="$2"
    local devplan_path="$3"
    local ralph_path="${4:-./ralph}"
    local log_file="${5:-/tmp/swarm_worker_$worker_num.log}"

    local worker_dir="$RALPH_DIR/swarm/runs/$run_id/worker-$worker_num"
    mkdir -p "$worker_dir"
    mkdir -p "$worker_dir/logs"

    local log_full="$worker_dir/logs/${worker_num}_$(date +%Y%m%d_%H%M%S).log"
    touch "$log_full"

    echo "Spawning worker $worker_num for run $run_id..."
    echo "Worker directory: $worker_dir"
    echo "Log file: $log_full"

    local repo_root
    repo_root="${SWARM_REPO_ROOT:-}"
    if [ -z "$repo_root" ]; then
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi
    if [ -z "$repo_root" ]; then
        echo "Error: swarm workers must run inside a git repository" 1>&2
        return 1
    fi

    local base_branch
    base_branch=$(swarm_git_default_base_branch 2>/dev/null || echo "main")

    local branch_name
    branch_name="swarm/${run_id}/worker-${worker_num}"

    local repo_dir="$worker_dir/repo"
    mkdir -p "$repo_dir"

    # Create a per-worker git worktree to isolate changes.
    if [ ! -e "$repo_dir/.git" ]; then
        rm -rf "$repo_dir"
        if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
            git -C "$repo_root" worktree add "$repo_dir" "$branch_name" >/dev/null
        else
            git -C "$repo_root" worktree add -b "$branch_name" "$repo_dir" "$base_branch" >/dev/null
        fi
    fi

    local worker_id
    # Register worker with placeholder PID; updated after spawn.
    worker_id=$(swarm_db_register_worker "$run_id" "$worker_num" 0 "$branch_name" "$worker_dir")

    (
        cd "$repo_dir" || exit 1

        echo "[$(date)] Worker $worker_num started (PID: $$, ID: $worker_id)"
        echo "[$(date)] Run ID: $run_id"
        echo "[$(date)] Worker directory: $worker_dir"

        swarm_worker_main_loop "$run_id" "$worker_num" "$worker_id" "$devplan_path" "$ralph_path" "$log_full"

        echo "[$(date)] Worker $worker_num shutting down"
        true
    ) > "$log_full" 2>&1 &

    local worker_pid=$!
    sleep 1

    if ! ps -p $worker_pid > /dev/null; then
        echo "Error: Failed to spawn worker $worker_num"
        swarm_db_worker_heartbeat "$worker_id" 2>/dev/null
        return 1
    fi

    swarm_db_update_worker_pid "$worker_id" "$worker_pid" 2>/dev/null || true
    swarm_db_worker_heartbeat "$worker_id"

    echo "Worker $worker_num spawned successfully (PID: $worker_pid, ID: $worker_id)"
    echo "$worker_id"
}

swarm_worker_main_loop() {
    local run_id="$1"
    local worker_num="$2"
    local worker_id="$3"
    local devplan_path="$4"
    local ralph_path="$5"
    local log_file="$6"

    while true; do
        local current_task
        current_task=$(swarm_db_claim_task "$worker_id")

        if [ -z "$current_task" ]; then
            sleep 2
            continue
        fi

        local task_id task_text estimated_files devplan_line
        task_id=$(echo "$current_task" | cut -d'|' -f1)
        task_text=$(echo "$current_task" | cut -d'|' -f2)
        estimated_files=$(echo "$current_task" | cut -d'|' -f3)
        devplan_line=$(echo "$current_task" | cut -d'|' -f4)

        echo "[$(date)] Worker $worker_num claimed task $task_id"
        echo "[$(date)] Task: $task_text"

        swarm_db_worker_heartbeat "$worker_id"

        if swarm_worker_execute_task "$run_id" "$worker_num" "$task_id" "$task_text" "$estimated_files" "$devplan_line" "$devplan_path" "$ralph_path" "$log_file"; then
            swarm_db_complete_task "$task_id" "$estimated_files" "$worker_id"
            echo "[$(date)] Task $task_id completed successfully"
        else
            local error_msg="Worker error on task $task_id"
            swarm_db_fail_task "$task_id" "$worker_id" "$error_msg"
            echo "[$(date)] Task $task_id failed: $error_msg"
        fi

        swarm_db_worker_heartbeat "$worker_id"
    done
}

swarm_worker_execute_task() {
    local run_id="$1"
    local worker_num="$2"
    local task_id="$3"
    local task_text="$4"
    local estimated_files="$5"
    local devplan_line="$6"
    local devplan_path="$7"
    local ralph_path="$8"
    local log_file="$9"

    local worker_dir="$RALPH_DIR/swarm/runs/$run_id/worker-$worker_num"
    local repo_dir="$worker_dir/repo"

    if [ ! -d "$repo_dir" ]; then
        echo "[$(date)] Error: worker repo dir missing: $repo_dir" 1>&2
        return 1
    fi

    # Ensure json_extract_text is available for completion detection.
    if ! command -v json_extract_text >/dev/null 2>&1; then
        # shellcheck source=ralph-refactor/lib/json.sh
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/json.sh"
    fi

    local prompt
    prompt=$(cat <<EOF
You are a swarm worker (#$worker_num) operating inside a git worktree.

Task ($task_id): $task_text

Constraints:
- Make changes in this repository (current working directory).
- Run relevant tests/linters if they exist.
- Create a git commit for your changes with a clear message.
- When finished, output: <promise>COMPLETE</promise>

If you need context, inspect files in the repo.
EOF
)

    echo "[$(date)] Running OpenCode for task $task_id"

    local opencode_cmd="opencode run"
    if [ -n "${RALPH_LLM_PROVIDER:-}" ]; then
        opencode_cmd="$opencode_cmd --provider ${RALPH_LLM_PROVIDER}"
    fi
    if [ -n "${RALPH_LLM_MODEL:-}" ]; then
        opencode_cmd="$opencode_cmd --model ${RALPH_LLM_MODEL}"
    fi

    local json_output
    if ! json_output=$(cd "$repo_dir" && $opencode_cmd --format json "$prompt" 2>&1); then
        echo "[$(date)] Task execution failed (opencode error)" 1>&2
        echo "$json_output" | head -c 300 1>&2
        return 1
    fi

    # Best-effort: record token/cost stats if possible.
    local prompt_tokens=0
    local completion_tokens=0
    local cost=0
    if command -v jq >/dev/null 2>&1; then
        prompt_tokens=$(echo "$json_output" | jq -r '.part.tokens.input // .tokens.input // 0' 2>/dev/null | head -1) || prompt_tokens=0
        completion_tokens=$(echo "$json_output" | jq -r '.part.tokens.output // .tokens.output // 0' 2>/dev/null | head -1) || completion_tokens=0
        cost=$(echo "$json_output" | jq -r '.part.cost // .cost // 0' 2>/dev/null | head -1) || cost=0
    fi
    if command -v swarm_db_record_task_cost >/dev/null 2>&1; then
        swarm_db_record_task_cost "$run_id" "$task_id" "$prompt_tokens" "$completion_tokens" "$cost" >/dev/null 2>&1 || true
    fi

    local text_output
    text_output=$(json_extract_text "$json_output" 2>/dev/null || true)
    if echo "$text_output" | grep -q "<promise>COMPLETE</promise>"; then
        echo "[$(date)] Task execution successful"
        return 0
    fi

    echo "[$(date)] Task execution did not return completion promise" 1>&2
    return 1
}

swarm_worker_poll_for_task() {
    local worker_id="$1"
    local timeout_seconds="${2:-300}"

    local start_time=$(date +%s)
    local elapsed=0

    while [ $elapsed -lt $timeout_seconds ]; do
        local current_task
        current_task=$(swarm_db_claim_task "$worker_id")

        if [ -n "$current_task" ]; then
            local task_id
            task_id=$(echo "$current_task" | cut -d'|' -f1)

            echo "[$(date)] Polling found task $task_id"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "[$(date)] Polling timeout after $timeout_seconds seconds"
    return 1
}

swarm_worker_start_heartbeat() {
    local worker_id="$1"
    local interval_seconds="${2:-10}"

    while true; do
        sleep "$interval_seconds"
        swarm_db_worker_heartbeat "$worker_id"
    done
}

swarm_worker_stop_heartbeat() {
    echo "Heartbeat stopped"
}

swarm_worker_cleanup() {
    local run_id="$1"
    local worker_num="$2"

    echo "[$(date)] Cleaning up worker $worker_num for run $run_id"

    local worker_dir="$RALPH_DIR/swarm/runs/$run_id/worker-$worker_num"
    if [ -d "$worker_dir" ]; then
        rm -rf "$worker_dir"
    fi
}

swarm_worker_stop() {
    local worker_id="$1"
    local worker_pid="$2"

    if [ -z "$worker_pid" ]; then
        echo "Worker PID not provided"
        return 1
    fi

    echo "Stopping worker (PID: $worker_pid)..."

    if ps -p "$worker_pid" > /dev/null; then
        kill "$worker_pid" 2>/dev/null || true
        sleep 2

        if ps -p "$worker_pid" > /dev/null; then
            echo "Forcing worker shutdown..."
            kill -9 "$worker_pid" 2>/dev/null || true
        fi
    else
        echo "Worker already stopped"
    fi
}

swarm_worker_list_active() {
    local db_path="$RALPH_DIR/swarm.db"
    local run_id="$1"

    if [ ! -f "$db_path" ]; then
        echo "No active swarm run"
        return 1
    fi

    sqlite3 "$db_path" <<EOF
SELECT id, worker_num, pid, branch_name, status, current_task_id
FROM workers
WHERE run_id = '$run_id';
EOF
}
