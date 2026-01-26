"""Basic devplan generator pipeline stage."""

from __future__ import annotations

import asyncio
import re
import sys
import os
from typing import Any, Optional

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

# Now import using simple names (works both as package and standalone)
from llm_client import LLMClient
from models import DevPlan, DevPlanPhase, ProjectDesign, TaskGroup, DevPlanStep
from templates import render_template


class BasicDevPlanGenerator:
    """Generate a high-level development plan with phases from a project design."""

    def __init__(self, llm_client: LLMClient):
        self.llm_client = llm_client

    async def generate(
        self,
        project_design: ProjectDesign,
        feedback_manager: Optional[Any] = None,
        task_group_size: int = 5,
        task_grouping: str = 'flat',
        repo_analysis: Optional[Any] = None,
        **llm_kwargs: Any,
    ) -> DevPlan:
        """Generate a high-level development plan with phases.
        
        Args:
            project_design: The project design to create a devplan for
            feedback_manager: Optional feedback manager for corrections
            task_group_size: Number of tasks per group (3-10, default 5)
            task_grouping: 'flat' for sequential or 'grouped' for parallel swarm execution
            repo_analysis: Optional repository analysis context
            **llm_kwargs: Additional arguments for LLM calls
            
        Returns:
            DevPlan with phases (and task_groups if task_grouping='grouped')
        """
        self._task_grouping = task_grouping
        
        context = {
            "project_design": project_design,
            "task_group_size": task_group_size,
            "task_grouping": task_grouping,
            "detail_level": llm_kwargs.get("detail_level", "normal"),
        }

        if repo_analysis is not None:
            context["repo_context"] = repo_analysis.to_prompt_context()

        if "code_samples" in llm_kwargs:
            context["code_samples"] = llm_kwargs.pop("code_samples")

        prompt = render_template("basic_devplan.jinja", context)

        if feedback_manager:
            prompt = feedback_manager.apply_corrections_to_prompt(prompt)

        streaming_handler = llm_kwargs.pop("streaming_handler", None)

        streaming_enabled = hasattr(self.llm_client, "streaming_enabled") and getattr(self.llm_client, "streaming_enabled", False)

        if streaming_enabled and streaming_handler is not None:
            async with streaming_handler:
                response_chunks: list[str] = []

                def token_callback(token: str) -> None:
                    response_chunks.append(token)
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        loop = None
                    if loop and loop.is_running():
                        loop.create_task(streaming_handler.on_token_async(token))
                    else:
                        asyncio.run(streaming_handler.on_token_async(token))

                full_response = await self.llm_client.generate_completion_streaming(prompt, callback=token_callback, **llm_kwargs)

                await streaming_handler.on_completion_async(full_response)

            response = full_response

        elif streaming_enabled:
            response = ""

            def token_callback(token: str) -> None:
                nonlocal response
                response += token

            response = await self.llm_client.generate_completion_streaming(prompt, callback=token_callback, **llm_kwargs)
        else:
            response = await self.llm_client.generate_completion(prompt, **llm_kwargs)

        # Save debug copy
        import os
        debug_dir = ".devussy_state"
        if not os.path.exists(debug_dir):
            os.makedirs(debug_dir)
        with open(os.path.join(debug_dir, "last_devplan_response.txt"), "w", encoding="utf-8") as f:
            f.write(response)

        # Parse based on task_grouping mode
        if self._task_grouping == 'grouped':
            devplan = self._parse_grouped_response(response, project_design.project_name)
        else:
            devplan = self._parse_response(response, project_design.project_name)
        
        devplan.raw_basic_response = response
        return devplan

    def _parse_response(self, response: str, project_name: str) -> DevPlan:
        phases = []
        current_phase = None
        current_items = []
        current_description = ""
        next_phase_number = 1

        lines = response.split("\n")
        phase_patterns = [
            re.compile(r"^\d+\.\s*\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
            re.compile(r"^#{1,6}\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
            re.compile(r"^(\d+)\s*[\.)]\s*(.+)$", re.IGNORECASE),
        ]

        for line in lines:
            stripped = line.strip()

            phase_match = None
            model_phase_num = None
            match_title = None
            for pat in phase_patterns:
                m = pat.match(stripped)
                if m:
                    phase_match = m
                    try:
                        model_phase_num = int(m.group(1))
                        match_title = m.group(2).strip()
                    except Exception:
                        phase_match = None
                        continue
                    break

            if phase_match:
                if current_phase is not None:
                    description = current_description.strip()
                    description = re.sub(r'\*+', '', description)
                    phases.append(DevPlanPhase(number=current_phase["number"], title=current_phase["title"], description=description if description else None, steps=[]))

                phase_num = next_phase_number
                next_phase_number += 1

                phase_title = match_title or f"Phase {phase_num}"
                phase_title = phase_title.rstrip("*").strip()

                current_phase = {"number": phase_num, "title": phase_title}
                current_items = []
                current_description = ""

            elif stripped.startswith("-") and current_phase:
                if stripped.startswith("- Summary:") or stripped.startswith("- summary:"):
                    summary_text = stripped.split(":", 1)[1].strip() if ":" in stripped else ""
                    if summary_text:
                        current_description = summary_text
                else:
                    item = stripped[1:].strip()
                    if item and not item.lower().startswith("summary:") and not item.lower().startswith("major components:"):
                        current_items.append(item)

            elif stripped and not stripped.startswith("#") and current_phase and not current_items and not current_description:
                if current_description:
                    current_description += " " + stripped
                else:
                    current_description = stripped

        if current_phase is not None:
            description = current_description.strip()
            description = re.sub(r'\*+', '', description)
            phases.append(DevPlanPhase(number=current_phase["number"], title=current_phase["title"], description=description if description else None, steps=[]))

        if not phases:
            phases.append(DevPlanPhase(number=1, title="Implementation", steps=[]))

        summary = f"Development plan for {project_name} with {len(phases)} phases"
        return DevPlan(phases=phases, summary=summary)

    def _parse_grouped_response(self, response: str, project_name: str) -> DevPlan:
        """Parse LLM response that contains grouped tasks.
        
        Expected format:
        **Phase 1: Title**
        Description
        
        - **Group 1** [estimated_files: src/auth/*, tests/auth/*]
          - Task 1
          - Task 2
        
        - **Group 2** [estimated_files: src/api/*]
          - Task 3
          - Task 4
        """
        phases = []
        current_phase = None
        current_phase_groups = []
        current_group = None
        current_group_tasks = []
        current_description = ""
        next_phase_number = 1
        
        lines = response.split("\n")
        
        # Patterns for parsing
        phase_patterns = [
            re.compile(r"^\d+\.\s*\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
            re.compile(r"^#{1,6}\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
        ]
        
        # Group pattern: - **Group N** [estimated_files: pattern1, pattern2]
        group_pattern = re.compile(
            r'^-?\s*\*\*\s*Group\s+(\d+)\s*\*\*\s*\[estimated_files:\s*(.*?)\]',
            re.IGNORECASE
        )
        
        for line in lines:
            stripped = line.strip()
            
            # Check for phase header
            phase_match = None
            match_title = None
            for pat in phase_patterns:
                m = pat.match(stripped)
                if m:
                    phase_match = m
                    try:
                        match_title = m.group(2).strip()
                    except Exception:
                        phase_match = None
                        continue
                    break
            
            if phase_match:
                # Save previous group and phase
                if current_group is not None:
                    current_phase_groups.append(TaskGroup(
                        group_number=current_group["number"],
                        description=current_group["description"],
                        estimated_files=current_group["files"],
                        steps=[DevPlanStep(number=f"{current_phase['number']}.{i+1}", description=t) 
                               for i, t in enumerate(current_group_tasks)]
                    ))
                
                if current_phase is not None:
                    description = current_description.strip()
                    description = re.sub(r'\*+', '', description)
                    phases.append(DevPlanPhase(
                        number=current_phase["number"],
                        title=current_phase["title"],
                        description=description if description else None,
                        steps=[],
                        task_groups=current_phase_groups
                    ))
                
                phase_num = next_phase_number
                next_phase_number += 1
                
                phase_title = match_title or f"Phase {phase_num}"
                phase_title = phase_title.rstrip("*").strip()
                
                current_phase = {"number": phase_num, "title": phase_title}
                current_phase_groups = []
                current_group = None
                current_group_tasks = []
                current_description = ""
                continue
            
            # Check for group header
            group_match = group_pattern.match(stripped)
            if group_match and current_phase:
                # Save previous group
                if current_group is not None:
                    current_phase_groups.append(TaskGroup(
                        group_number=current_group["number"],
                        description=current_group["description"],
                        estimated_files=current_group["files"],
                        steps=[DevPlanStep(number=f"{current_phase['number']}.{i+1}", description=t) 
                               for i, t in enumerate(current_group_tasks)]
                    ))
                
                group_num = int(group_match.group(1))
                files_str = group_match.group(2).strip()
                file_patterns = [f.strip() for f in files_str.split(',') if f.strip()]
                
                current_group = {
                    "number": group_num,
                    "description": f"Task group {group_num}",
                    "files": file_patterns
                }
                current_group_tasks = []
                continue
            
            # Check for task item (indented under group)
            if stripped.startswith("-") and current_group is not None:
                task = stripped[1:].strip()
                # Filter out group headers that slipped through
                if task and not task.startswith("**Group"):
                    current_group_tasks.append(task)
                continue
            
            # Description line (between phase header and first group)
            if stripped and current_phase and current_group is None and not stripped.startswith("#"):
                if current_description:
                    current_description += " " + stripped
                else:
                    current_description = stripped
        
        # Don't forget the last group and phase
        if current_group is not None:
            current_phase_groups.append(TaskGroup(
                group_number=current_group["number"],
                description=current_group["description"],
                estimated_files=current_group["files"],
                steps=[DevPlanStep(number=f"{current_phase['number']}.{i+1}", description=t) 
                       for i, t in enumerate(current_group_tasks)]
            ))
        
        if current_phase is not None:
            description = current_description.strip()
            description = re.sub(r'\*+', '', description)
            phases.append(DevPlanPhase(
                number=current_phase["number"],
                title=current_phase["title"],
                description=description if description else None,
                steps=[],
                task_groups=current_phase_groups
            ))
        
        if not phases:
            phases.append(DevPlanPhase(number=1, title="Implementation", steps=[], task_groups=[]))
        
        summary = f"Development plan for {project_name} with {len(phases)} phases (grouped mode)"
        return DevPlan(phases=phases, summary=summary)
