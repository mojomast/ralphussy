╔══════════════════════════════════════════════════════════════════════════╗
║          Ralph Slash Commands for OpenCode - Installation Summary        ║
╚══════════════════════════════════════════════════════════════════════════╝

## ✅ Installation Complete

Ralph slash commands have been successfully installed and configured!

## 📁 Files Created

```
/home/mojo/projects/opencode2/opencode-ralph/
├── ralph-integrated           Main Ralph autonomous loop script (482 lines)
├── ralph-commands.sh          Slash command functions for OpenCode (240 lines)
├── slash-commands.sh          Standalone slash command definitions
├── slash-commands.js          Command definition generator (Node.js)
├── setup-slash-commands.sh    Setup script
├── setup-and-demo.sh          Demo and setup script
├── SLASH_COMMANDS.md          Full documentation
├── QUICK_REFERENCE.md         Quick reference card
├── README.md                  Plugin documentation
└── INTEGRATION.md             Integration guide
```

## 🚀 Quick Start

### Enable Slash Commands

```bash
# Source the commands (add to ~/.bashrc for persistence)
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### Use in OpenCode

```
/ralph Build a REST API with CRUD operations.
        Output <promise>COMPLETE</promise> when all endpoints work.
```

## 📋 Available Slash Commands

| Command | Short | Description |
|---------|-------|-------------|
| `/ralph` | `/r` | Start autonomous loop with task |
| `/ralph-status` | `/rs` | Check current loop status |
| `/ralph-stop` | `/rq` | Stop running loop |
| `/ralph-context` | `/rc` | Add context to next iteration |
| `/ralph-clear` | `/rx` | Clear pending context |
| `/ralph-help` | `/rh` | Show help |

## 📝 Usage Examples

### Simple Task
```
/r Create a README.md with setup instructions.
   Output <promise>COMPLETE</promise> when done.
```

### Complex Task with Options
```
/ralph Build a todo API with tests.
       Output <promise>COMPLETE</promise> when all tests pass.
       --max-iterations 20
```

### Mid-Loop Guidance
```
/rc Try using TypeScript instead of JavaScript
```

### Monitor Progress
```
/ralph-status
```

## 🔧 Configuration

### Shell Integration

Added to `~/.bashrc`:
```bash
source /home/mojo/projects/opencode2/opencode-ralph/ralph-commands.sh
```

### Ralph Installed To

```
/home/mojo/.local/bin/ralph
```

### State Directory

```
~/.ralph/
├── state.json       # Current loop state
├── history.json     # Iteration history
├── progress.md      # Progress log
├── context.md       # Pending context
└── logs/            # Detailed logs
    ├── iteration_001.log
    └── ...
```

## ✨ Features

✅ **Autonomous Loop** - Runs OpenCode repeatedly until completion  
✅ **Slash Commands** - Native `/ralph` commands in OpenCode terminal  
✅ **State Persistence** - Maintains progress across iterations  
✅ **Progress Tracking** - Detailed logs and history  
✅ **Struggle Detection** - Warns when agent gets stuck  
✅ **Context Injection** - Guide mid-loop without restarting  
✅ **Short Aliases** - `/r`, `/rs`, `/rq`, `/rc`, `/rx`, `/rh`  

## 🧪 Tested & Working

Demo completed successfully:
- Created `demo.txt` with "Ralph slash commands work!" ✓
- Completed in 1 iteration ✓
- Progress logged to `.ralph/progress.md` ✓

## 📚 Documentation

- **Quick Reference**: [QUICK_REFERENCE.md](/home/mojo/projects/opencode2/opencode-ralph/QUICK_REFERENCE.md)
- **Full Docs**: [SLASH_COMMANDS.md](/home/mojo/projects/opencode2/opencode-ralph/SLASH_COMMANDS.md)
- **Plugin Guide**: [INTEGRATION.md](/home/mojo/projects/opencode2/opencode-ralph/INTEGRATION.md)

## 🔗 Next Steps

1. **Restart terminal** or run:
   ```bash
   source ~/.bashrc
   ```

2. **Try it out** in OpenCode:
   ```bash
   opencode
   ```

3. **Use slash commands**:
   ```
   /ralph Create a Python script that prints "Hello". Output <promise>COMPLETE</promise> when done.
   ```

4. **Monitor progress**:
   ```
   /ralph-status
   ```

## 💡 Tips

- Write clear prompts with specific success criteria
- Use `<promise>TAG</promise>` to signal completion
- Monitor with `/ralph-status` during long loops
- Guide stuck agents with `/ralph-context`
- Set `--max-iterations` to prevent runaway loops

## 🆘 Troubleshooting

### Command not found
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Agent stuck
```bash
/ralph-context Provide specific guidance
/ralph-stop
```

### Check status
```bash
/ralph-status
cat .ralph/progress.md
```

---

**Ralph** - Because sometimes you need to let the AI work while you sleep. 💤🤖