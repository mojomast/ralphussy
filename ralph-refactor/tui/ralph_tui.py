#!/usr/bin/env python3
"""pyright: reportMissingImports=false, reportMissingModuleSource=false"""
"""
Ralph TUI - A Terminal User Interface for the Ralph AI Development Agent

This TUI provides:
- Chat terminal for interacting with Ralph
- Worker status pane showing swarm activity  
- Progress dashboard for task tracking
- File browser for project exploration
"""

import os
import sys
import json
import asyncio
import sqlite3
import subprocess
import re
from dataclasses import dataclass, asdict
from contextlib import suppress
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

from textual.app import App, ComposeResult  # type: ignore[import-not-found]
from textual.containers import Container, Horizontal, Vertical, ScrollableContainer  # type: ignore[import-not-found]
from textual.widgets import (  # type: ignore[import-not-found]
    Header,
    Footer,
    Static,
    Input,
    Button,
    Tree,
    DirectoryTree,
    Label,
    Log,
    ProgressBar,
    TabbedContent,
    TabPane,
    RichLog,
    DataTable,
    TextArea,
    Switch,
    Select,
)
from textual.binding import Binding  # type: ignore[import-not-found]
from textual.reactive import reactive  # type: ignore[import-not-found]
from textual.message import Message  # type: ignore[import-not-found]
from textual.timer import Timer  # type: ignore[import-not-found]
from textual.screen import ModalScreen, Screen  # type: ignore[import-not-found]
from textual import events  # type: ignore[import-not-found]
from rich.text import Text  # type: ignore[import-not-found]
from rich.panel import Panel  # type: ignore[import-not-found]
from rich.table import Table  # type: ignore[import-not-found]
from rich.syntax import Syntax  # type: ignore[import-not-found]
from rich.console import Console  # type: ignore[import-not-found]

try:
    from watchfiles import awatch  # type: ignore[import-not-found]
except Exception:  # pragma: no cover
    awatch = None

# Configuration
RALPH_DIR = Path(os.environ.get("RALPH_DIR", Path.home() / ".ralph"))
# Projects should be in ~/projects not ~/.ralph/projects
PROJECTS_DIR = Path(os.environ.get("SWARM_PROJECTS_BASE", Path.home() / "projects"))
SWARM_DB = RALPH_DIR / "swarm.db"
TUI_CONFIG_PATH = RALPH_DIR / "tui_settings.json"

# Get the script's directory for locating ralph-refactor
SCRIPT_DIR = Path(__file__).parent.resolve()
RALPH_REFACTOR_DIR = SCRIPT_DIR.parent
RALPH2_PATH = RALPH_REFACTOR_DIR.parent / "ralph2"


def get_opencode_models() -> List[str]:
    """Fetch available models from opencode."""
    try:
        result = subprocess.run(
            ["opencode", "models"], 
            capture_output=True, 
            text=True, 
            timeout=5
        )
        if result.returncode == 0:
            return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except Exception:
        pass
    # Fallback defaults
    return [
        "opencode/claude-sonnet-4-5",
        "opencode/claude-3-5-haiku",
        "opencode/gpt-5",
        "opencode/gpt-4.1",
        "opencode/gemini-3-pro",
        "opencode",
    ]



@dataclass
class TUIConfig:
    orchestration_provider: str = ""
    orchestration_model: str = ""
    orchestration_attach_url: str = ""

    swarm_provider: str = "opencode"
    swarm_model: str = "opencode/claude-sonnet-4-5"
    default_workers: int = 4

    swarm_auto_merge: bool = False
    swarm_auto_start: bool = False
    swarm_collect_artifacts: bool = True

    refresh_interval_sec: float = 2.0
    enable_file_watch: bool = True
    theme: str = "paper"  # paper | midnight

    def validate(self) -> None:
        if self.default_workers < 1:
            self.default_workers = 1
        if self.refresh_interval_sec < 0.5:
            self.refresh_interval_sec = 0.5
        if self.theme not in {"paper", "midnight"}:
            self.theme = "paper"


def load_tui_config(path: Path = TUI_CONFIG_PATH) -> TUIConfig:
    cfg = TUIConfig()
    if not path.exists():
        return cfg
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        for k, v in raw.items():
            if hasattr(cfg, k):
                setattr(cfg, k, v)
    except Exception:
        return cfg
    cfg.validate()
    return cfg


def save_tui_config(cfg: TUIConfig, path: Path = TUI_CONFIG_PATH) -> None:
    cfg.validate()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(cfg), indent=2, sort_keys=True) + "\n", encoding="utf-8")


    class FileEditorScreen(Screen):
        """Screen for editing files."""
        BINDINGS = [("escape", "cancel", "Cancel"), ("ctrl+s", "save", "Save")]

        def __init__(self, path: Path):
            super().__init__()
            self.path = path

        def compose(self) -> ComposeResult:
            yield Header()
            yield Container(
                Static(f"Editing: {self.path}", id="editor-header"),
                TextArea(self.path.read_text(encoding="utf-8", errors="replace"), id="editor-area", language="python"),
                Horizontal(
                    Button("Save", variant="primary", id="save"),
                    Button("Cancel", variant="error", id="cancel"),
                    id="editor-buttons"
                )
            )
            yield Footer()

        def on_button_pressed(self, event: Button.Pressed) -> None:
            if event.button.id == "save":
                self.action_save()
            elif event.button.id == "cancel":
                self.action_cancel()

        def action_save(self) -> None:
            content = self.query_one("#editor-area", TextArea).text
            try:
                self.path.write_text(content, encoding="utf-8")
                self.app.notify(f"Saved {self.path}")
                self.dismiss(True)
            except Exception as e:
                self.app.notify(f"Error saving: {e}", severity="error")

        def action_cancel(self) -> None:
            self.dismiss(False)

    class FileBrowserScreen(ModalScreen[Optional[Path]]):
        """Popup file browser."""
        DEFAULT_CSS = """
        FileBrowserScreen {
            align: center middle;
        }
        FileBrowserScreen #browser-container {
            width: 80%;
            height: 80%;
            border: solid $primary;
            background: $surface;
            layout: grid;
            grid-size: 2 1;
            grid-columns: 1fr 2fr;
        }
        FileBrowserScreen DirectoryTree {
            height: 100%;
            border-right: solid $primary;
        }
        FileBrowserScreen #preview-container {
            height: 100%;
            padding: 1;
        }
        FileBrowserScreen #file-preview {
            height: 1fr;
            border: solid $secondary;
        }
        FileBrowserScreen #browser-buttons {
            height: 3;
            dock: bottom;
            padding: 0 1;
        }
        """

        def __init__(self, root_path: Path):
            super().__init__()
            self.root_path = root_path
            self.selected_path: Optional[Path] = None

        def compose(self) -> ComposeResult:
            with Container(id="browser-container"):
                yield DirectoryTree(str(self.root_path), id="browser-tree")
                with Vertical(id="preview-container"):
                    yield Static("Select a file to preview/edit", id="file-info")
                    yield TextArea(read_only=True, id="file-preview")
                    with Horizontal(id="browser-buttons"):
                        yield Button("Edit", id="edit", disabled=True)
                        yield Button("Close", id="close", variant="error")

        def on_directory_tree_file_selected(self, event: DirectoryTree.FileSelected) -> None:
            self.selected_path = Path(event.path)
            info = self.query_one("#file-info", Static)
            info.update(f"Selected: {self.selected_path.name}")
            
            preview = self.query_one("#file-preview", TextArea)
            btn_edit = self.query_one("#edit", Button)
            
            try:
                content = self.selected_path.read_text(encoding="utf-8", errors="replace")
                preview.text = content
                btn_edit.disabled = False
            except Exception as e:
                preview.text = f"Error reading file: {e}"
                btn_edit.disabled = True

        def on_button_pressed(self, event: Button.Pressed) -> None:
            if event.button.id == "close":
                self.dismiss(None)
            elif event.button.id == "edit" and self.selected_path:
                self.app.push_screen(FileEditorScreen(self.selected_path))

class WorkerLogScreen(ModalScreen):
        """Screen to view logs for a specific worker."""
        DEFAULT_CSS = """
        WorkerLogScreen {
            align: center middle;
        }
        WorkerLogScreen #log-container {
            width: 90%;
            height: 90%;
            border: solid $primary;
            background: $surface;
        }
        WorkerLogScreen #log-header {
            height: 3;
            padding: 1;
            background: $primary;
            color: $text;
            text-style: bold;
        }
        WorkerLogScreen TextArea {
            height: 1fr;
        }
        WorkerLogScreen Button {
            dock: bottom;
            width: 100%;
        }
        """

        def __init__(self, run_id: str, worker_num: int):
            super().__init__()
            self.run_id = run_id
            self.worker_num = worker_num

        def compose(self) -> ComposeResult:
            with Container(id="log-container"):
                yield Static(f"Worker {self.worker_num} Logs (Run {self.run_id})", id="log-header")
                yield TextArea(read_only=True, id="worker-log-area")
                yield Button("Close", id="close")

        def on_mount(self) -> None:
            self.refresh_logs()
            self.set_interval(2.0, self.refresh_logs)

        def refresh_logs(self) -> None:
            log_area = self.query_one("#worker-log-area", TextArea)
            log_path = RALPH_DIR / "swarm" / "runs" / self.run_id / f"worker-{self.worker_num}" / "logs"
            
            if not log_path.exists():
                log_area.text = "No logs found."
                return

            # Find latest log file
            try:
                logs = list(log_path.glob("*.log"))
                if not logs:
                    log_area.text = "No log files found."
                    return
                
                latest_log = max(logs, key=lambda p: p.stat().st_mtime)
                content = latest_log.read_text(encoding="utf-8", errors="replace")
                # Keep scroll position if user scrolled up? 
                # For now just update text.
                current_text = log_area.text
                if content != current_text:
                    log_area.text = content
                    log_area.scroll_end(animate=False)
            except Exception as e:
                log_area.text = f"Error reading logs: {e}"

        def on_button_pressed(self, event: Button.Pressed) -> None:
            self.dismiss()


