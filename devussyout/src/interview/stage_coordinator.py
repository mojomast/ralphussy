"""Stage coordination for multi-stage interview pipeline.

This module manages the interview stages and their transitions, loading
appropriate system prompts for each stage and coordinating the flow.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional


class Stage(str, Enum):
    """Interview pipeline stages.
    
    Each stage has a specific purpose and system prompt:
    - INTERVIEW: Gather project requirements through conversation
    - DESIGN: Generate project design from requirements
    - DEVPLAN: Create high-level development plan with phases
    - DETAILED: Generate detailed steps for each phase
    - HANDOFF: Create handoff prompt for implementation
    """
    INTERVIEW = "interview"
    DESIGN = "design"
    DEVPLAN = "devplan"
    DETAILED = "detailed"
    HANDOFF = "handoff"
    
    @property
    def display_name(self) -> str:
        """Human-readable stage name."""
        return {
            Stage.INTERVIEW: "Requirements Gathering",
            Stage.DESIGN: "Project Design",
            Stage.DEVPLAN: "Development Plan",
            Stage.DETAILED: "Detailed Steps",
            Stage.HANDOFF: "Handoff Prompt",
        }[self]
    
    @property
    def description(self) -> str:
        """Brief description of what this stage does."""
        return {
            Stage.INTERVIEW: "Chat to gather project requirements and preferences",
            Stage.DESIGN: "Generate a comprehensive project design document",
            Stage.DEVPLAN: "Create a high-level development plan with phases",
            Stage.DETAILED: "Generate detailed implementation steps for each phase",
            Stage.HANDOFF: "Create a handoff prompt for the implementation agent",
        }[self]
    
    @property
    def next_stage(self) -> Optional["Stage"]:
        """Get the next stage in the pipeline."""
        order = [Stage.INTERVIEW, Stage.DESIGN, Stage.DEVPLAN, Stage.DETAILED, Stage.HANDOFF]
        try:
            idx = order.index(self)
            if idx < len(order) - 1:
                return order[idx + 1]
        except ValueError:
            pass
        return None
    
    @property
    def prev_stage(self) -> Optional["Stage"]:
        """Get the previous stage in the pipeline."""
        order = [Stage.INTERVIEW, Stage.DESIGN, Stage.DEVPLAN, Stage.DETAILED, Stage.HANDOFF]
        try:
            idx = order.index(self)
            if idx > 0:
                return order[idx - 1]
        except ValueError:
            pass
        return None


@dataclass
class StageConfig:
    """Configuration for a pipeline stage.
    
    Attributes:
        stage: The stage enum value
        system_prompt: The system prompt for this stage
        temperature: LLM temperature setting (0.0-1.0)
        max_tokens: Maximum tokens for response
        requires_previous: List of stages that must complete before this one
        auto_advance: Whether to auto-advance to next stage when complete
    """
    stage: Stage
    system_prompt: str = ""
    temperature: float = 0.7
    max_tokens: int = 4000
    requires_previous: List[Stage] = field(default_factory=list)
    auto_advance: bool = False


class StageCoordinator:
    """Coordinates stage transitions and manages stage-specific configurations.
    
    Responsibilities:
    - Load system prompts for each stage
    - Track current stage and progress
    - Determine when stages are complete
    - Manage stage transitions
    - Provide stage context to LLM calls
    
    Example:
        coordinator = StageCoordinator()
        
        # Start interview
        prompt = coordinator.get_system_prompt(Stage.INTERVIEW)
        
        # Check if ready to advance
        if coordinator.can_advance():
            coordinator.advance_stage()
    """
    
    # Default prompts directory relative to this file
    DEFAULT_PROMPTS_DIR = Path(__file__).parent.parent.parent / "prompts"
    
    def __init__(self, prompts_dir: Optional[Path] = None):
        """Initialize stage coordinator.
        
        Args:
            prompts_dir: Directory containing system prompt files.
                        Defaults to devussyout/prompts/
        """
        self.prompts_dir = prompts_dir or self.DEFAULT_PROMPTS_DIR
        self._current_stage = Stage.INTERVIEW
        self._completed_stages: List[Stage] = []
        self._stage_configs: Dict[Stage, StageConfig] = {}
        self._stage_outputs: Dict[Stage, Any] = {}
        self._on_stage_change: Optional[Callable[[Stage, Stage], None]] = None
        
        # Initialize configs
        self._init_stage_configs()
    
    def _init_stage_configs(self) -> None:
        """Initialize configurations for all stages."""
        for stage in Stage:
            prompt = self._load_prompt(stage)
            
            # Stage-specific settings
            configs = {
                Stage.INTERVIEW: StageConfig(
                    stage=stage,
                    system_prompt=prompt,
                    temperature=0.7,
                    max_tokens=2000,
                    requires_previous=[],
                    auto_advance=False,  # User controls when interview is done
                ),
                Stage.DESIGN: StageConfig(
                    stage=stage,
                    system_prompt=prompt,
                    temperature=0.5,
                    max_tokens=4000,
                    requires_previous=[Stage.INTERVIEW],
                    auto_advance=True,
                ),
                Stage.DEVPLAN: StageConfig(
                    stage=stage,
                    system_prompt=prompt,
                    temperature=0.5,
                    max_tokens=3000,
                    requires_previous=[Stage.DESIGN],
                    auto_advance=True,
                ),
                Stage.DETAILED: StageConfig(
                    stage=stage,
                    system_prompt=prompt,
                    temperature=0.4,
                    max_tokens=4000,
                    requires_previous=[Stage.DEVPLAN],
                    auto_advance=True,
                ),
                Stage.HANDOFF: StageConfig(
                    stage=stage,
                    system_prompt=prompt,
                    temperature=0.3,
                    max_tokens=3000,
                    requires_previous=[Stage.DETAILED],
                    auto_advance=False,
                ),
            }
            
            self._stage_configs[stage] = configs.get(stage, StageConfig(stage=stage, system_prompt=prompt))
    
    def _load_prompt(self, stage: Stage) -> str:
        """Load system prompt for a stage from file.
        
        Args:
            stage: Stage to load prompt for
            
        Returns:
            System prompt text
        """
        prompt_file = self.prompts_dir / f"{stage.value}_system_prompt.md"
        
        if prompt_file.exists():
            return prompt_file.read_text(encoding="utf-8")
        
        # Return default prompts if file doesn't exist
        return self._get_default_prompt(stage)
    
    def _get_default_prompt(self, stage: Stage) -> str:
        """Get default system prompt for a stage.
        
        Used when prompt file doesn't exist.
        """
        defaults = {
            Stage.INTERVIEW: """You are Ralph, an AI assistant specializing in gathering requirements for software development planning.

