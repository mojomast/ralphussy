# Ralph Live - Handoff

## Date
2026-01-22

## Current Status

The ralph-live system has been extensively debugged and improved. The swarm functionality is now operational with proper:

- **Model Configuration:** Default is `zai-coding-plan/glm-4.7` (fixed from broken `glm-4.7-free`)
- **Token Counting:** Correctly aggregates all API events (was showing 0→0)
- **JSON Text Extraction:** Fixed critical bug - now extracts LAST text message containing completion marker
- **Task Timeout:** Increased to 600s (10 minutes) - was killing tasks at 180s
- **Database Lock Handling:** Improved with 30s busy timeout, retries, WAL auto-checkpoint
- **Model Validation:** Validates models against `~/.opencode/enabled-models.json`
- **Orphaned Process Cleanup:** Automatically kills orphaned opencode processes before new runs
- **Worker Count:** Reduced to 2 (from 4) to reduce contention
- **Real-Time Verbosity:** Shows task assignments, executions, API calls, and completions as they happen

## Recent Critical Fixes

###1. JSON Text Extraction (ralph-refactor/lib/json.sh:14)
- Fixed critical jq syntax error causing all tasks to fail
- Now correctly extracts LAST text message containing `<promise>COMPLETE</promise>` marker

###2. Token Aggregation (ralph-refactor/lib/swarm_worker.sh:329-332)
- Changed from `head -1` (first event only) to summing all step_finish events
- Now shows correct token counts (e.g., 68981→2018 instead of 0→0)

###3. Enhanced Completion Detection (ralph-refactor/lib/swarm_worker.sh:356-374)
- Added flexible patterns beyond exact `<promise>COMPLETE</promise>` marker
- Catches: "Task completed", "All done", "completed successfully", etc.

###4. Status Display Formatting (ralph-refactor/ralph-swarm:467-507)
- Fixed garbled pipe-delimited SQL output in status command
- Added proper parsing to format status, workers, tasks, and pending task lists
- Status display now shows clean, human-readable output

###5. Resume Commit Checking (ralph-refactor/lib/swarm_worker.sh:21-60, 239-267)
- Added `swarm_worker_check_commit_for_task()` function
- Workers check for existing git commits matching task description before executing
- Tasks with matching commits are skipped and marked complete
- Prevents redoing work from previous runs when resuming

## Known Issues

- **Model Compliance:** `zai-coding-plan/glm-4.7` sometimes omits completion marker on complex tasks despite emphatic instructions
- **Database Locks:** Still occasional lock errors despite improvements (consider 1 worker if persistent)

## Key Configuration Files

| File | Setting | Value |
|------|---------|-------|
| `~/.opencode/enabled-models.json` | zai-coding-plan | Enabled with glm-4.5 to glm-4.7 models |
| `ralph-refactor/lib/core.sh:35-36` | Default PROVIDER | `zai-coding-plan` |
| `ralph-refactor/lib/core.sh:35-36` | Default MODEL | `glm-4.7` |
| `ralph-refactor/lib/swarm_worker.sh:308` | Task Timeout | 600s (10 minutes) |
| `ralph-refactor/lib/swarm_db.sh:42` | DB Timeout | 30000ms (30 seconds) |
| `ralph-refactor/ralph-swarm:858` | Default Workers | 2 |
| `ralph-refactor/lib/swarm_worker.sh:21-60` | Commit Checking | Enabled for resume |
| `ralph-refactor/ralph-swarm:467-507` | Status Display | Formatted output |

## Test Commands

```bash
# Run swarm with default model
cd ralph-refactor
./ralph-swarm --devplan ../devplan.md --workers 2

# Run with live verbosity
SWARM_OUTPUT_MODE=live ./ralph-swarm --devplan ../devplan.md --workers 2

# Resume previous run (now checks for existing commits)
SWARM_OUTPUT_MODE=live ./ralph-swarm --resume 20260122_230145

# Run JSON extraction tests
./tests/test_json.sh
```

## Next Steps

1. Try alternative models for better instruction following:
   - `opencode/gemini-3-flash`
   - `opencode/claude-sonnet-4-5` (requires payment method)

2. Consider dynamic timeout based on task complexity

3. Monitor database lock errors and consider reducing to 1 worker if persistent

---

## Archive Index

Historical context has been moved to [handoffarchive.md](./handoffarchive.md). Feel free to move stale sections from this file to the archive to keep handoff.md concise.

- [📦 Fixed Model Selection Wizard Exit/Hang](./handoffarchive.md#fixed-model-selection-wizard-exithang)
- [📦 Added Project Menu + New Project](./handoffarchive.md#added-project-menu--new-project-devplan--swarm)
- [📦 UX: Single-Key Menus + Cooler ASCII Branding](./handoffarchive.md#ux-single-key-menus--cooler-ascii-branding)
- [📦 Real-Time Verbosity Implementation](./handoffarchive.md#handoff-ralph-live-swarm-verbosity-implementation)
- [📦 Swarm Cleanup & Bug Fixes](./handoffarchive.md#handoff-swarm-cleanup--bug-fixes)
- [📦 JSON Extraction & Completion Detection Fixes](./handoffarchive.md#handoff-json-extraction--completion-detection-fixes)
- [📦 Token Aggregation Bug Fix](./handoffarchive.md#handoff-token-aggregation-bug-fix)
- [📦 Swarm Run 20260122_213126 - Timeout Investigation](./handoffarchive.md#handoff-swarm-run-20260122_213126---timeout-investigation)
- [📦 JSON Text Extraction Critical Bug Fix](./handoffarchive.md#handoff-json-text-extraction-critical-bug-fix)
- [📦 Swarm Resume & Display Fixes](./handoffarchive.md#handoff-swarm-resume--display-fixes)

---

**Instructions for maintaining this handoff:**
- Keep only current issues, recent fixes, and essential configuration in handoff.md
- Move resolved issues, detailed root cause analysis, and historical context to handoffarchive.md
- Update archive index when moving content
- Add anchors (`## Section Name`) to archived sections for linking
