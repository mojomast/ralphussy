#!/bin/bash

set -euo pipefail

# Ralph Installation Script
# Installs Ralph CLI for OpenCode

RALPH_REPO="https://github.com/anomalyco/opencode"
RALPH_INSTALL_DIR="${RALPH_INSTALL_DIR:-/usr/local/bin}"
RALPH_CONFIG_DIR="${RALPH_CONFIG_DIR:-$HOME/.ralph}"

echo "🚀 Installing Ralph for OpenCode..."
echo ""

# Check for jq (required dependency)
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq dependency..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    else
        echo "❌ Could not install jq automatically. Please install jq manually:"
        echo "   Ubuntu/Debian: sudo apt install jq"
        echo "   macOS: brew install jq"
        exit 1
    fi
    echo "✅ jq installed"
fi

# Check for OpenCode
if ! command -v opencode &> /dev/null; then
    echo "📦 OpenCode not found. Installing..."
    curl -fsSL https://opencode.ai/install | bash
    echo "✅ OpenCode installed"
else
    echo "✅ OpenCode found: $(which opencode)"
fi

# Create config directory
echo "📁 Setting up Ralph configuration..."
mkdir -p "$RALPH_CONFIG_DIR"

# Download Ralph script
RALPH_SCRIPT="/tmp/ralph.$$.sh"
echo "📥 Downloading Ralph script..."
curl -fsSL "${RALPH_REPO}/raw/main/ralph" -o "$RALPH_SCRIPT"
chmod +x "$RALPH_SCRIPT"

# Install Ralph
echo "📦 Installing Ralph to ${RALPH_INSTALL_DIR}..."
if [ ! -w "$RALPH_INSTALL_DIR" ]; then
    echo "⚠️  $RALPH_INSTALL_DIR is not writable. Using sudo..."
    sudo mv "$RALPH_SCRIPT" "${RALPH_INSTALL_DIR}/ralph"
else
    mv "$RALPH_SCRIPT" "${RALPH_INSTALL_DIR}/ralph"
fi

# Create example prompts directory
mkdir -p "$RALPH_CONFIG_DIR/examples"

# Download example prompts
echo "📥 Downloading example prompts..."
curl -fsSL "${RALPH_REPO}/raw/main/examples/simple.txt" -o "$RALPH_CONFIG_DIR/examples/simple.txt" 2>/dev/null || true
curl -fsSL "${RALPH_REPO}/raw/main/examples/rest-api.txt" -o "$RALPH_CONFIG_DIR/examples/rest-api.txt" 2>/dev/null || true
curl -fsSL "${RALPH_REPO}/raw/main/examples/refactor.txt" -o "$RALPH_CONFIG_DIR/examples/refactor.txt" 2>/dev/null || true

# Initialize Ralph state
echo "🔧 Initializing Ralph state..."
echo '{"status": "idle", "iteration": 0, "prompt": "", "start_time": null, "last_activity": null, "context": ""}' > "$RALPH_CONFIG_DIR/state.json"
echo '{"iterations": [], "total_time": 0, "success": false}' > "$RALPH_CONFIG_DIR/history.json"
echo "# Ralph Progress Log" > "$RALPH_CONFIG_DIR/progress.md"

echo ""
echo "✅ Ralph installed successfully!"
echo ""
echo "📖 Quick Start:"
echo "   ralph --help                    # Show help"
echo "   ralph \"<task>\"               # Start a Ralph loop"
echo "   ralph --status                  # Check loop status"
echo ""
echo "📂 Configuration: $RALPH_CONFIG_DIR"
echo "📂 Examples: $RALPH_CONFIG_DIR/examples"
echo ""
echo "⚡ Next Steps:"
echo "   1. Try a simple task:"
echo "      ralph \"Create a hello.txt file. Output <promise>COMPLETE</promise> when done.\""
echo ""
echo "   2. Check progress:"
echo "      ralph --status"
echo ""
echo "   3. For complex tasks, create a prompt file:"
echo "      ralph --prompt-file /path/to/your-prompt.txt"
echo ""
echo "📚 Documentation: ${RALPH_REPO}/blob/main/README.md"