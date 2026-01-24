#!/usr/bin/env bash

# Color codes for live output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if a process is running by PID
swarm_scheduler_is_pid_alive() {
    local pid="$1"
    [ -n "$pid" ] && [ "$pid" != "NULL" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null
}

# Detect dead workers and requeue their tasks
swarm_scheduler_cleanup_dead_workers() {
    local run_id="$1"
    local db_path="$RALPH_DIR/swarm.db"
    local dead_count=0
    local requeued_count=0

    # Get all workers for this run
    while IFS='|' read -r worker_id worker_num pid branch status current_task started_at heartbeat; do
        [ -z "$worker_id" ] && continue
        
        # Check if worker process is actually running
        if ! swarm_scheduler_is_pid_alive "$pid"; then
            echo "[SCHEDULER] Worker $worker_num (PID: $pid) is DEAD"
            dead_count=$((dead_count + 1))
            
            # Requeue the current task if any
            if [ -n "$current_task" ] && [ "$current_task" != "NULL" ]; then
                echo "[SCHEDULER] Requeuing task $current_task from dead worker $worker_num"
                sqlite3 "$db_path" <<EOF
UPDATE tasks 
SET status = 'pending', 
    worker_id = NULL, 
    started_at = NULL,
    stall_count = COALESCE(stall_count, 0) + 1
WHERE id = $current_task AND status = 'in_progress';
EOF
                requeued_count=$((requeued_count + 1))
            fi
            
            # Mark worker as dead/stopped
            sqlite3 "$db_path" <<EOF
UPDATE workers 
SET status = 'stopped', 
    current_task_id = NULL 
WHERE id = $worker_id;
EOF
            
            # Release any locks held by this worker
            swarm_db_release_locks "$worker_id" 2>/dev/null || true
        fi
    done < <(swarm_db_list_workers "$run_id" 2>/dev/null)

    # Also check for orphaned in_progress tasks (worker_id points to dead/stopped worker)
    local orphaned_tasks
    orphaned_tasks=$(sqlite3 "$db_path" <<EOF
SELECT t.id, t.worker_id, w.pid, w.status as worker_status
FROM tasks t
LEFT JOIN workers w ON t.worker_id = w.id
WHERE t.run_id = '$run_id' 
AND t.status = 'in_progress'
AND (w.status = 'stopped' OR w.status IS NULL OR w.id IS NULL);
EOF
)
    
    if [ -n "$orphaned_tasks" ]; then
        echo "$orphaned_tasks" | while IFS='|' read -r task_id worker_id pid worker_status; do
            [ -z "$task_id" ] && continue
            echo "[SCHEDULER] Requeuing orphaned task $task_id (worker was $worker_status)"
            sqlite3 "$db_path" <<EOF
UPDATE tasks 
SET status = 'pending', 
    worker_id = NULL, 
    started_at = NULL,
    stall_count = COALESCE(stall_count, 0) + 1
WHERE id = $task_id;
EOF
            requeued_count=$((requeued_count + 1))
        done
    fi

    if [ $dead_count -gt 0 ] || [ $requeued_count -gt 0 ]; then
        echo "[SCHEDULER] Cleanup: $dead_count dead workers, $requeued_count tasks requeued"
    fi
    
    echo "$dead_count"
}

# Count alive workers
swarm_scheduler_count_alive_workers() {
    local run_id="$1"
    local alive=0
    
    while IFS='|' read -r worker_id worker_num pid rest; do
        [ -z "$worker_id" ] && continue
        if swarm_scheduler_is_pid_alive "$pid"; then
            alive=$((alive + 1))
        fi
    done < <(swarm_db_list_workers "$run_id" 2>/dev/null)
    
    echo "$alive"
}

swarm_scheduler_main_loop() {
    local run_id="$1"
    local stop_timeout="${2:-3600}"
    local verbose="${3:-false}"

    echo "Scheduler started for run $run_id"
    echo "Poll interval: 5 seconds"
    echo "Stop timeout: $stop_timeout seconds"
    if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
        echo "Output mode: live (verbose)"
    fi
    echo ""

    # In live mode, set up log file tailing for all workers
    local worker_log_tails=()
    if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
        local worker_dir="$RALPH_DIR/swarm/runs/$run_id"
        sleep 2  # Give workers time to start
        for worker_log in "$worker_dir"/worker-*/logs/*.log; do
            [ -f "$worker_log" ] || continue
            tail -f "$worker_log" 2>/dev/null &
            worker_log_tails+=($!)
        done
    fi

    local iteration=0
    local last_status_check=0
    local last_cleanup_check=0
    local scheduler_start_time=$(date +%s)

    while true; do
        iteration=$((iteration + 1))
        current_time=$(date +%s)

        # Periodic status display
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

        # Periodic dead worker cleanup (every 5 seconds instead of 15)
        if [ $((current_time - last_cleanup_check)) -ge 5 ]; then
            local dead_workers
            dead_workers=$(swarm_scheduler_cleanup_dead_workers "$run_id")
            last_cleanup_check=$current_time
            
            # Check if ALL workers are dead
            local alive_workers
            alive_workers=$(swarm_scheduler_count_alive_workers "$run_id")
            if [ "$alive_workers" -eq 0 ]; then
                echo ""
                echo "[SCHEDULER] All workers have died! No alive workers remaining."
                echo "[SCHEDULER] Run '/swarm resume $run_id' to restart workers and continue."
                break
            fi
        fi

        local pending_tasks
        pending_tasks=$(swarm_db_get_pending_tasks "$run_id" 2>/dev/null | wc -l)
        local worker_stats
        worker_stats=$(swarm_db_get_worker_stats "$run_id" 2>/dev/null || echo "")
        local alive_workers
        alive_workers=$(swarm_scheduler_count_alive_workers "$run_id")

        if [ "$verbose" = "true" ] || [ $((iteration % 10)) -eq 0 ]; then
            echo "[${current_time}] Iteration $iteration: $pending_tasks pending, $alive_workers alive workers"
        fi

        # In live mode, show more frequent updates about task progress
        if [ "${SWARM_OUTPUT_MODE:-}" = "live" ] && [ $((iteration % 3)) -eq 0 ]; then
            local task_stats
            task_stats=$(swarm_db_get_task_count_by_status "$run_id" 2>/dev/null || echo "")
            local pending completed in_progress failed
            pending=$(echo "$task_stats" | awk -F'|' '$1=="pending"{print $2}' || echo 0)
            in_progress=$(echo "$task_stats" | awk -F'|' '$1=="in_progress"{print $2}' || echo 0)
            completed=$(echo "$task_stats" | awk -F'|' '$1=="completed"{print $2}' || echo 0)
            failed=$(echo "$task_stats" | awk -F'|' '$1=="failed"{print $2}' || echo 0)

            if [ -n "$completed" ] && [ -n "$in_progress" ] && [ -n "$pending" ]; then
                local total=$((completed + in_progress + pending + failed))
                local progress=0
                if [ "$total" -gt 0 ]; then
                    progress=$((completed * 100 / total))
                fi
                echo -e "${CYAN}[SCHEDULER]${NC} Progress: $completed/$total ($progress%) | $in_progress in progress | $pending pending | $failed failed"
            fi
        fi

        if [ $pending_tasks -eq 0 ]; then
            echo ""
            echo "No pending tasks remaining"

            # Check for in-progress tasks
            local in_progress_count
            in_progress_count=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'in_progress';" 2>/dev/null || echo "0")
            
            if [ "$in_progress_count" -gt 0 ]; then
                echo "Waiting for $in_progress_count in-progress tasks to complete..."
                sleep 5
                continue
            else
                echo "All tasks completed or failed"
                break
            fi
        fi

        # Check for timeout using local start time (not database start time)
        local elapsed=$((current_time - scheduler_start_time))
        if [ $elapsed -ge $stop_timeout ]; then
            echo ""
            echo "Timeout reached after $elapsed seconds"
            break
        fi

        sleep 5
    done

    echo ""
    echo "Scheduler finished for run $run_id"

    # Cleanup tail processes
    for tail_pid in "${worker_log_tails[@]:-}"; do
        kill "$tail_pid" 2>/dev/null || true
    done
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
