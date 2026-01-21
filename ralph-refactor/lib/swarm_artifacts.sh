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

export -f swarm_collect_artifacts 2>/dev/null || true
