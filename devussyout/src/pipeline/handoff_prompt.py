"""Handoff prompt generator pipeline stage."""

from __future__ import annotations

from typing import Any, Dict, List
import sys
import os

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

# Now import using simple names (works both as package and standalone)
from models import DevPlan, HandoffPrompt
from templates import render_template
try:
    from utils.anchor_utils import ensure_anchors_exist
except ImportError:
    def ensure_anchors_exist(*args, **kwargs): pass


class HandoffPromptGenerator:
    def generate(self, devplan: DevPlan, project_name: str, project_summary: str = "", architecture_notes: str = "", dependencies_notes: str = "", config_notes: str = "", task_group_size: int = 5, repo_analysis: Any = None, **kwargs: Any,) -> HandoffPrompt:
        completed_phases = [p for p in devplan.phases if self._is_phase_complete(p)]
        in_progress_phase = self._get_in_progress_phase(devplan.phases)
        next_steps = self._get_next_steps(devplan.phases, limit=task_group_size)

        if in_progress_phase:
            current_phase_number = in_progress_phase["number"]
            current_phase_name = in_progress_phase["title"]
        else:
            current_phase_number = "None"
            current_phase_name = "No active phase"

        if next_steps:
            next_task_id = next_steps[0]["number"]
            next_task_description = next_steps[0]["description"]
        else:
            next_task_id = "None"
            next_task_description = "No remaining steps"

        context: Dict[str, Any] = {
            "project_name": project_name,
            "current_phase_number": current_phase_number,
            "current_phase_name": current_phase_name,
            "next_task_id": next_task_id,
            "next_task_description": next_task_description,
            "blockers": kwargs.get("blockers", "None known"),
            "detail_level": kwargs.get("detail_level", "normal"),
        }

        if repo_analysis is not None:
            context["repo_context"] = repo_analysis.to_prompt_context()

        if "code_samples" in kwargs:
            context["code_samples"] = kwargs.get("code_samples")

        content = render_template("handoff_prompt.jinja", context)
        content = ensure_anchors_exist(content, ["QUICK_STATUS", "DEV_INSTRUCTIONS", "TOKEN_RULES", "HANDOFF_NOTES"])

        next_step_summaries = [f"{s['number']}: {s['title']}" for s in next_steps]

        return HandoffPrompt(content=content, next_steps=next_step_summaries)

    def _is_phase_complete(self, phase: DevPlanPhase) -> bool:
        if not phase.steps:
            return False
        return all(step.done for step in phase.steps)

    def _get_in_progress_phase(self, phases: List[DevPlanPhase]) -> Dict[str, Any] | None:
        for phase in phases:
            if not self._is_phase_complete(phase) and any(step.done for step in phase.steps):
                completed_steps = [s for s in phase.steps if s.done]
                remaining_steps = [s for s in phase.steps if not s.done]

                return {"number": phase.number, "title": phase.title, "completed_steps": completed_steps, "remaining_steps": remaining_steps}
        return None

    def _get_next_steps(self, phases: List[DevPlanPhase], limit: int = 5) -> List[Dict[str, Any]]:
        next_steps = []

        for phase in phases:
            for step in phase.steps:
                if not step.done:
                    next_steps.append({"number": step.number, "title": step.description[:80], "description": step.description, "notes": None})
                    if len(next_steps) >= limit:
                        return next_steps

        return next_steps
