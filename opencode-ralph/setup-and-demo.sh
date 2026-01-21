#!/bin/bash

# Ralph Setup and Quick Start Script
# Installs Ralph and runs a demo task

set -euo pipefail

RALPH_PATH="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
RALPH_LOCAL="$HOME/.local/bin/ralph"
RALPH_DIR="$HOME/.ralph"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Ralph - Autonomous AI Coding Loop for OpenCode      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Setup Ralph
echo "🔧 Setting up Ralph..."
mkdir -p "$HOME/.local/bin"
mkdir -p "$RALPH_DIR"
mkdir -p "$RALPH_DIR/logs"
mkdir -p "$RALPH_DIR/examples"

cp "$RALPH_PATH" "$RALPH_LOCAL"
chmod +x "$RALPH_LOCAL"

# Create state files
echo '{"status": "idle", "iteration": 0, "prompt": "", "start_time": null, "last_activity": null, "context": ""}' > "$RALPH_DIR/state.json"
echo '{"iterations": [], "total_time": 0, "success": false}' > "$RALPH_DIR/history.json"
echo "# Ralph Progress Log" > "$RALPH_DIR/progress.md"

# Create example prompts
cat > "$RALPH_DIR/examples/simple.txt" << 'EOF'
Create a file called greeting.txt with "Hello from Ralph!" on line 1.
Output <promise>COMPLETE</promise> when done.
EOF

cat > "$RALPH_DIR/examples/rest-api.txt" << 'EOF'
Build a simple REST API with Express.js that:
1. Has a GET / endpoint returning "Hello API"
2. Has a GET /health endpoint returning status OK
3. Includes proper error handling

Create package.json, index.js, and run the server.
Output <promise>COMPLETE</promise> when the API is running and responding.
EOF

echo "✅ Ralph installed to $RALPH_LOCAL"
echo "✅ Configuration: $RALPH_DIR"
echo ""

# Add to PATH if not already there
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "⚠️  Add to PATH: export PATH=\"$HOME/.local/bin:\$PATH\""
    export PATH="$HOME/.local/bin:$PATH"
fi

# Check OpenCode
if ! command -v opencode &> /dev/null; then
    echo "❌ OpenCode not found. Install from https://opencode.ai"
    exit 1
fi
echo "✅ OpenCode found: $(which opencode)"
echo ""

# Quick test
echo "🧪 Running quick test..."
cd /tmp
rm -rf ralph-demo
mkdir -p ralph-demo
cd ralph-demo
git init > /dev/null 2>&1

echo ""
echo "🚀 Starting Ralph demo task..."
echo ""
echo "📝 Task: Create a hello.txt file with 'Hello from Ralph!'"
echo "⏳ This should complete in 1-2 iterations..."
echo ""

"$RALPH_LOCAL" "Create a file called hello.txt with 'Hello from Ralph!' on line 1. Output <promise>COMPLETE</promise> when done." --max-iterations 3

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Demo Complete!                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Show created file
if [ -f "hello.txt" ]; then
    echo "📄 Created file:"
    echo "   -------"
    cat hello.txt
    echo "   -------"
    echo ""
fi

# Show progress
echo "📊 Progress: $RALPH_DIR/progress.md"
echo "📊 History: $RALPH_DIR/history.json"
echo "📊 Logs: $RALPH_DIR/logs/"
echo ""

# Show usage
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Usage Examples                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "   # Run a task"
echo "   ralph \"Build a REST API. Output <promise>COMPLETE</promise> when done.\""
echo ""
echo "   # With options"
echo "   ralph \"Your task\" --max-iterations 20 --completion-promise DONE"
echo ""
echo "   # Check status"
echo "   ralph --status"
echo ""
echo "   # Add context mid-loop"
echo "   ralph --add-context \"Focus on the auth module first\""
echo ""
echo "   # From prompt file"
echo "   ralph \"\$(cat ~/.ralph/examples/simple.txt)\""
echo ""

echo "📚 Documentation: /home/mojo/projects/opencode2/opencode-ralph/README.md"
echo "🔗 Repository: https://github.com/anomalyco/opencode"
echo ""