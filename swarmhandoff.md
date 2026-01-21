Swarm Handoff
=============

What I delivered
- Interactive CLI for starting and inspecting swarm runs: `ralph-refactor/ralph-swarm` now supports `--interactive` (`-i`) and `--inspect` to simplify common workflows.
- Artifact collection: per-run artifacts are consolidated under `RALPH_DIR/swarm/runs/<RUN_ID>/artifacts` (configurable via `SWARM_ARTIFACTS_DIR`). See `ralph-refactor/lib/swarm_artifacts.sh`.
- Per-worker isolation: workers use per-worker git worktrees under `RALPH_DIR/swarm/runs/<RUN_ID>/worker-<N>/repo` and keep logs under `.../worker-<N>/logs`.
- Tests and smoke test: `ralph-refactor/tests/test_swarm.sh` includes unit tests for DB/locks/priority and a smoke test that validates artifact collection.
- Commit: changes committed in commit `c2badc3` on branch `master` (no remote push performed).

Important files (quick map)
- CLI orchestrator: `ralph-refactor/ralph-swarm`
- Artifact collector: `ralph-refactor/lib/swarm_artifacts.sh`
- Worker runtime: `ralph-refactor/lib/swarm_worker.sh`
- Git helpers: `ralph-refactor/lib/swarm_git.sh`
- DB layer: `ralph-refactor/lib/swarm_db.sh`
- Analyzer: `ralph-refactor/lib/swarm_analyzer.sh`
- Tests: `ralph-refactor/tests/test_swarm.sh`

How to run (examples)
- Interactive start (recommended for ad-hoc runs):
  - `./ralph-refactor/ralph-swarm --interactive --devplan path/to/devplan.md`
  - Prompts: worker count, timeout, provider, model, artifact collection, artifacts folder.
- Non-interactive start with artifacts:
  - `SWARM_COLLECT_ARTIFACTS=true ./ralph-refactor/ralph-swarm --devplan path/to/devplan.md --workers 4`
- Inspect latest or a specific run:
  - `./ralph-refactor/ralph-swarm --inspect` (shows latest run status and artifacts path)
  - `./ralph-refactor/ralph-swarm --inspect <RUN_ID>`

Environment variables and flags
- `RALPH_DIR` - run state root (default: `~/.ralph`). Tests use a temp directory.
- `RALPH_LLM_PROVIDER` / `RALPH_LLM_MODEL` - provider and model passed to the analyzer/worker (`opencode` CLI).
- `SWARM_AUTO_MERGE` (default `false`) - auto-merge worker branches at the end.
- `SWARM_PUSH_AFTER_MERGE` (default `false`) - push after merge if enabled.
- `SWARM_COLLECT_ARTIFACTS` (env or `--collect-artifacts`) - enable artifact collection.
- `SWARM_ARTIFACTS_DIR` - override artifacts destination; supports `%RUN_ID%` substitution; relative paths are resolved under the run directory.

Artifacts layout
- Per-run artifacts live at: `RALPH_DIR/swarm/runs/<RUN_ID>/artifacts/`
- Per-worker artifact folder: `.../artifacts/worker-<N>/` contains:
  - repository snapshot (no `.git`), `commits.txt`, `files.txt`
  - worker logs: `logs/*`

Testing and verification
- Run the suite: `./ralph-refactor/tests/test_swarm.sh` — all tests passed locally when these changes were committed.
- Quick smoke: run one worker with artifacts enabled and verify `RALPH_DIR/swarm/runs/<RUN_ID>/artifacts` exists.

Pending/optional improvements
1) Input validation for interactive fields (ensure integers for workers/timeout).
2) CLI presets or a config file to avoid repeated prompts for common runs.
3) `inspect-run.sh` wrapper that opens the artifacts folder in a file browser.
4) Artifact retention/cleanup policy and optional compression to save space.

If you want me to continue
- I can add any of the Pending/optional items, push the commit to a remote, or add richer summaries inside artifacts (diffs, archives, size limits). Say which item number to do next or request a push.
