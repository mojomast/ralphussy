#!/bin/bash
# Swarm Dashboard2 Launcher

# Add bun to PATH if not already available
if ! command -v bun &> /dev/null; then
    export PATH="$HOME/.bun/bin:$PATH"
fi

# Check if bun is available
if ! command -v bun &> /dev/null; then
    echo "Error: Bun is not installed"
    echo "Install it with: curl -fsSL https://bun.sh/install | bash"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Development behavior: prefer running source files so local edits in src/
# are reflected immediately. To force running the built bundle set env
# variable RUN_DIST=1 or build a dist bundle for swarm-dashboard2.
USE_SRC="true"
if [ -n "${RUN_DIST:-}" ]; then
    USE_SRC="false"
fi

# Locate swarm DB. Prefer explicit RALPH_DIR, then look upward from the current
# directory. Reuses the same heuristics as the original dashboard launcher.
RALPH_DIR_FOUND=""
if [ -n "${RALPH_DIR:-}" ] && [ -f "${RALPH_DIR%/}/swarm.db" ]; then
    RALPH_DIR_FOUND="${RALPH_DIR%/}"
else
    candidates=()
    SEARCH_DIR="$SCRIPT_DIR"
    while [ "$SEARCH_DIR" != "/" ] && [ -n "$SEARCH_DIR" ]; do
        if [ -f "$SEARCH_DIR/.ralph/swarm.db" ]; then
            candidates+=("$SEARCH_DIR/.ralph")
            break
        fi
        SEARCH_DIR=$(dirname "$SEARCH_DIR")
    done

    if [ -f "$HOME/projects/.ralph/swarm.db" ]; then
        candidates+=("$HOME/projects/.ralph")
    fi
    if [ -f "$HOME/.ralph/swarm.db" ]; then
        candidates+=("$HOME/.ralph")
    fi

    if [ ${#candidates[@]} -eq 0 ]; then
        RALPH_DIR_FOUND=""
    elif [ ${#candidates[@]} -eq 1 ]; then
        RALPH_DIR_FOUND="${candidates[0]}"
    else
        best=""
        best_score=-1
        for cand in "${candidates[@]}"; do
            dbfile="$cand/swarm.db"
            if [ ! -f "$dbfile" ]; then
                continue
            fi
            hb_epoch=0
            hb_epoch=$(sqlite3 "$dbfile" "SELECT MAX(strftime('%s', last_heartbeat)) FROM workers;" 2>/dev/null || echo 0)
            hb_epoch=${hb_epoch%%\n}
            hb_epoch=${hb_epoch:-0}

            inprog=0
            inprog=$(sqlite3 "$dbfile" "SELECT COUNT(*) FROM tasks WHERE status = 'in_progress';" 2>/dev/null || echo 0)
            inprog=${inprog%%\n}
            inprog=${inprog:-0}

            started_epoch=0
            started_epoch=$(sqlite3 "$dbfile" "SELECT COALESCE(MAX(strftime('%s', started_at)), 0) FROM swarm_runs WHERE status = 'running';" 2>/dev/null || echo 0)
            started_epoch=${started_epoch%%\n}
            started_epoch=${started_epoch:-0}

            score=$((hb_epoch * 1000000000 + inprog * 1000000 + started_epoch))
            if [ "$score" -gt "$best_score" ]; then
                best_score=$score
                best="$cand"
            fi
            echo "Candidate DB: $dbfile (hb: $hb_epoch, inprog: $inprog, started: $started_epoch)" >&2
        done
        if [ -n "$best" ]; then
            RALPH_DIR_FOUND="$best"
        else
            RALPH_DIR_FOUND="${candidates[0]}"
        fi
    fi
fi

if [ -z "$RALPH_DIR_FOUND" ]; then
    echo "Warning: Swarm database not found in common locations"
    echo "The dashboard will run but won't display any data unless you set RALPH_DIR or place swarm.db in ~/.ralph or a parent .ralph directory."
    echo ""
else
    export RALPH_DIR="$RALPH_DIR_FOUND"
    echo "Using swarm DB at: $RALPH_DIR/swarm.db"
fi

# Check if running in interactive terminal. You can override by setting
# ALLOW_NO_TTY=1 to run in non-interactive/debug environments.
if [ -z "${ALLOW_NO_TTY:-}" ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "Error: Dashboard requires an interactive terminal."
        echo "Please run this directly in your terminal, not through opencode or a pipe."
        echo "If you are debugging or running in CI, set ALLOW_NO_TTY=1 to bypass this check."
        echo ""
        echo "Usage:"
        echo "  ./run-swarm-dashboard2.sh"
        exit 1
    fi
fi

# Save terminal state
stty -echo 2>/dev/null || true
tput smcup 2>/dev/null || true

# Trap to restore terminal on exit
trap 'tput rmcup 2>/dev/null || true; stty echo 2>/dev/null || true; reset 2>/dev/null || true; clear; echo "Swarm Dashboard2 exited."' EXIT

# Run dashboard with Bun
export PATH="$HOME/.bun/bin:$PATH"
if [ "$USE_SRC" = "true" ]; then
    echo "Running swarm-dashboard2 from source: swarm-dashboard2/src/index.ts"
    bun swarm-dashboard2/src/index.ts
else
    echo "Running swarm-dashboard2 from dist (not present unless you build)."
    bun run swarm-dashboard2/dist/index.js
fi
