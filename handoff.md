# Ralph Live - Handoff

## Date
2026-01-23

## Current Status
 
  The ralph-live system has been extensively debugged and improved. The swarm functionality is now operational with proper:
  
  - **Worker Prompts:** All swarm start operations now prompt for worker count before starting
  - **Project Isolation:** Swarms create independent repos in `$RALPH_DIR/projects/PROJECT_NAME/` (not ralphussy worktrees)
  - **Git Repository Initialization:** Auto-initializes git repos in projects created by `ralph-live`
  - **Direct Merge:** Changes merge directly into project's `main` branch (no separate worker folders)
  - **Branch Cleanup:** Merged worker branches are automatically deleted after merging
  - **Model Configuration:** Default is `zai-coding-plan/glm-4.7` (fixed from broken `glm-4.7-free`)
 - **Token Counting:** Correctly aggregates all API events (was showing 0→0)
 - **JSON Text Extraction:** Fixed critical bug - now extracts LAST text message containing completion marker
 - **Task Timeout:** Increased to 600s (10 minutes) - was killing tasks at 180s
 - **Database Lock Handling:** Improved with 30s busy timeout, retries, WAL auto-checkpoint
 - **Model Validation:** Validates models against `~/.opencode/enabled-models.json`
 - **Orphaned Process Cleanup:** Automatically kills orphaned opencode processes before new runs
 - **Worker Count:** Reduced to 2 (from 4) to reduce contention
   - **Real-Time Verbosity:** Shows task assignments, executions, API calls, and completions as they happen
   - **Worker Count Prompts:** All swarm starts prompt for worker count (default 2)
   
  ## Recent Critical Fixes
   
   ###1. Project Repository Isolation (2026-01-23)
   - **Problem:** Swarm runs with `--project NAME` were creating worktrees from ralphussy instead of project's own repo
   - **Root Cause:** Path mismatch - `swarm_worker.sh` used `$HOME/projects` while `ralph-live` created projects in `$RALPH_DIR/projects`
   - **Root Cause:** Projects created by `ralph-live` weren't git repos (no `.git` folder)
   - **Root Cause:** Workers used fallback repo (ralphussy) when project directory existed but wasn't a git repo
   - **Solution:** Align project paths to use `$RALPH_DIR/projects` consistently
   - **Solution:** Auto-initialize git repo in existing projects if not already initialized
   - **Solution:** Ensure `main` branch is created (rename from default `master`)
   - **Solution:** `move_artifacts_for_run()` now merges directly into project repository (no separate `worker-1`, `worker-2` folders)
   - **Solution:** `swarm_merge_to_project()` detects project from source_path and merges into correct location
   - **Files Changed:**
     - `ralph-refactor/lib/swarm_worker.sh:105` - Changed `SWARM_PROJECTS_BASE` default to `$RALPH_DIR/projects`
     - `ralph-refactor/lib/swarm_worker.sh:121-132` - Auto-init git in existing projects
     - `ralph-refactor/lib/swarm_artifacts.sh:50-72` - Detect project from source_path in database
     - `ralph-refactor/lib/swarm_artifacts.sh:75-83` - Auto-init git with `main` branch in merge
     - `ralph-refactor/ralph-live:2086-2186` - Simplified to direct merge (no separate artifacts folders)
   - **Result:** Each project has its own independent git repository
   - **Result:** Changes merge directly into project's `main` branch
   - **Result:** No cross-stream between different projects or with ralphussy
   - **Result:** Artifacts merged, not copied to separate folders

   ###2. Worker Count Prompts (2026-01-23)
   - **Problem:** Swarms were starting with default 2 workers without prompting user
   - **Solution:** All swarm start operations now prompt for worker count before starting
   - **New Feature:** `ralph-swarm --devplan PATH` prompts for workers if not specified
   - **New Feature:** `ralph-live project_start_swarm_devplan()` prompts for workers
   - **New Feature:** `ralph-live project_resume_swarm()` prompts for workers (allows changing from saved value)
   - **New Feature:** `ralph-swarm --resume` accepts `--workers N` to override saved count
   - **Files Changed:**
     - `ralph-refactor/ralph-swarm:1308-1328` - Prompt for workers in non-interactive start
     - `ralph-refactor/ralph-swarm:1300-1309` - Resume accepts --workers override
     - `ralph-refactor/ralph-live:433-449` - Prompt for workers in project start
     - `ralph-refactor/ralph-live:883-905` - Prompt for workers in project resume
   - **Result:** User always sees "Number of workers [2]:" prompt before swarm starts
   - **Result:** Resume operations can change worker count from previous run

   ###3. Project Isolation & Artifact Extraction (2026-01-23)
   - **Problem:** Workers were creating git worktrees of ralphussy, mixing swarm commits with ralphussy history
   - **Solution:** Workers now create independent repos in `~/projects/PROJECT_NAME/`
   - **New Feature:** `--project NAME` flag for swarming on specific projects
   - **New Feature:** `swarm_extract_merged_artifacts()` extracts only changed files (not full project)
   - **New Feature:** `swarm_merge_to_project()` merges worker branches into project's main branch
   - **New Feature:** `ralph-live` option 'm' now prompts to merge changes into project repo
   - **Fixed:** Detached HEAD worktrees now use expected swarm branch instead of HEAD for diff calculation
   - **Fixed:** `move_artifacts_for_run()` removed old artifacts folder copy that overwrote correct extraction
  - **Fixed:** Base branch detection - now uses `swarm_git_default_base_branch()` instead of hardcoded 'main'
   - **Fixed:** Automatic branch cleanup - merged worker branches are deleted after merging
   - **Files Changed:**
     - `ralph-refactor/lib/swarm_worker.sh:82-150` - Project repo initialization logic
     - `ralph-refactor/ralph-swarm:943-949` - `--project` parameter
     - `ralph-refactor/lib/swarm_artifacts.sh:4-8,159-172,307-317` - Source swarm_git.sh, base branch detection
     - `ralph-refactor/lib/swarm_artifacts.sh:10-110` - `swarm_merge_to_project()` function
     - `ralph-refactor/lib/swarm_artifacts.sh:113-155` - `swarm_cleanup_branches()` function
     - `ralph-refactor/ralph-live:2086-2185` - Automatic merge in `move_artifacts_for_run()`
   - **Usage:**
     ```bash
     # Run swarm on isolated project
     ./ralph-refactor/ralph-swarm --devplan devplan.md --project my-app --workers 2
     
     # Move artifacts (merges automatically into main)
     ./ralph-live  # Select 'm' to move and merge
     
     # Clean up old swarm branches
     source ralph-refactor/lib/swarm_artifacts.sh
     cd ~/projects/ralphussy
     swarm_cleanup_branches
     ```
   - **Result:** Worker artifacts now ~200KB instead of 1.5MB (only swarm commits, not full ralphussy)
   - **Result:** Changes are AUTOMATICALLY merged into project's main branch when moving artifacts
   - **Result:** Merged worker branches are automatically deleted to keep project clean
   - **Result:** Changes are pushed to origin if remote is configured
   
 ###2. JSON Text Extraction (ralph-refactor/lib/json.sh:14)
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

