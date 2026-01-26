#!/usr/bin/env bash

# Color codes for live output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

swarm_worker_apply_limits() {
    # Resource limits are DISABLED by default (0 = no limit)
    # These would cause "fork: Resource temporarily unavailable" errors if set too low
    # Only enable by explicitly setting environment variables to non-zero values

    # Increase file descriptor limit if possible
    ulimit -n 4096 2>/dev/null || true
    # Disable core dumps
    ulimit -c 0 2>/dev/null || true
}

swarm_worker_check_commit_for_task() {
    local run_id="$1"
    local task_id="$2"
    local task_text="$3"
    local worker_dir="$4"

    # ALWAYS check completed_tasks table FIRST (source of truth)
    local task_hash
    task_hash=$(printf '%s' "$task_text" | sha256sum | cut -d' ' -f1)
    
    local is_completed
    is_completed=$(swarm_db_is_task_completed "$task_hash")
    
    if [ "$is_completed" = "yes" ]; then
        # Task is definitively completed according to database
        echo "check:completed_in_db|$task_hash|Found in completed_tasks table"
        return
    fi
    
    # Secondary check: look for git commits (fallback for legacy runs)
    local repo_dir="$worker_dir/repo"
    
    if [ ! -d "$repo_dir/.git" ]; then
        echo "check:no_git"
        return
    fi

    # Try to find commits that match the task text
    # Use more sophisticated matching than just keywords
    local task_keywords
    task_keywords=$(echo "$task_text" | grep -oE '\b[a-zA-Z]{4,}\b' | head -n 5 | tr '\n' '|' | sed 's/|$//')

    if [ -z "$task_keywords" ]; then
        echo "check:no_keywords"
        return
    fi

    # Search in commits from the current run's branches
    local matching_commit
    matching_commit=$(cd "$repo_dir" && git log --all --grep="$task_keywords" --oneline --since="7 days ago" 2>/dev/null | head -n 1 || true)

    if [ -n "$matching_commit" ]; then
        local commit_hash
        commit_hash=$(echo "$matching_commit" | cut -d' ' -f1)
        local commit_msg
        commit_msg=$(echo "$matching_commit" | cut -d' ' -f2-)
        
        # IMPORTANT: This is just a hint, not definitive
        # Don't auto-complete based on git alone, just log it
        echo "check:git_hint|$commit_hash|$commit_msg"
        return
    fi

    echo "check:not_found"
}

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
    local project_name="${SWARM_PROJECT_NAME:-}"

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
    
    # CRITICAL: When SWARM_PROJECT_NAME is set, ALWAYS use the project directory
    # This prevents ralphussy files from leaking into generated projects
    if [ -n "$project_name" ]; then
        local projects_base="${SWARM_PROJECTS_BASE:-$HOME/projects}"
        local project_dir="$projects_base/$project_name"
        
        if [ ! -d "$project_dir" ]; then
            echo "Creating new project directory: $project_dir"
            mkdir -p "$project_dir"
            
            # Create a fresh git repo - do NOT copy from current directory
            git -C "$project_dir" init >/dev/null
            git -C "$project_dir" config user.name "Swarm" >/dev/null
            git -C "$project_dir" config user.email "swarm@local" >/dev/null
            
            # Only copy devplan, nothing else
            if [ -f "$devplan_path" ]; then
                cp "$devplan_path" "$project_dir/devplan.md" 2>/dev/null || true
            fi
            
            # Create a minimal .gitignore - also exclude ralphussy internal files
            cat > "$project_dir/.gitignore" <<'GITIGNORE'