Your goal is to collect project information through natural conversation:
- Project name and description
- Programming languages and frameworks
- Technical requirements and constraints
- APIs and integrations needed
- Deployment preferences
- Testing requirements

Ask questions one at a time. Be conversational and follow up on answers.
When you have enough information, output a JSON object with the collected data:

```json
{
  "project_name": "...",
  "description": "...",
  "languages": ["...", "..."],
  "frameworks": ["...", "..."],
  "apis": ["...", "..."],
  "requirements": "...",
  "constraints": "..."
}
```

Commands the user can use:
- /done - Signal that requirements gathering is complete
- /skip - Skip current question
- /back - Go back to previous question""",

            Stage.DESIGN: """You are a Software Architect AI creating a comprehensive project design.

Based on the gathered requirements, create a technical design including:
- Architecture overview with component diagram
- Tech stack and technology choices with justifications
- Module/package structure
- Database design (if applicable)
- API design (if applicable)
- Security considerations
- Deployment strategy

Output in well-structured markdown with clear sections.
Be specific and actionable - this will guide the implementation.""",

            Stage.DEVPLAN: """You are a DevPlan Generator AI creating a high-level development plan.

Based on the project design, create a development plan with 3-7 major phases.
For each phase:
- Clear title and objective
- Key deliverables (3-7 items)
- Dependencies on previous phases
- Estimated complexity

Format:
**Phase N: [Title]**
[Brief description]
- Deliverable 1
- Deliverable 2
...""",

            Stage.DETAILED: """You are a Technical Specifier AI creating detailed implementation steps.

For each phase in the development plan, create 4-10 actionable steps.
Each step should:
- Use format: N.X: [Action description]
- Be specific and actionable
- Include file paths and code locations
- Reference examples where helpful

Format:
N.1: Create [specific file/component]
- Detail about what to include
- Another implementation detail
- Testing requirement""",

            Stage.HANDOFF: """You are a Prompt Engineering AI creating a handoff prompt for an implementation agent.

Create a comprehensive prompt that includes:
- Project context and objectives
- Tech stack details
- Architecture overview
- Step-by-step implementation plan
- Quality requirements and testing strategy
- File locations and references

