#!/bin/bash

# Ralph Installation and Integration Script for OpenCode
# Installs Ralph as a standalone tool and integrates with OpenCode

set -euo pipefail

RALPH_SOURCE="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
RALPH_INSTALL_DIR="${RALPH_INSTALL_DIR:-$HOME/.local/bin}"
RALPH_LINK="/usr/local/bin/ralph"
RALPH_COMPLETION="/usr/local/share/bash-completion/completions/ralph"

echo "🚀 Installing Ralph for OpenCode..."
echo ""

# Check for dependencies
echo "📦 Checking dependencies..."

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "  Installing jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo "  ⚠️  Could not install jq automatically. Please install jq manually."
    fi
fi
echo "  ✅ jq found"

# Check for OpenCode
if ! command -v opencode &> /dev/null; then
    echo "  📦 OpenCode not found. Installing..."
    curl -fsSL https://opencode.ai/install | bash
else
    echo "  ✅ OpenCode found: $(which opencode)"
fi

# Install Ralph
echo ""
echo "📦 Installing Ralph..."
mkdir -p "$RALPH_INSTALL_DIR"
cp "$RALPH_SOURCE" "$RALPH_INSTALL_DIR/ralph"
chmod +x "$RALPH_INSTALL_DIR/ralph"

# Create symlink in PATH
if [ -w /usr/local/bin ] || sudo -n true 2>/dev/null; then
    if [ ! -f "$RALPH_LINK" ]; then
        if sudo -n true 2>/dev/null; then
            sudo ln -sf "$RALPH_INSTALL_DIR/ralph" "$RALPH_LINK"
        else
            ln -sf "$RALPH_INSTALL_DIR/ralph" "$RALPH_LINK"
        fi
        echo "  ✅ Symlinked to $RALPH_LINK"
    fi
else
    echo "  ⚠️  Cannot create symlink. Add to PATH:"
    echo "      export PATH=\"$RALPH_INSTALL_DIR:\$PATH\""
fi

# Create completion
mkdir -p "$(dirname "$RALPH_COMPLETION")"
cat > "$RALPH_COMPLETION" << 'COMPLETION'
#!/bin/bash
_ralph_completion() {
    local cur prev
    _init_completion || return
    COMPREPLY=($(compgen -W "--help --status --add-context --clear-context --max-iterations --completion-promise --verbose" -- "$cur"))
}
complete -F _ralph_completion ralph
COMPLETION
chmod +x "$RALPH_COMPLETION"
echo "  ✅ Added bash completion"

# Create example prompts
mkdir -p "$HOME/.ralph/examples"
cat > "$HOME/.ralph/examples/simple.txt" << 'EOF'
Create a file called greeting.txt with:
"Hello, Ralph!"

Output <promise>COMPLETE</promise> when the file exists.
EOF

cat > "$HOME/.ralph/examples/rest-api.txt" << 'EOF'
Build a REST API for todos with:
- GET /todos - List all todos
- POST /todos - Create todo
- Tests for all endpoints

Run tests after changes. Output <promise>COMPLETE</promise> when all tests pass.
EOF

echo "  ✅ Created example prompts"

# Initialize Ralph state
mkdir -p "$HOME/.ralph"
echo '{"status": "idle", "iteration": 0, "prompt": "", "start_time": null, "last_activity": null, "context": ""}' > "$HOME/.ralph/state.json"
echo '{"iterations": [], "total_time": 0, "success": false}' > "$HOME/.ralph/history.json"
echo "# Ralph Progress Log" > "$HOME/.ralph/progress.md"

echo ""
echo "✅ Ralph installed successfully!"
echo ""
echo "📖 Quick Start:"
echo ""
echo "   1. Try a simple task:"
echo "      ralph \"Create a hello.txt file. Output <promise>COMPLETE</promise> when done.\""
echo ""
echo "   2. Check progress:"
echo "      ralph --status"
echo ""
echo "   3. From a prompt file:"
echo "      ralph \"\$(cat ~/.ralph/examples/simple.txt)\""
echo ""
echo "📂 Config: $HOME/.ralph"
echo "📂 Examples: $HOME/.ralph/examples"
echo ""
echo "🔗 For plugin integration, add to opencode.json:"
echo '   {'
echo '     "plugins": ['
echo '       "/home/mojo/projects/opencode2/opencode-ralph"'
echo '     ]'
echo '   }'
echo ""
echo "📚 Documentation: /home/mojo/projects/opencode2/opencode-ralph/README.md"