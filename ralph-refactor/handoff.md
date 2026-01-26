Handoff: Maze Game Swarm Run

What we did
- Ran a devplan to implement a small Python terminal maze game using the swarm runner; preserved the worker outputs for inspection.
- Extracted the worker's generated project into the projects folder at `/home/mojo/projects/maze-game-20260125_231129` so artifacts are directly available.
- Updated the orchestrator so completed swarm runs automatically call `swarm_extract_merged_artifacts` to publish artifacts under `${SWARM_PROJECTS_BASE:-$HOME/projects}`.
- Added a small safety marker on extraction: `.ralph_project_marker` is created by the extractor in destination folders so future merges treat the folder as an external project (prevents mixing internal files).

What the extracted project contains
- Location: `/home/mojo/projects/maze-game-20260125_231129`
- Package: `maze_game/` with these primary modules:
  - `maze.py` — maze generator (recursive backtracker) and `generate(width, height)` → ASCII grid
  - `player.py` — `Player` model, movement, collision detection and helpers
  - `renderer.py` — ASCII rendering; marks player with `@`
  - `game.py` — CLI game loop (WASD/arrow keys, restart, quit) and entry logic
  - `__main__.py` — program entrypoint used by `python -m maze_game` and prints `<promise>COMPLETE</promise>` on exit
- Project metadata: `pyproject.toml`; small `run.sh` wrapper was added.

Gaps and caveats we found
- README mentions `main.py`, `Makefile`, and tests, but none of these were present in the extracted tree — the real entry is `maze_game/__main__.py` so `python -m maze_game` works.
- No test files or CI workflows were produced; the README claims pytest-based tests that are not present.
- The project copied manually earlier did not include a `.ralph_project_marker`; the extraction routine now writes that marker but older artifact directories may need it added.

Immediate next actions (pick one)
1) Add a test suite and run verification: I will add `tests/test_maze.py` (generate/connectivity/player movement) and run `pytest` to validate behavior. (Recommended)
2) Add CI and a `Makefile` (or `run.sh` improvements) and update README to accurately describe entrypoints.
3) Clean up and commit: create a branch in your projects repo (e.g. `feat/maze-game`) and commit a cleaned project with `.ralph_project_marker` and the test/CI additions.
4) Run an end-to-end swarm test with a new devplan to validate that artifacts are auto-extracted into `~/projects` at run completion.

How I can help next
- If you pick 1 I will implement tests and run them, then report failures/fixes.
- If you pick 2 I will scaffold CI (GitHub Actions) and a `Makefile` with `make run` and `make test` targets.
- If you pick 3 I will create the branch and commit the cleaned project, or open a PR if you want to push.
- If you pick 4 I will run a short devplan and watch extraction happen, then verify the resulting project dir.

Notes for operations
- Artifacts extraction respects `SWARM_PROJECTS_BASE` and `SWARM_ARTIFACTS_DIR`. If you want artifacts placed under a different path by default, set `export SWARM_PROJECTS_BASE=/path/to/projects` before running the swarm or pass `SWARM_ARTIFACTS_DIR` including `%RUN_ID%`.
- The extraction code attempts to avoid copying internal `ralph-*` files; if you see files filtered incorrectly tell me which ones and I will refine the heuristics.

File created: `ralph-refactor/handoff.md`
