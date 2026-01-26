"""Detailed devplan generator pipeline stage."""

from __future__ import annotations

import re
import asyncio
import sys
import os
from dataclasses import dataclass
from typing import Any, List, Optional, Callable, Dict
from textwrap import dedent

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

# Now import using simple names (works both as package and standalone)
from concurrency import ConcurrencyManager
from llm_client import LLMClient
from models import DevPlan, DevPlanPhase, DevPlanStep, TaskGroup
from templates import render_template
from hivemind import HiveMindManager
from config import load_config


@dataclass
class PhaseDetailResult:
    phase: DevPlanPhase
    raw_response: str
    response_chars: int


class DetailedDevPlanGenerator:
    def __init__(self, llm_client: LLMClient, concurrency_manager: ConcurrencyManager):
        self.llm_client = llm_client
        self.concurrency_manager = concurrency_manager
        self.hivemind = HiveMindManager(llm_client)

    async def generate(
        self,
        basic_devplan: DevPlan,
        project_name: str,
        tech_stack: List[str] | None = None,
        feedback_manager: Optional[Any] = None,
        on_phase_complete: Optional[Callable[[PhaseDetailResult], None]] = None,
        task_group_size: int = 5,
        task_grouping: str = 'flat',
        repo_analysis: Optional[Any] = None,
        **llm_kwargs: Any,
    ) -> DevPlan:
        """Generate detailed implementation steps for each phase.
        
        Args:
            basic_devplan: The basic devplan with phases to detail
            project_name: Name of the project
            tech_stack: List of technologies used
            feedback_manager: Optional feedback manager for corrections
            on_phase_complete: Callback when a phase is detailed
            task_group_size: Number of tasks per group (3-10, default 5)
            task_grouping: 'flat' for sequential or 'grouped' for parallel swarm execution
            repo_analysis: Optional repository analysis context
            **llm_kwargs: Additional arguments for LLM calls
            
        Returns:
            DevPlan with detailed steps (and task_groups if task_grouping='grouped')
        """
        self._task_grouping = task_grouping
        unique_phases = []
        seen_numbers: Dict[int, DevPlanPhase] = {}
        for phase in basic_devplan.phases:
            if phase.number in seen_numbers:
                continue
            seen_numbers[phase.number] = phase
            unique_phases.append(phase)

        tasks = [
            asyncio.create_task(self.concurrency_manager.run_with_limit(
                self._generate_phase_details(
                    phase, project_name, tech_stack or [], feedback_manager,
                    task_group_size=task_group_size,
                    task_grouping=task_grouping,
                    repo_analysis=repo_analysis,
                    **llm_kwargs
                )
            ))
            for phase in unique_phases
        ]

        detailed_by_number: Dict[int, DevPlanPhase] = {}
        raw_detailed_responses: Dict[int, str] = {}

        for fut in asyncio.as_completed(tasks):
            phase_result = await fut
            detailed_by_number[phase_result.phase.number] = phase_result.phase
            raw_detailed_responses[phase_result.phase.number] = phase_result.raw_response
            if on_phase_complete:
                try:
                    on_phase_complete(phase_result)
                except Exception:
                    pass

        detailed_phases = [detailed_by_number[p.number] for p in unique_phases]

        devplan = DevPlan(phases=detailed_phases, summary=basic_devplan.summary)
        if raw_detailed_responses:
            devplan.raw_detailed_responses = raw_detailed_responses

        if hasattr(basic_devplan, 'raw_basic_response'):
            devplan.raw_basic_response = basic_devplan.raw_basic_response

        if feedback_manager:
            devplan = feedback_manager.preserve_manual_edits(devplan)

        return devplan

    async def _generate_phase_details(
        self,
        phase: DevPlanPhase,
        project_name: str,
        tech_stack: List[str],
        feedback_manager: Optional[Any] = None,
        task_group_size: int = 5,
        task_grouping: str = 'flat',
        repo_analysis: Optional[Any] = None,
        **llm_kwargs: Any,
    ) -> PhaseDetailResult:
        """Generate detailed steps for a phase, optionally grouped for parallel execution."""
        context = {
            "phase_number": phase.number,
            "phase_title": phase.title,
            "phase_description": "",
            "project_name": project_name,
            "tech_stack": tech_stack,
            "task_group_size": task_group_size,
            "task_grouping": task_grouping,
            "detail_level": llm_kwargs.get("detail_level", "normal"),
        }

        if repo_analysis is not None:
            context["repo_context"] = repo_analysis.to_prompt_context()

        if "code_samples" in llm_kwargs:
            context["code_samples"] = llm_kwargs.pop("code_samples")

        prompt = render_template("detailed_devplan.jinja", context)

        if feedback_manager:
            prompt = feedback_manager.apply_corrections_to_prompt(prompt)

        streaming_handler = llm_kwargs.pop("streaming_handler", None)
        streaming_enabled = hasattr(self.llm_client, "streaming_enabled") and getattr(self.llm_client, "streaming_enabled", False)

        config = load_config()

        if config.hivemind.enabled:
            if streaming_handler:
                llm_kwargs["streaming_handler"] = streaming_handler

            response = await self.hivemind.run_swarm(prompt, count=config.hivemind.drone_count, temperature_jitter=config.hivemind.temperature_jitter, **llm_kwargs)
            response_used = response

        elif streaming_enabled and streaming_handler is not None:
            response_chunks: list[str] = []

            def token_callback(token: str) -> None:
                response_chunks.append(token)
                try:
                    loop = asyncio.get_running_loop()
                except RuntimeError:
                    loop = None
                if loop and loop.is_running():
                    loop.create_task(streaming_handler.on_token_async(token))

            response = await self.llm_client.generate_completion_streaming(prompt, callback=token_callback, **llm_kwargs)
            response_used = response
        else:
            response = await self.llm_client.generate_completion(prompt, **llm_kwargs)
            response_used = response

        # Parse based on task_grouping mode
        if task_grouping == 'grouped':
            task_groups = self._parse_task_groups(response, phase.number)
            # Flatten steps from groups for backward compatibility
            steps = [step for group in task_groups for step in group.steps]
        else:
            steps = self._parse_steps(response, phase.number)
            task_groups = []

        if not response.strip() or not steps:
            fallback_prompt = dedent(f"""
                You are generating a detailed implementation plan for a software project.
                Project: {project_name}
                Phase {phase.number}: {phase.title}

                Return ONLY the following strict format in plain text (no headings, no extra prose):
                {phase.number}.1: <short step title>
                - <detail>
                - <detail>
                {phase.number}.2: <short step title>
                - <detail>
                - <detail>

                Provide at least 8 steps. Keep each step concise and actionable.
                Do not include any content other than the numbered steps and their '-' bullet details.
                """).strip()
            try:
                fallback_kwargs = dict(llm_kwargs)
                fallback_kwargs.setdefault("temperature", 0.3)
                if "max_tokens" not in fallback_kwargs:
                    fallback_kwargs["max_tokens"] = 1200
                response2 = await self.llm_client.generate_completion(fallback_prompt, **fallback_kwargs)
                steps2 = self._parse_steps(response2, phase.number)
                if steps2:
                    steps = steps2
                    response_used = response2
            except Exception:
                pass

        phase_model = DevPlanPhase(
            number=phase.number,
            title=phase.title,
            steps=steps,
            task_groups=task_groups if task_grouping == 'grouped' else []
        )
        return PhaseDetailResult(phase=phase_model, raw_response=response_used, response_chars=len(response_used or ""))

    def _parse_steps(self, response: str, phase_number: int) -> List[DevPlanStep]:
        steps = []
        lines = response.split("\n")
        step_pattern = re.compile(rf"^{phase_number}\.(\d+):?\s*(.+)$", re.IGNORECASE)

        current_step = None
        current_details = []

        for line in lines:
            stripped = line.strip()
            step_match = step_pattern.match(stripped)

            if step_match:
                if current_step is not None:
                    steps.append(DevPlanStep(number=current_step["number"], description=current_step["description"], details=current_details[:]))

                sub_num = int(step_match.group(1))
                description = step_match.group(2).strip()

                current_step = {"number": f"{phase_number}.{sub_num}", "description": description}
                current_details = []

            elif stripped.startswith("-") and current_step:
                detail = stripped[1:].strip()
                if detail:
                    current_details.append(detail)

        if current_step is not None:
            steps.append(DevPlanStep(number=current_step["number"], description=current_step["description"], details=current_details[:]))

        if not steps:
            steps.append(DevPlanStep(number=f"{phase_number}.1", description="Implement phase requirements"))

        return steps

    def _parse_task_groups(self, response: str, phase_number: int) -> List[TaskGroup]:
        """Parse grouped task format from LLM response.
        
        Expected format:
        - **Group 1** [estimated_files: src/auth/*, tests/auth/*]
          1.1: Create authentication module
          - Implementation details...
          1.2: Add login tests
          - Test details...
        
        - **Group 2** [estimated_files: src/api/*]
          1.3: Create API routes
          - Route details...
        """
        groups = []
        lines = response.split("\n")
        
        # Patterns
        group_pattern = re.compile(
            r'^-?\s*\*\*\s*Group\s+(\d+)\s*\*\*\s*\[estimated_files:\s*(.*?)\]',
            re.IGNORECASE
        )
        step_pattern = re.compile(rf'^{phase_number}\.(\d+):?\s*(.+)$', re.IGNORECASE)
        
        current_group = None
        current_steps = []
        current_step = None
        current_details = []
        group_num = 0
        
        for line in lines:
            stripped = line.strip()
            
            # Check for group header
            group_match = group_pattern.match(stripped)
            if group_match:
                # Save previous step to current_steps
                if current_step is not None:
                    current_steps.append(DevPlanStep(
                        number=current_step["number"],
                        description=current_step["description"],
                        details=current_details[:]
                    ))
                
                # Save previous group
                if current_group is not None and current_steps:
                    groups.append(TaskGroup(
                        group_number=current_group["number"],
                        description=f"Task group {current_group['number']}",
                        estimated_files=current_group["files"],
                        steps=current_steps
                    ))
                
                # Start new group
                group_num = int(group_match.group(1))
                files_str = group_match.group(2).strip()
                file_patterns = [f.strip() for f in files_str.split(',') if f.strip()]
                
                current_group = {
                    "number": group_num,
                    "files": file_patterns
                }
                current_steps = []
                current_step = None
                current_details = []
                continue
            
            # Check for step header
            step_match = step_pattern.match(stripped)
            if step_match:
                # Save previous step
                if current_step is not None:
                    current_steps.append(DevPlanStep(
                        number=current_step["number"],
                        description=current_step["description"],
                        details=current_details[:]
                    ))
                
                sub_num = int(step_match.group(1))
                description = step_match.group(2).strip()
                
                current_step = {
                    "number": f"{phase_number}.{sub_num}",
                    "description": description
                }
                current_details = []
                continue
            
            # Check for detail bullet
            if stripped.startswith("-") and current_step is not None:
                detail = stripped[1:].strip()
                if detail:
                    current_details.append(detail)
        
        # Don't forget the last step and group
        if current_step is not None:
            current_steps.append(DevPlanStep(
                number=current_step["number"],
                description=current_step["description"],
                details=current_details[:]
            ))
        
        if current_group is not None and current_steps:
            groups.append(TaskGroup(
                group_number=current_group["number"],
                description=f"Task group {current_group['number']}",
                estimated_files=current_group["files"],
                steps=current_steps
            ))
        
        # If no groups parsed, fall back to flat parsing and wrap in single group
        if not groups:
            flat_steps = self._parse_steps(response, phase_number)
            if flat_steps:
                groups.append(TaskGroup(
                    group_number=1,
                    description="All tasks for this phase",
                    estimated_files=[],
                    steps=flat_steps
                ))
        
        return groups
