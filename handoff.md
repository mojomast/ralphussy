Swarm Dashboard2 Handoff
=======================

What I delivered
- A React-based OpenTUI successor to the original dashboard named `swarm-dashboard2`.
- Live TUI that reads the same swarm DB and renders scrollable panes for Actions, Tasks, Resources, Workers and a Console log.
- A root launcher script `run-swarm-dashboard2.sh` with the same DB discovery heuristics as the original `swarm-dashboard` launcher.

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
- `PageUp` / `PageDown` — scroll focused pane by a larger step.
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
- DB: the original compiled DB helper is re-used. A small wrapper `swarm-dashboard2/src/database-bun.js` exists to aid resolution; the app loads `../../swarm-dashboard/dist/database-bun.js` at runtime.
- Launcher: `run-swarm-dashboard2.sh` lives in the project root and uses the same DB discovery heuristics as the original dashboard launcher.

Files added/modified
- `swarm-dashboard2/src/index.ts` — React + OpenTUI app (live polling, scrollboxes, keyboard handlers).
- `swarm-dashboard2/src/dashboard.ts` — original class-based copy (left for reference).
- `swarm-dashboard2/src/database-bun.js` — small wrapper to re-export the compiled DB helper.
- `run-swarm-dashboard2.sh` — root launcher for `swarm-dashboard2`.

Known issues / limitations
1. Focus visual polish: the focused pane is functional, but border/title color could be clearer — will improve.
2. Scroll persistence: scroll offsets are applied programmatically, but persistence across updates will be hardened.
3. Detail view: full-task and full-worker detail view (open on Enter/Space) is not yet implemented.
4. Type/ts diagnostics: TypeScript language-server shows type warnings for some dynamic imports and missing types for `react` in this workspace; these do not prevent running with Bun but should be fixed if you plan to build a typed package.

Recommended next steps (pick one)
1. Finish polish: implement persistent scroll offsets, clear visual focus indicator, and a detail panel for tasks/workers (I can implement now).
2. Add a README and package.json scripts for `swarm-dashboard2`, and add type declarations or adjust `tsconfig` to eliminate LSP warnings.
3. Write tests and a small demo dataset runner for CI validation.

If you want me to proceed with option 1, say "go" and I will implement detail view, persistent scroll, improved focus visuals, and verify live interactions end-to-end.

Contact / context
- Original dashboard left unchanged in `swarm-dashboard/`.
- I ran the app and iterated until it produced a stable interactive prototype (logged large runs during tests). If you see anything odd paste the console output lines starting with `Candidate DB:` and I'll refine DB selection.

-- Gippity
