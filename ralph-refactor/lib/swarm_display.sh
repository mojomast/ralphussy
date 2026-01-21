#!/usr/bin/env bash

swarm_display_show_header() {
    local run_id="$1"
    local mode="$2"
    local worker_count="$3"

    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                      RALPH SWARM                                 ║"
    echo "║  Run: $run_id  │  Mode: $mode  │  Workers: $worker_count       ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
}

swarm_display_show_progress() {
    local completed_tasks="$1"
    local total_tasks="$2"
    local in_progress_tasks="$3"
    local failed_tasks="$4"

    local percentage
    if [ "$total_tasks" -gt 0 ]; then
        percentage=$((completed_tasks * 100 / total_tasks))
    else
        percentage=0
    fi

    local bar_length=30
    local filled=$((percentage * bar_length / 100))

    local bar
    bar=$(printf '%0.s█' $(seq 1 $filled))
    local empty=$((bar_length - filled))
    bar="${bar}$(printf '%0.s░' $(seq 1 $empty))"

    echo "║  Progress: ${bar}  │  $completed_tasks/$total_tasks tasks ($percentage%)   ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"

    if [ $in_progress_tasks -gt 0 ]; then
        echo "║  In Progress: $in_progress_tasks                                              ║"
    fi

    if [ $failed_tasks -gt 0 ]; then
        echo "║  Failed: $failed_tasks                                                 ║"
    fi
}

swarm_display_show_workers() {
    local workers_info="$1"

    echo "║  Workers:" 
    echo "$workers_info" | head -n 5 | while IFS='|' read -r id worker_num pid branch_name status current_task_id; do
        if [ -n "$branch_name" ]; then
            echo "║    $worker_num [${status^^}]  Branch: $branch_name"
            if [ -n "$current_task_id" ]; then
                echo "║           Task: $current_task_id"
            fi
        fi
    done

    local total_workers
    total_workers=$(echo "$workers_info" | wc -l)
    if [ "$total_workers" -gt 5 ]; then
        echo "║    ... and $((total_workers - 5)) more workers"
    fi
}

swarm_display_show_summary() {
    local elapsed_time="$1"
    local remaining_time="$2"
    local cost="$3"

    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Completed: $completed_tasks  │  In Progress: $in_progress  │  Failed: $failed"
    echo "║  Elapsed: $elapsed_time  │  Est. remaining: $remaining_time  │  Cost: $cost"
    echo "╚══════════════════════════════════════════════════════════════════╝"
}

swarm_display_update() {
    local run_id="$1"

    local run_status
    run_status=$(swarm_db_get_run_status "$run_id" 2>/dev/null || echo "")

    if [ -z "$run_status" ]; then
        return 0
    fi

    local status completed_tasks failed_tasks
    status=$(echo "$run_status" | awk -F'|' '{print $1}')
    completed_tasks=$(echo "$run_status" | awk -F'|' '{print $4}')
    failed_tasks=$(echo "$run_status" | awk -F'|' '{print $5}')

    local task_stats
    task_stats=$(swarm_db_get_task_count_by_status "$run_id" 2>/dev/null || echo "")

    local pending
    pending=$(echo "$task_stats" | awk -F'|' '$1=="pending"{print $2}')
    local in_progress
    in_progress=$(echo "$task_stats" | awk -F'|' '$1=="in_progress"{print $2}')

    if [ -z "$pending" ]; then
        pending=0
    fi

    if [ -z "$in_progress" ]; then
        in_progress=0
    fi

    local total_tasks
    total_tasks=$((completed_tasks + pending + in_progress + failed_tasks))

    if [ "$total_tasks" -eq 0 ]; then
        total_tasks=1
    fi

    local worker_info
    worker_info=$(swarm_db_list_workers "$run_id" 2>/dev/null || echo "")

    swarm_display_show_progress "$completed_tasks" "$total_tasks" "$in_progress" "$failed_tasks"
    swarm_display_show_workers "$worker_info"

    local elapsed_time
    local remaining_time
    local cost
    elapsed_time="Calculating..."
    remaining_time="Calculating..."
    cost="0"

    local started_at
    started_at=$(echo "$run_status" | awk -F'|' '{print $6}')

    if [ -n "$started_at" ]; then
        local start_sec
        local now_sec
        start_sec=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
        now_sec=$(date +%s)
        elapsed_time=$((now_sec - start_sec))

        if [ "$elapsed_time" -gt 0 ]; then
            local tasks_per_sec
            tasks_per_sec=$(echo "scale=2; $completed_tasks / $elapsed_time" | bc 2>/dev/null || echo 0)

            if [ "$(echo "$tasks_per_sec > 0" | bc)" -eq 1 ]; then
                local remaining_tasks
                remaining_tasks=$((pending + in_progress))
                remaining_time=$((remaining_tasks / tasks_per_sec))
            fi
        fi
    fi

    swarm_display_show_summary "$elapsed_time" "$remaining_time" "$cost"
}

