# Ralph Slash Commands - OpenCode Integration Guide

## Why `/ralph` Might Not Appear

OpenCode's slash command system needs proper integration. Here are the reasons and solutions:

### 1. Slash Commands Must Be Registered

OpenCode doesn't automatically recognize custom slash commands. You need to:

**Solution A: Source the Commands First**
```bash
# In OpenCode terminal, run:
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

**Solution B: Add to Shell Profile (Permanent)**
```bash
echo "source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh" >> ~/.bashrc
source ~/.bashrc
```

### 2. Use Alias Instead

If slash commands don't work, use these alternatives:

| Instead of | Use |
|------------|-----|
| `/ralph ...` | `ralph "..."` |
| `/ralph-status` | `cat .ralph/state.json` |
| `/ralph-stop` | `pkill -f ralph` |
| `/ralph-context "msg"` | `echo "msg" >> .ralph/context.md` |

### 3. Direct Usage Methods

**Method 1: CLI Command**
```bash
ralph "Build a REST API. Output <promise>COMPLETE</promise> when done."
```

**Method 2: OpenCode run Command**
```bash
opencode run --agent ralph "Your task description"
```

**Method 3: In OpenCode Terminal**
```bash
# Source first
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh

# Then use
/ralph "Your task"
```

### 4. Make Slash Commands Persistent

Create a wrapper script that OpenCode will recognize:

```bash
# Create /home/mojo/.local/bin/ralph-cmd
cat > /home/mojo/.local/bin/ralph-cmd << 'EOF'
#!/bin/bash
# Ralph command wrapper for OpenCode

case "$1" in
    start|run)
        shift
        /home/mojo/.local/bin/ralph "$@"
        ;;
    status)
        cat .ralph/state.json 2>/dev/null || echo "No active loop"
        ;;
    stop)
        pkill -f ralph
        echo "Ralph stopped"
        ;;
    context|add)
        shift
        echo "$@" >> .ralph/context.md
        echo "Context added"
        ;;
    help|--help|-h)
        echo "Ralph Commands:"
        echo "  ralph-cmd start <task>  - Start Ralph loop"
        echo "  ralph-cmd status        - Check status"
        echo "  ralph-cmd stop          - Stop loop"
        echo "  ralph-cmd context <msg> - Add context"
        ;;
esac
EOF
chmod +x /home/mojo/.local/bin/ralph-cmd
```

### 5. OpenCode Configuration

Create `/home/mojo/.opencode/agents.json`:

```json
{
  "agents": {
    "ralph": {
      "name": "Ralph",
      "description": "Autonomous loop agent",
      "command": "ralph",
      "systemPrompt": "You are Ralph. Output <promise>COMPLETE</promise> when done."
    }
  }
}
```

### 6. Testing Slash Commands

After sourcing, test if functions are loaded:

```bash
# Check if functions are available
type _ralph_help
# Should show: _ralph_help is a function

# Show help
_ralph_help

# Check status (should show "No active loop")
_ralph_status
```

### 7. Troubleshooting

**Problem:** `/ralph` not recognized
```bash
# Solution: Source the commands
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh

# Or use direct command
/home/mojo/.local/bin/ralph "Your task"
```

**Problem:** Functions not defined
```bash
# Solution: Check if file is being sourced
bash -c 'source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh; type _ralph'

# Should show function definition, not "not found"
```

**Problem:** Command not in PATH
```bash
# Solution: Add to PATH
export PATH="$HOME/.local/bin:$PATH"

# Verify
which ralph
```

### 8. Quick Reference

```bash
# Setup (one-time)
echo "source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh" >> ~/.bashrc

# In OpenCode terminal:
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh

# Run task
/ralph "Build a REST API. Output <promise>COMPLETE</promise> when done."

# Check status
/ralph-status

# Add guidance
/ralph-context "Focus on authentication first"

# Stop
/ralph-stop
```

### 9. Alternative: Use ralph Directly

If slash commands still don't work:

```bash
# Instead of /ralph task
ralph "task description" --max-iterations 20

# Instead of /ralph-status
cat .ralph/state.json

# Instead of /ralph-context "msg"
echo "msg" >> .ralph/context.md
```

### 10. File Locations

```
Ralph Scripts:     /home/mojo/.local/bin/ralph
Commands Source:   /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
OpenCode Config:   /home/mojo/.opencode/agents.json
State Directory:   .ralph/
```