Dashboard Handoff
=================

> **Note**: A newer dashboard (`swarm-dashboard2`) is now available with full scrolling support (including global scroll with Shift+arrows), dynamic sizing, and detail views. See `handoff.md` or `swarm-dashboard2/README.md` for details. Run with `./run-swarm-dashboard2.sh`.

What I changed (summary)
- Fixed the accidental import in `swarm-dashboard/src/index.ts` to import `./dashboard.js` so Bun/Node can run the src files without TypeScript import-extension errors.
- Improved launcher DB selection in `swarm-dashboard/run.sh`:
  - When multiple `.ralph` locations exist the launcher now compares candidates and prefers the DB with the most recent worker heartbeat (strong signal of an active swarm). It also prints candidate metrics for debugging.
- Made the dashboard resilient to stale worker records:
  - `swarm-dashboard/src/dashboard.ts` now cross-checks the `tasks` table and maps `in_progress` tasks to workers when `workers.current_task_id` is not populated.
- Reworked TUI panes and scrolling:
  - Actions pane now shows a live activity stream (recent log lines) pulled from run logs (`getRecentLogs`).
  - Workers pane renders stable single-line entries that include worker_num, status icon, status, branch, task id and first line of task text.
  - Implemented keyboard focus and simple scrolling: Tab cycles panes; Up/Down/PageUp/PageDown scroll the focused pane. Scrolling is implemented by rendering a window slice (page) to avoid garbling.

Why these changes
- The dashboard previously attached to a stale `projects/.ralph` DB or used an older compiled bundle; the index import + run.sh fixes make it easier to run the live source and pick the active DB.
- Workers sometimes had `current_task_id` empty while `tasks.worker_id` was set — showing task ownership required joining both tables.
- Scrolling previously manipulated live node lists and caused garbled layout; rendering a stable slice avoids that.

How to run and verify
- cd `swarm-dashboard`
- ./run.sh
- Confirm the script prints which DB it selected: `Using swarm DB at: <path>/swarm.db` and candidate metrics lines.
- In the TUI:
  - Press `Tab` to cycle focus across panes (tasks, actions, workers, console).
  - Use `Up/Down/PageUp/PageDown` to scroll the focused pane.
  - Actions pane should display recent log lines; Workers pane should show task name (first line) and T# assignment.

Next recommended steps (pick one)
1) Rebuild `dist/` so compiled bundles match `src/` (helpful for RUN_DIST deployments).
2) Improve wrapping and full-task detail view: measure pane width and wrap task descriptions cleanly; add a detail panel that shows the full task text when a task or worker is selected.
3) Expose the DB path and focused pane clearly in the header (visual) and add a small status line showing how many live logs were read and the time of last heartbeat.

Files touched
- `swarm-dashboard/src/index.ts`
- `swarm-dashboard/run.sh`
- `swarm-dashboard/src/dashboard.ts`

If you want me to proceed: tell me a choice (1-3) above or paste the `Candidate DB:` lines you see when starting `./run.sh` and I will refine the DB selection heuristics or implement the chosen enhancement.
