╔══════════════════════════════════════════════════════════════════════════╗
║          Ralph Slash Commands - Usage Guide for OpenCode                 ║
╚══════════════════════════════════════════════════════════════════════════╝

## The Issue: `/ralph` Not Appearing

OpenCode's slash command system doesn't automatically recognize custom commands.
Here's exactly how to make it work:

## ✅ SOLUTION 1: Use Direct CLI (Recommended)

```bash
# Instead of /ralph task, use:
ralph "Build a REST API. Output <promise>COMPLETE</promise> when done."

# With options:
ralph "Your task" --max-iterations 20
```

This works NOW and doesn't require any additional setup.

## ✅ SOLUTION 2: Source Commands in OpenCode Terminal

In your OpenCode terminal:

```bash
# Run this command first:
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh

# Then use slash commands:
/ralph Your task here
/ralph-status
/ralph-stop
/ralph-context "Focus on X"
```

## ✅ SOLUTION 3: Add to Shell Profile (Permanent)

```bash
# Add this to ~/.bashrc:
echo "source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh" >> ~/.bashrc

# Then restart terminal or:
source ~/.bashrc

# Now in OpenCode, use:
/ralph Your task
```

## Available Commands

| Command | Description |
|---------|-------------|
| `/ralph <task>` | Start autonomous loop |
| `/ralph-status` | Check loop status |
| `/ralph-stop` | Stop running loop |
| `/ralph-context <msg>` | Add context to next iteration |
| `/ralph-clear` | Clear pending context |
| `/ralph-help` | Show help |

## Quick Test

```bash
# Test that Ralph works:
cd /tmp
mkdir test-ralph && cd test-ralph
git init

# Run Ralph:
ralph "Create hello.txt with 'Hello from Ralph!' Output <promise>COMPLETE</promise> when done."

# Verify:
cat hello.txt
```

## Files Created

```
/home/mojo/.local/bin/ralph           - Main Ralph CLI
/home/mojo/.opencode/agents.json      - OpenCode agent config
~/.bashrc                             - Added Ralph sourcing
/home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh  - Slash commands
```

## Troubleshooting

### `/ralph` not recognized
```bash
# Use direct CLI instead:
ralph "Your task"
```

### Command not found after sourcing
```bash
# Check if commands file exists:
ls -la /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh

# Source with full path:
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### Ralph not in PATH
```bash
export PATH="/home/mojo/.local/bin:$PATH"
which ralph
```

## Summary

The simplest way to use Ralph RIGHT NOW:

```bash
ralph "Your task here. Output <promise>COMPLETE</promise> when done."
```

No slash commands needed. This works perfectly with OpenCode.

For slash commands, source the commands file before using OpenCode:
```bash
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

Then type `/ralph` in the OpenCode terminal.