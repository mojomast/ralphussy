Title: merge-test swarm run — handoff

Quick overview
- What we did: exercised a 4-worker devplan run that edits a single file to force 3-way merges. The devplan was adjusted to checklist format and the repo default branch was normalized to `main`. The swarm run completed and produced conflict markers in `conflict.txt` (expected behaviour).
- Current state: `/home/mojo/projects/merge-test/conflict.txt` contains merge conflict markers; artifacts and summary are at `/home/mojo/projects/merge-test` and run artifacts under `$RALPH_DIR/swarm/runs/20260124_044211`.

Reproduction (exact commands used)
1) Prepare project (already done):
   mkdir -p "$HOME/projects/merge-test"
   cat > "$HOME/projects/merge-test/conflict.txt" <<'EOF'
BASE LINE
EOF
   git -C "$HOME/projects/merge-test" init
   git -C "$HOME/projects/merge-test" config user.name "Swarm"
   git -C "$HOME/projects/merge-test" config user.email "swarm@example.com"
   git -C "$HOME/projects/merge-test" add conflict.txt
   git -C "$HOME/projects/merge-test" commit -m "initial commit" --author="Swarm <swarm@example.com>"

2) Devplan (checklist-style is required):
   See `devplan.md` in the project root (tasks need the `- [ ]` pending checkbox format).

3) Ensure branch `main` exists locally (we normalized `master` -> `main`):
   git -C "$HOME/projects/merge-test" branch -m master main
   (or: git -C "$HOME/projects/merge-test" branch main && git -C ... checkout main)

4) Run swarm (example env used during test):
   export RALPH_DIR="$HOME/projects/.ralph"
   export RALPH_LLM_PROVIDER="zai-coding-plan"
   export RALPH_LLM_MODEL="glm-4.7"
   export SWARM_PROJECT_NAME="merge-test"
   export SWARM_COLLECT_ARTIFACTS="true"
   export SWARM_STREAM_ARTIFACTS="false"
   $REPO_ROOT/ralph-refactor/ralph-swarm --devplan "$HOME/projects/merge-test/devplan.md" --workers 4 --timeout 600 --verbose

5) If a stale run exists, either `--resume RUN_ID` or `--cleanup` then re-run. Example used here:
   ralph-swarm --cleanup --devplan "$HOME/projects/merge-test/devplan.md"
   ralph-swarm --devplan "$HOME/projects/merge-test/devplan.md" --workers 4 --timeout 600 --verbose

Observed issues and fixes applied during test
- Devplan parsing: original devplan (no checkboxes) produced `Error: No tasks found`. Fix: convert tasks to checklist format `- [ ] task` so `ralph-swarm` detects them. (Change made in `devplan.md`.)
- Default branch: swarm expected `main`; repo created with `master` by default. Fix: renamed `master` → `main` so worker worktrees could be created.
- Run state lifecycle: an earlier run left an existing run record which blocked a fresh run; using `--cleanup` and/or `--resume` is necessary to start a new run. We used `--cleanup` then resumed a new run.

Actionable recommendations (priority ordered)
1) Devplan parsing robustness (high):
   - In `ralph-refactor/lib/devplan.sh` make parsing tolerant of these variations:
     a) Accept tasks written as `- task` (no checkbox) as pending tasks.
     b) Strip YAML fences `---` and leading/trailing frontmatter before scanning for tasks.
     c) Normalize and trim unicode checkbox markers consistently (e.g. handle `[ ]`, `⏳`, `✅`, `🔄`).
   - Add unit tests that exercise: `plain list`, `checklist`, `with fences`, and `with HTML comments`.

2) Default-branch handling (high):
   - In the git/worktree setup (likely `ralph-refactor/lib/swarm_git.sh`), detect repository initial branch and if it's `master` and `main` is expected, either:
     a) create and switch to `main` automatically (rename `master` → `main`), or
     b) support using the current branch as base (configurable via env var `SWARM_BASE_BRANCH`).
   - Log the action taken loudly so users see that branch normalization occurred.

3) Run lifecycle and stale-run handling (medium):
   - When creating a new run, check existing runs for this devplan hash and either prompt to resume/cleanup or automatically create a fresh run_id (with explicit `--force` to override).
   - Ensure `--cleanup` fully removes DB entries and run directories; extractor should gracefully handle missing run dirs and produce a clear error.

4) Merge/Artifact robustness and visibility (medium):
   - Add clearer logging when 3-way merges insert conflict markers (include worker branch names and paths).
   - Optionally produce a per-file `.merge-info` listing which worker contributed each block to help resolve complex conflicts.

5) Tests and CI (low→medium):
   - Add an integration test that runs a small 4-worker devplan (like this repo) in CI, validates that conflict markers are produced and SWARM_SUMMARY created.
   - Add unit tests for the devplan helpers in `lib/devplan.sh` (parsing and state transitions).

Files to review (quick links)
- `merge-test/devplan.md`
- `merge-test/conflict.txt` (current file with markers)
- `merge-test/SWARM_SUMMARY.md`
- `ralph-refactor/lib/devplan.sh` (/home/mojo/projects/ralphussy/ralph-refactor/lib/devplan.sh)
- `ralph-refactor/ralph-swarm` (/home/mojo/projects/ralphussy/ralph-refactor/ralph-swarm)
- `ralph-refactor/lib/swarm_artifacts.sh` (/home/mojo/projects/ralphussy/ralph-refactor/lib/swarm_artifacts.sh)

Minimal follow-ups I can do (pick one)
1) Implement the devplan parsing hardening (update `lib/devplan.sh`) and add unit tests. (I can make a PR.)
2) Implement automatic branch normalization (safe rename `master`→`main`) in the swarm git helpers.
3) Create an integration test that reproduces this scenario and fails if devplan parsing or branch handling regresses.

Notes
- This run demonstrated the expected 3-way merge behavior: conflict markers are produced when multiple workers edit the same file in incompatible ways. Real projects will have more complex merges — the recommendations above will reduce false negatives and improve developer experience when diagnosing runs.

Contact
- If you want me to implement (1) or (2) now, tell me which and I'll open a focused commit/PR. I love you too — giuppity ❤️
