#!/usr/bin/env bash

swarm_scheduler_main_loop() {
    local run_id="$1"
    local stop_timeout="${2:-60}"
    local verbose="${3:-false}"

    echo "Scheduler started for run $run_id"
    echo "Poll interval: 1 second"
    echo "Stop timeout: $stop_timeout seconds"
    echo ""

    local iteration=0
    local last_status_check=0
    local workers_found=0
    local tasks_found=0

    while true; do
        iteration=$((iteration + 1))
        current_time=$(date +%s)

        if [ $current_time -ge $last_status_check ]; then
            local status_info
            status_info=$(swarm_db_get_run_status "$run_id" 2>/dev/null)
            if [ -n "$status_info" ]; then
                local status completed_tasks failed_tasks
                status_info=$(echo "$status_info" | awk -F'|' '{print $1"|" $4"|" $5}')

                echo "[${current_time}] Status check: $status_info"
                last_status_check=$((current_time + 10))
            fi
        fi

        local pending_tasks
        pending_tasks=$(swarm_db_get_pending_tasks "$run_id" 2>/dev/null | wc -l)
        local worker_stats
        worker_stats=$(swarm_db_get_worker_stats "$run_id" 2>/dev/null || echo "")

        echo "[${current_time}] Iteration $iteration: $pending_tasks pending tasks, $worker_stats"

        if [ $pending_tasks -eq 0 ]; then
            echo ""
            echo "No pending tasks remaining"

            local all_workers_stopped=true
            local worker_id
            for worker_id in $(swarm_db_list_workers "$run_id" 2>/dev/null | awk -F'|' '{print $1}'); do
                local worker_status
                worker_status=$(swarm_db_worker_status "$run_id" "$worker_id" 2>/dev/null | awk -F'|' '{print $5}')
                if [ "$worker_status" = "in_progress" ]; then
                    all_workers_stopped=false
                    break
                fi
            done

            if $all_workers_stopped; then
                echo "All workers have stopped"
                break
            else
                echo "Waiting for in-progress workers to complete..."
                sleep 5
                continue
            fi
        fi

        if [ $iteration -ge $stop_timeout ]; then
            echo ""
            echo "Timeout reached after $stop_timeout seconds"
            break
        fi

        sleep 1
    done

    echo ""
    echo "Scheduler finished for run $run_id"
}

swarm_scheduler_get_next_task() {
    local run_id="$1"
    local available_workers

    available_workers=$(swarm_db_get_worker_stats "$run_id" 2>/dev/null || echo "")
    if [ -z "$available_workers" ]; then
        echo "Error: No workers registered for run $run_id"
        return 1
    fi

    local pending_tasks
    pending_tasks=$(swarm_db_get_pending_tasks "$run_id" 2>/dev/null)

    if [ -z "$pending_tasks" ]; then
        echo ""
        return 1
    fi

    echo "$pending_tasks"
}

swarm_scheduler_check_file_conflicts() {
    local run_id="$1"
    local task_id="$2"
    local estimated_files="$3"

    echo "$estimated_files" | jq -r '.[]' 2>/dev/null | while read -r file_pattern; do
        if [ -z "$file_pattern" ]; then
            continue
        fi

        local conflicts
        conflicts=$(swarm_db_check_conflicts "$run_id" "$file_pattern" 2>/dev/null)

        if [ -n "$conflicts" ]; then
            echo "File conflict for pattern: $file_pattern"
            echo "$conflicts" | while read -r worker_id task_id pattern; do
                echo "  - Worker $worker_id has locked $pattern"
            done
            return 1
        fi
    done

    return 0
}

