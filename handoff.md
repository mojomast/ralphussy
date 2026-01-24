# Repo Handoff (2026-01-24)

## What Changed

- Implemented the last 2 items in `RALPH_IMPROVEMENTS.md`:
  - Devplan task batching lookahead optimization (removes O(n^2) awk scanning).
  - Refactored duplicated OpenCode execution logic into a shared helper.

## Key Implementation Notes

- Shared OpenCode executor lives in `ralph-refactor/lib/core.sh` as `_ralph_execute_opencode`.
  - It prints the same UX (API request/response, filtered stream, token + cost line).
  - It stores results in globals:
    - `RALPH_LAST_TEXT_OUTPUT`
    - `RALPH_LAST_TOOLS_USED`
    - `RALPH_LAST_DURATION`
    - `RALPH_LAST_TOTAL_TOKENS`
    - `RALPH_LAST_COST`

- Call sites updated:
  - `ralph-refactor/ralph` `run_iteration()` now delegates to `_ralph_execute_opencode`.
  - `ralph-refactor/lib/devplan.sh` `run_devplan_iteration()` now delegates as well.

- Devplan batching optimization:
  - `ralph-refactor/ralph` devplan loop now pre-parses all pending tasks once via `mapfile` + `awk`.
  - Lookahead batching uses array indexing (`lookahead_index`) instead of repeated awk scans.
  - Index advancement uses `current_task_index += batch_count` so batched tasks are skipped.

## How To Validate

- Syntax:
  - `bash -n ralph-refactor/ralph`
  - `bash -n ralph-refactor/lib/core.sh`
  - `bash -n ralph-refactor/lib/devplan.sh`

- Smoke tests:
  - `./ralph2 "echo test" --max-iterations 1`
  - `./ralph2 --devplan ralph-refactor/tests/devplan_complex.md --max-iterations 5`

## Watch Outs / Follow-ups

- The devplan pre-parse includes both `[ ]` and `⏳` tasks (but skips `[✅]` and `[🔄]`).
- `_ralph_execute_opencode` relies on `start_monitor`/`stop_monitor` being in scope (sourced by `ralph-refactor/ralph`). Avoid calling it from contexts that don't source `monitor.sh`.