class SettingsScreen(ModalScreen[TUIConfig]):
    DEFAULT_CSS = """
    SettingsScreen {
        align: center middle;
    }
    SettingsScreen #settings {
        width: 90%;
        max-width: 120;
        height: 90%;
        max-height: 90%;
        border: solid $primary;
        background: $surface;
        padding: 1 2;
    }
    SettingsScreen #settings-body {
        height: 1fr;
        overflow-y: auto;
    }
    SettingsScreen .row {
        height: auto;
        margin: 0 0 1 0;
    }
    SettingsScreen .label {
        width: 28;
        content-align: left middle;
    }
    SettingsScreen Input, SettingsScreen Select {
        width: 1fr;
    }
    SettingsScreen #buttons {
        height: auto;
        margin-top: 1;
        content-align: right middle;
    }
    """

    def __init__(self, cfg: TUIConfig):
        super().__init__()
        self._cfg = cfg
        self._available_models = get_opencode_models()

    def compose(self) -> ComposeResult:
        with Container(id="settings"):
            yield Static("[bold]Settings[/bold]", classes="row")

            with ScrollableContainer(id="settings-body"):
                with Horizontal(classes="row"):
                    yield Static("Orchestrator provider", classes="label")
                    yield Input(value=self._cfg.orchestration_provider, id="orch-provider")
                with Horizontal(classes="row"):
                    yield Static("Orchestrator model", classes="label")
                    yield Input(value=self._cfg.orchestration_model, id="orch-model")
                with Horizontal(classes="row"):
                    yield Static("Orchestrator attach URL", classes="label")
                    yield Input(value=self._cfg.orchestration_attach_url, placeholder="http://localhost:4096", id="orch-attach")

                yield Static("[bold]Swarm[/bold]", classes="row")
                with Horizontal(classes="row"):
                    yield Static("Swarm provider", classes="label")
                    yield Input(value=self._cfg.swarm_provider, id="swarm-provider")
                with Horizontal(classes="row"):
                    yield Static("Swarm model", classes="label")
                    # Use Select for models
                    model_options = [(m, m) for m in self._available_models]
                    # Ensure current value is in options
                    if self._cfg.swarm_model not in self._available_models:
                         model_options.insert(0, (self._cfg.swarm_model, self._cfg.swarm_model))
                    
                    yield Select(model_options, value=self._cfg.swarm_model, id="swarm-model-select")
                with Horizontal(classes="row"):
                    yield Static("Default workers", classes="label")
                    yield Input(value=str(self._cfg.default_workers), id="swarm-workers")
                with Horizontal(classes="row"):
                    yield Static("Auto-merge", classes="label")
                    yield Switch(value=self._cfg.swarm_auto_merge, id="swarm-auto-merge")
                with Horizontal(classes="row"):
                    yield Static("Auto-start swarm", classes="label")
                    yield Switch(value=self._cfg.swarm_auto_start, id="swarm-auto-start")
                with Horizontal(classes="row"):
                    yield Static("Collect artifacts", classes="label")
                    yield Switch(value=self._cfg.swarm_collect_artifacts, id="swarm-artifacts")

                yield Static("[bold]UI[/bold]", classes="row")
                with Horizontal(classes="row"):
                    yield Static("Refresh interval (sec)", classes="label")
                    yield Input(value=str(self._cfg.refresh_interval_sec), id="ui-refresh")
                with Horizontal(classes="row"):
                    yield Static("File watching", classes="label")
                    yield Switch(value=self._cfg.enable_file_watch, id="ui-watch")
                with Horizontal(classes="row"):
                    yield Static("Theme (paper|midnight)", classes="label")
                    yield Input(value=self._cfg.theme, id="ui-theme")

            with Horizontal(id="buttons"):
                yield Button("Cancel", id="cancel")
                yield Button("Save", id="save", variant="primary")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
            return

        if event.button.id != "save":
            return

        chat_pane = self.app.query_one("#chat-pane", ChatPane)

        def _parse_int(raw: str, default: int) -> int:
            try:
                return int(raw)
            except Exception:
                return default

        def _parse_float(raw: str, default: float) -> float:
            try:
                return float(raw)
            except Exception:
                return default

        default_workers_raw = self.query_one("#swarm-workers", Input).value.strip()
        refresh_raw = self.query_one("#ui-refresh", Input).value.strip()
        default_workers = _parse_int(default_workers_raw or "4", 4)
        refresh_interval_sec = _parse_float(refresh_raw or "2.0", 2.0)
        
        # Get selected model
        swarm_model = self.query_one("#swarm-model-select", Select).value
        if not swarm_model:
             # Fallback if Select behaves oddly (though value shouldn't be None usually)
             swarm_model = "opencode/claude-sonnet-4-5"

        if default_workers_raw and str(default_workers) != default_workers_raw:
            chat_pane.log_message("Settings: invalid Default workers value; using 4", "error")
        if refresh_raw and str(refresh_interval_sec) != refresh_raw:
            chat_pane.log_message("Settings: invalid Refresh interval value; using 2.0", "error")

        cfg = TUIConfig(
            orchestration_provider=self.query_one("#orch-provider", Input).value.strip(),
            orchestration_model=self.query_one("#orch-model", Input).value.strip(),
            orchestration_attach_url=self.query_one("#orch-attach", Input).value.strip(),
            swarm_provider=self.query_one("#swarm-provider", Input).value.strip() or "opencode",
            swarm_model=str(swarm_model),
            default_workers=default_workers,
            swarm_auto_merge=self.query_one("#swarm-auto-merge", Switch).value,
            swarm_auto_start=self.query_one("#swarm-auto-start", Switch).value,
            swarm_collect_artifacts=self.query_one("#swarm-artifacts", Switch).value,
            refresh_interval_sec=refresh_interval_sec,
            enable_file_watch=self.query_one("#ui-watch", Switch).value,
            theme=self.query_one("#ui-theme", Input).value.strip() or "paper",
        )
        cfg.validate()
        self.dismiss(cfg)



class ProjectManager:
    """Manages projects and their structure."""
    
    def __init__(self, projects_dir: Path = PROJECTS_DIR):
        self.projects_dir = projects_dir
        self.projects_dir.mkdir(parents=True, exist_ok=True)
        self.current_project: Optional[Path] = None
    
    def create_project(self, name: str) -> Path:
        """Create a new project with proper structure."""
        project_dir = self.projects_dir / name
        project_dir.mkdir(parents=True, exist_ok=True)
        
        # Create standard structure
        (project_dir / "src").mkdir(exist_ok=True)
        (project_dir / "docs").mkdir(exist_ok=True)
        (project_dir / "artifacts").mkdir(exist_ok=True)
        (project_dir / "output").mkdir(exist_ok=True)
        
        # Initialize Git repository
        subprocess.run(["git", "init"], cwd=str(project_dir), check=True, stdout=subprocess.DEVNULL)
        
        # Create initial devplan
        devplan = project_dir / "devplan.md"
        if not devplan.exists():
            devplan.write_text(f"# {name} Development Plan\n\n## Tasks\n\n- [ ] Initial task\n")
        
        # Initial commit
        subprocess.run(["git", "add", "."], cwd=str(project_dir), check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=str(project_dir), check=True, stdout=subprocess.DEVNULL)
        
        self.current_project = project_dir
        return project_dir
    
    def list_projects(self) -> List[str]:
        """List all projects."""
        if not self.projects_dir.exists():
            return []
        return [d.name for d in self.projects_dir.iterdir() if d.is_dir()]
    
    def open_project(self, name: str) -> Optional[Path]:
        """Open an existing project."""
        project_dir = self.projects_dir / name
        if project_dir.exists():
            self.current_project = project_dir
            return project_dir
        return None
    
    def get_artifacts_dir(self) -> Optional[Path]:
        """Get artifacts directory for current project."""
        if self.current_project:
            return self.current_project / "artifacts"
        return None
    
    def get_output_dir(self) -> Optional[Path]:
        """Get output directory for current project."""
        if self.current_project:
            return self.current_project / "output"
        return None