###6. Swarm Attach Mode (ralph-refactor/ralph-live:1973-2200)
- **New Feature:** `ralph-live --attach [RUN_ID]` attaches to running swarms
- **New Feature:** Interactive selection from list of running swarms
- **Display:** Real-time progress bar, worker status, task counts
- **Controls:** `r` to refresh, `q` to quit
- **Usage:** Read-only, does not interfere with running swarms
- **Files Changed:**
   - `ralph-refactor/ralph-live:1973-2200` - `attach_swarm_live()` and `list_running_swarm()` functions
   - `ralph-refactor/ralph-live:90` - `read_key()` fixed for non-TTY environments
   - `ralph-refactor/ralph-live:2372` - menu option `a` for attach mode

###7. Swarm Artifacts to Projects (ralph-refactor/ralph-live:2032-2120, 1973-2030)
- **New Feature:** `ralph-live` menu option `m` to move artifacts to projects folder
- **Function:** `move_swarm_artifacts()` lists completed swarms and copies artifacts
- **Function:** `move_artifacts_for_run()` copies worker repos, logs, and creates SWARM_SUMMARY.md
- **Destination:** `/projects/swarm-RUN_ID/`
- **Files Changed:**
   - `ralph-refactor/ralph-live:1973-2030` - `move_swarm_artifacts()` and `move_artifacts_for_run()`
   - `ralph-refactor/ralph-live:2435` - menu option `m` added
