# Swarm Artifact Extraction

## Overview

The `swarm_extract_merged_artifacts` function extracts completed swarm work into a projects directory.

## Usage

### List Available Runs
```bash
source ralph-refactor/lib/swarm_artifacts.sh
export RALPH_DIR="$HOME/.ralph"
swarm_list_runs
```

### Extract Artifacts from a Run
```bash
# Extract to ~/projects (default)
swarm_extract_merged_artifacts "RUN_ID"

# Extract to custom location
swarm_extract_merged_artifacts "RUN_ID" "/path/to/destination"
```

### What Gets Extracted

1. **Merged Repository** - Contains all files changed by workers in the run
   - Excludes base project files (only changes from swarm tasks)
   - Includes new files created by workers
   - Includes modified files from workers

2. **Summary Report** (SWARM_SUMMARY.md)
   - Run status (total/completed/failed/pending tasks)
   - List of completed tasks with timestamps
   - List of failed tasks with error messages
   - List of pending tasks
   - Git commits by worker
   - List of changed files in merged repo

### Example Output

```
Extracting merged artifacts for run: 20260123_002350
Destination: /home/mojo/projects/swarm-20260123_002350

=== Run Summary ===
Status: running
Total Tasks: 20
Completed: 17
Failed: 3
Pending: 0

Extracting changes from worker-2 (8 commits)...
Merged 1 worker repositories into: /home/mojo/projects/swarm-20260123_002350/merged-repo
Total files added/modified: 15

Summary report created: /home/mojo/projects/swarm-20260123_002350/SWARM_SUMMARY.md

=== Merged Repository Contents ===
/home/mojo/projects/swarm-20260123_002350/merged-repo/...
```

## How It Works

1. **Identifies completed commits** - Uses git merge-base to find commits made by workers
2. **Extracts only changed files** - Doesn't include entire base project history
3. **Merges across workers** - Combines changes from all workers into single repo
4. **Creates summary report** - Documents what was completed and what's missing

## Functions Available

- `swarm_list_runs` - List all swarm runs with status
- `swarm_collect_artifacts` - Original artifact collection (all files)
- `swarm_extract_merged_artifacts` - New extraction (only changes)