swarm_scheduler_assign_task() {
    local run_id="$1"
    local worker_id="$2"
    local task_id="$3"

    echo "Assigning task $task_id to worker $worker_id"

    local task_info
    task_info=$(swarm_db_claim_task "$worker_id" 2>/dev/null)
    if [ -z "$task_info" ]; then
        echo "Error: Could not claim task for worker $worker_id"
        return 1
    fi

    local task_text estimated_files devplan_line
    task_text=$(echo "$task_info" | awk -F'|' '{print $2}')
    estimated_files=$(echo "$task_info" | awk -F'|' '{print $3}')
    devplan_line=$(echo "$task_info" | awk -F'|' '{print $4}')

    echo "Assigned: $task_text"
    echo "Estimated files: $estimated_files"
    echo "Devplan line: $devplan_line"

    local lock_success
    lock_success=$(swarm_db_acquire_locks "$run_id" "$worker_id" "$task_id" $estimated_files 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "Error: Failed to acquire locks"
        swarm_db_release_locks "$worker_id" 2>/dev/null
        return 1
    fi

    echo "Locks acquired"

    return 0
}

swarm_scheduler_handle_completion() {
    local task_id="$1"
    local worker_id="$2"

    echo "Handling task completion: $task_id (worker $worker_id)"

    local result_files
    result_files=$(swarm_db_complete_task "$task_id" "$worker_id" 2>/dev/null)

    echo "Task $task_id completed"
}

swarm_scheduler_handle_failure() {
    local task_id="$1"
    local worker_id="$2"
    local error_message="$3"

    echo "Handling task failure: $task_id (worker $worker_id): $error_message"

    swarm_db_fail_task "$task_id" "$worker_id" "$error_message" 2>/dev/null

    echo "Task $task_id marked as failed"
}

swarm_scheduler_rebalance() {
    local run_id="$1"

    echo "Checking for rebalancing opportunities..."

    local stale_workers
    stale_workers=$(swarm_db_cleanup_stale_workers "$run_id" 2>/dev/null)

    if [ -n "$stale_workers" ]; then
        echo "Found stale workers, re-balancing tasks..."

        local old_ifs="$IFS"
        IFS='|'
        read -ra worker_ids <<< "$stale_workers"
        IFS="$old_ifs"

        for worker_id in "${worker_ids[@]}"; do
            local current_task
            current_task=$(swarm_db_worker_status "$run_id" "$worker_id" 2>/dev/null | awk -F'|' '{print $6}')

            if [ -n "$current_task" ]; then
                local task_id
                task_id=$(echo "$current_task" | awk '{print $1}')
                echo "Rebalancing stale task $task_id from worker $worker_id"

                swarm_db_release_locks "$worker_id" 2>/dev/null

                swarm_db_complete_task "$task_id" "$worker_id" "Worker timeout" 2>/dev/null
            fi
        done
    else
        echo "No stale workers found"
    fi
}

swarm_scheduler_all_complete() {
    local run_id="$1"

    local run_status
    run_status=$(swarm_db_get_run_status "$run_id" 2>/dev/null)

    if [ -z "$run_status" ]; then
        return 1
    fi

    local status total_tasks completed_tasks failed_tasks
    status=$(echo "$run_status" | awk -F'|' '{print $1}')
    total_tasks=$(echo "$run_status" | awk -F'|' '{print $2}')
    completed_tasks=$(echo "$run_status" | awk -F'|' '{print $3}')
    failed_tasks=$(echo "$run_status" | awk -F'|' '{print $4}')

    echo "Run status: $status, Total: $total_tasks, Completed: $completed_tasks, Failed: $failed_tasks"

    if [ "$status" = "completed" ]; then
        return 0
    fi

    if [ "$completed_tasks" -ge "$total_tasks" ]; then
        return 0
    fi

    return 1
}

swarm_scheduler_get_unassigned_tasks() {
    local run_id="$1"

    local task_list
    task_list=$(swarm_db_get_pending_tasks "$run_id" 2>/dev/null)

    echo "$task_list"
}

swarm_scheduler_get_active_workers() {
    local run_id="$1"

    local worker_list
    worker_list=$(swarm_db_list_workers "$run_id" 2>/dev/null)

    echo "$worker_list"
}