node_modules/
.env
*.log
__pycache__/
.DS_Store
# Exclude ralphussy internal files (should never be in project)
ralph-refactor/
ralph-tui/
swarm-dashboard/
opencode-ralph*/
*.db
GITIGNORE
            
            git -C "$project_dir" add . >/dev/null 2>&1 || true
            git -C "$project_dir" commit -m "Initial project setup" >/dev/null 2>&1 || true
        elif [ ! -d "$project_dir/.git" ]; then
            echo "Initializing git repository in existing project: $project_dir"
            git -C "$project_dir" init >/dev/null
            git -C "$project_dir" config user.name "Swarm" >/dev/null
            git -C "$project_dir" config user.email "swarm@local" >/dev/null
            git -C "$project_dir" checkout -b main 2>/dev/null || true
            
            if [ -f "$devplan_path" ] && [ ! -f "$project_dir/devplan.md" ]; then
                cp "$devplan_path" "$project_dir/devplan.md" 2>/dev/null || true
            fi
            
            git -C "$project_dir" add . >/dev/null 2>&1 || true
            git -C "$project_dir" commit -m "Initial commit by swarm" >/dev/null 2>&1 || true
        fi
        
        # ALWAYS use project_dir as repo_root when project_name is set
        repo_root="$project_dir"
        echo "Using project directory as repo root: $repo_root"
    fi
    
    # Only fall back to current directory if no project_name was specified
    if [ -z "$repo_root" ]; then
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi
    
    if [ -z "$repo_root" ]; then
        if [ ! -d ".git" ]; then
             echo "Initializing new git repository for swarm..."
             git init >/dev/null
             git add . >/dev/null 2>&1 || true
             git commit -m "Initial commit by swarm" >/dev/null 2>&1 || true
             repo_root=$(pwd)
        else
             repo_root=$(pwd)
        fi
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

    # Spawn worker fully detached using setsid to avoid inheriting parent restrictions
    # This creates a new session and process group, avoiding issues with pipe buffering
    # and inherited file descriptor limits
    local swarm_dir="$__RALPH_SWARM_DIR__"
    local ralph_dir_val="$RALPH_DIR"
    local llm_provider="${RALPH_LLM_PROVIDER:-}"
    local llm_model="${RALPH_LLM_MODEL:-}"

    setsid bash -c '
        cd "'"$repo_dir"'" || exit 1

        # Increase file descriptor limit
        ulimit -n 4096 2>/dev/null || true

        echo "Worker '"$worker_num"' started (PID: $$, ID: '"$worker_id"')"
        echo "Run ID: '"$run_id"'"
        echo "Worker directory: '"$worker_dir"'"

        # Export necessary variables
        export RALPH_DIR="'"$ralph_dir_val"'"
        export RALPH_LLM_PROVIDER="'"$llm_provider"'"
        export RALPH_LLM_MODEL="'"$llm_model"'"
        export SWARM_OUTPUT_MODE="'"${SWARM_OUTPUT_MODE:-}"'"
        export SWARM_PROJECT_NAME="'"${SWARM_PROJECT_NAME:-}"'"
        export SWARM_PROJECTS_BASE="'"${SWARM_PROJECTS_BASE:-$HOME/projects}"'"
        export SWARM_REPO_ROOT="'"${repo_root}"'"

        # Redirect all output to log file
        exec > "'"$log_full"'" 2>&1

        # Source from worker module and run main loop
        source "'"$swarm_dir"'/lib/swarm_db.sh"
        source "'"$swarm_dir"'/lib/swarm_worker.sh"

        swarm_worker_main_loop "'"$run_id"'" "'"$worker_num"'" "'"$worker_id"'" "'"$devplan_path"'" "'"$ralph_path"'" "'"$log_full"'"

        echo "Worker '"$worker_num"' shutting down"
    ' >/dev/null 2>&1 &

    local worker_pid=$!
    sleep 1

    if ! ps -p $worker_pid > /dev/null; then
        echo "Error: Failed to spawn worker $worker_num"
        swarm_db_worker_heartbeat "$worker_id" 2>/dev/null
        return 1
    fi

    swarm_db_update_worker_pid "$worker_id" "$worker_pid" 2>/dev/null || true
    swarm_db_worker_heartbeat "$worker_id"

    # Register in global worker registry
    if command -v swarm_db_register_worker_global >/dev/null 2>&1; then
        swarm_db_register_worker_global "$worker_id" "$run_id" "$worker_num" "$worker_pid" >/dev/null || true
    fi

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
            # Update global heartbeat periodically
            if command -v swarm_db_heartbeat_worker_global >/dev/null 2>&1; then
                swarm_db_heartbeat_worker_global "$worker_id" >/dev/null 2>&1 || true
            fi
            continue
        fi

        local task_id task_text estimated_files devplan_line
        task_id=$(echo "$current_task" | cut -d'|' -f1)
        task_text=$(echo "$current_task" | cut -d'|' -f2)
        estimated_files=$(echo "$current_task" | cut -d'|' -f3)
        devplan_line=$(echo "$current_task" | cut -d'|' -f4)

        echo "[$(date)] Worker $worker_num claimed task $task_id"
        echo "[$(date)] Task: $task_text"

        if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
            echo -e "${CYAN}▶${NC} Worker $worker_num assigned task $task_id"
            echo -e "${CYAN}▶${NC}   Task: ${task_text:0:80}..."
            echo ""
        fi

        swarm_db_worker_heartbeat "$worker_id"

        # Check if this task has already been completed by checking for matching commits
        local worker_dir
        worker_dir="$RALPH_DIR/swarm/runs/$run_id/worker-$worker_num"
        local commit_check_result
        commit_check_result=$(swarm_worker_check_commit_for_task "$run_id" "$task_id" "$task_text" "$worker_dir")

        local check_status
        check_status=$(echo "$commit_check_result" | cut -d'|' -f1)

        case "$check_status" in
            check:completed_in_db)
                # Definitive: task is done according to database
                local task_hash
                task_hash=$(echo "$commit_check_result" | cut -d'|' -f2)
                echo "[$(date)] Task $task_id already completed (DB hash: $task_hash)"
                
                if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
                    echo -e "${GREEN}✓${NC} Worker $worker_num skipping task $task_id (completed in DB)"
                fi
                
                # Mark as completed in this run's tasks table
                swarm_db_complete_task "$task_id" "$estimated_files" "$worker_id"
                continue
                ;;
                
            check:git_hint)
                # Found matching commit but NOT in completed_tasks
                # This is suspicious - task may have been completed but not recorded
                # Log it but DON'T skip - let it run to be safe
                local commit_hash
                commit_hash=$(echo "$commit_check_result" | cut -d'|' -f2)
                local commit_msg
                commit_msg=$(echo "$commit_check_result" | cut -d'|' -f3-)
                
                echo "[$(date)] WARNING: Found matching commit $commit_hash but task not in completed_tasks"
                echo "[$(date)] Commit: $commit_msg"
                echo "[$(date)] Running task $task_id to be safe..."
                ;;
                
            check:not_found|check:no_git|check:no_keywords|check:skip)
                # No evidence of completion, proceed with task
                ;;
        esac

        # Update global heartbeat before task execution
        if command -v swarm_db_heartbeat_worker_global >/dev/null 2>&1; then
            swarm_db_heartbeat_worker_global "$worker_id" >/dev/null 2>&1 || true
        fi

        if swarm_worker_execute_task "$run_id" "$worker_num" "$task_id" "$task_text" "$estimated_files" "$devplan_line" "$devplan_path" "$ralph_path" "$log_file"; then
            swarm_db_complete_task "$task_id" "$estimated_files" "$worker_id"
            echo "[$(date)] Task $task_id completed successfully"
            if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
                echo -e "${GREEN}✓${NC} Worker $worker_num marked task $task_id as complete"
                echo ""
            fi
        else
            local error_msg="Worker error on task $task_id"
            swarm_db_fail_task "$task_id" "$worker_id" "$error_msg"
            echo "[$(date)] Task $task_id failed: $error_msg"
            if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
                echo -e "${RED}✗${NC} Worker $worker_num task $task_id failed: $error_msg"
                echo ""
            fi
        fi

        swarm_db_worker_heartbeat "$worker_id"

        # Update global heartbeat after task completion
        if command -v swarm_db_heartbeat_worker_global >/dev/null 2>&1; then
            swarm_db_heartbeat_worker_global "$worker_id" >/dev/null 2>&1 || true
        fi
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

    # Get worker_id for locking
    local worker_id
    worker_id=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT id FROM workers WHERE run_id = '$run_id' AND worker_num = $worker_num ORDER BY id DESC LIMIT 1;")

    # Check if we already created a commit for this task (idempotency check)
    local existing_commit
    existing_commit=$(cd "$repo_dir" && git log --all --oneline --grep="Task $task_id:" 2>/dev/null | head -n 1)

    if [ -n "$existing_commit" ]; then
        echo "[$(date)] Task $task_id already has commit: $existing_commit"
        echo "[$(date)] Treating as completed (idempotency check)"
        
        if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
            echo -e "${GREEN}✓${NC} Worker $worker_num found existing commit for task $task_id"
        fi
        
        # Release locks and return success
        swarm_db_release_locks "$worker_id" 2>/dev/null || true
        return 0
    fi

    # ACQUIRE FILE LOCKS BEFORE EXECUTION
    if [ -n "$estimated_files" ] && [ "$estimated_files" != "[]" ] && [ "$estimated_files" != "null" ]; then
        echo "[$(date)] Acquiring locks for estimated files: $estimated_files"
        
        if ! swarm_db_acquire_locks "$run_id" "$worker_id" "$task_id" "$estimated_files" 2>/dev/null; then
            echo "[$(date)] Failed to acquire file locks for task $task_id" 1>&2
            
            # Check if locks are held by another worker
            local locked_by
            locked_by=$(swarm_db_check_conflicts "$run_id" "$estimated_files" 2>/dev/null)
            
            if [ -n "$locked_by" ]; then
                echo "[$(date)] Files locked by: $locked_by" 1>&2
                echo "[$(date)] Re-queuing task $task_id for later attempt" 1>&2
                
                # Re-queue task (don't fail it, just defer)
                sqlite3 "$RALPH_DIR/swarm.db" <<EOF
