# Ralph Monitor Fix - Log Detection Issue

## Problem

The monitor wasn't showing activity because it was watching the **OLD** log file that existed before opencode started. When opencode runs, it creates a **NEW** log file (based on current timestamp), but the monitor was still watching the old one.

## Root Cause

The `find_latest_log()` function found the most recently modified log file, which was from a **previous** session, not the current one. The monitor then watched this old log and never saw new activity.

## Solution

Rewrote `start_monitor()` to:
1. Get the initial newest log (before opencode starts)
2. Watch for a **new** log file to be created
3. Only start monitoring once we see the NEW log file
4. Timeout after 10 seconds if no new log appears
5. Display which log file is being watched

## Changes Made

### 1. Enhanced `start_monitor()` function

**Old logic:**
```bash
MONITOR_LOG=$(find_latest_log)
# Wait for log file to be created
while [ ! -f "$MONITOR_LOG" ] ...
```

**New logic:**
```bash
# Get initial log before opencode starts
initial_log=$(find_latest_log)

# Watch for NEW log file to appear
while [ "$found_new_log" = false ]; do
    newest_log=$(find "$log_dir" ...)
    if [ "$newest_log" != "$initial_log" ]; then
        MONITOR_LOG="$newest_log"
        found_new_log=true
    fi
done

# Display which file we're watching
echo "[Monitor] Watching: $(basename "$MONITOR_LOG")" >&2
```

### 2. Added Monitoring Indicator

Now shows "(Monitor starting - watching for activity...)" after "Waiting for API response..." message.

### 3. Improved `stop_monitor()` function

Extended line clear from 50 to 80 characters to cover longer monitor output.

## Testing

### Quick Syntax Test
```bash
bash -n /home/mojo/projects/opencode2/ralph
# Output: ✓ Final syntax OK
```

### Real Test
```bash
cd ~/projects/ralph1

# Monitor enabled (default)
ralph --devplan devplan.md --model zai-coding-plan/glm-4.7-flash

# Should now see:
# ⏳ Waiting for API response...
#    (Monitor starting - watching for activity...)
# [Monitor] Watching: 2026-01-21TXXXXXX.log
# 📋 Step 1 started
# 📖 Read
# ✏️ Write
```

### Disable Monitor
```bash
# Temporary disable
ralph --devplan devplan.md --no-monitor

# Global disable
export RALPH_NO_MONITOR=1
ralph "task"
```

## What You'll See Now

**Before fix:**
```
⏳ Waiting for API response...
```
*(silence - monitor watching wrong log)*

**After fix:**
```
⏳ Waiting for API response...
   (Monitor starting - watching for activity...)
[Monitor] Watching: 2026-01-21T001234.log
📋 Step 1 started
📖 Read
✏️ Write
✓ Complete: 1234 tokens
```

## Additional Improvements

1. **Better timeout handling** - Monitor gives up after 10 seconds if no new log appears
2. **Clearer feedback** - Shows which log file is being monitored
3. **Visual indicator** - "Monitor starting" message confirms it's active

## Troubleshooting

**If still no activity:**

1. Check log directory exists:
```bash
ls -la ~/.local/share/opencode/log/
```

2. Check opencode is creating logs:
```bash
# Run a quick test
opencode run "say hello" --format json
# Then check logs
ls -lt ~/.local/share/opencode/log/ | head -1
```

3. Verify monitor is enabled:
```bash
echo $MONITOR_ENABLED  # Should be "true"
echo $RALPH_NO_MONITOR  # Should be empty or not "1"
```

## Files Modified

- `/home/mojo/projects/opencode2/ralph` - Main ralph script
  - Enhanced `start_monitor()` function
  - Updated both call sites with monitoring indicator
  - Improved `stop_monitor()` function

## Next Steps

Test with your current ralph session:
```bash
# Stop current ralph if running (Ctrl+C)
cd ~/projects/ralph1
ralph --devplan devplan.md --model zai-coding-plan/glm-4.7-flash
```

You should now see real-time tool usage and step progress!
