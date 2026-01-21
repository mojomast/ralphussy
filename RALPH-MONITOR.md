# Ralph Live Monitor Integration

The ralph script now has **built-in real-time monitoring** to show activity while tasks are running - no need for separate terminal windows!

## Features

✅ **Inline Activity Display** - See what ralph is doing right in your terminal
✅ **Tool Usage** - Shows when ralph uses tools (Read, Write, Edit, Bash, etc.)
✅ **Step Progress** - Displays step starts/completions with token counts
✅ **Error Detection** - Immediate warning when errors occur
✅ **Non-Invasive** - Doesn't break ralph's JSON parsing or workflow

## Usage

**By default, monitoring is enabled:**
```bash
ralph "Create a hello.txt file"
ralph --devplan devplan.md --model zai-coding-plan/glm-4.7-flash
```

**Disable monitoring temporarily:**
```bash
ralph "task" --no-monitor
ralph --devplan devplan.md --no-monitor
```

**Disable monitoring globally (environment variable):**
```bash
export RALPH_NO_MONITOR=1
ralph "task"
```

## What You'll See

While ralph is working, you'll see live updates like:

```
[RALPH] ==========================================
[RALPH] === Task 1: Implement feature ===
[RALPH] ==========================================

📤 API REQUEST
   Provider: default
   Model: zai-coding-plan/glm-4.7-flash
   Task: Implement feature

⏳ Waiting for API response...
📋 Step 1 started
📖 Read
✏️ Write
💻 Bash
✓ Complete: 1234 tokens
```

## Icons Used

| Icon | Meaning |
|-------|---------|
| 📋 | Step started |
| ✓ | Step complete |
| 📖 | Read file |
| ✏️ | Write file |
| 🔨 | Edit file |
| 💻 | Bash command |
| 🔍 | Glob search |
| 🔎 | Grep search |
| 📋 | Task launch |
| ❓ | Question |
| 🌐 | Web fetch |
| 📝 | Todo write |
| 📜 | Todo read |
| ⚠ | Error detected |

## How It Works

1. Before calling opencode, ralph starts a background monitor process
2. The monitor watches the opencode log file in real-time
3. Important events are displayed inline with the "Waiting for API response..." message
4. When opencode completes, the monitor is stopped
5. All monitoring output goes to stderr so it doesn't interfere with JSON parsing

## Changes Made

**To `/home/mojo/projects/opencode2/ralph`:**

1. Added color codes (MAGENTA, CYAN) for monitor output
2. Added `start_monitor()` function - spawns background monitor
3. Added `stop_monitor()` function - cleans up background process
4. Added `find_latest_log()` function - finds most recent opencode log
5. Modified `run_iteration()` - starts/stops monitor around opencode calls
6. Modified `run_devplan_iteration()` - starts/stops monitor around opencode calls
7. Added `--no-monitor` CLI flag to disable monitoring
8. Added `RALPH_NO_MONITOR` environment variable for global disable
9. Updated help text to include `--no-monitor` option

## Backward Compatibility

✅ **Fully backward compatible** - Existing ralph commands work unchanged
✅ **Optional** - Can be disabled with `--no-monitor` flag
✅ **Safe** - Only reads logs, never modifies files

## Testing

Test the integration:

```bash
# Quick syntax check
bash -n /home/mojo/projects/opencode2/ralph

# Run ralph with monitoring (default)
cd ~/projects/ralph1
ralph "Create a test.txt file"

# Run ralph without monitoring
ralph "Create a test.txt file" --no-monitor
```

## Benefits

- ✅ No need for separate terminal windows
- ✅ See progress in real-time while ralph works
- ✅ Know exactly which tools are being used
- ✅ Spot errors immediately
- ✅ Watch token usage and costs live
- ✅ Fully integrated - no extra scripts needed

## Related Files

- `/home/mojo/projects/opencode2/ralph-watch` - Standalone monitor (still works)
- `/home/mojo/projects/opencode2/RALPH-WATCH.md` - Standalone monitor docs
- `/home/mojo/projects/opencode2/RALPH-MONITOR.md` - This file
