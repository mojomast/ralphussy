#!/bin/bash
# Simple Swarm Dashboard Launcher (no TUI, just terminal output)

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
if [ ! -f "dist/simple.js" ]; then
    echo "Dashboard not built. Building now..."
    npm run build
fi

# Check if database exists
if [ ! -f "$HOME/.ralph/swarm.db" ]; then
    echo "Warning: Swarm database not found at ~/.ralph/swarm.db"
    echo "The dashboard will run but won't display any data."
    echo ""
fi

# Run simple dashboard with Bun
export PATH="$HOME/.bun/bin:$PATH"
bun run dist/simple.js
