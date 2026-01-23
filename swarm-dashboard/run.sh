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

# Check if dist exists
if [ ! -f "dist/index.js" ]; then
    echo "Dashboard not built. Building now..."
    npm run build
fi

# Check if database exists
if [ ! -f "$HOME/.ralph/swarm.db" ]; then
    echo "Warning: Swarm database not found at ~/.ralph/swarm.db"
    echo "The dashboard will run but won't display any data."
    echo ""
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
bun run dist/index.js
