#!/usr/bin/env bash

# Collect artifacts for a completed run into RALPH_DIR/swarm/runs/<RUN_ID>/artifacts
swarm_collect_artifacts() {
    local run_id="$1"
    if [ -z "$run_id" ]; then
        echo "swarm_collect_artifacts: run_id required" 1>&2
        return 1
    fi

    # Support two common run directory layouts for compatibility with tests and older code:
    #  - $RALPH_DIR/swarm/runs/<RUN_ID>
    #  - $RALPH_DIR/runs/<RUN_ID>
    local run_dir1="$RALPH_DIR/swarm/runs/$run_id"
    local run_dir2="$RALPH_DIR/runs/$run_id"
    local run_dir=""
    if [ -d "$run_dir1" ]; then
        run_dir="$run_dir1"
    elif [ -d "$run_dir2" ]; then
        run_dir="$run_dir2"
    else
        echo "swarm_collect_artifacts: run directory not found: checked $run_dir1 and $run_dir2" 1>&2
        return 1
    fi

    # Allow overriding artifacts base via SWARM_ARTIFACTS_DIR.
    # If SWARM_ARTIFACTS_DIR contains "%RUN_ID%" it will be substituted.
    if [ -n "${SWARM_ARTIFACTS_DIR:-}" ]; then
        if printf '%s' "$SWARM_ARTIFACTS_DIR" | grep -q '%RUN_ID%'; then
            artifacts_dir=${SWARM_ARTIFACTS_DIR//%RUN_ID%/$run_id}
        else
            artifacts_dir="$SWARM_ARTIFACTS_DIR/$run_id"
        fi
        # if relative path, treat as relative to run_dir
        if [ "${artifacts_dir#/}" = "$artifacts_dir" ]; then
            artifacts_dir="$run_dir/$artifacts_dir"
        fi
    else
        local artifacts_dir="$run_dir/artifacts"
    fi
    mkdir -p "$artifacts_dir"

    for worker_dir in "$run_dir"/worker-*; do
        [ -d "$worker_dir" ] || continue
        local worker_name
        worker_name=$(basename "$worker_dir")
        local repo_dir="$worker_dir/repo"
        local dest="$artifacts_dir/$worker_name"
        mkdir -p "$dest"

        if [ -d "$repo_dir" ]; then
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --exclude='.git' --exclude='node_modules' --delete "$repo_dir"/ "$dest"/ 2>/dev/null || true
            else
                # fallback: tar stream excluding common heavy dirs
                (cd "$repo_dir" && tar -cf - --exclude='.git' --exclude='node_modules' .) | tar -xf - -C "$dest" || true
            fi

            # gather git summaries if available
            git -C "$repo_dir" log --oneline -n 200 > "$dest/commits.txt" 2>/dev/null || true
            git -C "$repo_dir" ls-files > "$dest/files.txt" 2>/dev/null || true
        fi

        # copy logs
        mkdir -p "$dest/logs"
        if [ -d "$worker_dir/logs" ]; then
            cp -a "$worker_dir"/logs/* "$dest/logs/" 2>/dev/null || true
        fi
    done

    echo "Artifacts collected to: $artifacts_dir"
}

swarm_extract_merged_artifacts() {
    local run_id="$1"
    local dest_base="${2:-$HOME/projects}"
    
    if [ -z "$run_id" ]; then
        echo "swarm_extract_merged_artifacts: run_id required" 1>&2
        return 1
    fi

    local run_dir="$RALPH_DIR/swarm/runs/$run_id"
    if [ ! -d "$run_dir" ]; then
        echo "swarm_extract_merged_artifacts: run directory not found: $run_dir" 1>&2
        return 1
    fi

    local project_name="swarm-$run_id"
    local dest_dir="$dest_base/$project_name"
    mkdir -p "$dest_dir"

    local db_path="$RALPH_DIR/swarm.db"
    if [ ! -f "$db_path" ]; then
        echo "swarm_extract_merged_artifacts: database not found: $db_path" 1>&2
        return 1
    fi

    echo "Extracting merged artifacts for run: $run_id"
    echo "Destination: $dest_dir"
    echo

    local run_status total_tasks completed_tasks failed_tasks pending_tasks
    run_status=$(sqlite3 "$db_path" "SELECT status FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null)
    total_tasks=$(sqlite3 "$db_path" "SELECT total_tasks FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null || echo "0")
    completed_tasks=$(sqlite3 "$db_path" "SELECT completed_tasks FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null || echo "0")
    failed_tasks=$(sqlite3 "$db_path" "SELECT failed_tasks FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null || echo "0")

    run_status="${run_status:-unknown}"
    total_tasks="${total_tasks:-0}"
    completed_tasks="${completed_tasks:-0}"
    failed_tasks="${failed_tasks:-0}"
    pending_tasks=$((total_tasks - completed_tasks - failed_tasks))

    echo "=== Run Summary ==="
    echo "Status: $run_status"
    echo "Total Tasks: $total_tasks"
    echo "Completed: $completed_tasks"
    echo "Failed: $failed_tasks"
    echo "Pending: $pending_tasks"
    echo

    local merged_repo_dir="$dest_dir/merged-repo"
    mkdir -p "$merged_repo_dir"

    cd "$merged_repo_dir" || exit 1
    git init 2>/dev/null || true
    git config user.name "Swarm Extractor" 2>/dev/null || true
    git config user.email "swarm@local" 2>/dev/null || true
    cd - > /dev/null || true

    local worker_count=0
    local total_files_added=0
    local total_lines_added=0

    for worker_dir in "$run_dir"/worker-*; do
        [ -d "$worker_dir" ] || continue
        
        worker_name=$(basename "$worker_dir")
        repo_dir="${worker_dir}/repo"
        
        if [ ! -d "$repo_dir" ]; then
            continue
        fi
        
        if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
            continue
        fi

        local branch_name
        branch_name=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
        
        local swarm_commit_count=0
        local base_commit=""
        local head_ref=""
        
        if [ "$branch_name" != "HEAD" ] && git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
            base_commit=$(git -C "$repo_dir" merge-base main "$branch_name" 2>/dev/null)
            swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..${branch_name}" 2>/dev/null | wc -l)
            head_ref="$branch_name"
        else
            local expected_branch="swarm/${run_id}/${worker_name}"
            if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$expected_branch" 2>/dev/null; then
                head_ref="$expected_branch"
                base_commit=$(git -C "$repo_dir" merge-base main "$head_ref" 2>/dev/null)
                swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..${head_ref}" 2>/dev/null | wc -l)
            else
                head_ref=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)
                if [ -n "$head_ref" ]; then
                    base_commit=$(git -C "$repo_dir" merge-base main HEAD 2>/dev/null)
                    swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..HEAD" 2>/dev/null | wc -l)
                fi
            fi
        fi
        
        if [ -z "$base_commit" ] || [ "$swarm_commit_count" -eq 0 ]; then
            continue
        fi

        worker_count=$((worker_count + 1))

        echo "Extracting changes from $worker_name ($swarm_commit_count commits)..."
        
        local changed_files
        changed_files=$(git -C "$repo_dir" diff --name-only "${base_commit}..${head_ref}" 2>/dev/null)
        
        if [ -n "$changed_files" ]; then
            while IFS= read -r file; do
                if [ -n "$file" ]; then
                    local src_file="${repo_dir}/${file}"
                    local dst_file="${merged_repo_dir}/${file}"
                    
                    mkdir -p "$(dirname "$dst_file")" 2>/dev/null || true
                    
                    if [ -f "$src_file" ]; then
                        cp "$src_file" "$dst_file" 2>/dev/null || true
                    fi
                fi
            done <<< "$changed_files"
        fi
        
        files_added=$(git -C "$repo_dir" diff --stat "${base_commit}..${head_ref}" 2>/dev/null | grep "files changed" | awk '{print $1}' || echo "0")
        lines_added=$(git -C "$repo_dir" diff --stat "${base_commit}..${head_ref}" 2>/dev/null | grep "insertion" | sed 's/[^0-9]//g' || echo "0")
        
        total_files_added=$((total_files_added + files_added))
        total_lines_added=$((total_lines_added + lines_added))
    done

    echo "Merged $worker_count worker repositories into: $merged_repo_dir"
    echo "Total files added/modified: $total_files_added"
    echo "Total lines added: $total_lines_added"
    echo

    if [ "$worker_count" -gt 0 ]; then
        cd "$merged_repo_dir" 2>/dev/null || true
        git add . 2>/dev/null || true
        git commit -m "Merge all worker changes" 2>/dev/null || true
        cd - > /dev/null || true
    fi

    local summary_file="$dest_dir/SWARM_SUMMARY.md"
    {
        echo "# Swarm Run Summary: $run_id"
        echo
        echo "## Run Status"
        echo "- **Status**: $run_status"
        echo "- **Total Tasks**: $total_tasks"
        echo "- **Completed**: $completed_tasks"
        echo "- **Failed**: $failed_tasks"
        echo "- **Pending**: $pending_tasks"
        echo

        if [ "$completed_tasks" -gt 0 ]; then
            echo "## Completed Tasks"
            echo
            sqlite3 "$db_path" <<EOF 2>/dev/null
.mode column
.headers on
.width 60 8 12
SELECT 
    substr(task_text, 1, 60) as task,
    priority,
    datetime(completed_at) as completed
FROM tasks
WHERE run_id = '$run_id' AND status = 'completed'
ORDER BY completed_at;
EOF
            echo
        fi

        if [ "$failed_tasks" -gt 0 ]; then
            echo "## Failed Tasks"
            echo
            sqlite3 "$db_path" <<EOF 2>/dev/null
.mode column
.headers on
.width 60 8 12 40
SELECT 
    substr(task_text, 1, 60) as task,
    priority,
    datetime(completed_at) as completed,
    error_message
FROM tasks
WHERE run_id = '$run_id' AND status = 'failed'
ORDER BY completed_at;
EOF
            echo
        fi

        if [ "$pending_tasks" -gt 0 ]; then
            echo "## Pending Tasks (Not Completed)"
            echo
            sqlite3 "$db_path" <<EOF 2>/dev/null
.mode column
.headers on
.width 60 8 8
SELECT 
    substr(task_text, 1, 60) as task,
    priority,
    status
FROM tasks
WHERE run_id = '$run_id' AND status IN ('pending', 'in_progress')
ORDER BY priority ASC, id ASC;
EOF
            echo
        fi

        echo "## Artifacts"
        echo "- **Merged Repository**: \`merged-repo/\`"
        echo "- **Worker Count**: $worker_count"
        echo
        echo "## Git Commits by Worker"
        echo

        for worker_dir in "$run_dir"/worker-*; do
            [ -d "$worker_dir" ] || continue
            
            worker_name=$(basename "$worker_dir")
            repo_dir="${worker_dir}/repo"
            
            if [ -d "$repo_dir" ] && git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
                branch_name=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                
                local target_branch="$branch_name"
                if [ "$branch_name" = "HEAD" ]; then
                    local expected_branch="swarm/${run_id}/${worker_name}"
                    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$expected_branch" 2>/dev/null; then
                        target_branch="$expected_branch"
                    fi
                fi
                
                if [ "$target_branch" != "HEAD" ] && git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
                    base_commit=$(git -C "$repo_dir" merge-base main "$target_branch" 2>/dev/null)
                    swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..${target_branch}" 2>/dev/null | wc -l)
                    
                    if [ "$swarm_commit_count" -gt 0 ]; then
                        echo "### $worker_name ($swarm_commit_count commits)"
                        echo
                        git -C "$repo_dir" log --name-status --oneline "${base_commit}..${target_branch}" 2>/dev/null || true
                        echo
                    fi
                fi
            fi
        done

        echo "## Changed Files in Merged Repository"
        echo
        if [ -d "$merged_repo_dir" ]; then
            echo "\`\`\`"
            find "$merged_repo_dir" -type f -not -path "*/\.git/*" 2>/dev/null | sort | head -50
            echo "\`\`\`"
        fi
    } > "$summary_file"

    echo "Summary report created: $summary_file"

    if [ -d "$merged_repo_dir" ] && [ "$(find "$merged_repo_dir" -maxdepth 1 -mindepth 1 -not -path "*/\.git/*" | wc -l)" -gt 0 ]; then
        echo
        echo "=== Merged Repository Contents ==="
        find "$merged_repo_dir" -type f -not -path "*/\.git/*" -not -path "*/__pycache__/*" 2>/dev/null | head -30
        echo
        echo "To explore merged artifacts:"
        echo "  cd $merged_repo_dir"
    else
        echo
        echo "Warning: No artifacts found - workers may not have made any commits"
    fi

    echo
    echo "Artifacts extracted to: $dest_dir"
    echo "Summary: $summary_file"
}

export -f swarm_extract_merged_artifacts 2>/dev/null || true

swarm_list_runs() {
    local db_path="$RALPH_DIR/swarm.db"
    if [ ! -f "$db_path" ]; then
        echo "swarm_list_runs: database not found: $db_path" 1>&2
        return 1
    fi

    echo "=== Swarm Runs ==="
    echo
    sqlite3 "$db_path" <<EOF 2>/dev/null
.mode column
.headers on
.width 18 10 8 8 8 19 19
SELECT 
    run_id,
    status,
    total_tasks,
    completed_tasks,
    failed_tasks,
    datetime(started_at) as started,
    datetime(completed_at) as completed
FROM swarm_runs
ORDER BY id DESC
LIMIT 20;
EOF
    echo
}

export -f swarm_list_runs 2>/dev/null || true


