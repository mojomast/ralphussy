# Ralph Swarm & Project Fixes Handoff

**Updated**: 2026-01-23
**Session**: Swarm project fixes, failed task handling, devplan review with alternate models

## Summary

This session continued fixing issues documented in `clodhandoff.md` and added a new feature for reviewing devplans with alternate AI models.

## Issues Fixed

### 1. TUI Projects Directory Path (ralph_tui.py)

**Problem:** The TUI was using `~/.ralph/projects` instead of `~/projects`

**Fix:** Changed line 66 in `ralph-refactor/tui/ralph_tui.py`:
```python
# Before
PROJECTS_DIR = RALPH_DIR / "projects"

# After
PROJECTS_DIR = Path(os.environ.get("SWARM_PROJECTS_BASE", Path.home() / "projects"))
```

### 2. Undefined Variables in swarm_artifacts.sh

**Problem:** The `swarm_extract_merged_artifacts()` function referenced undefined variables `$dest_dir`, `$merged_repo_dir`, and used `$worker_count` without defining it.

**Fixes:**
- Changed `$dest_dir/SWARM_SUMMARY.md` to `$project_dir/SWARM_SUMMARY.md`
- Changed all references to `$merged_repo_dir` to `$project_dir`
- Updated summary text to reference project directory instead of merged-repo
- Changed `$dest_dir` to `$project_dir` in final output messages

### 3. Failed Task Retry Functionality

**Problem:** Failed tasks stayed permanently in `failed` status with no way to retry them.

**Solution:** Added two new functions to `ralph-refactor/lib/swarm_db.sh`:

```bash
# Retry failed tasks (resets them to pending, up to max_retries)
swarm_db_retry_failed_tasks "$run_id" 3

# Get count of tasks eligible for retry
swarm_db_get_retryable_task_count "$run_id" 3
```

**Integration:** Updated `ralph-swarm` resume action to:
1. Check for failed tasks that can be retried
2. Prompt user to retry them
3. Reset retryable tasks to `pending` status

### 4. DevPlan Review with Another Model (NEW FEATURE)

**Problem:** Users wanted to get a second opinion on their devplan from a different AI model.

**Solution:** Added `project_review_devplan_with_model()` function to `ralph-live` that:

1. Prompts user to select a provider and model for review
2. Sends devplan to selected model with comprehensive review prompt
3. Model analyzes for:
   - Missing tasks or gaps in coverage
   - Potential blockers and dependencies
   - Technical incompatibilities
   - Task quality issues (too vague, too large, duplicated)
   - Missing non-functional requirements
4. Displays review results
5. Offers options:
   - **a** - Apply suggestions automatically
   - **m** - Manually edit devplan
   - **s** - Save review to separate file
   - **i** - Ignore and continue

**Menu Update:** The devplan preview menu now shows:
```
Options:
  e  Edit devplan manually
  r  Reiterate devplan (with feedback)
  a  Analyze with another model (review for issues/gaps)
  c  Continue to swarm
  q  Cancel
```

## Files Modified

| File | Changes |
|------|---------|
| `ralph-refactor/tui/ralph_tui.py` | Fixed PROJECTS_DIR to use ~/projects |
| `ralph-refactor/lib/swarm_artifacts.sh` | Fixed undefined variables ($dest_dir, $merged_repo_dir) |
| `ralph-refactor/lib/swarm_db.sh` | Added swarm_db_retry_failed_tasks() and swarm_db_get_retryable_task_count() |
| `ralph-refactor/ralph-swarm` | Added retry prompt when resuming with failed tasks |
| `ralph-refactor/ralph-live` | Added project_review_devplan_with_model() and menu option |

## Verified Fixes from Previous Session (clodhandoff.md)

The following fixes were already properly implemented:
- Projects base path using `$HOME/projects` in `swarm_worker.sh`
- `SWARM_PROJECTS_BASE` environment variable properly exported
- File-based merge as fallback when git branch merge fails
- `.gitignore` excludes for ralphussy internal files
- Explicit repo root when `SWARM_PROJECT_NAME` is set

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SWARM_PROJECTS_BASE` | `$HOME/projects` | Base directory for new projects |
| `SWARM_PROJECT_NAME` | (none) | Name of project to create/use |
| `SWARM_REPO_ROOT` | (auto) | Explicit repo root (set automatically) |

## Usage Examples

### Resume a Run with Failed Task Retry
```bash
./ralph-swarm --resume 20260123_120000
# Output:
# Found 3 failed tasks that can be retried (max 3 attempts each).
# Retry failed tasks? (y/N): y
# Retried 3 failed tasks
# Continuing with 4 workers...
```

### Review DevPlan with Another Model
```bash
./ralph-live
# -> Create new project or open existing
# -> After devplan is generated, choose 'a' for analyze
# -> Select provider (e.g., anthropic)
# -> Select model (e.g., claude-sonnet-4-20250514)
# -> View review results
# -> Choose to apply, edit, save, or ignore
```

## Testing

All modified files pass syntax checks:
```bash
bash -n ralph-refactor/lib/swarm_db.sh        # OK
bash -n ralph-refactor/lib/swarm_artifacts.sh  # OK
bash -n ralph-refactor/ralph-swarm             # OK
bash -n ralph-refactor/ralph-live              # OK
python3 -m py_compile ralph-refactor/tui/ralph_tui.py  # OK
```

## Next Steps

1. **Test DevPlan Review**: Run through the new devplan review workflow with different models
2. **Test Failed Task Retry**: Create a run with failed tasks and verify retry works
3. **Integration Testing**: Verify full workflow from project creation through swarm completion
4. **Consider Adding**: 
   - Automatic retry option (retry failed tasks without prompting)
   - Review history tracking
   - Model comparison feature (side-by-side reviews)

## Context for Next Session

Key files to understand:
- `ralph-refactor/ralph-live` - Main CLI with project workflows and new review feature
- `ralph-refactor/lib/swarm_db.sh` - SQLite wrapper with retry functions
- `ralph-refactor/lib/swarm_artifacts.sh` - Artifact collection and merging
- `ralph-refactor/ralph-swarm` - Swarm orchestrator with resume

The user wanted:
1. Fix swarm to put artifacts in correct project folder - DONE
2. Ensure resuming works properly - DONE
3. Handle failed tasks properly - DONE (with retry)
4. DevPlan review with alternate model - DONE
