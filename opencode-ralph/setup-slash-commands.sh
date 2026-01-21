#!/bin/bash

# Ralph Slash Commands Setup Script
# Sets up slash commands for use in OpenCode

RALPH_COMMANDS="/home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh"
RALPH_SCRIPT="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
RALPH_BIN="$HOME/.local/bin/ralph"
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Ralph Slash Commands Setup for OpenCode             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check Ralph script
if [ ! -f "$RALPH_SCRIPT" ]; then
    echo "❌ Ralph script not found: $RALPH_SCRIPT"
    exit 1
fi
echo "  ✅ Ralph script found"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "  ⚠️  jq not found. Install with: sudo apt install jq"
else
    echo "  ✅ jq found"
fi

# Check for OpenCode
if ! command -v opencode &> /dev/null; then
    echo "  ⚠️  OpenCode not found. Install from https://opencode.ai"
else
    echo "  ✅ OpenCode found: $(which opencode)"
fi

echo ""
echo "📦 Setting up Ralph..."

# Create bin directory
mkdir -p "$HOME/.local/bin"

# Copy Ralph script
cp "$RALPH_SCRIPT" "$RALPH_BIN"
chmod +x "$RALPH_BIN"
echo "  ✅ Installed Ralph to $RALPH_BIN"

# Add to PATH if not already
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "  ⚠️  Add to PATH: export PATH=\"$HOME/.local/bin:\$PATH\""
fi

# Create bash completion
mkdir -p "$HOME/.local/share/bash-completion/completions"
cat > "$HOME/.local/share/bash-completion/completions/ralph" << 'COMPLETION'
#!/bin/bash
_ralph() {
    local cur prev words cword
    _init_completion || return
    
    local commands="start status stop context clear help"
    local aliases="r rs rq rc rx rh"
    
    if [[ "$cur" == /* ]]; then
        COMPREPLY=( $(compgen -W "/ralph /ralph-status /ralph-stop /ralph-context /ralph-clear /ralph-help" -- "$cur") )
        return
    fi
    
    COMPREPLY=( $(compgen -W "$commands $aliases" -- "$cur") )
}
complete -F _ralph ralph
COMPLETION
chmod +x "$HOME/.local/share/bash-completion/completions/ralph"
echo "  ✅ Added bash completion"

# Create function file
mkdir -p "$HOME/.ralph"
cat > "$HOME/.ralph/commands.sh" << 'FUNCTIONS'
# Ralph command functions for OpenCode
RALPH_SCRIPT="$HOME/.local/bin/ralph"
RALPH_DIR=".ralph"

ralph() {
    local prompt="$*"
    if [ -z "$prompt" ]; then
        echo "Usage: /ralph <task>"
        return 1
    fi
    "$RALPH_SCRIPT" "$prompt"
}
FUNCTIONS

# Add to shell rc files
echo ""
echo "🔧 Configuring shell integration..."

# Add to bashrc
if ! grep -q "ralph-commands.sh" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# Ralph slash commands for OpenCode" >> "$BASHRC"
    echo "source $RALPH_COMMANDS" >> "$BASHRC"
    echo "  ✅ Added to $BASHRC"
else
    echo "  ✅ Already configured in $BASHRC"
fi

# Add to zshrc if exists
if [ -f "$ZSHRC" ] && ! grep -q "ralph-commands.sh" "$ZSHRC" 2>/dev/null; then
    echo "" >> "$ZSHRC"
    echo "# Ralph slash commands for OpenCode" >> "$ZSHRC"
    echo "source $RALPH_COMMANDS" >> "$ZSHRC"
    echo "  ✅ Added to $ZSHRC"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📖 Quick Start:"
echo ""
echo "   1. Source the commands (or restart terminal):"
echo "      source $RALPH_COMMANDS"
echo ""
echo "   2. In OpenCode, use slash commands:"
echo "      /ralph Build a REST API. Output <promise>COMPLETE</promise> when done."
echo ""
echo "   3. Monitor progress:"
echo "      /ralph-status"
echo ""
echo "📋 Available Commands:"
echo ""
echo "   /ralph <task>              Start autonomous loop"
echo "   /ralph-status              Check status"
echo "   /ralph-stop                Stop loop"
echo "   /ralph-context <msg>       Add context"
echo "   /ralph-clear               Clear context"
echo "   /ralph-help                Show help"
echo ""
echo "📂 Files:"
echo "   Ralph:     $RALPH_BIN"
echo "   Commands:  $RALPH_COMMANDS"
echo "   State:     $HOME/.ralph/"
echo ""
echo "📚 Documentation: /home/mojo/projects/opencode2/opencode-ralph/SLASH_COMMANDS.md"
echo ""