The prompt should be executable by an autonomous coding agent.""",
        }
        
        return defaults.get(stage, f"You are an AI assistant for the {stage.display_name} stage.")
    
    @property
    def current_stage(self) -> Stage:
        """Get the current stage."""
        return self._current_stage
    
    @property
    def completed_stages(self) -> List[Stage]:
        """Get list of completed stages."""
        return list(self._completed_stages)
    
    @property
    def is_complete(self) -> bool:
        """Check if all stages are complete."""
        return Stage.HANDOFF in self._completed_stages
    
    def get_config(self, stage: Optional[Stage] = None) -> StageConfig:
        """Get configuration for a stage.
        
        Args:
            stage: Stage to get config for. Defaults to current stage.
            
        Returns:
            StageConfig for the stage
        """
        stage = stage or self._current_stage
        return self._stage_configs[stage]
    
    def get_system_prompt(self, stage: Optional[Stage] = None) -> str:
        """Get system prompt for a stage.
        
        Args:
            stage: Stage to get prompt for. Defaults to current stage.
            
        Returns:
            System prompt text
        """
        return self.get_config(stage).system_prompt
    
    def set_stage_output(self, stage: Stage, output: Any) -> None:
        """Store the output for a completed stage.
        
        Args:
            stage: Stage that was completed
            output: Output data from that stage
        """
        self._stage_outputs[stage] = output
    
    def get_stage_output(self, stage: Stage) -> Optional[Any]:
        """Get the output from a completed stage.
        
        Args:
            stage: Stage to get output for
            
        Returns:
            Output data or None if stage not complete
        """
        return self._stage_outputs.get(stage)
    
    def get_context_for_stage(self, stage: Optional[Stage] = None) -> Dict[str, Any]:
        """Get context data needed for a stage.
        
        Collects outputs from required previous stages.
        
        Args:
            stage: Stage to get context for. Defaults to current stage.
            
        Returns:
            Dictionary with context data
        """
        stage = stage or self._current_stage
        config = self.get_config(stage)
        
        context: Dict[str, Any] = {
            "stage": stage.value,
            "stage_name": stage.display_name,
        }
        
        # Add outputs from required stages
        for req_stage in config.requires_previous:
            output = self.get_stage_output(req_stage)
            if output is not None:
                context[f"{req_stage.value}_output"] = output
        
        return context
    
    def can_advance(self) -> bool:
        """Check if we can advance to the next stage.
        
        Returns:
            True if current stage is complete and next stage is available
        """
        if self._current_stage in self._completed_stages:
            return self._current_stage.next_stage is not None
        return False
    
    def mark_complete(self, stage: Optional[Stage] = None, output: Optional[Any] = None) -> None:
        """Mark a stage as complete.
        
        Args:
            stage: Stage to mark complete. Defaults to current stage.
            output: Optional output data to store
        """
        stage = stage or self._current_stage
        
        if stage not in self._completed_stages:
            self._completed_stages.append(stage)
        
        if output is not None:
            self.set_stage_output(stage, output)
    
    def advance_stage(self) -> Optional[Stage]:
        """Advance to the next stage.
        
        Returns:
            The new current stage, or None if no more stages
        """
        if self._current_stage not in self._completed_stages:
            # Current stage not complete, can't advance
            return None
        
        next_stage = self._current_stage.next_stage
        if next_stage is None:
            return None
        
        # Check requirements
        config = self.get_config(next_stage)
        for req in config.requires_previous:
            if req not in self._completed_stages:
                return None
        
        old_stage = self._current_stage
        self._current_stage = next_stage
        
        # Notify listener
        if self._on_stage_change:
            self._on_stage_change(old_stage, next_stage)
        
        return next_stage
    
    def go_to_stage(self, stage: Stage) -> bool:
        """Jump to a specific stage.
        
        Only allowed if all required previous stages are complete.
        
        Args:
            stage: Stage to go to
            
        Returns:
            True if successful, False if requirements not met
        """
        config = self.get_config(stage)
        
        # Check requirements
        for req in config.requires_previous:
            if req not in self._completed_stages:
                return False
        
        old_stage = self._current_stage
        self._current_stage = stage
        
        # Notify listener
        if self._on_stage_change:
            self._on_stage_change(old_stage, stage)
        
        return True
    
    def reset(self) -> None:
        """Reset to initial state."""
        self._current_stage = Stage.INTERVIEW
        self._completed_stages.clear()
        self._stage_outputs.clear()
    
    def reset_from_stage(self, stage: Stage) -> None:
        """Reset from a specific stage onwards.
        
        Clears completion status and outputs for the stage and all following stages.
        
        Args:
            stage: Stage to reset from
        """
        order = [Stage.INTERVIEW, Stage.DESIGN, Stage.DEVPLAN, Stage.DETAILED, Stage.HANDOFF]
        
        try:
            idx = order.index(stage)
            stages_to_clear = order[idx:]
            
            for s in stages_to_clear:
                if s in self._completed_stages:
                    self._completed_stages.remove(s)
                if s in self._stage_outputs:
                    del self._stage_outputs[s]
            
            self._current_stage = stage
        except ValueError:
            pass
    
    def set_on_stage_change(self, callback: Callable[[Stage, Stage], None]) -> None:
        """Set callback for stage changes.
        
        Args:
            callback: Function(old_stage, new_stage) called on stage changes
        """
        self._on_stage_change = callback
    
    def get_progress(self) -> Dict[str, Any]:
        """Get progress information.
        
        Returns:
            Dictionary with progress data
        """
        all_stages = list(Stage)
        completed = len(self._completed_stages)
        total = len(all_stages)
        
        return {
            "current_stage": self._current_stage.value,
            "current_stage_name": self._current_stage.display_name,
            "completed_stages": [s.value for s in self._completed_stages],
            "completed_count": completed,
            "total_stages": total,
            "progress_percent": int((completed / total) * 100) if total > 0 else 0,
            "is_complete": self.is_complete,
        }
