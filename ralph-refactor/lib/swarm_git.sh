#!/usr/bin/env bash

swarm_git_default_base_branch() {
    if [ -n "${SWARM_BASE_BRANCH:-}" ]; then
        printf '%s' "$SWARM_BASE_BRANCH"
        return 0
    fi

    # Prefer the remote default branch when available (origin/HEAD -> origin/main).
    local remote_head
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
        printf '%s' "${remote_head#origin/}"
        return 0
    fi

    # Fall back to the current branch if it exists locally; otherwise prefer 'main'.
    local current
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [ -n "$current" ] && [ "$current" != "HEAD" ]; then
        # Ensure the current branch exists in refs/heads (sometimes HEAD points to a ref that isn't present)
        if git show-ref --verify --quiet "refs/heads/$current" 2>/dev/null; then
            printf '%s' "$current"
            return 0
        fi
    fi

    # Last-resort default: prefer 'main' which is common in new repos
    printf '%s' "main"
}


# Ensure local default branch exists and normalize master -> main when safe.
# This performs a local rename only; it will not push or change remotes.
# If SWARM_BASE_BRANCH is set, that value takes precedence.
swarm_git_normalize_default_branch() {
    local desired
    desired=$(swarm_git_default_base_branch)

    # If env override present, honor it
    if [ -n "${SWARM_BASE_BRANCH:-}" ]; then
        desired="$SWARM_BASE_BRANCH"
    fi

    # If desired branch exists locally, prefer it.
    if git show-ref --verify --quiet "refs/heads/$desired"; then
        echo "Using existing base branch: $desired"
        return 0
    fi

    # If desired doesn't exist but master exists and desired is 'main', rename master -> main locally.
    if [ "$desired" = "main" ] && git show-ref --verify --quiet "refs/heads/master"; then
        echo "Normalizing default branch: renaming local 'master' -> 'main'"
        git branch -m master main || {
            echo "Warning: failed to rename master -> main"
            return 1
        }
        return 0
    fi

    # If desired missing and master missing, fall back to current branch
    local current
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    echo "Falling back to current branch: ${current:-master}"
    return 0
}

swarm_git_create_worker_branch() {
    local run_id="$1"
    local worker_num="$2"
    local base_branch="${3:-}"

    if [ -z "$base_branch" ]; then
        base_branch=$(swarm_git_default_base_branch)
    fi

    local branch_name="swarm/${run_id}/worker-${worker_num}"

    git fetch origin "$base_branch" 2>/dev/null || true

    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        git checkout -b "$branch_name" "origin/$base_branch" 2>/dev/null || \
            git checkout -b "$branch_name"
        echo "Created new branch: $branch_name"
    else
        git checkout "$branch_name"
        git pull origin "$branch_name" 2>/dev/null || true
        echo "Checked out existing branch: $branch_name"
    fi

    echo "$branch_name"
}

swarm_git_switch_to_branch() {
    local branch_name="$1"

    git checkout "$branch_name" 2>/dev/null || {
        echo "Error: Cannot checkout branch $branch_name"
        return 1
    }

    echo "Switched to branch: $branch_name"
}

swarm_git_commit_work() {
    local message="$1"
    local files=("$@")

    shift

    git add "${files[@]}" 2>/dev/null || true

    if git diff --cached --quiet; then
        echo "No changes to commit"
        return 1
    fi

    git commit -m "$(echo "$message" | sed 's/'\''//g')" || {
        echo "Error committing changes"
        return 1
    }

    echo "Changes committed successfully"
}