class SwarmDBReader:
    """Reads swarm database for status updates."""
    
    def __init__(self, db_path: Path = SWARM_DB):
        self.db_path = db_path
    
    def get_connection(self) -> Optional[sqlite3.Connection]:
        """Get database connection if DB exists."""
        if not self.db_path.exists():
            return None
        try:
            conn = sqlite3.connect(str(self.db_path), timeout=10.0)
            conn.row_factory = sqlite3.Row
            return conn
        except sqlite3.Error:
            return None
    
    def get_latest_run(self) -> Optional[Dict[str, Any]]:
        """Get the latest swarm run."""
        conn = self.get_connection()
        if not conn:
            return None
        try:
            cursor = conn.execute(
                "SELECT * FROM swarm_runs ORDER BY id DESC LIMIT 1"
            )
            row = cursor.fetchone()
            if row:
                return dict(row)
            return None
        except sqlite3.Error:
            return None
        finally:
            conn.close()

    def get_run_info(self, run_id: str) -> Optional[Dict[str, Any]]:
        """Fetch a specific run by run_id (for reports/inspection)."""
        conn = self.get_connection()
        if not conn:
            return None
        try:
            cursor = conn.execute(
                "SELECT * FROM swarm_runs WHERE run_id = ? ORDER BY id DESC LIMIT 1",
                (run_id,),
            )
            row = cursor.fetchone()
            return dict(row) if row else None
        except sqlite3.Error:
            return None
        finally:
            conn.close()
    
    def get_run_workers(self, run_id: str) -> List[Dict[str, Any]]:
        """Get workers for a run, including current task text."""
        conn = self.get_connection()
        if not conn:
            return []
        try:
            cursor = conn.execute(
                """
                SELECT w.*, t.task_text as current_task_text
                FROM workers w
                LEFT JOIN tasks t ON w.current_task_id = t.id
                WHERE w.run_id = ?
                ORDER BY w.worker_num
                """,
                (run_id,)
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.Error:
            return []
        finally:
            conn.close()
    
    def get_run_tasks(self, run_id: str) -> List[Dict[str, Any]]:
        """Get tasks for a run."""
        conn = self.get_connection()
        if not conn:
            return []
        try:
            cursor = conn.execute(
                "SELECT * FROM tasks WHERE run_id = ? ORDER BY priority, id",
                (run_id,)
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.Error:
            return []
        finally:
            conn.close()
    
    def get_task_stats(self, run_id: str) -> Dict[str, int]:
        """Get task statistics for a run."""
        conn = self.get_connection()
        if not conn:
            return {"pending": 0, "in_progress": 0, "completed": 0, "failed": 0}
        try:
            cursor = conn.execute(
                "SELECT status, COUNT(*) as count FROM tasks WHERE run_id = ? GROUP BY status",
                (run_id,)
            )
            stats = {"pending": 0, "in_progress": 0, "completed": 0, "failed": 0}
            for row in cursor.fetchall():
                stats[row["status"]] = row["count"]
            return stats
        except sqlite3.Error:
            return {"pending": 0, "in_progress": 0, "completed": 0, "failed": 0}
        finally:
            conn.close()

    def get_run_cost(self, run_id: str) -> float:
        conn = self.get_connection()
        if not conn:
            return 0.0
        try:
            cursor = conn.execute(
                "SELECT COALESCE(SUM(cost), 0) as total_cost FROM task_costs WHERE run_id = ?",
                (run_id,),
            )
            row = cursor.fetchone()
            if not row:
                return 0.0
            return float(row["total_cost"] or 0)
        except sqlite3.Error:
            return 0.0
        finally:
            conn.close()


class ChatInput(Input):
    def __init__(self, chat_pane: "ChatPane", **kwargs: Any):
        super().__init__(**kwargs)
        self._chat_pane = chat_pane

    def on_key(self, event: events.Key) -> None:
        if event.key == "up":
            event.stop()
            self._chat_pane.history_prev()
            return
        if event.key == "down":
            event.stop()
            self._chat_pane.history_next()
            return
        if event.key == "tab":
            event.stop()
            self._chat_pane.autocomplete()
            return


class ChatPane(Vertical):
    """Chat terminal pane for user interaction with enhanced styling."""
    
    DEFAULT_CSS = """
    ChatPane {
        height: 100%;
        border: solid #2ecc71;
    }
    
    ChatPane #chat-header {
        height: 3;
        background: #27ae60;
        color: white;
        padding: 1;
    }
    
    ChatPane #chat-log {
        height: 1fr;
        scrollbar-gutter: stable;
        overflow-y: scroll;
        background: $surface;
    }
    
    ChatPane #chat-input {
        dock: bottom;
        height: 3;
        border-top: solid #2ecc71;
    }
    """
    
    class CommandSubmitted(Message):
        """Message when a command is submitted."""
        def __init__(self, command: str):
            self.command = command
            super().__init__()
    
    def compose(self) -> ComposeResult:
        yield Static("[bold]💬 Chat[/bold] [dim](commands: /help)[/dim]", id="chat-header")
        yield TextArea(id="chat-log", read_only=True)
        yield ChatInput(self, placeholder="Enter command or chat...", id="chat-input")
    
    def on_mount(self) -> None:
        """Initialize chat pane."""
        self._history: List[str] = []
        self._history_index: Optional[int] = None
        self._autocomplete_last_prefix: str = ""
        self._autocomplete_index: int = 0
        self.log_message("Ralph TUI initialized", "system")
        self.log_message("Type /help for available commands", "system")

    def remember_history(self, command: str) -> None:
        if not command:
            return
        if self._history and self._history[-1] == command:
            return
        self._history.append(command)
        self._history_index = None

    def history_prev(self) -> None:
        if not self._history:
            return
        if self._history_index is None:
            self._history_index = len(self._history) - 1
        else:
            self._history_index = max(0, self._history_index - 1)
        self.query_one("#chat-input", Input).value = self._history[self._history_index]

    def history_next(self) -> None:
        if not self._history:
            return
        if self._history_index is None:
            return
        if self._history_index >= len(self._history) - 1:
            self._history_index = None
            self.query_one("#chat-input", Input).value = ""
            return
        self._history_index += 1
        self.query_one("#chat-input", Input).value = self._history[self._history_index]

    def get_command_completions(self, prefix: str) -> List[str]:
        app = self.app
        if not isinstance(app, RalphTUI):
            return []

        commands = [
            "/help",
            "/settings",
            "/mode ",
            "/new ",
            "/open ",
            "/projects",
            "/devplan ",
            "/swarm ",
            "/reiterate ",
            "/report ",
            "/sessions",
            "/focus ",
            "/status",
            "/stop",
            "/emergency-stop",
            "/system",
            "/resume",
            "/logs",
        ]

        if prefix.startswith("/open "):
            base = "/open "
            rest = prefix[len(base):]
            candidates = [base + p for p in app.project_manager.list_projects() if p.startswith(rest)]
            return candidates

        if prefix.startswith("/mode "):
            base = "/mode "
            rest = prefix[len(base):]
            return [base + m for m in ["orchestrator", "ralph"] if m.startswith(rest)]

        if prefix.startswith("/swarm "):
            base = "/swarm "
            rest = prefix[len(base):]
            sub = ["start", "status", "stop", "logs", "inspect", "cleanup", "reiterate", "resume"]
            return [base + s + (" " if s in {"logs", "reiterate"} else "") for s in sub if (s + " ").startswith(rest) or s.startswith(rest)]

        return [c for c in commands if c.startswith(prefix)]

    def autocomplete(self) -> None:
        input_widget = self.query_one("#chat-input", Input)
        value = input_widget.value
        if not value.startswith("/"):
            return

        candidates = self.get_command_completions(value)
        if not candidates:
            return

        if value != self._autocomplete_last_prefix:
            self._autocomplete_last_prefix = value
            self._autocomplete_index = 0
        else:
            self._autocomplete_index = (self._autocomplete_index + 1) % len(candidates)

        input_widget.value = candidates[self._autocomplete_index]
    
    def log_message(self, message: str, msg_type: str = "info") -> None:
        """Log a message to the chat with color-coded prefixes."""
        log = self.query_one("#chat-log", TextArea)
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Color-coded prefixes and symbols for different message types
        prefix = ""
        symbol = ""
        if msg_type == "user":
            symbol = "▶"
            prefix = f"{timestamp} {symbol} You: "
        elif msg_type == "ralph":
            symbol = "◆"
            prefix = f"{timestamp} {symbol} Ralph: "
        elif msg_type == "system":
            symbol = "●"
            prefix = f"{timestamp} {symbol} System: "
        elif msg_type == "error":
            symbol = "✗"
            prefix = f"{timestamp} {symbol} Error: "
        elif msg_type == "success":
            symbol = "✓"
            prefix = f"{timestamp} {symbol} "
        elif msg_type == "warning":
            symbol = "⚠"
            prefix = f"{timestamp} {symbol} Warning: "
        else:
            prefix = f"{timestamp}   "
            
        # Append text to the TextArea
        # Strip rich markup for the plain text area
        try:
            clean_msg = Text.from_markup(message).plain
        except Exception:
            clean_msg = message
            
        # Append text directly to the property
        log.text += f"{prefix}{clean_msg}\n"
        
        # Pin to bottom without animation to prevent jumping ("popcorning")
        log.scroll_end(animate=False)
        
        # Force cursor to end to help maintain position
        try:
            log.cursor_location = (log.document.line_count - 1, 0)
        except Exception:
            pass
    
    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle input submission."""
        command = event.value.strip()
        if command:
            event.input.value = ""
            self.remember_history(command)
            self.log_message(command, "user")
            self.post_message(self.CommandSubmitted(command))



class WorkerPane(Vertical):
    """Worker status pane showing swarm activity with color-coded status."""

    DEFAULT_CSS = """
    WorkerPane {
        height: 100%;
        border: solid blue;
    }

    WorkerPane #worker-header {
        height: 3;
        background: $surface;
        padding: 1;
    }

    WorkerPane #worker-table {
        height: 1fr;
    }
    """

    class WorkerSelected(Message):
        """Message when a worker is selected from the table."""
        def __init__(self, run_id: str, worker_num: int):
            self.run_id = run_id
            self.worker_num = worker_num
            super().__init__()

    def compose(self) -> ComposeResult:
        yield Static("[bold cyan]⚙ Workers[/bold cyan] [dim](click for logs)[/dim]", id="worker-header")
        yield DataTable(id="worker-table", cursor_type="row")

    def on_mount(self) -> None:
        """Initialize worker table."""
        table = self.query_one("#worker-table", DataTable)
        table.add_columns("W#", "Status", "Task", "Progress")

    def update_workers(self, workers: List[Dict[str, Any]]) -> None:
        """Update worker table with current workers and activity."""
        table = self.query_one("#worker-table", DataTable)
        table.clear()

        # Deduplicate workers: keep only the latest worker per worker_num
        # This prevents row key collisions when old + new workers exist
        workers_by_num: Dict[int, Dict[str, Any]] = {}
        for worker in workers:
            worker_num = worker.get("worker_num")
            if worker_num is None:
                continue
            worker_id = worker.get("id", 0)
            existing = workers_by_num.get(worker_num)
            if existing is None or worker_id > existing.get("id", 0):
                workers_by_num[worker_num] = worker

        # Sort by worker_num for display
        sorted_workers = sorted(workers_by_num.values(), key=lambda w: w.get("worker_num", 0))

        for worker in sorted_workers:
            worker_id = worker.get("id", "?")
            worker_num = worker.get("worker_num", "?")
            status = worker.get("status", "unknown")
            task_id = worker.get("current_task_id", "-")
            task_text = worker.get("current_task_text", "")
            run_id = worker.get("run_id", "")

            # Color-coded status with symbols
            if status == "idle":
                status_display = "[yellow]○ idle[/yellow]"
            elif status == "working":
                status_display = "[green]● working[/green]"
            elif status == "error":
                status_display = "[red]✗ error[/red]"
            elif status == "stuck":
                status_display = "[yellow]⏳ stuck[/yellow]"
            elif status == "completed":
                status_display = "[cyan]✓ done[/cyan]"
            elif status == "stopped":
                status_display = "[dim]◼ stopped[/dim]"
            else:
                status_display = f"[dim]{status}[/dim]"

            # Task display with truncation
            if task_text:
                # Truncate but keep meaningful context
                if len(task_text) > 35:
                    task_display = f"{task_text[:32]}..."
                else:
                    task_display = task_text
            elif task_id and task_id != "-" and task_id != "None":
                task_display = f"[dim]#{task_id}[/dim]"
            else:
                task_display = "[dim]—[/dim]"

            # Progress indicator based on status
            if status == "working":
                progress = "[green]▓▓▓░░[/green]"
            elif status == "idle":
                progress = "[dim]░░░░░[/dim]"
            elif status == "completed":
                progress = "[cyan]▓▓▓▓▓[/cyan]"
            elif status == "error":
                progress = "[red]▓▓✗░░[/red]"
            elif status == "stopped":
                progress = "[dim]—————[/dim]"
            else:
                progress = "[dim]?????[/dim]"

            # Use unique worker database ID as key to prevent collisions
            table.add_row(
                f"[bold]{worker_num}[/bold]",
                status_display,
                task_display,
                progress,
                key=str(worker_id)
            )

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection."""
        if not event.row_key.value:
             return
        try:
            parts = str(event.row_key.value).split("|")
            if len(parts) == 2:
                run_id, worker_num = parts[0], int(parts[1])
                self.post_message(self.WorkerSelected(run_id, worker_num))
        except Exception:
            pass


