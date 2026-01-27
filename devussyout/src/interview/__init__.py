"""Interview module for continuous LLM chat-based devplan generation.

This module provides a conversational interface for generating development plans
through a multi-stage LLM chat experience. Users can chat naturally to:
1. Gather project requirements
2. Generate and review project designs
3. Create and refine development plans
4. Generate detailed phase steps
5. Create handoff prompts

Key components:
- InterviewManager: Main orchestrator for conversation flow
- ConversationHistory: Stores messages across stages
- StageCoordinator: Manages stage transitions with stage-specific prompts
- JSONExtractor: Parses structured data from LLM responses
"""

from .conversation_history import ConversationHistory, Message
from .json_extractor import JSONExtractor
from .stage_coordinator import StageCoordinator, Stage
from .interview_manager import InterviewManager

__all__ = [
    "ConversationHistory",
    "Message",
    "JSONExtractor",
    "StageCoordinator",
    "Stage",
    "InterviewManager",
]