swarm_git_merge_worker_branches() {
    local run_id="$1"
    local push_after_merge="${SWARM_PUSH_AFTER_MERGE:-false}"

    echo "Merging worker branches for run $run_id..."

    local main_branch
    main_branch=$(swarm_git_default_base_branch)
    local worker_branches

    worker_branches=$(git branch | grep "swarm/${run_id}/worker-" || true)

    if [ -z "$worker_branches" ]; then
        echo "No worker branches found for run $run_id"
        return 0
    fi

    git checkout "$main_branch" || {
        echo "Error: Cannot checkout $main_branch"
        return 1
    }

    local branch_list
    branch_list=$(echo "$worker_branches" | sed 's/.* //' | tr '\n' ' ')

    if [ -z "$branch_list" ]; then
        echo "No worker branches to merge"
        return 0
    fi

    echo "Merging branches: $branch_list"

    for branch in $branch_list; do
        echo "Merging $branch into $main_branch..."
        if git merge --no-edit "$branch" 2>/dev/null; then
            echo "Successfully merged $branch"
        else
            echo "Merge conflict in $branch - handling conflicts..."
            swarm_git_handle_conflicts "$branch"
        fi
    done

    if [ "$push_after_merge" = "true" ]; then
        git push origin "$main_branch" || {
            echo "Error pushing to origin/$main_branch"
            return 1
        }
        echo "All worker branches merged and pushed successfully"
    else
        echo "All worker branches merged locally (push disabled; set SWARM_PUSH_AFTER_MERGE=true to push)"
    fi
}

swarm_git_cleanup_branches() {
    local run_id="$1"
    local keep_main="${2:-false}"

    local worker_branches
    worker_branches=$(git branch | grep "swarm/${run_id}/worker-" || true)

    if [ -z "$worker_branches" ]; then
        echo "No worker branches found for run $run_id"
        return 0
    fi

    echo "Cleaning up worker branches for run $run_id..."

    for branch in $worker_branches; do
        local branch_name
        branch_name=$(echo "$branch" | sed 's/.* //')

        if [ "$keep_main" = "true" ]; then
            git branch -d "$branch_name" || echo "Cannot delete $branch_name (merged)"
        else
            git branch -D "$branch_name" || echo "Cannot force delete $branch_name"
        fi
    done

    echo "Worker branches cleaned up"
}

swarm_git_handle_conflicts() {
    local branch_name="$1"

    echo "Detecting merge conflicts for $branch_name..."

    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U || true)

    if [ -z "$conflicts" ]; then
        echo "No merge conflicts found"
        return 0
    fi

    echo "Merge conflicts detected in:"
    echo "$conflicts" | sed 's/^/  - /'

    echo ""
    echo "Attempting to resolve conflicts automatically..."

    for file in $conflicts; do
        if [ -f "$file" ]; then
            echo "  Attempting to auto-resolve: $file"

            if [ "$file" = "devplan.md" ]; then
                cat "$file" | grep -E "^## Task" -A 10 | head -n -1 > "$file.tmp" || true
                mv "$file.tmp" "$file" 2>/dev/null || true
            else
                git checkout --ours "$file" 2>/dev/null || true
                git add "$file" 2>/dev/null || true
            fi
        fi
    done

    git add "${conflicts[@]}" 2>/dev/null || true

    if git commit --no-edit 2>/dev/null; then
        echo "Conflicts resolved and committed"
    else
        echo "Warning: Could not auto-resolve all conflicts"
    fi
}

swarm_git_get_modified_files() {
    local branch_name="$1"

    git diff --name-only "$branch_name" origin/main 2>/dev/null || \
        git diff --name-only "$branch_name"
}

swarm_git_get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

swarm_git_reset_branch() {
    local branch_name="$1"
    local target="${2:-origin/main}"

    echo "Resetting branch $branch_name to $target..."

    git checkout "$branch_name" || {
        echo "Error: Cannot checkout $branch_name"
        return 1
    }

    git reset --hard "$target" 2>/dev/null || {
        echo "Error: Cannot reset to $target"
        return 1
    }

    git push -f origin "$branch_name" 2>/dev/null || {
        echo "Warning: Cannot push to origin/$branch_name"
    }

    echo "Branch $branch_name reset to $target"
}
