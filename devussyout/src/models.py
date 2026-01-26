"""Pydantic models used across the pipeline stages.

Exported from original project to provide data models for the pipeline.
"""

from __future__ import annotations

from typing import List, Optional, Dict

from pydantic import BaseModel, Field


class ProjectDesign(BaseModel):
    """Structured representation of a project design document."""

    project_name: str
    objectives: List[str] = Field(default_factory=list)
    tech_stack: List[str] = Field(default_factory=list)
    architecture_overview: Optional[str] = None
    dependencies: List[str] = Field(default_factory=list)
    challenges: List[str] = Field(default_factory=list)
    mitigations: List[str] = Field(default_factory=list)
    raw_llm_response: Optional[str] = Field(default=None, description="Full raw markdown response from LLM")
    complexity: Optional[str] = Field(default=None, description="Project complexity rating (Low, Medium, High)")
    estimated_phases: Optional[int] = Field(default=None, description="Estimated number of phases required")

    def to_json(self) -> str:
        return self.model_dump_json(indent=2)

    @classmethod
    def from_json(cls, data: str) -> "ProjectDesign":
        return cls.model_validate_json(data)


class DevPlanStep(BaseModel):
    """An actionable, numbered step within a phase."""

    number: str  # e.g., "2.7"
    description: str
    details: list[str] = Field(default_factory=list)
    done: bool = False


class TaskGroup(BaseModel):
    """A group of steps that can be executed in parallel by swarm workers.
    
    Tasks in the same group:
    - Touch related files (specified in estimated_files)
    - Should be executed by the same worker to avoid conflicts
    - Can be completed atomically as a unit
    
    This enables the swarm scheduler to:
    1. Assign entire groups to single workers
    2. Lock all estimated_files for the duration
    3. Minimize file conflicts between parallel workers
    """
    group_number: int = Field(description="Sequential group number within a phase")
    description: str = Field(description="Brief description of this task group")
    estimated_files: List[str] = Field(
        default_factory=list,
        description="File patterns (glob) this group will modify, e.g., ['src/auth/*', 'tests/auth/*']"
    )
    steps: List[DevPlanStep] = Field(
        default_factory=list,
        description="Steps that belong to this group"
    )


class DevPlanPhase(BaseModel):
    """A development plan phase containing multiple steps or task groups.
    
    Supports two modes:
    - Flat mode: steps are executed sequentially (traditional)
    - Grouped mode: steps are organized into TaskGroups for parallel execution
    """

    number: int
    title: str
    description: Optional[str] = None
    steps: List[DevPlanStep] = Field(default_factory=list)
    task_groups: List[TaskGroup] = Field(
        default_factory=list,
        description="For grouped mode: parallel-executable task units. When populated, swarm can execute groups in parallel."
    )


class DevPlan(BaseModel):
    """The complete development plan made of multiple phases."""

    phases: List[DevPlanPhase] = Field(default_factory=list)
    summary: Optional[str] = None
    raw_basic_response: Optional[str] = Field(default=None, description="Full raw markdown from basic devplan generation")
    raw_detailed_responses: Optional[Dict[int, str]] = Field(default=None, description="Raw markdown for each phase detail")

    def to_json(self) -> str:
        return self.model_dump_json(indent=2)

    @classmethod
    def from_json(cls, data: str) -> "DevPlan":
        return cls.model_validate_json(data)


class HandoffPrompt(BaseModel):
    """The final handoff prompt document and metadata."""

    content: str
    next_steps: List[str] = Field(default_factory=list)

    def to_json(self) -> str:
        return self.model_dump_json(indent=2)

    @classmethod
    def from_json(cls, data: str) -> "HandoffPrompt":
        return cls.model_validate_json(data)
