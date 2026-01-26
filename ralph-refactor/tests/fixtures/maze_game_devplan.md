# Simple Python Maze Game DevPlan

A minimal devplan for implementing a small CLI Python maze game. Breaks the work into small, testable tasks so the swarm worker can complete them iteratively.

- [ ] Initialize project: create `maze_game/` package, `pyproject.toml` or `setup.cfg`, and a `README.md` with run instructions.
- [ ] Implement `maze.py`: create a maze generator using a simple algorithm (recursive backtracker or randomized Prim) and expose `generate(width, height)` returning a grid structure.
- [ ] Implement `player.py`: player state and movement logic (position, move functions, collision detection with walls).
- [ ] Implement `renderer.py`: simple CLI renderer that prints the maze and player using ASCII (e.g. `#` walls, space for paths, `@` for player).
- [ ] Implement `main.py`: CLI entrypoint to run the game loop, accept WASD/arrow keys (or single-character input), and allow restarting/exiting.
- [ ] Add tests: unit tests for `generate()` (correct dimensions, connectivity) and for `player` movement and collision.
- [ ] Add a `run.sh` or `Makefile` target: `make run` or `./run.sh` to start the game.
- [ ] Write `README.md` gameplay instructions and developer notes (how to run tests, how to run the game locally).
- [ ] Add minimal CI/test command (e.g. `python -m pytest`) to the project.
- [ ] Finalize: ensure the package runs via `python -m maze_game` and the assistant prints the completion promise when finished.

When finished, include the completion marker exactly as a single line in the output:

<promise>COMPLETE</promise>
