"""Session-based interview manager for non-TTY environments.

This module provides a state machine for running interviews in environments
like OpenTUI where:
- sys.stdin.isatty() is False
- Blocking input() doesn't work
- The program must process one message at a time and return
- State must persist across invocations

The SessionManager handles:
- Detecting active sessions
- Persisting interview state to disk
- Loading and resuming sessions
- One-message-at-a-time processing
"""

import json
import sys
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import dataclass, asdict
import asyncio

from .interview_manager import InterviewManager, InterviewConfig


@dataclass
class SessionState:
    """Persistent state for an interview session."""
    session_id: str
    project_name: Optional[str]
    current_stage: str
    is_complete: bool
    last_response: str
    message_count: int
    config_dict: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'SessionState':
        return cls(**data)


class SessionManager:
    """Manages persistent interview sessions for non-TTY environments."""

    def __init__(self, session_dir: Optional[Path] = None):
        """Initialize session manager.

        Args:
            session_dir: Directory to store session state files.
                        Defaults to ~/.ralph/sessions
        """
        self.session_dir = session_dir or (Path.home() / ".ralph" / "sessions")
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.manager: Optional[InterviewManager] = None
        self.state: Optional[SessionState] = None

    def _get_session_file(self, session_id: str) -> Path:
        """Get the session state file path."""
        return self.session_dir / f"{session_id}.json"

    def _get_active_session_file(self) -> Path:
        """Get the active session marker file."""
        return self.session_dir / "active_session.txt"

    def get_active_session_id(self) -> Optional[str]:
        """Get the ID of the currently active session."""
        active_file = self._get_active_session_file()
        if active_file.exists():
            return active_file.read_text().strip()
        return None

    def set_active_session(self, session_id: str) -> None:
        """Mark a session as active."""
        self._get_active_session_file().write_text(session_id)

    def clear_active_session(self) -> None:
        """Clear the active session marker."""
        active_file = self._get_active_session_file()
        if active_file.exists():
            active_file.unlink()

    def session_exists(self, session_id: str) -> bool:
        """Check if a session exists."""
        return self._get_session_file(session_id).exists()

    def save_state(self) -> None:
        """Save current session state to disk."""
        if not self.state or not self.manager:
            return

        # Update state from manager
        self.state.current_stage = str(self.manager.coordinator.current_stage)
        self.state.is_complete = self.manager.is_complete
        self.state.project_name = self.manager._project_name

        # Save to file
        session_file = self._get_session_file(self.state.session_id)
        with open(session_file, 'w') as f:
            json.dump(self.state.to_dict(), f, indent=2)

    def load_state(self, session_id: str) -> bool:
        """Load session state from disk.

        Args:
            session_id: Session ID to load

        Returns:
            True if session was loaded successfully
        """
        session_file = self._get_session_file(session_id)
        if not session_file.exists():
            return False

        with open(session_file, 'r') as f:
            state_dict = json.load(f)

        self.state = SessionState.from_dict(state_dict)

        # Reconstruct InterviewManager
        config_dict = self.state.config_dict
        config = InterviewConfig(
            provider=config_dict.get('provider', ''),
            model=config_dict.get('model', ''),
            streaming=config_dict.get('streaming', False),
            save_dir=Path(config_dict.get('save_dir', str(Path.home() / ".ralph" / "devplans"))),
            max_history=config_dict.get('max_history', 50),
            timeout=config_dict.get('timeout', 300),
        )

        self.manager = InterviewManager(config)

        # Restore manager state by loading its conversation history
        # The InterviewManager will restore its internal state from the history
        if self.manager._project_name is None and self.state.project_name:
            self.manager._project_name = self.state.project_name

        return True

    async def create_session(self, config: InterviewConfig, initial_message: Optional[str] = None) -> str:
        """Create a new interview session.

        Args:
            config: Interview configuration
            initial_message: Optional initial user message

        Returns:
            Response from the interview
        """
        import time

        # Generate session ID
        session_id = f"session_{int(time.time())}"

        # Create manager
        self.manager = InterviewManager(config)

        # Disable streaming for non-TTY
        self.manager.config.streaming = False

        # Initialize state
        self.state = SessionState(
            session_id=session_id,
            project_name=None,
            current_stage="INTERVIEW",
            is_complete=False,
            last_response="",
            message_count=0,
            config_dict={
                'provider': config.provider,
                'model': config.model,
                'streaming': False,
                'save_dir': str(config.save_dir),
                'max_history': config.max_history,
                'timeout': config.timeout,
            }
        )

        # Mark as active
        self.set_active_session(session_id)

        # Start interview
        response = await self.manager.start(initial_message)

        self.state.last_response = response
        self.state.message_count = 1

        # Save state
        self.save_state()

        return response

    async def process_message(self, message: str) -> str:
        """Process a single user message in the current session.

        Args:
            message: User message

        Returns:
            Response from the interview
        """
        if not self.manager or not self.state:
            return "Error: No active session. This should not happen."

        # Process message
        response = await self.manager.chat(message)

        # Update state
        self.state.last_response = response
        self.state.message_count += 1

        # Save state
        self.save_state()

        # If complete, clear active session
        if self.manager.is_complete:
            result = self.manager.get_result()
            self.clear_active_session()
            return f"{response}\n\nInterview complete! Output saved to: {result.output_dir}"

        return response

    async def resume_or_create(
        self,
        config: InterviewConfig,
        initial_message: Optional[str] = None
    ) -> str:
        """Resume active session or create new one.

        Args:
            config: Interview configuration
            initial_message: Optional initial user message for new sessions

        Returns:
            Response from the interview
        """
        # Check for active session
        active_id = self.get_active_session_id()

        if active_id and self.session_exists(active_id):
            # Resume existing session
            self.load_state(active_id)
            return f"[Resumed session {active_id}]\n\n{self.state.last_response}"
        else:
            # Create new session
            return await self.create_session(config, initial_message)

    def get_status(self) -> str:
        """Get current session status."""
        if not self.state or not self.manager:
            return "No active session"

        progress = self.manager.get_progress()

        return f"""Session: {self.state.session_id}
Project: {self.state.project_name or 'Not set'}
Stage: {progress.get('stage', 'Unknown')}
Progress: {progress.get('progress_percent', 0)}%
Messages: {self.state.message_count}
Complete: {self.state.is_complete}"""
