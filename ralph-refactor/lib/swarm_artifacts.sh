#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/swarm_git.sh"

# Merge all worker branches for a run into the project repo's main branch
swarm_merge_to_project() {
    local run_id="$1"
    
    if [ -z "$run_id" ]; then
        echo "swarm_merge_to_project: run_id required" 1>&2
        return 1
    fi

    local run_dir="$RALPH_DIR/swarm/runs/$run_id"
    if [ ! -d "$run_dir" ]; then
        echo "swarm_merge_to_project: run directory not found: $run_dir" 1>&2
        return 1
    fi

    echo "Merging swarm changes to project repository for run: $run_id"
    echo

    local worker_dir
    worker_dir=$(find "$run_dir" -type d -name "worker-*" | head -1)
    if [ ! -d "$worker_dir/repo" ]; then
        echo "Error: No worker repos found" 1>&2
        return 1
    fi

    local repo_dir="$worker_dir/repo"
    if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: Worker repo is not a git repository" 1>&2
        return 1
    fi

    local db_path="$RALPH_DIR/swarm.db"
    local source_path
    source_path=$(sqlite3 "$db_path" "SELECT source_path FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null || true)

    local project_dir
    if [ -n "$source_path" ] && [[ "$source_path" == */projects/* ]]; then
        local project_name
        project_name=$(dirname "$source_path" | xargs basename)
        local projects_base="${SWARM_PROJECTS_BASE:-$HOME/projects}"
        project_dir="$projects_base/$project_name"
        
        if [ ! -d "$project_dir" ]; then
            echo "Error: Project directory not found: $project_dir" 1>&2
            return 1
        fi
    else
        project_dir=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$project_dir" ]; then
            echo "Error: Could not find project repository" 1>&2
            return 1
        fi
    fi

    echo "Project repository: $project_dir"
    echo

    if [ ! -d "$project_dir/.git" ]; then
        echo "Initializing git repository in project: $project_dir"
        git -C "$project_dir" init >/dev/null
        git -C "$project_dir" config user.name "Swarm" >/dev/null
        git -C "$project_dir" config user.email "swarm@local" >/dev/null
        git -C "$project_dir" checkout -b main 2>/dev/null || true
        git -C "$project_dir" add . >/dev/null 2>&1 || true
        git -C "$project_dir" commit -m "Initial commit by swarm" >/dev/null 2>&1 || true
    fi


    local base_branch
    base_branch=$(swarm_git_default_base_branch 2>/dev/null || echo "main")
    local merge_branch="swarm-merge-${run_id}"

    cd "$project_dir" || return 1

    if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$base_branch"; then
        echo "Error: Base branch '$base_branch' not found in project" 1>&2
        return 1
    fi

    git checkout "$base_branch" 2>/dev/null || {
        echo "Error: Could not checkout $base_branch" 1>&2
        return 1
    }

    git pull origin "$base_branch" 2>/dev/null || true

    echo "Merging worker branches into $base_branch..."
    echo

    local merged_count=0
    local total_files_changed=0
    local total_lines_added=0

    for worker_path in "$run_dir"/worker-*; do
        [ -d "$worker_path" ] || continue
        
        local worker_name
        worker_name=$(basename "$worker_path")
        local worker_repo="$worker_path/repo"
        
        if [ ! -d "$worker_repo" ]; then
            continue
        fi

        if ! git -C "$worker_repo" rev-parse --git-dir >/dev/null 2>&1; then
            continue
        fi

        local branch_name
        branch_name=$(git -C "$worker_repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
        
        local target_branch="$branch_name"
        if [ "$branch_name" = "HEAD" ]; then
            local expected_branch="swarm/${run_id}/${worker_name}"
            if git -C "$worker_repo" show-ref --verify --quiet "refs/heads/$expected_branch" 2>/dev/null; then
                target_branch="$expected_branch"
            else
                target_branch=$(git -C "$worker_repo" rev-parse HEAD 2>/dev/null)
            fi
        fi

        if [ "$target_branch" = "HEAD" ] || [ "$target_branch" = "$base_branch" ]; then
            continue
        fi

        # Check if branch exists in project repo - if not, use file-based merge
        local use_file_merge=false
        if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
            use_file_merge=true
        fi

        local base_commit
        base_commit=$(git -C "$worker_repo" merge-base "$base_branch" "$target_branch" 2>/dev/null || git -C "$worker_repo" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
        
        local swarm_commit_count
        if [ -n "$base_commit" ]; then
            swarm_commit_count=$(git -C "$worker_repo" log --oneline "${base_commit}..${target_branch}" 2>/dev/null | wc -l)
        else
            swarm_commit_count=$(git -C "$worker_repo" rev-list --count HEAD 2>/dev/null || echo "0")
        fi
        
        if [ "$swarm_commit_count" -eq 0 ]; then
            echo "Skipping $worker_name (no commits to merge)"
            continue
        fi

        echo "Merging $worker_name ($swarm_commit_count commits)..."
        
        if [ "$use_file_merge" = true ]; then
            # Use file-based merge: copy changed files from worker repo to project
            echo "  Using file-based merge (branch not in project repo)..."
            
            local changed_files
            if [ -n "$base_commit" ]; then
                changed_files=$(git -C "$worker_repo" diff --name-only "${base_commit}..${target_branch}" 2>/dev/null)
            else
                changed_files=$(git -C "$worker_repo" ls-files 2>/dev/null)
            fi
            
            local files_copied=0
            if [ -n "$changed_files" ]; then
                while IFS= read -r file; do
                    if [ -n "$file" ]; then
                        # Skip ralphussy-specific files
                        case "$file" in
                            ralph-refactor/*|ralph-tui/*|swarm-dashboard/*|opencode-ralph*/*|.git/*|*.db)
                                continue
                                ;;
                        esac
                        
                        local src_file="${worker_repo}/${file}"
                        local dst_file="${project_dir}/${file}"
                        
                        if [ -f "$src_file" ]; then
                            mkdir -p "$(dirname "$dst_file")" 2>/dev/null || true
                            cp "$src_file" "$dst_file" 2>/dev/null || true
                            files_copied=$((files_copied + 1))
                        fi
                    fi
                done <<< "$changed_files"
            fi
            
            if [ "$files_copied" -gt 0 ]; then
                merged_count=$((merged_count + 1))
                total_files_changed=$((total_files_changed + files_copied))
                echo "  ✓ Copied $files_copied files from $worker_name"
            fi
        elif git merge --no-edit "$target_branch" 2>/dev/null; then
            merged_count=$((merged_count + 1))
            
            local files_changed
            files_changed=$(git diff --stat "$base_commit..$target_branch" 2>/dev/null | grep "files changed" | awk '{print $1}' || echo "0")
            total_files_changed=$((total_files_changed + files_changed))
            
            echo "  ✓ Merged successfully, deleting branch $target_branch"
            git branch -D "$target_branch" 2>/dev/null || true
        else
            echo "  ✗ Git merge conflict, falling back to file-based merge..."
            git merge --abort 2>/dev/null || true
            
            # Fall back to file-based merge
            local changed_files
            if [ -n "$base_commit" ]; then
                changed_files=$(git -C "$worker_repo" diff --name-only "${base_commit}..${target_branch}" 2>/dev/null)
            else
                changed_files=$(git -C "$worker_repo" ls-files 2>/dev/null)
            fi
            
            local files_copied=0
            if [ -n "$changed_files" ]; then
                while IFS= read -r file; do
                    if [ -n "$file" ]; then
                        case "$file" in
                            ralph-refactor/*|ralph-tui/*|swarm-dashboard/*|opencode-ralph*/*|.git/*|*.db)
                                continue
                                ;;
                        esac
                        
                        local src_file="${worker_repo}/${file}"
                        local dst_file="${project_dir}/${file}"
                        
                        if [ -f "$src_file" ]; then
                            mkdir -p "$(dirname "$dst_file")" 2>/dev/null || true
                            cp "$src_file" "$dst_file" 2>/dev/null || true
                            files_copied=$((files_copied + 1))
                        fi
                    fi
                done <<< "$changed_files"
            fi
            
            if [ "$files_copied" -gt 0 ]; then
                merged_count=$((merged_count + 1))
                total_files_changed=$((total_files_changed + files_copied))
                echo "  ✓ Copied $files_copied files from $worker_name (file-based fallback)"
            fi
        fi
    done
    
    # Commit merged changes if any
    if [ "$merged_count" -gt 0 ]; then
        git add . 2>/dev/null || true
        git commit -m "Merge swarm run $run_id: $merged_count workers, $total_files_changed files" 2>/dev/null || true
    fi

    echo
    echo "Merge complete:"
    echo "  - Merged $merged_count worker branches"
    echo "  - Total files changed: $total_files_changed"
    echo
    echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Latest commit: $(git log --oneline -1)"
    echo

    local has_remote
    has_remote=$(git remote 2>/dev/null | head -1 || true)
    if [ -n "$has_remote" ]; then
        echo "Pushing to remote origin..."
        if git push origin "$base_branch" 2>/dev/null; then
            echo "  ✓ Pushed successfully"
        else
            echo "  ✗ Push failed (may need to resolve conflicts or use --force)"
        fi
        echo
    fi

    local remaining_swarm_branches
    remaining_swarm_branches=$(git branch -a 2>/dev/null | grep -c "swarm/" || echo "0")
    echo "Remaining swarm branches: $remaining_swarm_branches"
    echo

    cd - > /dev/null || true
}

export -f swarm_merge_to_project 2>/dev/null || true

# Clean up all swarm branches in current project
swarm_cleanup_branches() {
    echo "Cleaning up swarm branches in current project..."
    echo

    local count=0
    local local_branches
    local_branches=$(git branch 2>/dev/null | grep "swarm/" | sed 's/^[ *]//' || true)

    if [ -n "$local_branches" ]; then
        echo "Deleting local swarm branches:"
        while IFS= read -r branch; do
            if [ -n "$branch" ]; then
                echo "  - Deleting $branch"
                git branch -D "$branch" 2>/dev/null || true
                count=$((count + 1))
            fi
        done <<< "$local_branches"
    fi

    local remote_branches
    remote_branches=$(git branch -r 2>/dev/null | grep "origin/swarm/" | sed 's|origin/||' || true)

    if [ -n "$remote_branches" ]; then
        echo "Deleting remote swarm branches:"
        while IFS= read -r branch; do
            if [ -n "$branch" ]; then
                echo "  - Deleting $branch from origin"
                git push origin --delete "$branch" 2>/dev/null || true
                count=$((count + 1))
            fi
        done <<< "$remote_branches"
    fi

    echo
    echo "Cleanup complete. Removed $count swarm branches."
    echo
}

export -f swarm_cleanup_branches 2>/dev/null || true

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

    local db_path="$RALPH_DIR/swarm.db"
    if [ ! -f "$db_path" ]; then
        echo "swarm_extract_merged_artifacts: database not found: $db_path" 1>&2
        return 1
    fi

    # Try to determine the actual project directory from the run
    local source_path
    source_path=$(sqlite3 "$db_path" "SELECT source_path FROM swarm_runs WHERE run_id = '$run_id';" 2>/dev/null || true)
    
    local project_dir=""
    local project_name=""
    
    # Check if source_path points to a project
    if [ -n "$source_path" ]; then
        # Try to find project from devplan path (e.g., /home/user/projects/myproject/devplan.md)
        local potential_project_dir
        potential_project_dir=$(dirname "$source_path" 2>/dev/null || true)
        
        if [ -d "$potential_project_dir" ]; then
            project_dir="$potential_project_dir"
            project_name=$(basename "$project_dir")
        fi
    fi
    
    # Fallback: check if any worker repo exists and get its toplevel
    if [ -z "$project_dir" ]; then
        local first_worker_repo
        first_worker_repo=$(find "$run_dir" -type d -name "repo" | head -1)
        if [ -n "$first_worker_repo" ] && [ -d "$first_worker_repo" ]; then
            project_dir=$(git -C "$first_worker_repo" rev-parse --show-toplevel 2>/dev/null || true)
            if [ -n "$project_dir" ]; then
                project_name=$(basename "$project_dir")
            fi
        fi
    fi
    
    # Final fallback: create swarm-$run_id directory
    if [ -z "$project_dir" ]; then
        project_name="swarm-$run_id"
        project_dir="$dest_base/$project_name"
    fi
    
    echo "Extracting merged artifacts for run: $run_id"
    echo "Project directory: $project_dir"
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

    # Use project_dir directly instead of creating a separate merged-repo
    mkdir -p "$project_dir"
    
    if [ ! -d "$project_dir/.git" ]; then
        cd "$project_dir" || exit 1
        git init 2>/dev/null || true
        git config user.name "Swarm" 2>/dev/null || true
        git config user.email "swarm@local" 2>/dev/null || true
        cd - > /dev/null || true
    fi

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
        local base_branch
        base_branch=$(swarm_git_default_base_branch 2>/dev/null || echo "main")
        
        if [ "$branch_name" != "HEAD" ] && git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
            base_commit=$(git -C "$repo_dir" merge-base "$base_branch" "$branch_name" 2>/dev/null || git -C "$repo_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
            swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..${branch_name}" 2>/dev/null | wc -l)
            head_ref="$branch_name"
        else
            local expected_branch="swarm/${run_id}/${worker_name}"
            if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$expected_branch" 2>/dev/null; then
                head_ref="$expected_branch"
                base_commit=$(git -C "$repo_dir" merge-base "$base_branch" "$head_ref" 2>/dev/null || git -C "$repo_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
                swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..${head_ref}" 2>/dev/null | wc -l)
            else
                head_ref=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)
                if [ -n "$head_ref" ]; then
                    # Get the initial commit as base
                    base_commit=$(git -C "$repo_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
                    swarm_commit_count=$(git -C "$repo_dir" log --oneline "${base_commit}..HEAD" 2>/dev/null | wc -l)
                fi
            fi
        fi
        
        # If no base_commit found but we have commits, extract all non-.git files
        if [ -z "$base_commit" ]; then
            local commit_count
            commit_count=$(git -C "$repo_dir" rev-list --count HEAD 2>/dev/null || echo "0")
            if [ "$commit_count" -gt 0 ]; then
                swarm_commit_count="$commit_count"
                base_commit=""
            fi
        fi

        if [ "$swarm_commit_count" -eq 0 ]; then
            continue
        fi

        worker_count=$((worker_count + 1))

        echo "Extracting changes from $worker_name ($swarm_commit_count commits)..."
        
        # Get changed files - if no base_commit, get all tracked files
        local changed_files
        if [ -n "$base_commit" ]; then
            changed_files=$(git -C "$repo_dir" diff --name-only "${base_commit}..${head_ref}" 2>/dev/null)
        else
            changed_files=$(git -C "$repo_dir" ls-files 2>/dev/null)
        fi
        
        if [ -n "$changed_files" ]; then
            while IFS= read -r file; do
                if [ -n "$file" ]; then
                    # Skip ONLY if file is in .gitignore or is clearly internal
                    local should_skip=false
                    
                    # Check if file path starts with known internal directories AT ROOT LEVEL
                    case "$file" in
                        ralph-refactor/*|ralph-tui/*|swarm-dashboard/*|.git/*|*.db)
                            # Only skip if this is a ROOT-level internal directory
                            if [ ! -f "$repo_dir/.ralph_project_marker" ]; then
                                # This is ralphussy itself, skip these
                                should_skip=true
                            fi
                            ;;
                        opencode-ralph/*|opencode-ralph-slash/*)
                            # Only skip opencode-ralph if it's the main repo's copy
                            # Allow project-specific opencode plugins
                            local file_path="$repo_dir/$file"
                            if [ -L "$file_path" ] || grep -q "opencode-ralph" "$repo_dir/.gitmodules" 2>/dev/null; then
                                # It's a symlink or submodule to internal tooling
                                should_skip=true
                            fi
                            ;;
                    esac
                    
                    if [ "$should_skip" = true ]; then
                        echo "  Skipping internal file: $file"
                        continue
                    fi
                    
                    local src_file="${repo_dir}/${file}"
                    local dst_file="${project_dir}/${file}"
                    
                    mkdir -p "$(dirname "$dst_file")" 2>/dev/null || true
                    
                    if [ -f "$src_file" ]; then
                        # Check for conflicts: if file exists and differs, warn
                        if [ -f "$dst_file" ]; then
                            if ! cmp -s "$src_file" "$dst_file"; then
                                echo "  ⚠️  CONFLICT: $file modified by multiple workers, using latest version"
                                # TODO: Implement 3-way merge here
                            fi
                        fi
                        
                        cp "$src_file" "$dst_file" 2>/dev/null || true
                    fi
                fi
            done <<< "$changed_files"
        fi
        
        if [ -n "$base_commit" ]; then
            files_added=$(git -C "$repo_dir" diff --stat "${base_commit}..${head_ref}" 2>/dev/null | grep "files changed" | awk '{print $1}' || echo "0")
            lines_added=$(git -C "$repo_dir" diff --stat "${base_commit}..${head_ref}" 2>/dev/null | grep "insertion" | sed 's/[^0-9]//g' || echo "0")
        else
            files_added=$(echo "$changed_files" | wc -l || echo "0")
            lines_added=0
        fi
        
        total_files_added=$((total_files_added + files_added))
        total_lines_added=$((total_lines_added + lines_added))
    done

    echo ""
    echo "=== Merge Summary ==="
    echo "Workers processed: $worker_count"
    echo "Total files added/modified: $total_files_added"
    echo "Total lines added: $total_lines_added"
    echo

    if [ "$worker_count" -gt 0 ]; then
        cd "$project_dir" 2>/dev/null || true
        git add . 2>/dev/null || true
        git commit -m "Merge swarm run $run_id ($worker_count workers, $total_files_added files)" 2>/dev/null || true
        cd - > /dev/null || true
        echo "Changes committed to: $project_dir"
    else
        echo "Warning: No worker changes found to merge"
    fi

    # Summary file goes in the project directory
    local summary_file="$project_dir/SWARM_SUMMARY.md"
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
        echo "- **Project Directory**: \`$project_dir\`"
        echo "- **Workers Processed**: $worker_count"
        echo
        echo "## Git Commits by Worker"
        echo

        for worker_dir in "$run_dir"/worker-*; do
            [ -d "$worker_dir" ] || continue
            
            worker_name=$(basename "$worker_dir")
            repo_dir="${worker_dir}/repo"
            
            if [ -d "$repo_dir" ] && git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
                branch_name=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                
                local base_branch
                base_branch=$(swarm_git_default_base_branch 2>/dev/null || echo "main")
                
                local target_branch="$branch_name"
                if [ "$branch_name" = "HEAD" ]; then
                    local expected_branch="swarm/${run_id}/${worker_name}"
                    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$expected_branch" 2>/dev/null; then
                        target_branch="$expected_branch"
                    fi
                fi
                
                if [ "$target_branch" != "HEAD" ] && git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
                    base_commit=$(git -C "$repo_dir" merge-base "$base_branch" "$target_branch" 2>/dev/null)
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

        echo "## Changed Files in Project"
        echo
        if [ -d "$project_dir" ]; then
            echo "\`\`\`"
            find "$project_dir" -type f -not -path "*/\.git/*" 2>/dev/null | sort | head -50
            echo "\`\`\`"
        fi
    } > "$summary_file"

    echo "Summary report created: $summary_file"

    if [ -d "$project_dir" ] && [ "$(find "$project_dir" -maxdepth 1 -mindepth 1 -not -path "*/\.git/*" | wc -l)" -gt 0 ]; then
        echo
        echo "=== Project Contents ==="
        find "$project_dir" -type f -not -path "*/\.git/*" -not -path "*/__pycache__/*" 2>/dev/null | head -30
        echo
        echo "To explore project:"
        echo "  cd $project_dir"
    else
        echo
        echo "Warning: No artifacts found - workers may not have made any commits"
    fi

    # Verify all completed tasks have their changes in the merged project
    swarm_verify_merge_completeness "$run_id" "$project_dir" || {
        echo "⚠️  WARNING: Some completed task files are missing from merged project"
        echo "This may indicate a merge issue or files were filtered incorrectly"
    }

    echo
    echo "Artifacts extracted to: $project_dir"
    echo "Summary: $summary_file"
}

# Verify all completed tasks have their changes in the merged project
swarm_verify_merge_completeness() {
    local run_id="$1"
    local project_dir="$2"
    local db_path="$RALPH_DIR/swarm.db"
    
    echo "Verifying merge completeness..."
    
    local completed_tasks
    completed_tasks=$(sqlite3 "$db_path" "SELECT id, task_text, actual_files FROM tasks WHERE run_id = '$run_id' AND status = 'completed';" 2>/dev/null || true)
    
    local missing_count=0
    
    while IFS='|' read -r task_id task_text actual_files; do
        if [ -z "$actual_files" ] || [ "$actual_files" = "null" ] || [ "$actual_files" = "[]" ]; then
            continue
        fi
        
        # Check if files from this task exist in project
        echo "$actual_files" | jq -r '.[]' 2>/dev/null | while read -r file; do
            if [ -n "$file" ] && [ ! -f "$project_dir/$file" ]; then
                echo "  ⚠️  Task $task_id file missing: $file"
                missing_count=$((missing_count + 1))
            fi
        done
    done <<< "$completed_tasks"
    
    if [ $missing_count -gt 0 ]; then
        echo "  WARNING: $missing_count files from completed tasks are missing!"
        return 1
    else
        echo "  ✓ All completed task files present in project"
        return 0
    fi
}

export -f swarm_extract_merged_artifacts 2>/dev/null || true
export -f swarm_verify_merge_completeness 2>/dev/null || true

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