class ProgressPane(Vertical):
    """Progress dashboard pane with enhanced visual display."""

    DEFAULT_CSS = """
    ProgressPane {
        height: auto;
        border-top: solid #f1c40f;
        dock: bottom;
        max-height: 3;
        background: $surface-darken-1;
        padding: 0 1;
    }

    ProgressPane #stats-line {
        height: 1;
        width: 1fr;
    }

    ProgressPane #progress-bar {
        height: 1;
        width: 25;
    }
    
    ProgressPane #progress-row {
        height: 1;
        padding: 0;
    }
    """

    progress = reactive(0.0)

    def compose(self) -> ComposeResult:
        yield Horizontal(
            Static("[dim]◎ Ready[/dim]", id="stats-line"),
            ProgressBar(total=100, id="progress-bar", show_eta=False),
            id="progress-row"
        )

    def update_progress(self, run_info: Optional[Dict], stats: Dict[str, int], total_cost: float = 0.0) -> None:
        """Update progress display with color-coded stats."""
        total = sum(stats.values())
        completed = stats.get("completed", 0)
        failed = stats.get("failed", 0)
        in_progress = stats.get("in_progress", 0)
        pending = stats.get("pending", 0)

        # Update stats display
        stats_widget = self.query_one("#stats-line", Static)

        cost_text = f" | [cyan]${total_cost:.4f}[/cyan]" if total_cost else ""

        if not run_info:
             stats_widget.update("[dim]◎ No active run[/dim]")
             self.query_one("#progress-bar", ProgressBar).update(progress=0)
             return

        run_id = run_info.get("run_id", "N/A")
        status = run_info.get("status", "N/A")
        
        # Color-code the status
        if status == "running":
            status_display = "[green bold]● RUNNING[/green bold]"
        elif status == "completed":
            status_display = "[cyan bold]✓ DONE[/cyan bold]"
        elif status == "failed":
            status_display = "[red bold]✗ FAILED[/red bold]"
        elif status == "stopped":
            status_display = "[yellow bold]◼ STOPPED[/yellow bold]"
        else:
            status_display = f"[bold]{status}[/bold]"

        stats_text = (
            f"{status_display} [dim]({run_id[:8]})[/dim] │ "
            f"[green]✓{completed}[/green] "
            f"[blue]●{in_progress}[/blue] "
            f"[yellow]○{pending}[/yellow] "
            f"[red]✗{failed}[/red]"
            f"{cost_text}"
        )
        stats_widget.update(stats_text)

        # Update progress bar
        progress_bar = self.query_one("#progress-bar", ProgressBar)
        if total > 0:
            progress_bar.update(progress=(completed * 100) // total)
        else:
            progress_bar.update(progress=0)
    
    def add_task_update(self, task_text: str, status: str) -> None:
        pass


class LogPane(Vertical):
    """Non-interactive system log pane for swarm/agent process details with real-time updates."""

    DEFAULT_CSS = """
    LogPane {
        height: 100%;
        border: solid cyan;
    }

    LogPane #log-header {
        height: 3;
        background: $surface;
        padding: 1;
    }

    LogPane #system-log {
        height: 1fr;
    }
    """

    def __init__(self, **kwargs: Any):
        super().__init__(**kwargs)
        self._max_lines = 1000
        self._log_levels = {
            "info": "[blue]●[/blue]",
            "success": "[green]✓[/green]",
            "warning": "[yellow]⚠[/yellow]",
            "error": "[red]✗[/red]",
            "task": "[magenta]→[/magenta]",
            "tool": "[cyan]◇[/cyan]",
            "file": "[green]◆[/green]",
            "cmd": "[yellow]$[/yellow]",
            "completed": "[green]✓[/green]",
            "failed": "[red]✗[/red]",
            "stuck": "[yellow]⏳[/yellow]",
            "read": "[blue]◈[/blue]",
            "write": "[green]◈[/green]",
            "edit": "[cyan]◈[/cyan]",
            "thinking": "[magenta]◎[/magenta]",
        }
        # Track file positions for incremental reading
        self._log_file_positions: Dict[str, int] = {}
        # Patterns to detect interesting log events
        self._tool_pattern = re.compile(r"Tool[:\s]+(\w+)\s*[\(\[]?(.{0,60})")
        self._file_pattern = re.compile(r"(Read|Write|Edit|Create|Delete)[:\s]+(.+?)(?:\s|$)")
        self._cmd_pattern = re.compile(r"(Bash|Command|Run|Exec)[:\s]+(.+?)(?:\s|$)")
        self._thinking_pattern = re.compile(r"(Thinking|Planning|Analyzing)[:\s]*(.{0,50})")

    def compose(self) -> ComposeResult:
        yield Static("[bold orange1]◉ System Log[/bold orange1] [dim](live worker activity)[/dim]", id="log-header")
        yield TextArea(id="system-log", read_only=True)

    def scan_worker_logs(self, run_id: str) -> None:
        """Scan worker log files for new content and display updates."""
        if not run_id:
            return
        
        run_dir = RALPH_DIR / "swarm" / "runs" / run_id
        if not run_dir.exists():
            return

        # Find all worker log directories
        try:
            worker_dirs = list(run_dir.glob("worker-*"))
        except Exception:
            return

        for worker_dir in worker_dirs:
            worker_num = worker_dir.name.replace("worker-", "")
            log_dir = worker_dir / "logs"
            if not log_dir.exists():
                continue

            # Find log files
            try:
                log_files = list(log_dir.glob("*.log"))
                if not log_files:
                    continue
                
                # Process each log file
                for log_file in log_files:
                    self._process_log_file(log_file, f"W{worker_num}")
            except Exception:
                continue

    def _process_log_file(self, log_path: Path, worker_id: str) -> None:
        """Process a single log file for new content."""
        file_key = str(log_path)
        
        try:
            file_size = log_path.stat().st_size
            last_pos = self._log_file_positions.get(file_key, 0)
            
            # Skip if no new content
            if file_size <= last_pos:
                return
            
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                f.seek(last_pos)
                new_content = f.read()
                self._log_file_positions[file_key] = f.tell()
            
            # Parse and display interesting events
            for line in new_content.splitlines():
                self._parse_and_log_line(line.strip(), worker_id)
                
        except Exception:
            pass

    def _parse_and_log_line(self, line: str, worker_id: str) -> None:
        """Parse a log line and display if it's interesting."""
        if not line or len(line) < 3:
            return
        
        # Skip noise lines
        noise_patterns = ["---", "===", "***", "DEBUG:", "TRACE:"]
        if any(line.startswith(p) for p in noise_patterns):
            return
        
        # Check for tool calls
        tool_match = self._tool_pattern.search(line)
        if tool_match:
            tool_name = tool_match.group(1)
            args = tool_match.group(2) if tool_match.group(2) else ""
            self.write_log(f"{tool_name}: {args[:40]}", "tool", worker_id)
            return
        
        # Check for file operations
        file_match = self._file_pattern.search(line)
        if file_match:
            action = file_match.group(1).lower()
            filepath = file_match.group(2)[:50]
            level = "read" if action == "read" else "write" if action in ["write", "create"] else "edit"
            self.write_log(f"{action}: {filepath}", level, worker_id)
            return
        
        # Check for command execution
        cmd_match = self._cmd_pattern.search(line)
        if cmd_match:
            cmd = cmd_match.group(2)[:45]
            self.write_log(f"$ {cmd}", "cmd", worker_id)
            return
        
        # Check for thinking/planning
        thinking_match = self._thinking_pattern.search(line)
        if thinking_match:
            thought = thinking_match.group(2)[:40] if thinking_match.group(2) else "..."
            self.write_log(f"thinking: {thought}", "thinking", worker_id)
            return
        
        # Check for errors/warnings in the line
        line_lower = line.lower()
        if "error" in line_lower or "exception" in line_lower or "failed" in line_lower:
            self.write_log(line[:60], "error", worker_id)
            return
        if "warning" in line_lower or "warn" in line_lower:
            self.write_log(line[:60], "warning", worker_id)
            return
        if "success" in line_lower or "completed" in line_lower or "done" in line_lower:
            self.write_log(line[:60], "success", worker_id)
            return

    def write_log(self, message: str, level: str = "info", worker_id: Optional[str] = None) -> None:
        """Write a log entry to the pane."""
        log = self.query_one("#system-log", TextArea)
        timestamp = datetime.now().strftime("%H:%M:%S")

        prefix = self._log_levels.get(level, "[dim]?[/dim]")
        worker_tag = f"[dim][{worker_id}][/dim] " if worker_id else ""

        full_message = f"{timestamp} {prefix} {worker_tag}{message}"

        # Strip Rich markup tags for display (user can copy plain text)
        clean_msg = Text.from_markup(full_message).plain

        lines = log.text.split("\n")
        if len(lines) > self._max_lines:
            log.text = "\n".join(lines[-self._max_lines:])
        log.text += f"{clean_msg}\n"
        log.scroll_end(animate=False)

    def log_task_start(self, worker_id: str, task_text: str) -> None:
        """Log task start with task flair."""
        short_task = task_text[:60] + "..." if len(task_text) > 60 else task_text
        self.write_log(f"Starting task: {short_task}", "task", worker_id)

    def log_tool_call(self, worker_id: str, tool_name: str, args: str) -> None:
        """Log tool call with tool flair."""
        short_args = args[:40] + "..." if len(args) > 40 else args
        self.write_log(f"Tool: {tool_name}({short_args})", "tool", worker_id)

    def log_file_edit(self, worker_id: str, file_path: str, action: str = "edit") -> None:
        """Log file edit with file flair."""
        self.write_log(f"File {action}: {file_path}", "file", worker_id)

    def log_command(self, worker_id: str, cmd: str) -> None:
        """Log command execution with cmd flair."""
        short_cmd = cmd[:50] + "..." if len(cmd) > 50 else cmd
        self.write_log(f"Cmd: {short_cmd}", "cmd", worker_id)

    def log_completed(self, worker_id: str, task_text: str) -> None:
        """Log task completion with completed flair."""
        short_task = task_text[:50] + "..." if len(task_text) > 50 else task_text
        self.write_log(f"COMPLETED: {short_task}", "completed", worker_id)

    def log_failed(self, worker_id: str, task_text: str, error: str) -> None:
        """Log task failure with failed flair."""
        short_task = task_text[:50] + "..." if len(task_text) > 50 else task_text
        self.write_log(f"FAILED: {short_task} - {error}", "failed", worker_id)

    def log_stuck(self, worker_id: str, task_text: str, duration: int) -> None:
        """Log stuck task with stuck flair."""
        short_task = task_text[:45] + "..." if len(task_text) > 45 else task_text
        self.write_log(f"STUCK ({duration}s): {short_task}", "stuck", worker_id)

    def clear(self) -> None:
        """Clear the log."""
        log = self.query_one("#system-log", TextArea)
        log.text = ""


class FilePane(Vertical):
    """File browser pane for project exploration with enhanced styling."""
    
    DEFAULT_CSS = """
    FilePane {
        height: 100%;
        border: solid #9b59b6;
    }
    
    FilePane #file-header {
        height: 3;
        background: #8e44ad;
        color: white;
        padding: 1;
    }
    
    FilePane #file-tree {
        height: 1fr;
        background: $surface;
    }
    
    FilePane #file-preview {
        height: 1fr;
        border-top: solid #9b59b6;
        background: $surface-darken-1;
        padding: 0 1;
        overflow-y: scroll;
    }
    """
    
    class FileSelected(Message):
        """Message when a file is selected."""
        def __init__(self, path: Path):
            self.path = path
            super().__init__()
    
    def __init__(self, root_path: Path = Path.cwd(), id: Optional[str] = None):
        super().__init__(id=id)
        self.root_path = root_path
    
    def compose(self) -> ComposeResult:
        yield Static(f"[bold]📁 Files:[/bold] {self.root_path.name}", id="file-header")
        yield DirectoryTree(str(self.root_path), id="file-tree")
        yield Static("[dim]Select a file to preview[/dim]", id="file-preview")
    
    def on_directory_tree_file_selected(self, event: DirectoryTree.FileSelected) -> None:
        """Handle file selection."""
        path = Path(event.path)
        self.post_message(self.FileSelected(path))
        
        # Show preview (best-effort syntax highlighting)
        preview = self.query_one("#file-preview", Static)
        try:
            if path.is_dir():
                preview.update(f"[dim]{path.name}[/dim]/")
                return

            if path.suffix.lower() in [".py", ".sh", ".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".js", ".ts", ".tsx", ".jsx", ".css", ".html"]:
                content = path.read_text(encoding="utf-8", errors="replace")
                content = "\n".join(content.splitlines()[:200])
                lexer = "text"
                if path.suffix.lower() == ".py":
                    lexer = "python"
                elif path.suffix.lower() == ".sh":
                    lexer = "bash"
                elif path.suffix.lower() == ".md":
                    lexer = "markdown"
                elif path.suffix.lower() == ".json":
                    lexer = "json"
                elif path.suffix.lower() in [".yaml", ".yml"]:
                    lexer = "yaml"
                elif path.suffix.lower() == ".toml":
                    lexer = "toml"
                elif path.suffix.lower() in [".js", ".jsx"]:
                    lexer = "javascript"
                elif path.suffix.lower() in [".ts", ".tsx"]:
                    lexer = "typescript"
                elif path.suffix.lower() == ".css":
                    lexer = "css"
                elif path.suffix.lower() == ".html":
                    lexer = "html"

                preview.update(Syntax(content, lexer, theme="monokai", line_numbers=True, word_wrap=True))
            else:
                preview.update(f"[dim]{path.name}[/dim] ({path.suffix or 'file'})")
        except Exception as e:
            preview.update(f"[red]Error reading file: {e}[/red]")
    
    def set_root(self, root_path: Path) -> None:
        """Change the root directory."""
        self.root_path = root_path
        header = self.query_one("#file-header", Static)
        header.update(f"[bold]📁 Files:[/bold] {root_path.name}")

        # Update existing tree in place to avoid duplicate widget IDs.
        tree = self.query_one("#file-tree", DirectoryTree)
        tree.path = root_path
        tree.reload()

    def refresh_tree(self) -> None:
        self.set_root(self.root_path)


class RalphTUI(App):
    """Main Ralph TUI Application."""

    CSS = """
    Screen {
        layout: grid;
        grid-size: 3 2;
        grid-rows: 1fr 3;
        grid-columns: 1.4fr 0.8fr 1.2fr;
    }

    /* Main chat area - left column */
    #chat-container {
        row-span: 1;
        column-span: 1;
    }

    /* Center column: Log console (expanded) */
    #center-column {
        row-span: 1;
        column-span: 1;
    }

    #worker-container {
        height: auto;
        min-height: 5;
        max-height: 24;
    }

    /* Right column: Workers (compact) + File browser (expanded) */
    #right-column {
        row-span: 1;
        column-span: 1;
        layout: vertical;
    }

    #worker-container {
        height: auto;
        min-height: 5;
        max-height: 8;
    }

    #file-container {
        height: 1fr;
    }

    /* Progress bar - full width bottom */
    #progress-container {
        row-span: 1;
        column-span: 3;
        height: 3;
    }

    .pane-title {
        text-style: bold;
        background: $surface;
        padding: 0 1;
    }

    /* Enhanced color scheme with vivid borders */
    ChatPane {
        border: solid #2ecc71;
    }
    
    ChatPane #chat-log {
        background: $surface;
    }
    
    WorkerPane {
        border: solid #3498db;
    }
    
    WorkerPane #worker-header {
        background: #2980b9;
        color: white;
    }
    
    WorkerPane DataTable {
        background: $surface;
    }
    
    LogPane {
        border: solid #e67e22;
    }
    
    LogPane #log-header {
        background: #d35400;
        color: white;
    }
    
    FilePane {
        border: solid #9b59b6;
    }
    
    FilePane #file-header {
        background: #8e44ad;
        color: white;
    }
    
    FilePane DirectoryTree {
        background: $surface;
    }
    
    FilePane #file-preview {
        height: 1fr;
        border-top: solid #9b59b6;
        background: $surface-darken-1;
        padding: 0 1;
        overflow-y: scroll;
    }
    
    ProgressPane {
        border-top: solid #f1c40f;
        background: $surface-darken-1;
    }
    """
    
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("ctrl+n", "new_project", "New Project"),
        Binding("ctrl+o", "open_project", "Open Project"),
        Binding("ctrl+r", "run_swarm", "Run Swarm"),
        Binding("ctrl+s", "stop_swarm", "Stop Swarm"),
        Binding("ctrl+comma", "open_settings", "Settings"),
        Binding("ctrl+t", "toggle_theme", "Theme"),
        Binding("f1", "show_help", "Help"),
        Binding("f5", "refresh", "Refresh"),
    ]
    
    TITLE = "Ralph TUI - AI Development Agent"
    
    def __init__(self):
        super().__init__()
        self.project_manager = ProjectManager()
        self.db_reader = SwarmDBReader()
        self.config = load_tui_config()

        # Back-compat: keep a default process slot.
        self.ralph_process: Optional[subprocess.Popen] = None

        # Multiple sessions (processes) support.
        self.processes: Dict[str, subprocess.Popen] = {}
        self.process_names: Dict[str, str] = {}
        self.active_process_id: Optional[str] = None

        self.chat_mode: str = "orchestrator"  # orchestrator | ralph

        # State tracking for notifications
        self._last_task_stats: Dict[str, str] = {}  # task_id -> status
        self._last_run_id: Optional[str] = None

        self.refresh_timer: Optional[Timer] = None
        self._file_watch_task: Optional[asyncio.Task] = None
        self._file_watch_stop: Optional[asyncio.Event] = None

        # Multi-step command state (used for /swarm devplan selection).
        self._pending_swarm_workers: Optional[str] = None
        self._pending_swarm_devplans: List[Path] = []
    
    def compose(self) -> ComposeResult:
        yield Header()
        # Left column: Chat
        yield Container(
            ChatPane(id="chat-pane"),
            id="chat-container"
        )
        # Center column: System Log (expanded)
        yield Container(
            LogPane(id="log-pane"),
            id="center-column"
        )
        # Right column: Workers (compact) + File browser (expanded)
        yield Vertical(
            Container(
                WorkerPane(id="worker-pane"),
                id="worker-container"
            ),
            Container(
                FilePane(id="file-pane"),
                id="file-container"
            ),
            id="right-column"
        )
        # Bottom: Progress bar
        yield Container(
            ProgressPane(id="progress-pane"),
            id="progress-container"
        )
        yield Footer()
    
    def on_mount(self) -> None:
        """Initialize the application."""
        # Ensure directories exist
        RALPH_DIR.mkdir(parents=True, exist_ok=True)
        PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
        
        # Start refresh timer for status updates
        self.refresh_timer = self.set_interval(self.config.refresh_interval_sec, self.refresh_status)

        self.apply_theme(self.config.theme)
        
        # Log welcome message
        chat_pane = self.query_one("#chat-pane", ChatPane)
        chat_pane.log_message("Welcome to Ralph TUI!", "system")
        chat_pane.log_message(f"Projects directory: {PROJECTS_DIR}", "system")
        chat_pane.log_message("Chat mode: orchestrator (use /mode ralph to run ralph2)", "system")
        chat_pane.log_message("Commands: /new, /open, /devplan, /swarm, /status, /settings, /help", "system")
    
    def refresh_status(self) -> None:
        """Timer callback: schedule async status refresh."""
        task = asyncio.create_task(self.refresh_status_async())

        def _on_done(t: asyncio.Task) -> None:
            with suppress(Exception):
                exc = t.exception()
                if exc is not None:
                    chat_pane = self.query_one("#chat-pane", ChatPane)
                    chat_pane.log_message(f"Status refresh failed: {exc}", "error")

        task.add_done_callback(_on_done)

    async def refresh_status_async(self) -> None:
        """Refresh swarm status periodically."""
        run_info = self.db_reader.get_latest_run()

        if not run_info:
            return

        run_id = run_info.get("run_id", "")
        if not run_id:
            return

        # Update workers
        workers = self.db_reader.get_run_workers(run_id)
        worker_pane = self.query_one("#worker-pane", WorkerPane)
        worker_pane.update_workers(workers)

        # Update progress
        stats = self.db_reader.get_task_stats(run_id)
        total_cost = self.db_reader.get_run_cost(run_id)
        progress_pane = self.query_one("#progress-pane", ProgressPane)
        progress_pane.update_progress(run_info, stats, total_cost)

        # Get LogPane for system logging
        try:
            log_pane = self.query_one("#log-pane", LogPane)
        except Exception:
            log_pane = None

        # Task completion notifications
        if self._last_run_id != run_id:
            # New run detected, reset tracking
            self._last_run_id = run_id
            self._last_task_stats = {}

            # Log new run to LogPane
            if log_pane:
                log_pane.write_log(f"New swarm run started: {run_id[:12]}...", "info")

        # We need to fetch tasks to check for status changes
        current_tasks = self.db_reader.get_run_tasks(run_id)
        chat_pane = self.query_one("#chat-pane", ChatPane)

        for task in current_tasks:
            t_id = str(task.get("id"))
            t_status = task.get("status")
            t_text = task.get("task_text", "")
            worker_id = task.get("worker_id", "")
            error_msg = task.get("error_message", "")

            # If we've seen this task before and status changed
            if t_id in self._last_task_stats:
                old_status = self._last_task_stats[t_id]
                if old_status != t_status:
                    # Log to LogPane with flair
                    if log_pane:
                        worker_tag = f"W{worker_id}" if worker_id else ""

                        if t_status == "completed":
                            log_pane.log_completed(worker_tag, t_text)
                            chat_pane.log_message(f"[green]Task Completed:[/green] {t_text[:60]}...", "system")
                        elif t_status == "failed":
                            log_pane.log_failed(worker_tag, t_text, error_msg or "Unknown error")
                            chat_pane.log_message(f"[red]Task Failed:[/red] {t_text[:60]}... ({error_msg})", "error")
                        elif t_status == "in_progress" and old_status == "pending":
                            log_pane.log_task_start(worker_tag, t_text)
                        elif old_status == "in_progress" and t_status == "pending":
                            # Task was interrupted
                            log_pane.write_log(f"Task interrupted: {t_text[:50]}...", "warning", worker_tag)

            # Update tracked status
            self._last_task_stats[t_id] = str(t_status)

        # Scan worker log files for real-time activity updates
        if log_pane:
            log_pane.scan_worker_logs(run_id)
    
    def on_chat_pane_command_submitted(self, event: ChatPane.CommandSubmitted) -> None:
        """Handle commands from chat pane."""
        command = event.command.strip()
        chat_pane = self.query_one("#chat-pane", ChatPane)

        # If we're waiting for the user to choose a devplan for swarm, treat the
        # next input as a selection (number) or a path.
        if self._pending_swarm_workers is not None and not command.startswith("/"):
            self._handle_pending_swarm_devplan_choice(command, chat_pane)
            return
        
        if command.startswith("/"):
            self.handle_slash_command(command, chat_pane)
        else:
            if self.chat_mode == "ralph":
                self.run_ralph_command(command, chat_pane)
            else:
                self.run_orchestrator_command(command, chat_pane)

    def get_command_completions(self, prefix: str) -> List[str]:
        commands = [
            "/help",
            "/settings",
            "/mode ",
            "/new ",
            "/open ",
            "/projects",
            "/devplan ",
            "/swarm ",
            "/reiterate ",
            "/report ",
            "/sessions",
            "/focus ",
            "/status",
            "/stop",
            "/emergency-stop",
            "/system",
            "/resume",
            "/logs",
        ]

        if prefix.startswith("/open "):
            base = "/open "
            rest = prefix[len(base):]
            candidates = [base + p for p in self.project_manager.list_projects() if p.startswith(rest)]
            return candidates

        if prefix.startswith("/mode "):
            base = "/mode "
            rest = prefix[len(base):]
            return [base + m for m in ["orchestrator", "ralph"] if m.startswith(rest)]

        if prefix.startswith("/swarm "):
            base = "/swarm "
            rest = prefix[len(base):]
            sub = ["start", "status", "stop", "logs", "inspect", "cleanup", "reiterate", "resume"]
            return [base + s + (" " if s in {"logs", "reiterate"} else "") for s in sub if (s + " ").startswith(rest) or s.startswith(rest)]

        return [c for c in commands if c.startswith(prefix)]
    
    def handle_slash_command(self, command: str, chat_pane: ChatPane) -> None:
        """Handle slash commands."""
        parts = command.split(maxsplit=1)
        cmd = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""
        
        if cmd == "/help":
            self.show_help_text(chat_pane)

        elif cmd == "/settings":
            self.open_settings(chat_pane)

        elif cmd == "/mode":
            mode = args.strip().lower()
            if mode in {"orchestrator", "ralph"}:
                self.chat_mode = mode
                chat_pane.log_message(f"Chat mode set to: {mode}", "system")
            else:
                chat_pane.log_message("Usage: /mode orchestrator|ralph", "error")
        
        elif cmd == "/new":
            if args:
                self.create_new_project(args, chat_pane)
            else:
                chat_pane.log_message("Usage: /new <project_name>", "error")
        
        elif cmd == "/open":
            if args:
                self.open_project(args, chat_pane)
            else:
                # List projects
                projects = self.project_manager.list_projects()
                if projects:
                    chat_pane.log_message("Available projects: " + ", ".join(projects), "system")
                else:
                    chat_pane.log_message("No projects found. Use /new <name> to create one.", "system")
        
        elif cmd == "/projects":
            projects = self.project_manager.list_projects()
            if projects:
                chat_pane.log_message("Projects: " + ", ".join(projects), "system")
            else:
                chat_pane.log_message("No projects found.", "system")
        
        elif cmd == "/devplan":
            self.run_devplan_mode(args, chat_pane)
        
        elif cmd == "/swarm":
            self.handle_swarm_command(args, chat_pane)

        elif cmd == "/cancel":
            if self._pending_swarm_workers is not None:
                self._pending_swarm_workers = None
                self._pending_swarm_devplans = []
                chat_pane.log_message("Cancelled pending swarm devplan selection.", "system")
            else:
                chat_pane.log_message("Nothing to cancel.", "system")

        elif cmd == "/reiterate":
            self.force_reiterate(args, chat_pane)

        elif cmd == "/report":
            self.export_run_report(args, chat_pane)

        elif cmd == "/sessions":
            self.list_sessions(chat_pane)

        elif cmd == "/focus":
            self.focus_session(args, chat_pane)
        
        elif cmd == "/status":
            self.show_status(chat_pane)
        
        elif cmd == "/stop":
            self.stop_ralph(chat_pane)

        elif cmd == "/emergency-stop":
            self.emergency_stop_swarm(chat_pane)

        elif cmd == "/system":
            self.show_system_stats(chat_pane)

        elif cmd == "/resume":
            self.resume_run(args, chat_pane)

        elif cmd == "/logs":
            self.show_logs(chat_pane)
        
        else:
            chat_pane.log_message(f"Unknown command: {cmd}. Try /help", "error")
    
    def show_help_text(self, chat_pane: ChatPane) -> None:
        """Display help information."""
        help_text = """
[bold]Ralph TUI Commands:[/bold]

[bold cyan]Project Management:[/bold cyan]
  /new <name>     Create a new project
  /open <name>    Open an existing project
  /projects       List all projects

[bold cyan]Ralph Operations:[/bold cyan]
  /devplan [file] Run Ralph in devplan mode
  /mode <name>    Switch chat mode (orchestrator|ralph)
  /swarm ...      Swarm control (start/status/logs/stop/reiterate/resume/reset)
  /reiterate N    Force worker N to re-queue current task
  /resume RUN_ID  Resume a previous swarm run
  /status         Show current status
  /stop           Stop current Ralph run
  /emergency-stop Kill all swarm workers immediately (DANGER)
  /system         Show system-wide swarm statistics
  /logs           Show recent logs
  /report [RUN_ID] Export swarm run report to markdown
  /cancel         Cancel a pending selection prompt

[bold cyan]Settings:[/bold cyan]
  /settings       Open settings menu

[bold cyan]General:[/bold cyan]
  /help           Show this help

[bold cyan]Keyboard Shortcuts:[/bold cyan]
  Ctrl+N          New project
  Ctrl+R          Run swarm
  Ctrl+S          Stop swarm
  Ctrl+,          Settings
  Ctrl+T          Toggle theme
  F5              Refresh status
  Q               Quit
"""
        chat_pane.log_message(help_text, "system")

    def open_settings(self, chat_pane: ChatPane) -> None:
        def _on_dismiss(result: Optional[TUIConfig]) -> None:
            if not result:
                return
            self.config = result
            save_tui_config(self.config)
            self.apply_theme(self.config.theme)
            if self.refresh_timer:
                self.refresh_timer.stop()
            self.refresh_timer = self.set_interval(self.config.refresh_interval_sec, self.refresh_status)
            if self.project_manager.current_project and self.config.enable_file_watch:
                self.start_file_watch(self.project_manager.current_project)
            chat_pane.log_message("Settings saved.", "system")

        self.push_screen(SettingsScreen(self.config), _on_dismiss)
    
    def create_new_project(self, name: str, chat_pane: ChatPane) -> None:
        """Create a new project."""
        try:
            project_dir = self.project_manager.create_project(name)
            chat_pane.log_message(f"Created project: {project_dir}", "system")
            
            # Update file browser
            file_pane = self.query_one("#file-pane", FilePane)
            file_pane.set_root(project_dir)

            if self.config.enable_file_watch:
                self.start_file_watch(project_dir)
            
            chat_pane.log_message("Project structure created:", "system")
            chat_pane.log_message("  - src/       Source code", "system")
            chat_pane.log_message("  - docs/      Documentation", "system")
            chat_pane.log_message("  - artifacts/ Swarm artifacts", "system")
            chat_pane.log_message("  - output/    Ralph output", "system")
            chat_pane.log_message("  - devplan.md Development plan", "system")
        except Exception as e:
            chat_pane.log_message(f"Failed to create project: {e}", "error")
    
    def open_project(self, name: str, chat_pane: ChatPane) -> None:
        """Open an existing project."""
        project_dir = self.project_manager.open_project(name)
        if project_dir:
            chat_pane.log_message(f"Opened project: {project_dir}", "system")
            
            # Update file browser
            file_pane = self.query_one("#file-pane", FilePane)
            file_pane.set_root(project_dir)

            if self.config.enable_file_watch:
                self.start_file_watch(project_dir)
        else:
            chat_pane.log_message(f"Project not found: {name}", "error")
            projects = self.project_manager.list_projects()
            if projects:
                chat_pane.log_message("Available: " + ", ".join(projects), "system")
    
    def run_devplan_mode(self, devplan_path: str, chat_pane: ChatPane) -> None:
        """Run Ralph in devplan mode."""
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return
        
        project_dir = self.project_manager.current_project
        devplan = Path(devplan_path) if devplan_path else project_dir / "devplan.md"
        
        if not devplan.exists():
            chat_pane.log_message(f"Devplan not found: {devplan}", "error")
            return
        
        chat_pane.log_message(f"Running devplan mode: {devplan}", "system")
        
        # Set up environment for output to project folder
        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        env["SWARM_ARTIFACTS_DIR"] = str(project_dir / "artifacts")
        
        try:
            cmd = [str(RALPH2_PATH), "--devplan", str(devplan)]
            self.spawn_process("ralph-devplan", cmd, project_dir, env, chat_pane)
        except Exception as e:
            chat_pane.log_message(f"Failed to start Ralph: {e}", "error")
    
    def run_swarm_mode(self, args: str, chat_pane: ChatPane) -> None:
        """Run Ralph in swarm mode."""
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return

        project_dir = self.project_manager.current_project

        # Parse args: /swarm [N] [devplan_path]
        raw = args.strip()
        worker_count = str(self.config.default_workers)
        devplan_path = ""

        if raw:
            first, rest = (raw.split(maxsplit=1) + [""])[:2]
            if first.isdigit():
                worker_count = first
                devplan_path = rest.strip()
            else:
                devplan_path = raw

        # Validate worker count against limits
        try:
            workers_int = int(worker_count)
            if workers_int < 1:
                chat_pane.log_message("Worker count must be at least 1", "error")
                return
            # Check against configured maximum
            max_workers = 8  # Default from ralph.config
            config_path = RALPH_DIR / "ralph.config"
            try:
                if config_path.exists():
                    for line in config_path.read_text().splitlines():
                        if line.startswith("SWARM_MAX_WORKERS="):
                            max_workers = int(line.split("=", 1)[1].strip())
                            break
            except Exception:
                pass

            if workers_int > max_workers:
                chat_pane.log_message(f"Worker count {workers_int} exceeds maximum allowed ({max_workers})", "error")
                chat_pane.log_message(f"Set SWARM_MAX_WORKERS in {RALPH_DIR}/ralph.config to increase this limit", "system")
                return

            # Check total system workers
            try:
                db_path = SWARM_DB
                if db_path.exists():
                    import sqlite3
                    conn = sqlite3.connect(str(db_path), timeout=10.0)
                    cursor = conn.execute(
                        "SELECT COUNT(*) FROM worker_registry WHERE last_heartbeat >= datetime('now', '-60 seconds')"
                    )
                    active_workers = cursor.fetchone()[0]
                    conn.close()

                    max_total = 16  # Default
                    try:
                        for line in config_path.read_text().splitlines():
                            if line.startswith("SWARM_MAX_TOTAL_WORKERS="):
                                max_total = int(line.split("=", 1)[1].strip())
                                break
                    except Exception:
                        pass

                    if active_workers + workers_int > max_total:
                        chat_pane.log_message(
                            f"Cannot spawn {workers_int} workers: would exceed system limit of {max_total} "
                            f"(currently {active_workers} active)",
                            "error"
                        )
                        return
            except Exception as e:
                chat_pane.log_message(f"Warning: Could not check system limits: {e}", "system")

        except ValueError:
            chat_pane.log_message("Invalid worker count", "error")
            return

        if not devplan_path:
            self._prompt_for_swarm_devplan(worker_count, chat_pane)
            return

        devplan = (project_dir / devplan_path).resolve() if not Path(devplan_path).is_absolute() else Path(devplan_path)
        if not devplan.exists():
            chat_pane.log_message(f"Devplan not found: {devplan}", "error")
            self._prompt_for_swarm_devplan(worker_count, chat_pane)
            return

        chat_pane.log_message(f"Running swarm mode: {devplan}", "system")
        chat_pane.log_message(f"Workers: {worker_count} (max per-run: {max_workers})", "system")
        
        # Set up environment
        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        env["SWARM_COLLECT_ARTIFACTS"] = "true" if self.config.swarm_collect_artifacts else "false"
        env["SWARM_ARTIFACTS_DIR"] = str(project_dir / "artifacts")
        env["SWARM_AUTO_MERGE"] = "true" if self.config.swarm_auto_merge else "false"
        env["RALPH_LLM_PROVIDER"] = self.config.swarm_provider
        env["RALPH_LLM_MODEL"] = self.config.swarm_model
        
        ralph_swarm = RALPH_REFACTOR_DIR / "ralph-swarm"
        
        try:
            cmd = [
                str(ralph_swarm),
                "--devplan", str(devplan),
                "--workers", worker_count,
            ]
            self.spawn_process(f"swarm({worker_count})", cmd, project_dir, env, chat_pane)
        except Exception as e:
            chat_pane.log_message(f"Failed to start swarm: {e}", "error")

    def _prompt_for_swarm_devplan(self, worker_count: str, chat_pane: ChatPane) -> None:
        """Ask user where the devplan is located."""
        if not self.project_manager.current_project:
            return

        project_dir = self.project_manager.current_project

        candidates: List[Path] = []
        root_default = project_dir / "devplan.md"
        if root_default.exists():
            candidates.append(root_default)

        # Best-effort discovery: look for devplan*.md, skip bulky/irrelevant dirs.
        with suppress(Exception):
            for p in project_dir.rglob("devplan*.md"):
                if p == root_default:
                    continue
                parts = set(p.parts)
                if {".git", ".venv", "node_modules", "artifacts", "output"} & parts:
                    continue
                candidates.append(p)
                if len(candidates) >= 12:
                    break

        # Store state for the next user input.
        self._pending_swarm_workers = worker_count
        self._pending_swarm_devplans = candidates

        chat_pane.log_message(f"Swarm needs a devplan file (workers={worker_count}).", "system")
        if candidates:
            chat_pane.log_message("Select a devplan by number, or paste a path:", "system")
            for i, p in enumerate(candidates, start=1):
                rel = str(p.relative_to(project_dir)) if str(p).startswith(str(project_dir)) else str(p)
                chat_pane.log_message(f"  {i}) {rel}", "system")
            chat_pane.log_message("Tip: type /cancel to abort.", "system")
        else:
            chat_pane.log_message("No devplan*.md found in the project.", "error")
            chat_pane.log_message("Provide a path (relative to project root or absolute), e.g. docs/devplan.md", "system")
            chat_pane.log_message("Tip: type /cancel to abort.", "system")

    def _handle_pending_swarm_devplan_choice(self, raw: str, chat_pane: ChatPane) -> None:
        workers = self._pending_swarm_workers
        candidates = list(self._pending_swarm_devplans)
        self._pending_swarm_workers = None
        self._pending_swarm_devplans = []

        choice = raw.strip()
        if not choice:
            chat_pane.log_message("No selection provided.", "error")
            return

        devplan_path = ""
        if choice.isdigit() and candidates:
            idx = int(choice)
            if 1 <= idx <= len(candidates):
                p = candidates[idx - 1]
                # Prefer project-relative paths for display/consistency.
                if self.project_manager.current_project and str(p).startswith(str(self.project_manager.current_project)):
                    devplan_path = str(p.relative_to(self.project_manager.current_project))
                else:
                    devplan_path = str(p)
            else:
                chat_pane.log_message(f"Invalid selection: {choice}", "error")
                return
        else:
            devplan_path = choice

        # Re-enter swarm mode with explicit devplan.
        effective_workers = workers or str(self.config.default_workers)
        self.run_swarm_mode(f"{effective_workers} {devplan_path}", chat_pane)
    
    async def read_process_output(self, chat_pane: ChatPane) -> None:
        """Legacy output reader (kept for backwards compatibility)."""
        if not self.ralph_process or not self.ralph_process.stdout:
            return
        try:
            while True:
                line = await asyncio.get_event_loop().run_in_executor(None, self.ralph_process.stdout.readline)
                if not line:
                    break
                chat_pane.log_message(line.strip(), "ralph")
        finally:
            if self.ralph_process:
                rc = self.ralph_process.poll()
                if rc is not None:
                    chat_pane.log_message(f"Ralph process exited with code {rc}", "system")

    def spawn_process(self, name: str, cmd: List[str], cwd: Path, env: Dict[str, str], chat_pane: ChatPane) -> str:
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        pid = str(proc.pid)
        self.processes[pid] = proc
        self.process_names[pid] = name
        self.active_process_id = pid
        chat_pane.log_message(f"Started {name} (PID: {pid})", "system")

        # Also log to LogPane
        try:
            log_pane = self.query_one("#log-pane", LogPane)
            short_cmd = " ".join(cmd[:3]) + (" ..." if len(cmd) > 3 else "")
            log_pane.write_log(f"[{name}] PID:{pid} - {short_cmd}", "info")
        except Exception:
            pass

        asyncio.create_task(self.read_named_process_output(pid, chat_pane))
        return pid

    async def read_named_process_output(self, pid: str, chat_pane: ChatPane) -> None:
        proc = self.processes.get(pid)
        if not proc or not proc.stdout:
            return
        name = self.process_names.get(pid, pid)

        try:
            if name == "orchestrator":
                await self._read_orchestrator_output(proc, chat_pane)
                return

            spinner_re = re.compile(r"^\s*(?:[|\\/\-]|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏])\s")
            last_spinner_emit = 0.0
            last_spinner_text = ""

            stdout = proc.stdout
            if stdout is None:
                return

            while True:
                line = await asyncio.get_event_loop().run_in_executor(None, stdout.readline)
                if not line:
                    break

                # Some tools print spinner/progress frames as many newline-terminated
                # lines (especially when stdout isn't a TTY). Throttle those frames
                # to avoid flooding the chat log.
                cleaned = line.rstrip("\n")
                if "\r" in cleaned:
                    cleaned = cleaned.replace("\r", "")
                if spinner_re.match(cleaned):
                    now = asyncio.get_event_loop().time()
                    if cleaned == last_spinner_text and (now - last_spinner_emit) < 5.0:
                        continue
                    if (now - last_spinner_emit) < 1.0:
                        continue
                    last_spinner_emit = now
                    last_spinner_text = cleaned

                chat_pane.log_message(f"[dim][{name}][/dim] {cleaned.rstrip()}", "ralph")
        finally:
            rc = proc.poll()
            if rc is not None:
                chat_pane.log_message(f"{name} exited with code {rc}", "system")

                # Also log to LogPane
                try:
                    log_pane = self.query_one("#log-pane", LogPane)
                    if rc == 0:
                        log_pane.write_log(f"[{name}] Exit: 0 (success)", "success")
                    else:
                        log_pane.write_log(f"[{name}] Exit: {rc} (failed)", "error")
                except Exception:
                    pass

            with suppress(Exception):
                self.processes.pop(pid, None)
                self.process_names.pop(pid, None)
                if self.active_process_id == pid:
                    self.active_process_id = None

            # Resume database refresh timer
            if self.refresh_timer:
                self.refresh_timer.stop()
            self.refresh_timer = self.set_interval(self.config.refresh_interval_sec, self.refresh_status)

    async def _read_orchestrator_output(self, proc: subprocess.Popen, chat_pane: ChatPane) -> None:
        """Read opencode output without flooding the chat.

        We run the orchestrator as `opencode run --format json` and only emit the
        final assistant message.
        """

        def _extract_text(obj: Any) -> str:
            if not isinstance(obj, dict):
                return ""

            part = obj.get("part")
            if isinstance(part, dict):
                msgs = part.get("messages")
                if isinstance(msgs, list):
                    for m in msgs:
                        if isinstance(m, dict) and m.get("role") == "assistant" and m.get("text"):
                            return str(m.get("text"))
                    for m in reversed(msgs):
                        if isinstance(m, dict) and m.get("text"):
                            return str(m.get("text"))
                out = part.get("output")
                if isinstance(out, dict) and out.get("text"):
                    return str(out.get("text"))

            # Generic fallbacks (matches `ralph-refactor/lib/json.sh` intent)
            if obj.get("completion"):
                return str(obj.get("completion"))
            if obj.get("text"):
                return str(obj.get("text"))

            choices = obj.get("choices")
            if isinstance(choices, list) and choices:
                msg0 = choices[0].get("message") if isinstance(choices[0], dict) else None
                if isinstance(msg0, dict) and msg0.get("content"):
                    return str(msg0.get("content"))
                if isinstance(choices[0], dict) and choices[0].get("text"):
                    return str(choices[0].get("text"))

            return ""

        stdout = proc.stdout
        if stdout is None:
            return

        # Keep a small buffer for debugging if JSON parsing fails.
        raw_debug = ""
        last_text = ""
        try:
            while True:
                line = await asyncio.get_event_loop().run_in_executor(None, stdout.readline)
                if not line:
                    break
                raw_debug += line
                if len(raw_debug) > 20000:
                    raw_debug = raw_debug[-20000:]

                candidate = line.strip()
                if not candidate:
                    continue
                with suppress(Exception):
                    obj = json.loads(candidate)
                    extracted = _extract_text(obj)
                    if extracted:
                        last_text = extracted
        finally:
            if last_text:
                chat_pane.log_message(last_text.strip(), "ralph")
                return

            # Fallback: sometimes opencode returns a single JSON blob, not JSON-lines.
            with suppress(Exception):
                obj = json.loads(raw_debug.strip())
                last_text = _extract_text(obj)
            if last_text:
                chat_pane.log_message(last_text.strip(), "ralph")
                return

            if raw_debug.strip():
                chat_pane.log_message("[orchestrator] (no assistant text found in JSON output)", "error")
                chat_pane.log_message(raw_debug.strip()[:500], "system")

    def list_sessions(self, chat_pane: ChatPane) -> None:
        if not self.processes:
            chat_pane.log_message("No active sessions.", "system")
            return
        for pid, proc in self.processes.items():
            name = self.process_names.get(pid, pid)
            state = "running" if proc.poll() is None else f"exited({proc.poll()})"
            active = " (active)" if self.active_process_id == pid else ""
            chat_pane.log_message(f"{pid}: {name} - {state}{active}", "system")

    def focus_session(self, args: str, chat_pane: ChatPane) -> None:
        pid = args.strip()
        if not pid:
            chat_pane.log_message("Usage: /focus <PID>", "error")
            return
        if pid not in self.processes:
            chat_pane.log_message(f"Unknown PID: {pid}", "error")
            return
        self.active_process_id = pid
        chat_pane.log_message(f"Active session set to PID {pid} ({self.process_names.get(pid)})", "system")

    def stop_active_process(self, chat_pane: ChatPane) -> None:
        pid = self.active_process_id
        if not pid:
            chat_pane.log_message("No active session to stop.", "system")
            return
        proc = self.processes.get(pid)
        if not proc or proc.poll() is not None:
            chat_pane.log_message("Active session already exited.", "system")
            return
        proc.terminate()
        chat_pane.log_message(f"Stopping session {pid}...", "system")

    def handle_swarm_command(self, args: str, chat_pane: ChatPane) -> None:
        sub = args.strip().split(maxsplit=1)
        if not sub or not sub[0]:
            # Back-compat: /swarm [N]
            self.run_swarm_mode("", chat_pane)
            return
        op = sub[0].lower()
        rest = sub[1] if len(sub) > 1 else ""

        if op.isdigit():
            self.run_swarm_mode(op, chat_pane)
            return

        ralph_swarm = RALPH_REFACTOR_DIR / "ralph-swarm"
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return

        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        env["RALPH_LLM_PROVIDER"] = self.config.swarm_provider
        env["RALPH_LLM_MODEL"] = self.config.swarm_model

        cwd = self.project_manager.current_project

        if op == "start":
            self.run_swarm_mode(rest.strip(), chat_pane)
            return
        if op == "status":
            cmd = [str(ralph_swarm), "--status"]
            if rest.strip():
                cmd.append(rest.strip())
            self.spawn_process("swarm-status", cmd, cwd, env, chat_pane)
            return
        if op == "stop":
            cmd = [str(ralph_swarm), "--stop"]
            if rest.strip():
                cmd.append(rest.strip())
            self.spawn_process("swarm-stop", cmd, cwd, env, chat_pane)
            return
        if op == "cleanup":
            cmd = [str(ralph_swarm), "--cleanup"]
            if rest.strip():
                cmd.append(rest.strip())
            self.spawn_process("swarm-cleanup", cmd, cwd, env, chat_pane)
            return
        if op == "inspect":
            cmd = [str(ralph_swarm), "--inspect"]
            if rest.strip():
                cmd.append(rest.strip())
            self.spawn_process("swarm-inspect", cmd, cwd, env, chat_pane)
            return
        if op == "logs":
            # /swarm logs [RUN_ID] [--worker N] [--lines N] [--grep TEXT]
            cmd = [str(ralph_swarm), "--logs"]
            # naive arg passthrough (quoting not preserved)
            if rest.strip():
                cmd.extend(rest.split())
            self.spawn_process("swarm-logs", cmd, cwd, env, chat_pane)
            return
        if op == "reiterate":
            # /swarm reiterate [RUN_ID] --worker N
            cmd = [str(ralph_swarm), "--reiterate"]
            if rest.strip():
                cmd.extend(rest.split())
            self.spawn_process("swarm-reiterate", cmd, cwd, env, chat_pane)
            return
        if op == "resume":
            # /swarm resume RUN_ID
            run_id = rest.strip()
            if not run_id:
                chat_pane.log_message("Usage: /swarm resume <RUN_ID>", "error")
                return
            cmd = [str(ralph_swarm), "--resume", run_id]
            self.spawn_process("swarm-resume", cmd, cwd, env, chat_pane)
            return
        if op == "reset":
            # /swarm reset [RUN_ID] - resets a run to start fresh with same devplan
            run_id = rest.strip()
            cmd = [str(ralph_swarm), "--reset"]
            if run_id:
                cmd.append(run_id)
            self.spawn_process("swarm-reset", cmd, cwd, env, chat_pane)
            return

        chat_pane.log_message("Usage: /swarm start|status|logs|stop|inspect|cleanup|reiterate|resume|reset", "error")

    def force_reiterate(self, args: str, chat_pane: ChatPane) -> None:
        # /reiterate N [RUN_ID]
        parts = args.strip().split()
        if not parts:
            chat_pane.log_message("Usage: /reiterate <worker_num> [run_id]", "error")
            return
        worker = parts[0]
        run_id = parts[1] if len(parts) > 1 else ""
        ralph_swarm = RALPH_REFACTOR_DIR / "ralph-swarm"
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return
        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        env["RALPH_LLM_PROVIDER"] = self.config.swarm_provider
        env["RALPH_LLM_MODEL"] = self.config.swarm_model
        cmd = [str(ralph_swarm), "--reiterate"]
        if run_id:
            cmd.append(run_id)
        cmd.extend(["--worker", worker])
        self.spawn_process("swarm-reiterate", cmd, self.project_manager.current_project, env, chat_pane)

    def resume_run(self, args: str, chat_pane: ChatPane) -> None:
        """Resume a previous swarm run."""
        run_id = args.strip()
        if not run_id:
            chat_pane.log_message("Usage: /resume <RUN_ID>", "error")
            chat_pane.log_message("Use /system to see available runs", "system")
            return

        ralph_swarm = RALPH_REFACTOR_DIR / "ralph-swarm"
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return

        # Verify the run exists
        run_info = self.db_reader.get_run_info(run_id)
        if not run_info:
            chat_pane.log_message(f"Run not found: {run_id}", "error")
            return

        status = run_info.get("status", "unknown")
        source_path = run_info.get("source_path", "")

        chat_pane.log_message(f"Resuming run: {run_id}", "system")
        chat_pane.log_message(f"  Status: {status}", "system")
        chat_pane.log_message(f"  Devplan: {source_path}", "system")

        if status == "completed":
            chat_pane.log_message("This run is already completed. Use /swarm start to start a new run.", "warning")
            return

        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        env["RALPH_LLM_PROVIDER"] = self.config.swarm_provider
        env["RALPH_LLM_MODEL"] = self.config.swarm_model
        env["SWARM_COLLECT_ARTIFACTS"] = "true" if self.config.swarm_collect_artifacts else "false"

        cmd = [str(ralph_swarm), "--resume", run_id]
        self.spawn_process(f"swarm-resume({run_id[:8]})", cmd, self.project_manager.current_project, env, chat_pane)

    def export_run_report(self, args: str, chat_pane: ChatPane) -> None:
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return
        run_id = args.strip() or ""
        run_info = None
        if not run_id:
            run_info = self.db_reader.get_latest_run() or None
            if run_info:
                run_id = run_info.get("run_id", "")
        if not run_id:
            chat_pane.log_message("No run id found. Provide /report <run_id> or run swarm first.", "error")
            return

        out_dir = self.project_manager.current_project / "output"
        out_dir.mkdir(parents=True, exist_ok=True)
        report_path = out_dir / f"swarm-report-{run_id}.md"

        run_info = run_info or self.db_reader.get_run_info(run_id) or {}
        workers = self.db_reader.get_run_workers(run_id)
        tasks = self.db_reader.get_run_tasks(run_id)
        stats = self.db_reader.get_task_stats(run_id)
        cost = self.db_reader.get_run_cost(run_id)

        lines: List[str] = []
        lines.append(f"# Swarm Run Report: {run_id}")
        lines.append("")
        lines.append(f"- Status: {run_info.get('status', 'unknown')}")
        lines.append(f"- Workers: {run_info.get('worker_count', len(workers) or 'unknown')}")
        lines.append(f"- Tasks: done={stats.get('completed', 0)} active={stats.get('in_progress', 0)} pending={stats.get('pending', 0)} failed={stats.get('failed', 0)}")
        lines.append(f"- Cost: ${cost:.4f}")
        lines.append("")

        lines.append("## Workers")
        lines.append("")
        for w in workers:
            lines.append(
                f"- Worker {w.get('worker_num')}: status={w.get('status')} pid={w.get('pid')} branch={w.get('branch_name')} task_id={w.get('current_task_id')}"
            )
        lines.append("")

        lines.append("## Tasks")
        lines.append("")
        for t in tasks:
            lines.append(
                f"- [{t.get('status')}] #{t.get('id')} worker={t.get('worker_id')} priority={t.get('priority')} line={t.get('devplan_line')}: {t.get('task_text')}"
            )
        lines.append("")

        report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        chat_pane.log_message(f"Wrote report: {report_path}", "system")

    def build_orchestrator_prompt(self, user_prompt: str) -> str:
        project = self.project_manager.current_project
        run = self.db_reader.get_latest_run() or {}
        run_id = run.get("run_id", "")
        workers = self.db_reader.get_run_workers(run_id) if run_id else []
        stats = self.db_reader.get_task_stats(run_id) if run_id else {"pending": 0, "in_progress": 0, "completed": 0, "failed": 0}
        cost = self.db_reader.get_run_cost(run_id) if run_id else 0.0

        devplan_path = project / "devplan.md" if project else None
        devplan_excerpt = ""
        if devplan_path and devplan_path.exists():
            with suppress(Exception):
                devplan_excerpt = "\n".join(devplan_path.read_text(encoding="utf-8", errors="replace").splitlines()[:120])

        worker_lines = []
        for w in workers:
            worker_lines.append(
                f"- worker_num={w.get('worker_num')} status={w.get('status')} pid={w.get('pid')} task_id={w.get('current_task_id')} branch={w.get('branch_name')} heartbeat={w.get('last_heartbeat')}"
            )
        workers_block = "\n".join(worker_lines) if worker_lines else "(no workers)"

        return "\n".join(
            [
                "You are the Orchestration Agent inside Ralph TUI.",
                "Your job: answer questions about the current swarm run and help control it.",
                "You can edit project files (especially devplan.md) and run CLI commands.",
                "If the user asks to add detours or update the devplan, edit the project devplan.md accordingly.",
                "If the user reports a worker is stuck or misbehaving, force a reiteration by running:",
                f"  {RALPH_REFACTOR_DIR}/ralph-swarm --reiterate {run_id} --worker <N>",
                "If run_id is empty, instruct the user to start the swarm or provide the run id.",
                "Prefer minimal, safe actions. Explain what you changed.",
                "",
                f"Project: {project}",
                f"Swarm run_id: {run_id}",
                f"Task stats: {stats}  cost=${cost:.4f}",
                "Workers:",
                workers_block,
                "",
                "devplan.md (excerpt):",
                devplan_excerpt or "(missing)",
                "",
                "User:",
                user_prompt,
            ]
        )

    def run_orchestrator_command(self, prompt: str, chat_pane: ChatPane) -> None:
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return

        full_prompt = self.build_orchestrator_prompt(prompt)
        cmd: List[str] = ["opencode", "run", "--format", "json"]
        if self.config.orchestration_attach_url:
            cmd.extend(["--attach", self.config.orchestration_attach_url])

        provider = (self.config.orchestration_provider or "").strip()
        model = (self.config.orchestration_model or "").strip()
        model_arg = model
        if provider and model and "/" not in model:
            model_arg = f"{provider}/{model}"
        if model_arg:
            cmd.extend(["--model", model_arg])
        cmd.append(full_prompt)

        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        self.spawn_process("orchestrator", cmd, self.project_manager.current_project, env, chat_pane)

    def apply_theme(self, theme: str) -> None:
        theme = theme or "paper"
        if theme == "midnight":
            self.dark = True
        else:
            self.dark = False

    def action_open_settings(self) -> None:
        chat_pane = self.query_one("#chat-pane", ChatPane)
        self.open_settings(chat_pane)

    def action_toggle_theme(self) -> None:
        self.config.theme = "midnight" if self.config.theme == "paper" else "paper"
        save_tui_config(self.config)
        self.apply_theme(self.config.theme)
        chat_pane = self.query_one("#chat-pane", ChatPane)
        chat_pane.log_message(f"Theme set to: {self.config.theme}", "system")

    def start_file_watch(self, root: Path) -> None:
        if not self.config.enable_file_watch:
            return
        if awatch is None:
            return
        if self._file_watch_task:
            self.stop_file_watch()
        self._file_watch_stop = asyncio.Event()
        self._file_watch_task = asyncio.create_task(self._watch_project(root))

    def stop_file_watch(self) -> None:
        if self._file_watch_stop:
            self._file_watch_stop.set()
        if self._file_watch_task:
            with suppress(Exception):
                self._file_watch_task.cancel()
        self._file_watch_task = None
        self._file_watch_stop = None

    async def _watch_project(self, root: Path) -> None:
        if awatch is None or not self._file_watch_stop:
            return
        debounce_deadline: Optional[float] = None
        async for _changes in awatch(str(root), stop_event=self._file_watch_stop):
            debounce_deadline = asyncio.get_event_loop().time() + 0.25
            await asyncio.sleep(0.05)
            if debounce_deadline and asyncio.get_event_loop().time() < debounce_deadline:
                continue
            with suppress(Exception):
                file_pane = self.query_one("#file-pane", FilePane)
                file_pane.refresh_tree()
    
    def show_status(self, chat_pane: ChatPane) -> None:
        """Show current status."""
        run_info = self.db_reader.get_latest_run()
        
        if run_info:
            run_id = run_info.get("run_id", "N/A")
            status = run_info.get("status", "N/A")
            stats = self.db_reader.get_task_stats(run_id)
            
            chat_pane.log_message(f"Run: {run_id}, Status: {status}", "system")
            chat_pane.log_message(
                f"Tasks - Completed: {stats['completed']}, "
                f"In Progress: {stats['in_progress']}, "
                f"Pending: {stats['pending']}, "
                f"Failed: {stats['failed']}",
                "system"
            )
        else:
            chat_pane.log_message("No active swarm runs.", "system")
        
        if self.ralph_process and self.ralph_process.poll() is None:
            chat_pane.log_message(f"Ralph process running (PID: {self.ralph_process.pid})", "system")
        else:
            chat_pane.log_message("No Ralph process running.", "system")
        
        if self.project_manager.current_project:
            chat_pane.log_message(f"Current project: {self.project_manager.current_project}", "system")
    
    def stop_ralph(self, chat_pane: ChatPane) -> None:
        """Stop current Ralph process."""
        # Prefer stopping active session if present.
        if self.active_process_id and self.active_process_id in self.processes:
            self.stop_active_process(chat_pane)
            return
        if self.ralph_process and self.ralph_process.poll() is None:
            self.ralph_process.terminate()
            chat_pane.log_message("Stopping Ralph...", "system")
            try:
                self.ralph_process.wait(timeout=5)
                chat_pane.log_message("Ralph stopped.", "system")
            except subprocess.TimeoutExpired:
                self.ralph_process.kill()
                chat_pane.log_message("Ralph killed.", "system")
        else:
            chat_pane.log_message("No Ralph process running.", "system")

    def emergency_stop_swarm(self, chat_pane: ChatPane) -> None:
        """Emergency stop - kill all swarm workers immediately."""
        chat_pane.log_message("[bold red]EMERGENCY STOP[/bold red] - Killing all swarm workers...", "error")

        # Kill all managed processes
        killed_count = 0
        for pid_str, proc in list(self.processes.items()):
            try:
                if proc.poll() is None:
                    proc.kill()
                    killed_count += 1
                    chat_pane.log_message(f"Killed process {pid_str} ({self.process_names.get(pid_str, 'unknown')})", "error")
            except Exception:
                pass

        # Also try to kill via ralph-swarm emergency-stop
        try:
            ralph_swarm = RALPH_REFACTOR_DIR / "ralph-swarm"
            if ralph_swarm.exists():
                result = subprocess.run(
                    [str(ralph_swarm), "--emergency-stop"],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                if result.returncode == 0:
                    chat_pane.log_message("ran ralph-swarm --emergency-stop", "system")
        except Exception as e:
            chat_pane.log_message(f"Could not run emergency-stop: {e}", "error")

        # Clear process tracking
        self.processes.clear()
        self.process_names.clear()
        self.active_process_id = None

        chat_pane.log_message(f"Emergency stop complete. Killed {killed_count} processes.", "system")

    def show_system_stats(self, chat_pane: ChatPane) -> None:
        """Show system-wide swarm statistics."""
        try:
            db_path = SWARM_DB
            if not db_path.exists():
                chat_pane.log_message("No swarm database found.", "system")
                return

            import sqlite3
            conn = sqlite3.connect(str(db_path), timeout=10.0)

            # Get active workers
            cursor = conn.execute(
                "SELECT COUNT(*) FROM worker_registry WHERE last_heartbeat >= datetime('now', '-60 seconds')"
            )
            active_workers = cursor.fetchone()[0]

            # Get running runs
            cursor = conn.execute("SELECT COUNT(*) FROM swarm_runs WHERE status = 'running'")
            running_runs = cursor.fetchone()[0]

            # Get pending tasks
            cursor = conn.execute("SELECT COUNT(*) FROM tasks WHERE status = 'pending'")
            pending_tasks = cursor.fetchone()[0]

            # Get active tasks
            cursor = conn.execute("SELECT COUNT(*) FROM tasks WHERE status = 'in_progress'")
            active_tasks = cursor.fetchone()[0]

            conn.close()

            # Read limits from config
            max_workers = 8
            max_total = 16
            config_path = RALPH_DIR / "ralph.config"
            if config_path.exists():
                for line in config_path.read_text().splitlines():
                    if line.startswith("SWARM_MAX_WORKERS="):
                        max_workers = int(line.split("=", 1)[1].strip())
                    elif line.startswith("SWARM_MAX_TOTAL_WORKERS="):
                        max_total = int(line.split("=", 1)[1].strip())

            stats_msg = f"""[bold]System Statistics:[/bold]
[cyan]Active Workers:[/cyan] {active_workers} / {max_total} (system limit)
[cyan]Running Runs:[/cyan] {running_runs}
[cyan]Pending Tasks:[/cyan] {pending_tasks}
[cyan]Active Tasks:[/cyan] {active_tasks}
[cyan]Max Workers/Run:[/cyan] {max_workers}
[cyan]Max Total Workers:[/cyan] {max_total}"""

            chat_pane.log_message(stats_msg, "system")

        except Exception as e:
            chat_pane.log_message(f"Error getting system stats: {e}", "error")
    
    def show_logs(self, chat_pane: ChatPane) -> None:
        """Show recent logs."""
        run_info = self.db_reader.get_latest_run()
        if not run_info:
            chat_pane.log_message("No runs found.", "system")
            return
        
        run_id = run_info.get("run_id", "")
        run_dir = RALPH_DIR / "swarm" / "runs" / run_id
        
        if not run_dir.exists():
            chat_pane.log_message(f"Run directory not found: {run_dir}", "error")
            return
        
        # Find log files
        log_files = list(run_dir.glob("worker-*/logs/*.log"))
        if log_files:
            for log_file in log_files[:3]:  # Show first 3 log files
                chat_pane.log_message(f"Log: {log_file.name}", "system")
                try:
                    lines = log_file.read_text().split("\n")[-5:]
                    for line in lines:
                        if line.strip():
                            chat_pane.log_message(f"  {line[:80]}", "system")
                except Exception as e:
                    chat_pane.log_message(f"Error reading log: {e}", "error")
        else:
            chat_pane.log_message("No log files found.", "system")
    
    def run_ralph_command(self, prompt: str, chat_pane: ChatPane) -> None:
        """Run a general Ralph command/prompt."""
        if not self.project_manager.current_project:
            chat_pane.log_message("No project open. Use /new or /open first.", "error")
            return
        
        project_dir = self.project_manager.current_project
        
        env = os.environ.copy()
        env["RALPH_DIR"] = str(RALPH_DIR)
        
        try:
            cmd = [str(RALPH2_PATH), prompt]
            self.spawn_process("ralph", cmd, project_dir, env, chat_pane)
        except Exception as e:
            chat_pane.log_message(f"Failed to run command: {e}", "error")
    
    async def action_quit(self) -> None:
        """Quit the application."""
        # Best-effort: terminate any active sessions.
        for proc in list(self.processes.values()):
            if proc.poll() is None:
                with suppress(Exception):
                    proc.terminate()
        if self.ralph_process and self.ralph_process.poll() is None:
            self.ralph_process.terminate()
        self.stop_file_watch()
        self.exit()
    
    def action_new_project(self) -> None:
        """Action: New project."""
        chat_pane = self.query_one("#chat-pane", ChatPane)
        chat_pane.log_message("Enter project name with /new <name>", "system")
    
    def action_open_project(self) -> None:
        """Action: Open project."""
        chat_pane = self.query_one("#chat-pane", ChatPane)
        projects = self.project_manager.list_projects()
        if projects:
            chat_pane.log_message("Available projects: " + ", ".join(projects), "system")
            chat_pane.log_message("Use /open <name> to open", "system")
        else:
            chat_pane.log_message("No projects. Use /new <name> to create.", "system")
    
    def action_run_swarm(self) -> None:
        """Action: Run swarm."""
        chat_pane = self.query_one("#chat-pane", ChatPane)
        self.run_swarm_mode("", chat_pane)
    
    def action_stop_swarm(self) -> None:
        """Action: Stop swarm."""
        chat_pane = self.query_one("#chat-pane", ChatPane)
        self.stop_active_process(chat_pane)
    
    def action_show_help(self) -> None:
        """Action: Show help."""
        chat_pane = self.query_one("#chat-pane", ChatPane)
        self.show_help_text(chat_pane)
    
    def action_refresh(self) -> None:
        """Action: Refresh status."""
        self.refresh_status()


def main():
    """Main entry point."""
    app = RalphTUI()
    app.run()


if __name__ == "__main__":
    main()
