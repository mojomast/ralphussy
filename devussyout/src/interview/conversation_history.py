"""Conversation history management for multi-stage LLM interviews.

This module stores and manages conversation messages across all interview stages,
providing methods to retrieve context for each stage and format messages for LLM APIs.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from pathlib import Path


class MessageRole(str, Enum):
    """Role of a message in the conversation."""
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"


@dataclass
class Message:
    """A single message in the conversation history.
    
    Attributes:
        role: Who sent the message (system, user, assistant)
        content: The text content of the message
        timestamp: When the message was created
        stage: Which interview stage this message belongs to
        metadata: Optional additional data (e.g., token counts, model info)
    """
    role: MessageRole
    content: str
    timestamp: datetime = field(default_factory=datetime.now)
    stage: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert message to dictionary format."""
        return {
            "role": self.role.value,
            "content": self.content,
            "timestamp": self.timestamp.isoformat(),
            "stage": self.stage,
            "metadata": self.metadata,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Message":
        """Create message from dictionary."""
        return cls(
            role=MessageRole(data["role"]),
            content=data["content"],
            timestamp=datetime.fromisoformat(data["timestamp"]) if data.get("timestamp") else datetime.now(),
            stage=data.get("stage"),
            metadata=data.get("metadata", {}),
        )


class ConversationHistory:
    """Manages conversation history across interview stages.
    
    Provides methods for:
    - Adding messages with stage tracking
    - Retrieving messages by stage or recency
    - Formatting messages for LLM API calls
    - Persisting and loading conversation state
    - Summarizing conversation for context windows
    
    Example:
        history = ConversationHistory()
        history.add_message(MessageRole.USER, "I want to build a REST API", stage="interview")
        history.add_message(MessageRole.ASSISTANT, "What language...", stage="interview")
        
        # Get messages for LLM call
        messages = history.to_llm_format(recent_count=10)
    """
    
    def __init__(self, max_history: int = 100):
        """Initialize conversation history.
        
        Args:
            max_history: Maximum messages to retain (oldest are dropped)
        """
        self._messages: List[Message] = []
        self._max_history = max_history
        self._stage_outputs: Dict[str, Any] = {}  # Stores extracted data per stage
    
    def add_message(
        self,
        role: MessageRole,
        content: str,
        stage: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Message:
        """Add a new message to the conversation.
        
        Args:
            role: Who sent the message
            content: Message text
            stage: Current interview stage
            metadata: Optional extra data
            
        Returns:
            The created Message object
        """
        msg = Message(
            role=role,
            content=content,
            stage=stage,
            metadata=metadata or {},
        )
        self._messages.append(msg)
        
        # Trim if over max
        if len(self._messages) > self._max_history:
            self._messages = self._messages[-self._max_history:]
        
        return msg
    
    def add_user_message(self, content: str, stage: Optional[str] = None) -> Message:
        """Convenience method to add a user message."""
        return self.add_message(MessageRole.USER, content, stage)
    
    def add_assistant_message(self, content: str, stage: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> Message:
        """Convenience method to add an assistant message."""
        return self.add_message(MessageRole.ASSISTANT, content, stage, metadata)
    
    def add_system_message(self, content: str, stage: Optional[str] = None) -> Message:
        """Convenience method to add a system message."""
        return self.add_message(MessageRole.SYSTEM, content, stage)
    
    def get_all(self) -> List[Message]:
        """Get all messages in order."""
        return list(self._messages)
    
    def get_recent(self, count: int = 10) -> List[Message]:
        """Get the most recent messages.
        
        Args:
            count: Number of recent messages to return
            
        Returns:
            List of most recent messages
        """
        return self._messages[-count:] if count < len(self._messages) else list(self._messages)
    
    def get_by_stage(self, stage: str) -> List[Message]:
        """Get all messages for a specific stage.
        
        Args:
            stage: Stage name to filter by
            
        Returns:
            List of messages from that stage
        """
        return [m for m in self._messages if m.stage == stage]
    
    def get_by_role(self, role: MessageRole) -> List[Message]:
        """Get all messages from a specific role."""
        return [m for m in self._messages if m.role == role]
    
    def to_llm_format(
        self,
        recent_count: Optional[int] = None,
        include_system: bool = True,
        stages: Optional[List[str]] = None,
    ) -> List[Dict[str, str]]:
        """Format messages for LLM API calls.
        
        Args:
            recent_count: If set, only include this many recent messages
            include_system: Whether to include system messages
            stages: If set, only include messages from these stages
            
        Returns:
            List of {"role": "...", "content": "..."} dicts
        """
        messages = self._messages
        
        # Filter by stages if specified
        if stages:
            messages = [m for m in messages if m.stage in stages]
        
        # Filter system messages if requested
        if not include_system:
            messages = [m for m in messages if m.role != MessageRole.SYSTEM]
        
        # Get recent if specified
        if recent_count and recent_count < len(messages):
            messages = messages[-recent_count:]
        
        return [{"role": m.role.value, "content": m.content} for m in messages]
    
    def get_context_summary(self, max_tokens: int = 2000) -> str:
        """Generate a summary of the conversation for context.
        
        Useful when conversation is too long for context window.
        
        Args:
            max_tokens: Approximate max tokens for summary (rough char estimate)
            
        Returns:
            Summarized conversation text
        """
        # Simple implementation: take recent messages + stage outputs
        summary_parts = []
        
        # Add stage outputs
        for stage, output in self._stage_outputs.items():
            if isinstance(output, dict):
                summary_parts.append(f"[{stage.upper()} OUTPUT]:\n{json.dumps(output, indent=2)[:500]}")
            else:
                summary_parts.append(f"[{stage.upper()} OUTPUT]:\n{str(output)[:500]}")
        
        # Add recent messages
        recent = self.get_recent(5)
        for msg in recent:
            content = msg.content[:300] + "..." if len(msg.content) > 300 else msg.content
            summary_parts.append(f"[{msg.role.value.upper()}]: {content}")
        
        summary = "\n\n".join(summary_parts)
        
        # Rough token estimation (1 token ~ 4 chars)
        max_chars = max_tokens * 4
        if len(summary) > max_chars:
            summary = summary[:max_chars] + "..."
        
        return summary
    
    def set_stage_output(self, stage: str, output: Any) -> None:
        """Store the extracted output for a stage.
        
        Args:
            stage: Stage name
            output: Extracted data (usually dict or Pydantic model)
        """
        self._stage_outputs[stage] = output
    
    def get_stage_output(self, stage: str) -> Optional[Any]:
        """Get the stored output for a stage."""
        return self._stage_outputs.get(stage)
    
    def get_all_stage_outputs(self) -> Dict[str, Any]:
        """Get all stage outputs."""
        return dict(self._stage_outputs)
    
    def clear(self) -> None:
        """Clear all messages and stage outputs."""
        self._messages.clear()
        self._stage_outputs.clear()
    
    def clear_from_stage(self, stage: str) -> None:
        """Clear messages from a specific stage onwards.
        
        Useful when user wants to redo a stage.
        """
        # Find first message of stage and remove from there
        idx = None
        for i, msg in enumerate(self._messages):
            if msg.stage == stage:
                idx = i
                break
        
        if idx is not None:
            self._messages = self._messages[:idx]
            # Also clear stage outputs from this stage onwards
            stages_to_clear = []
            for s in self._stage_outputs:
                # This is a simple clear - in practice you'd want stage ordering
                if s == stage:
                    stages_to_clear.append(s)
            for s in stages_to_clear:
                del self._stage_outputs[s]
    
    def save(self, path: Path) -> None:
        """Save conversation to a JSON file.
        
        Args:
            path: File path to save to
        """
        data = {
            "messages": [m.to_dict() for m in self._messages],
            "stage_outputs": {
                k: v.model_dump() if hasattr(v, 'model_dump') else v
                for k, v in self._stage_outputs.items()
            },
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, default=str)
    
    def load(self, path: Path) -> None:
        """Load conversation from a JSON file.
        
        Args:
            path: File path to load from
        """
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        self._messages = [Message.from_dict(m) for m in data.get("messages", [])]
        self._stage_outputs = data.get("stage_outputs", {})
    
    def __len__(self) -> int:
        """Return number of messages."""
        return len(self._messages)
    
    def __bool__(self) -> bool:
        """Return True if there are any messages."""
        return len(self._messages) > 0
