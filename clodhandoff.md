# Clod Handoff - Swarm Project Creation & Merging Fixes

## Date: Jan 23, 2026

## Issues Fixed

### 1. Projects Being Created in Wrong Folder
**Problem:** Projects were being created in `~/.ralph/projects/` instead of `~/projects/`

**Solution:** Changed all default paths from `${RALPH_DIR}/projects` to `$HOME/projects`

**Files Modified:**
- `ralph-refactor/lib/swarm_worker.sh:107` - `projects_base` default
- `ralph-refactor/lib/swarm_worker.sh:230` - exported `SWARM_PROJECTS_BASE`
- `ralph-refactor/lib/swarm_artifacts.sh:44` - merge function path
- `ralph-refactor/lib/swarm_artifacts.sh:394` - extract function path  
- `ralph-refactor/ralph-live:30` - `PROJECTS_DIR` variable

### 2. Swarm Workers Not Merging Their Parts Together
**Problem:** Each worker's output was separate - the merge functions weren't combining them into one cohesive project

**Root Cause:** The `swarm_merge_to_project()` function tried to merge using git branches, but worker worktrees create branches in `$RALPH_DIR/swarm/runs/$run_id/worker-N/repo`, not in the main project repo. So branch-based merging failed silently.

**Solution:** Added file-based merge as primary/fallback mechanism:

```bash
# In swarm_artifacts.sh - swarm_merge_to_project()
if [ "$use_file_merge" = true ]; then
    # Copy changed files directly from worker repo to project
    changed_files=$(git -C "$worker_repo" diff --name-only "${base_commit}..${target_branch}")
    while IFS= read -r file; do
        cp "${worker_repo}/${file}" "${project_dir}/${file}"
    done <<< "$changed_files"
fi
```

Also updated `swarm_extract_merged_artifacts()` to:
- Detect actual project directory from run metadata
- Merge directly into project folder (not separate `merged-repo/` subdir)
- Create single commit with all worker changes combined

### 3. Ralphussy Project Files Leaking into Generated Projects
**Problem:** Files from the ralphussy codebase (ralph-refactor/, ralph-tui/, etc.) were ending up in generated projects

**Root Cause:** When `SWARM_PROJECT_NAME` wasn't set or when falling back, the system used `git rev-parse --show-toplevel` which returned the ralphussy directory if that's where the command was run from.

**Solution:** Multiple safeguards:

1. **Worker Prompt** (`swarm_worker.sh:378-395`):
```
DO NOT reference, copy, or include any files from ralph-refactor/, ralph-tui/, 
swarm-dashboard/, or opencode-ralph* directories - these are internal tooling files
```

2. **Project .gitignore** (`swarm_worker.sh:117-126`):
```gitignore
ralph-refactor/
ralph-tui/
swarm-dashboard/
opencode-ralph*/
*.db
```

3. **Merge Filters** (in both merge functions):
```bash
case "$file" in
    ralph-refactor/*|ralph-tui/*|swarm-dashboard/*|opencode-ralph*/*|.git/*|*.db)
        echo "  Skipping ralphussy file: $file"
        continue
        ;;
esac
```

4. **Explicit Repo Root** (`swarm_worker.sh:108-151`):
When `SWARM_PROJECT_NAME` is set, the project directory is ALWAYS used as repo root - no fallback to current directory.

## Key Code Changes

### swarm_worker.sh

```bash
# Line 107 - Changed default projects base
local projects_base="${SWARM_PROJECTS_BASE:-$HOME/projects}"

# Lines 108-151 - Enhanced project creation with explicit repo root
if [ -n "$project_name" ]; then
    # ... create project ...
    repo_root="$project_dir"  # ALWAYS use project dir, no fallback
    echo "Using project directory as repo root: $repo_root"
fi

# Lines 117-126 - New .gitignore with ralphussy exclusions
cat > "$project_dir/.gitignore" <<'GITIGNORE'
node_modules/
.env
ralph-refactor/
ralph-tui/
swarm-dashboard/
opencode-ralph*/
*.db
GITIGNORE

# Line 230 - Export SWARM_REPO_ROOT to workers
export SWARM_REPO_ROOT="'"${repo_root}"'"
```

### swarm_artifacts.sh

```bash
# swarm_merge_to_project() - Added file-based merge (lines ~130-200)
local use_file_merge=false
if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$target_branch"; then
    use_file_merge=true
fi

if [ "$use_file_merge" = true ]; then
    # Copy files directly instead of git merge
    changed_files=$(git -C "$worker_repo" diff --name-only ...)
    # ... copy with filters ...
fi

# swarm_extract_merged_artifacts() - Fixed to merge into project dir
# Now detects project dir from source_path in database
# Merges all workers into single location with one commit
```

### ralph-live

```bash
# Line 30 - Changed projects directory
PROJECTS_DIR="${SWARM_PROJECTS_BASE:-$HOME/projects}"
```

## Testing Recommendations

1. **Test new project creation:**
   ```bash
   SWARM_PROJECT_NAME=test-project ralph-swarm --devplan /path/to/devplan.md --workers 2
   # Verify project created in ~/projects/test-project NOT ~/.ralph/projects/
   ```

2. **Test merge after swarm completes:**
   ```bash
   # After swarm run completes, check:
   ls ~/projects/test-project/
   # Should have all files from all workers merged together
   ```

3. **Verify no ralphussy files leaked:**
   ```bash
   find ~/projects/test-project -name "ralph-*" -o -name "swarm-dashboard" -o -name "*.db"
   # Should return nothing
   ```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SWARM_PROJECTS_BASE` | `$HOME/projects` | Base directory for new projects |
| `SWARM_PROJECT_NAME` | (none) | Name of project to create/use |
| `SWARM_REPO_ROOT` | (auto) | Explicit repo root (set automatically) |

## Remaining Considerations

1. The TUI Python file (`ralph_tui.py`) may also have the old `RALPH_DIR/projects` path - didn't check/modify that file
2. Old projects in `~/.ralph/projects/` won't be automatically migrated
3. If users have `SWARM_PROJECTS_BASE` explicitly set to old location, that will still be honored