swarm_display_show_initial() {
    local run_id="$1"
    local mode="$2"
    local worker_count="$3"

    swarm_display_show_header "$run_id" "$mode" "$worker_count"

    local run_status
    run_status=$(swarm_db_get_run_status "$run_id" 2>/dev/null || echo "")

    if [ -n "$run_status" ]; then
        local completed_tasks failed_tasks
        completed_tasks=$(echo "$run_status" | awk -F'|' '{print $4}')
        failed_tasks=$(echo "$run_status" | awk -F'|' '{print $5}')
        local total_tasks
        total_tasks=$((completed_tasks + failed_tasks))

        swarm_display_show_progress "$completed_tasks" "$total_tasks" 0 "$failed_tasks"
    fi
}

swarm_display_show_worker_status() {
    local worker_id="$1"
    local run_id="$2"

    local worker_info
    worker_info=$(swarm_db_worker_status "$run_id" "$worker_id" 2>/dev/null || echo "")

    if [ -z "$worker_info" ]; then
        echo "Worker $worker_id not found"
        return 1
    fi

    local id worker_num pid branch_name status current_task_id locked_files work_dir started_at last_heartbeat
    IFS='|' read -r id worker_num pid branch_name status current_task_id locked_files work_dir started_at last_heartbeat <<< "$worker_info"

    echo "Worker #$worker_num:"
    echo "  ID: $id"
    echo "  PID: $pid"
    echo "  Branch: $branch_name"
    echo "  Status: $status"

    if [ -n "$current_task_id" ]; then
        local task_info
        task_info=$(swarm_db_claim_task "$worker_id" 2>/dev/null | cut -d'|' -f2)
        echo "  Current Task: $current_task_id - $task_info"
    fi

    echo "  Work Directory: $work_dir"

    if [ -n "$last_heartbeat" ]; then
        local now
        now=$(date +%s)
        local last_heartbeat_sec
        last_heartbeat_sec=$(date -d "$last_heartbeat" +%s 2>/dev/null || echo 0)
        local heartbeat_age=$((now - last_heartbeat_sec))

        if [ $heartbeat_age -lt 60 ]; then
            echo "  Heartbeat: Active ($heartbeat_age seconds ago)"
        else
            echo "  Heartbeat: Stale ($heartbeat_age seconds ago)"
        fi
    fi
}

swarm_display_show_log_tail() {
    local worker_num="$1"
    local lines="${2:-50}"

    local run_dir
    run_dir="$RALPH_DIR/swarm/runs"

    if [ -d "$run_dir" ]; then
        local worker_dir
        worker_dir="$run_dir/worker-$worker_num/logs"

        if [ -d "$worker_dir" ]; then
            echo "=== Worker $worker_num logs ==="
            tail -n "$lines" "$worker_dir"/*.log 2>/dev/null || echo "No log files found"
        else
            echo "No logs found for worker $worker_num"
        fi
    else
        echo "No run directory found"
    fi
}

swarm_display_show_cost_summary() {
    local run_id="$1"

    echo "=== Cost Summary ==="

    local total_cost
    total_cost=$(sqlite3 "$RALPH_DIR/swarm.db" <<EOF
SELECT SUM(cost) FROM task_costs WHERE run_id = '$run_id';
EOF
)

    if [ -z "$total_cost" ] || [ "$total_cost" = "NULL" ]; then
        total_cost=0
    fi

    echo "Total Cost: $total_cost"
}

swarm_display_show_task_details() {
    local run_id="$1"
    local task_id="$2"

    local task_info
    task_info=$(sqlite3 "$RALPH_DIR/swarm.db" <<EOF
SELECT id, task_text, status, worker_id, priority, estimated_files, actual_files, error_message
FROM tasks
WHERE run_id = '$run_id' AND id = $task_id;
EOF
)

    if [ -z "$task_info" ]; then
        echo "Task $task_id not found"
        return 1
    fi

    echo "=== Task $task_id ==="
    echo "$task_info"
}

swarm_display_show_waiting_workers() {
    local run_id="$1"

    echo "=== Workers Waiting for Tasks ==="

    local workers_info
    workers_info=$(swarm_db_list_workers "$run_id" 2>/dev/null || echo "")

    local waiting_count=0

    while IFS='|' read -r id worker_num pid branch_name status current_task_id; do
        if [ -z "$branch_name" ]; then
            continue
        fi

        if [ "$status" = "idle" ]; then
            echo "Worker #$worker_num ($branch_name) - Waiting for task"
            waiting_count=$((waiting_count + 1))
        fi
    done <<< "$workers_info"

    if [ "$waiting_count" -eq 0 ]; then
        echo "All workers are busy"
    fi
}
