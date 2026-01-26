Swarm Dashboard2 Handoff
=======================

What I delivered
- A React-based OpenTUI successor to the original dashboard named `swarm-dashboard2`.
- Live TUI that reads the same swarm DB and renders scrollable panes for Actions, Tasks, Resources, Workers and a Console log.
- A root launcher script `run-swarm-dashboard2.sh` with the same DB discovery heuristics as the original `swarm-dashboard` launcher.
- **Full scrolling support**: Users can scroll through all content using arrow keys (per-pane) or Shift+arrows (global dashboard scroll).
- **Dynamic sizing**: Panes grow based on content size rather than fixed percentages, so all tasks/logs are accessible.
- **Detail views**: Press Enter/Space on a task or worker to see full details in an overlay panel.

Quick start (interactive terminal required)
1. Make launcher executable (one-time):
   - `chmod +x run-swarm-dashboard2.sh`
2. Run the dashboard from the repository root:
   - `./run-swarm-dashboard2.sh`
   - (Alternative) `bun swarm-dashboard2/src/index.ts`
3. If your environment blocks TTY detection for debugging, you may run:
   - `ALLOW_NO_TTY=1 ./run-swarm-dashboard2.sh` (not recommended for normal use).

What the launcher does
- Prints which DB it chose: `Using swarm DB at: <path>/swarm.db`.
- Prefers source-mode (runs `swarm-dashboard2/src/index.ts`) so local edits are used during development.
- Uses the same DB candidate scoring (heartbeat, in_progress count, started_at) as `swarm-dashboard/run.sh`.

Keyboard controls (implemented)
- `Tab` — cycle focused pane (order: tasks → actions → workers → console).
- `Up` / `Down` — scroll focused pane by one line.
- `PageUp` / `PageDown` — scroll focused pane by 10 lines.
- `Shift+Up` / `Shift+Down` — scroll the entire dashboard (global scroll).
- `Shift+PageUp` / `Shift+PageDown` — scroll entire dashboard by 10 lines.
- `Enter` / `Space` — open detail view for selected task or worker.
- `Escape` / `q` (in detail view) — close detail view.
- `r` — manual refresh (UI auto-polls every ~2s).
- `q` or `Ctrl-C` — quit; renderer now traps signals and restores the terminal.

Troubleshooting (if terminal appears garbled or stuck)
- The app uses the terminal alternate screen and turns off local echo; if you see only a blank screen or the alternate screen remains after exit:
  1. Try `Ctrl-C` or press `q`.
  2. From another terminal run:
     - `tput rmcup || true`
     - `stty echo || true`
     - `reset`
- I added signal handlers in `swarm-dashboard2/src/index.ts` to restore state on SIGINT/SIGTERM and unhandled errors, but older runs may leave the terminal altered.

Implementation notes
- UI: `swarm-dashboard2/src/index.ts` is the React OpenTUI entry. It uses `scrollbox` components for scrollable panes and polls the DB every 2s for live updates.
- Scrolling: The main content is wrapped in a `scrollbox` with id `main-scroll`. Individual panes (tasks, actions, workers, console) each have their own scrollbox. Arrow keys scroll the focused pane; Shift+arrows scroll the entire dashboard.
- Dynamic sizing: Pane heights are calculated based on content (e.g., `Math.max(20, tasks.length + 5)`) rather than fixed percentages, ensuring all content is accessible.
- Console: Shows all logs (previously limited to 15) with 120-character line width.
- DB: the original compiled DB helper is re-used. A small wrapper `swarm-dashboard2/src/database-bun.js` exists to aid resolution; the app loads `../../swarm-dashboard/dist/database-bun.js` at runtime.
- Launcher: `run-swarm-dashboard2.sh` lives in the project root and uses the same DB discovery heuristics as the original dashboard launcher.

Files added/modified
- `swarm-dashboard2/src/index.ts` — React + OpenTUI app (live polling, scrollboxes, keyboard handlers).
- `swarm-dashboard2/src/dashboard.ts` — original class-based copy (left for reference).
- `swarm-dashboard2/src/database-bun.js` — small wrapper to re-export the compiled DB helper.
- `swarm-dashboard2/README.md` — comprehensive documentation for dashboard2.
- `run-swarm-dashboard2.sh` — root launcher for `swarm-dashboard2`.

Known issues / limitations
1. ~~Focus visual polish: the focused pane is functional, but border/title color could be clearer — will improve.~~ **FIXED**
2. ~~Scroll persistence: scroll offsets are applied programmatically, but persistence across updates will be hardened.~~ **FIXED**
3. ~~Detail view: full-task and full-worker detail view (open on Enter/Space) is not yet implemented.~~ **FIXED**
4. Type/ts diagnostics: TypeScript language-server shows type warnings for some dynamic imports and missing types for `react` in this workspace; these do not prevent running with Bun but should be fixed if you plan to build a typed package.