- **Tested:** Successfully extracted artifacts from run `20260123_022949` to `/projects/swarm-20260123_022949/`
- **Usage:** 
   ```bash
   # Interactive mode - select swarm from list
   ./ralph-live
   # Then select option 'm'
   
   # Direct move (pipe selection)
   echo "1" | ./ralph-live
   ```

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
  # Run swarm on isolated project (NEW workflow)
  # Note: Will prompt "Number of workers [2]:" before starting
  cd ralph-refactor
  ./ralph-swarm --devplan ../devplan.md --project warp-clone
  
  # Run with specific worker count (no prompt)
  ./ralph-swarm --devplan ../devplan.md --project warp-clone --workers 4
  
  # Interactive mode (prompts for project name, workers, etc.)
  ./ralph-swarm --interactive
  
  # Run with live verbosity
  SWARM_OUTPUT_MODE=live ./ralph-swarm --devplan ../devplan.md --project warp-clone
  
  # Resume previous run (now prompts for workers to allow changing)
  SWARM_OUTPUT_MODE=live ./ralph-swarm --resume 20260122_230145
  
  # Move artifacts (automatically merges and cleans up)
  ./ralph-live  # Select 'm'
  
  # Clean up old swarm branches (manual cleanup)
  source ralph-refactor/lib/swarm_artifacts.sh
  cd ~/projects/ralphussy
  swarm_cleanup_branches
  
  # Run JSON extraction tests
  ./tests/test_json.sh
  ```

   ## Next Steps
   
    1. Clean up existing swarm branches in ralphussy (34 branches remaining):
       ```bash
       source ralph-refactor/lib/swarm_artifacts.sh
       cd ~/projects/ralphussy
       swarm_cleanup_branches
       ```
    
    2. Use `--project NAME` when running swarms to avoid cross-stream with ralphussy repo:
       - Creates independent repo at `~/projects/NAME` (empty, just devplan.md)
       - Workers create branches like `swarm/RUN_ID/worker-N` in that project
       - `move artifacts` (option 'm' in ralph-live) automatically merges all worker branches
    
    3. Test new automatic merge functionality on a new project:
       ```bash
       ./ralph-refactor/ralph-swarm --devplan devplan.md --project my-new-app --workers 2
       # Wait for completion, then:
       ./ralph-live  # Select 'm' to move and merge automatically
       cd ~/projects/my-new-app
       git log --oneline  # Should show merged worker commits
       git branch -a  # Should have NO swarm branches (they were deleted)
       ```
    
    4. Try alternative models for better instruction following:
       - `opencode/gemini-3-flash`
       - `opencode/claude-sonnet-4-5` (requires payment method)
    
    5. Consider dynamic timeout based on task complexity
    
    6. Monitor database lock errors and consider reducing to 1 worker if persistent
   
---

## Archive Index

Historical context has been moved to [handoffarchive.md](./handoffarchive.md). Feel free to move stale sections from this file to the archive to keep handoff.md concise.

- [📦 Fixed Model Selection Wizard Exit/Hang](./handoffarchive.md#fixed-model-selection-wizard-exithang)
- [📦 Added Project Menu + New Project Wizard](./handoffarchive.md#added-project-menu--new-project-devplan--swarm)
- [📦 UX: Single-Key Menus + Cooler ASCII Branding](./handoffarchive.md#ux-single-key-menus--cooler-ascii-branding)
- [📦 Real-Time Verbosity Implementation](./handoffarchive.md#handoff-ralph-live-swarm-verbosity-implementation)
- [📦 Swarm Cleanup & Bug Fixes](./handoffarchive.md#handoff-swarm-cleanup--bug-fixes)
- [📦 JSON Extraction & Completion Detection Fixes](./handoffarchive.md#handoff-json-extraction--completion-detection-fixes)
- [📦 Token Aggregation Bug Fix](./handoffarchive.md#handoff-token-aggregation-bug-fix)
- [📦 Swarm Run 20260122_213126 - Timeout Investigation](./handoffarchive.md#handoff-swarm-run-20260122_213126---timeout-investigation)
- [📦 JSON Text Extraction Critical Bug Fix](./handoffarchive.md#handoff-json-text-extraction-critical-bug-fix)
- [📦 Swarm Resume & Display Fixes](./handoffarchive.md#handoff-swarm-resume--display-fixes)
- [📦 Swarm Attach Mode & Artifacts Move (2026-01-23)](#handoff-swarm-attach-mode--artifacts-move-2026-01-23)

---

**Instructions for maintaining this handoff:**
- Keep only current issues, recent fixes, and essential configuration in handoff.md
- Move resolved issues, detailed root cause analysis, and historical context to handoffarchive.md
- Update archive index when moving content
- Add anchors (`## Section Name`) to archived sections for linking

---

## Archive Index

- [📦 Swarm Attach Mode & Artifacts Move (2026-01-23)](#handoff-swarm-attach-mode--artifacts-move-2026-01-23) - Today's changes added to archive
