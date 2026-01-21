#!/bin/bash

# Ralph OpenCode Integration Script
# This script creates the proper integration for Ralph with OpenCode

RALPH_PLUGIN_DIR="/home/mojo/projects/opencode2/opencode-ralph-slash"
RALPH_CONFIG="/home/mojo/.opencode/ralph-config.json"
RALPH_AGENT="/home/mojo/.local/bin/ralph-agent"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.opencode}"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Ralph OpenCode Integration Setup                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Create config directory
mkdir -p "$OPENCODE_CONFIG_DIR"

# Install Ralph agent wrapper
echo "📦 Installing Ralph agent..."
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ralph" << 'RALPH'
#!/bin/bash
RALPH_SCRIPT="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
RALPH_DIR="${RALPH_DIR:-.ralph}"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: sudo apt install jq"
    exit 1
fi

# Check for OpenCode
if ! command -v opencode &> /dev/null; then
    echo "Error: OpenCode not found. Install from https://opencode.ai"
    exit 1
fi

# Run Ralph
exec "$RALPH_SCRIPT" "$@"
RALPH
chmod +x "$HOME/.local/bin/ralph"
echo "  ✅ Installed Ralph CLI to $HOME/.local/bin/ralph"

# Create OpenCode agent configuration
cat > "$OPENCODE_CONFIG_DIR/agents.json" << 'AGENTS'
{
  "agents": {
    "ralph": {
      "name": "Ralph",
      "description": "Autonomous loop agent - iterates until task completion",
      "command": "ralph",
      "systemPrompt": "You are Ralph, an autonomous coding agent. You work iteratively on tasks, running them repeatedly until successful completion. Output <promise>COMPLETE</promise> when done.",
      "temperature": 0.1,
      "topP": 0.95
    }
  }
}
AGENTS
echo "  ✅ Created agent configuration"

# Create Ralph config
cat > "$OPENCODE_CONFIG_DIR/ralph.json" << 'RALPH'
{
  "ralph": {
    "enabled": true,
    "maxIterations": 100,
    "completionPromise": "COMPLETE",
    "stateDirectory": ".ralph"
  }
}
RALPH
echo "  ✅ Created Ralph configuration"

# Add to PATH if needed
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo ""
    echo "⚠️  Add to PATH:"
    echo "   echo 'export PATH=\"$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📖 How to Use Ralph with OpenCode:"
echo ""
echo "   Method 1: Using ralph CLI directly"
echo "   -----------------------------------"
echo "   ralph \"Build a REST API. Output <promise>COMPLETE</promise> when done.\""
echo ""
echo "   Method 2: Using OpenCode agent (if supported)"
echo "   ------------------------------------------------"
echo "   opencode run --agent ralph \"Your task here\""
echo ""
echo "   Method 3: Using slash commands"
echo "   --------------------------------"
echo "   source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh"
echo "   /ralph Your task here"
echo ""
echo "📂 Configuration:"
echo "   Agents: $OPENCODE_CONFIG_DIR/agents.json"
echo "   Ralph:  $OPENCODE_CONFIG_DIR/ralph.json"
echo ""
echo "📚 Documentation:"
echo "   /home/mojo/projects/opencode2/opencode-ralph/README.md"