#!/bin/bash
# Swarm Dashboard Launcher

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
# variable RUN_DIST=1 or call `npm run build` to produce dist/index.js.
USE_SRC="true"
if [ -n "${RUN_DIST:-}" ]; then
    # User explicitly requested the built distribution
    USE_SRC="false"
elif [ -f "dist/index.js" ]; then
    # dist exists but we still prefer source for development unless RUN_DIST=1
    echo "Note: dist/index.js exists but will run source (src/index.ts) by default. Set RUN_DIST=1 to run dist." 
    USE_SRC="true"
fi

# Locate swarm DB. Prefer explicit RALPH_DIR, then look upward from the dashboard directory,
# then common locations ($HOME/projects/.ralph, $HOME/.ralph).
RALPH_DIR_FOUND=""
if [ -n "${RALPH_DIR:-}" ] && [ -f "${RALPH_DIR%/}/swarm.db" ]; then
    RALPH_DIR_FOUND="${RALPH_DIR%/}"
else
    # Walk up from the script dir looking for a .ralph directory
    SEARCH_DIR="$SCRIPT_DIR"
    while [ "$SEARCH_DIR" != "/" ] && [ -n "$SEARCH_DIR" ]; do
        if [ -f "$SEARCH_DIR/.ralph/swarm.db" ]; then
            RALPH_DIR_FOUND="$SEARCH_DIR/.ralph"
            break
        fi
        SEARCH_DIR=$(dirname "$SEARCH_DIR")
    done
    # Common fallbacks
    if [ -z "$RALPH_DIR_FOUND" ] && [ -f "$HOME/projects/.ralph/swarm.db" ]; then
        RALPH_DIR_FOUND="$HOME/projects/.ralph"
    fi
    if [ -z "$RALPH_DIR_FOUND" ] && [ -f "$HOME/.ralph/swarm.db" ]; then
        RALPH_DIR_FOUND="$HOME/.ralph"
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

# Check if running in interactive terminal
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "Error: Dashboard requires an interactive terminal."
    echo "Please run this directly in your terminal, not through opencode or a pipe."
    echo ""
    echo "Usage:"
    echo "  cd /home/mojo/projects/ralphussy/swarm-dashboard"
    echo "  ./run.sh"
    exit 1
fi

# Save terminal state
stty -echo 2>/dev/null || true
tput smcup 2>/dev/null || true

# Trap to restore terminal on exit
trap 'tput rmcup 2>/dev/null || true; stty echo 2>/dev/null || true; reset 2>/dev/null || true; clear; echo "Dashboard exited."' EXIT

# Run dashboard with Bun
export PATH="$HOME/.bun/bin:$PATH"
if [ "$USE_SRC" = "true" ]; then
    echo "Running swarm-dashboard from source: src/index.ts"
    # Bun can execute TypeScript directly; run the source so your changes are used
    bun src/index.ts
else
    bun run dist/index.js
fi
