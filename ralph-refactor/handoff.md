# Ralph Refactor Handoff

## Project State
We have significantly refactored the Ralph TUI (`ralph-refactor/tui/ralph_tui.py`) to improve the user experience and visibility into swarm operations. The backend logic for the swarm remains largely in shell scripts (`ralph-refactor/lib/`), but the TUI is now a robust Python Textual application.

## Recent Changes
1.  **Interactive Worker Pane:**
    *   Workers are now displayed in a `DataTable` that includes the specific task description they are working on (truncated).
    *   Clicking a worker row opens a `WorkerLogScreen` modal that tails the logs for that specific worker in real-time.
    *   Added `current_task_text` to the worker query by joining the `tasks` table in `SwarmDBReader`.

2.  **File Management:**
    *   **Browser:** Replaced the sidebar file tree with a full-screen modal `FileBrowserScreen` for better browsing.
    *   **Editor:** Implemented a `FileEditorScreen` that allows basic editing of files directly within the TUI.

3.  **Notifications & Progress:**
    *   **Notifications:** The TUI now detects when tasks complete or fail and posts a notification message directly to the main `ChatPane`.
    *   **Progress Bar:** The progress pane is now a compact, single-line docked bar at the bottom, saving screen real estate. Detailed task logs were removed from this pane in favor of the main chat notifications.

4.  **Settings & Configuration:**
    *   **Dynamic Models:** The settings screen now dynamically fetches available models using `opencode models`.
    *   **Settings Screen:** Updated to use `Select` widgets for model selection.

## Key Files
*   `ralph-refactor/tui/ralph_tui.py`: The main TUI application. Contains all screen definitions (Chat, Workers, Files, Settings) and the main event loop.
*   `ralph-refactor/lib/swarm_db.sh`: The shell-based SQLite wrapper. *Note: We partially replicated reading logic in Python within `ralph_tui.py`'s `SwarmDBReader` class.*
*   `ralph-refactor/lib/swarm_worker.sh`: The worker agent logic.

## Known Issues / TODOs
*   **Performance:** `refresh_status_async` polls the DB every 2 seconds. For very large task histories, fetching all tasks to check for status changes might become slow. Consider adding a `last_updated` filter or limiting the query if performance degrades.
*   **Editor:** The `FileEditorScreen` is basic. It lacks syntax highlighting *editing* (though it has highlighting for *viewing* if `TextArea` supports it sufficiently) and advanced features like search/replace.
*   **Shell Integration:** The TUI currently relies on `subprocess` to call `ralph` shell scripts. Ensure the path resolution in `ralph_tui.py` (specifically `RALPH_REFACTOR_DIR`) stays aligned with the actual directory structure.

## How to Run
1.  Ensure you are in the `ralph-refactor` directory.
2.  Run the TUI:
    ```bash
    python3 tui/ralph_tui.py
    ```
3.  Inside the TUI, use `/help` to see commands. Use `/swarm start ...` to kick off a run.