Recommended next steps (pick one)
1. ~~Finish polish: implement persistent scroll offsets, clear visual focus indicator, and a detail panel for tasks/workers (I can implement now).~~ **DONE**
2. ~~Add a README and package.json scripts for `swarm-dashboard2`, and add type declarations or adjust `tsconfig` to eliminate LSP warnings.~~ **README DONE** (package.json scripts and type declarations still pending)
3. Write tests and a small demo dataset runner for CI validation.

If you want me to proceed with option 1, say "go" and I will implement detail view, persistent scroll, improved focus visuals, and verify live interactions end-to-end.

Contact / context
- Original dashboard left unchanged in `swarm-dashboard/`.
- I ran the app and iterated until it produced a stable interactive prototype (logged large runs during tests). If you see anything odd paste the console output lines starting with `Candidate DB:` and I'll refine DB selection.

-- Gippity

---

Devussy / Basic DevPlan Parser Update
-------------------------------------

What I did
- Improved robustness of the basic devplan parser so it tolerates LLM output variations and prefers an explicit JSON block when present.
- Added multiple group-header regexes (bracketed, inline, simple), normalised file-pattern separators, and defensive guards for missing phase/group state.
- Added a JSON fenced-block fallback: if the LLM emits a ```json { ... } ``` block the parser will parse that directly into phases, task_groups and steps.

Files changed
- `devussyout/src/pipeline/basic_devplan.py` — added JSON-block parsing, new group header patterns, safer phase/group handling and normalization of file patterns.

Why this change
- The LLM sometimes emits group/phase headers in different formats (e.g. `[files: ...]`, `files: ...` or plain headers) which the original strict regexes missed and caused a coarse single-task devplan.
- A machine-readable JSON block (when present) is much more reliable to parse; the parser now prefers it if available.

How to reproduce / verify
- Regenerate the devplan so the pipeline writes the LLM response: `.devussy_state/last_devplan_response.txt` will be created.
- Inspect the raw response:
  - `cat .devussy_state/last_devplan_response.txt | sed -n '1,240p'`
- If you want to test the parser locally, run the devussy generator (same command you usually use) and confirm `.devussy_state/last_devplan_response.txt` exists, then re-run the pipeline that consumes it.
- Run the swarm and verify multiple task groups spawn: (example)
  - `cd ~/projects/hello-world-python`
  - `export RALPH_PROVIDER="zai-coding-plan"`
  - `export RALPH_MODEL="glm-4.7"`
  - `/home/mojo/projects/ralphussy/ralph-refactor/ralph-swarm --devplan devplan.md --project hello-world-python --workers 2`

Quick debug notes
- If the LLM includes a fenced JSON block (```json ... ```), the parser will use it. If not, it falls back to regex parsing with several tolerant patterns.
- Step numbering is defensive: if a phase number is missing the parser falls back to `1` to avoid crashes.

Next recommended steps (pick one)
1) Run a generation, inspect `.devussy_state/last_devplan_response.txt`, and confirm the parser extracted multiple groups (I can do this and paste the parsed DevPlan). (Recommended)
2) Update `devussyout/templates/basic_devplan.jinja` to instruct the LLM to append an explicit JSON block (machine-readable) at the end of its response — this is the most robust long-term fix.
3) Add unit tests that feed representative LLM outputs (including the saved `last_devplan_response.txt`) to the parser and assert the DevPlan structure.

If you want me to proceed with one of those, say which (1–3) and I'll run it.

Recent changes (2026-01-26)
---------------------------------
- Committed and pushed a parser and docs update: `feat(devussy): robustly extract LLM text from opencode JSON logs and improve devplan parsing; document swarm-dashboard2` (commit `db3f60f` on `origin/main`).
- Files changed in that commit: `devussyout/src/pipeline/basic_devplan.py`, `swarm-dashboard/README.md`.
- Notes: the devplan parser now extracts LLM text from Opencode JSON log entries and prefers fenced JSON blocks when present; `swarm-dashboard` docs were updated to reference `swarm-dashboard2`.

Recommended verification steps
---------------------------------
1. Run unit/integration tests: `./ralph-refactor/tests/run_all_tests.sh` or project-specific suites.
2. Inspect the parser behavior with a recent devplan response: `cat .devussy_state/last_devplan_response.txt | sed -n '1,240p'` and re-run the generator.
3. Check CI on GitHub to ensure there are no regressions after the push.
