#!/bin/bash

# OpenCode Ralph Setup - Complete Installation
# Run this to set up everything for slash commands to work

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Ralph OpenCode Integration - Complete Setup         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

RALPH_PATH="/home/mojo/projects/opencode2/opencode-ralph"
RALPH_BIN="$HOME/.local/bin/ralph"
RALPH_RC="$HOME/.ralph/ralph-bashrc.sh"

# Step 1: Install Ralph CLI
echo "📦 Step 1: Installing Ralph CLI..."
mkdir -p "$HOME/.local/bin"
cp "$RALPH_PATH/ralph-integrated" "$RALPH_BIN"
chmod +x "$RALPH_BIN"
echo "  ✅ Installed to $RALPH_BIN"

# Step 2: Create bashrc integration
echo ""
echo "📝 Step 2: Setting up bash integration..."
cat > "$RALPH_RC" << 'EOF'
#!/bin/bash
# Ralph Integration for OpenCode

RALPH_PATH="/home/mojo/.local/bin/ralph"
RALPH_COMMANDS="/home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh"

export PATH="/home/mojo/.local/bin:$PATH"

ralph() {
    if [ $# -eq 0 ]; then
        echo "🤖 Ralph - Autonomous AI Coding Loop"
        echo ""
        echo "Usage: ralph \"<task description>\" [options]"
        echo ""
        echo "Options:"
        echo "  --max-iterations N    Max iterations (default: 100)"
        echo "  --completion-promise T Completion signal"
        echo "  --verbose, -v         Verbose output"
        echo ""
        echo "Examples:"
        echo '  ralph "Create a file. Output <promise>COMPLETE</promise> when done."'
        echo ""
        echo "Slash commands (source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh)"
        return 0
    fi
    "$RALPH_PATH" "$@"
}

alias r='ralph'
alias rs='cat .ralph/state.json 2>/dev/null || echo "No loop"'
alias rq='pkill -f ralph 2>/dev/null; echo "Ralph stopped"'
alias rx='rm -f .ralph/context.md 2>/dev/null; echo "Context cleared"'

if [ -f "$RALPH_COMMANDS" ]; then
    source "$RALPH_COMMANDS"
fi

echo "🤖 Ralph loaded! Type 'ralph' for help."
EOF

# Add to bashrc if not already there
if ! grep -q "ralph-bashrc.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Ralph integration for OpenCode" >> "$HOME/.bashrc"
    echo "[ -f \"$RALPH_RC\" ] && source \"$RALPH_RC\"" >> "$HOME/.bashrc"
fi
echo "  ✅ Added to ~/.bashrc"

# Step 3: Create OpenCode config
echo ""
echo "📋 Step 3: Creating OpenCode configuration..."
mkdir -p "$HOME/.opencode"
cat > "$HOME/.opencode/agents.json" << 'EOF'
{
  "agents": {
    "ralph": {
      "name": "Ralph",
      "description": "Autonomous loop agent",
      "command": "ralph",
      "systemPrompt": "You are Ralph. Output <promise>COMPLETE</promise> when done.",
      "temperature": 0.1
    }
  }
}
EOF
echo "  ✅ Created $HOME/.opencode/agents.json"

# Step 4: Verify installation
echo ""
echo "🔍 Step 4: Verifying installation..."
if [ -x "$RALPH_BIN" ]; then
    echo "  ✅ Ralph CLI installed"
else
    echo "  ❌ Ralph CLI not executable"
fi

if command -v jq &> /dev/null; then
    echo "  ✅ jq found"
else
    echo "  ⚠️  jq not found (install with: sudo apt install jq)"
fi

if command -v opencode &> /dev/null; then
    echo "  ✅ OpenCode found: $(which opencode)"
else
    echo "  ⚠️  OpenCode not in PATH"
fi

# Step 5: Instructions
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📖 Next Steps:"
echo ""
echo "   1. Restart your terminal or run:"
echo "      source ~/.bashrc"
echo ""
echo "   2. Use Ralph:"
echo "      ralph \"Build a REST API. Output <promise>COMPLETE</promise> when done.\""
echo ""
echo "   3. For slash commands, source the commands file:"
echo "      source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh"
echo ""
echo "   4. Then use in OpenCode:"
echo "      /ralph Your task here"
echo ""
echo "📂 Files:"
echo "   CLI:        $RALPH_BIN"
echo "   Bash RC:    $RALPH_RC"
echo "   OpenCode:   $HOME/.opencode/agents.json"
echo "   Commands:   /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh"
echo ""
echo "📚 Docs:"
echo "   /home/mojo/projects/opencode2/opencode-ralph/README.md"
echo "   /home/mojo/projects/opencode2/opencode-ralph/SLASH_TROUBLESHOOTING.md"
echo ""