UPDATE tasks 
SET status = 'pending', 
    worker_id = NULL, 
    started_at = NULL,
    stall_count = COALESCE(stall_count, 0) + 1
WHERE id = $task_id;
EOF
                return 1
            fi
        fi
        
        echo "[$(date)] Locks acquired for task $task_id"
    fi

    # Ensure json_extract_text is available for completion detection
    if ! command -v json_extract_text >/dev/null 2>&1; then
        # shellcheck source=ralph-refactor/lib/json.sh
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/json.sh"
    fi

    local prompt
    prompt=$(cat <<EOF
CRITICAL INSTRUCTION: You MUST end your response with the exact string "<promise>COMPLETE</promise>" when you have finished the task. Do not omit this marker under any circumstances.

You are a swarm worker (#$worker_num) operating inside a git worktree for a NEW PROJECT.

Task ($task_id): $task_text

Constraints:
- Make changes ONLY in this repository (current working directory).
- This is a fresh project - create the necessary files and structure for the task.
- DO NOT reference, copy, or include any files from ralph-refactor/, ralph-tui/, swarm-dashboard/, or opencode-ralph* directories - these are internal tooling files and must NOT be included in the project.
- Run relevant tests/linters if they exist.
- Create a git commit for your changes with a clear message in this format:
  "Task $task_id: <brief description of what you did>"
  This allows the swarm to detect if this task was already completed.
- When finished, you MUST output exactly: <promise>COMPLETE</promise>

CRITICAL - SOURCE FILE CLEANLINESS:
- NEVER insert progress markers, anchors, checkpoints, or annotations into source code files.
- NEVER add HTML/Markdown comments (<!-- -->) into non-HTML/Markdown files.
- NEVER add comments like "// PROGRESS:", "// SWARM:", "// Worker N:", "// Task completed" etc.
- Source files (.go, .py, .rs, .js, .ts, .c, .cpp, etc.) must contain ONLY legitimate code and standard code comments.
- Progress tracking is handled externally by the swarm system - do NOT track it in code files.
- If you need to leave development notes, put them in a separate NOTES.md or TODO.md file, NEVER inline in source code.

Remember: End your response with "<promise>COMPLETE</promise>" to signal task completion. This is required for the swarm system to recognize your work as done.

If you need context, inspect files in the repo. Focus on building the requested functionality from scratch.
EOF
)

    echo "[$(date)] Running OpenCode for task $task_id"

    if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
        echo -e "${YELLOW}▸${NC} Worker $worker_num executing task $task_id..."
        echo -e "${YELLOW}▸${NC}   ${task_text:0:100}"
        echo ""
    fi

    local opencode_cmd="opencode run"
    local full_model=""

    # Construct model argument in "provider/model" format if needed
    if [ -n "${RALPH_LLM_MODEL:-}" ]; then
        if [[ "${RALPH_LLM_MODEL}" == *"/"* ]]; then
            full_model="${RALPH_LLM_MODEL}"
        elif [ -n "${RALPH_LLM_PROVIDER:-}" ]; then
            full_model="${RALPH_LLM_PROVIDER}/${RALPH_LLM_MODEL}"
        else
            full_model="${RALPH_LLM_MODEL}"
        fi
    fi

    if [ -n "$full_model" ]; then
        opencode_cmd="$opencode_cmd --model $full_model"
    fi

    local timeout_seconds="${SWARM_TASK_TIMEOUT:-600}"
    local json_output
    local execution_failed=false

    if ! json_output=$(cd "$repo_dir" && timeout "$timeout_seconds" $opencode_cmd --format json "$prompt" 2>&1); then
        execution_failed=true
        local exit_code=$?
        
        # ALWAYS release locks on failure
        swarm_db_release_locks "$worker_id" 2>/dev/null || true
        
        if [ $exit_code -eq 124 ]; then
            echo "[$(date)] Task execution failed (timeout after ${timeout_seconds}s)" 1>&2
            if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
                echo -e "${RED}✗${NC} Worker $worker_num task $task_id failed: timeout after ${timeout_seconds}s"
            fi
        else
            echo "[$(date)] Task execution failed (opencode error)" 1>&2
            echo "$json_output" | head -c 300 1>&2
            if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
                echo -e "${RED}✗${NC} Worker $worker_num task $task_id failed: opencode error"
                echo -e "${RED}✗${NC}   $(echo "$json_output" | head -c 150)..."
            fi
            # Persist full opencode output for offline inspection
            if [ -n "$json_output" ]; then
                echo "$json_output" > "${repo_dir}/.swarm_debug_${task_id}.json" 2>/dev/null || true
            fi
        fi
        return 1
    fi

    # Best-effort: record token/cost stats if possible
    local prompt_tokens=0
    local completion_tokens=0
    local cost=0
    if command -v jq >/dev/null 2>&1; then
        # Single jq call for efficiency
        local stats
        stats=$(echo "$json_output" | jq -s '{
            prompt: (map(select(.part.tokens.input)) | map(.part.tokens.input) | add // 0),
            completion: (map(select(.part.tokens.output)) | map(.part.tokens.output) | add // 0),
            cost: (map(select(.part.cost)) | map(.part.cost) | add // 0)
        }' 2>/dev/null) || stats='{"prompt":0,"completion":0,"cost":0}'
        
        prompt_tokens=$(echo "$stats" | jq -r '.prompt')
        completion_tokens=$(echo "$stats" | jq -r '.completion')
        cost=$(echo "$stats" | jq -r '.cost')
    fi
    
    if command -v swarm_db_record_task_cost >/dev/null 2>&1; then
        swarm_db_record_task_cost "$run_id" "$task_id" "$prompt_tokens" "$completion_tokens" "$cost" >/dev/null 2>&1 || true
    fi

    # Persist debug output when there are no completion tokens so we can inspect provider failures.
    if [ "$completion_tokens" -eq 0 ] && [ -n "$json_output" ]; then
        echo "$json_output" > "${repo_dir}/.swarm_debug_${task_id}.json" 2>/dev/null || true
    fi

    if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
        echo -e "${BLUE}✓${NC} API call complete: ${prompt_tokens}→${completion_tokens} tokens | \$${cost}"
        if [ "$completion_tokens" -eq 0 ]; then
            echo -e "${YELLOW}⚠${NC} Warning: 0 tokens returned. Full response saved to: ${repo_dir}/.swarm_debug_${task_id}.json"
        fi
        echo ""
    fi

    local text_output
    text_output=$(json_extract_text "$json_output" 2>/dev/null || true)

    # Debug: Warn if text extraction failed but tokens were generated
    if [ -z "$text_output" ] && [ "$completion_tokens" -gt 0 ]; then
        if [ "${SWARM_DEBUG:-false}" = "true" ]; then
            echo "[$(date)] DEBUG: Text extraction failed despite $completion_tokens completion tokens" 1>&2
            echo "[$(date)] DEBUG: Full JSON saved to: ${repo_dir}/.swarm_text_debug_${task_id}.json" 1>&2
            echo "$json_output" > "${repo_dir}/.swarm_text_debug_${task_id}.json"
        fi
    fi

    # Check for completion using multiple patterns
    local completed=false
    if echo "$text_output" | grep -qiE "<promise>COMPLETE</promise>|Task completed|task completed|completed successfully|All done|Task finished|Done|done"; then
        completed=true
    fi
    
    if $completed; then
        echo "[$(date)] Task execution successful"
        
        # RELEASE LOCKS AFTER SUCCESSFUL COMPLETION
        swarm_db_release_locks "$worker_id" 2>/dev/null || true
        echo "[$(date)] Locks released for task $task_id"
        
        if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
            echo -e "${GREEN}✓${NC} Worker $worker_num completed task $task_id"
            echo ""

            # Show tool call summary
            echo "$text_output" | tr '|' '\n' | grep -vE '^\[RALPH\]|^=== Task|^=================================|^[0-9]\+' | while IFS= read -r line; do
                line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$line" ] && continue

                if echo "$line" | grep -qE '^(Read|Write|Edit|Bash|grep|glob|task|webfetch|codesearch|websearch|todoread|todowrite)'; then
                    echo -e "  ${CYAN}→ $line${NC}"
                elif echo "$line" | grep -qE '^(✅|❌|⚠️)'; then
                    echo -e "  ${GREEN}$line${NC}"
                fi
            done
            echo ""
        fi
        return 0
    fi

    # RELEASE LOCKS ON INCOMPLETE/FAILED TASK
    swarm_db_release_locks "$worker_id" 2>/dev/null || true
    
    echo "[$(date)] Task execution did not return completion promise" 1>&2
    if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
        echo -e "${YELLOW}⚠${NC} Worker $worker_num task $task_id did not complete (no promise)"
    fi
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

    local worker_id
    worker_id=$(sqlite3 "$RALPH_DIR/swarm.db" "SELECT id FROM workers WHERE run_id = '$run_id' AND worker_num = $worker_num ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)

    # Unregister from global registry
    if [ -n "$worker_id" ] && command -v swarm_db_unregister_worker >/dev/null 2>&1; then
        swarm_db_unregister_worker "$worker_id" >/dev/null 2>&1 || true
    fi

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
