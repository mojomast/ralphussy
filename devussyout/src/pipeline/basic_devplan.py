"""Basic devplan generator pipeline stage."""

from __future__ import annotations

import asyncio
import re
import json
import sys
import os
from typing import Any, Optional, List

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

    def _extract_text_from_log_entries(self, response: str) -> str:
        """Extract actual LLM text from JSON log entries if present.
        
        The response may contain JSON log entries from streaming sessions like:
        {"type":"text","timestamp":...,"part":{"type":"text","text":"actual content..."}}
        
        This method detects and extracts the text content from such entries.
        
        Args:
            response: Raw response string (may be plain text or JSON log entries)
            
        Returns:
            Extracted text content ready for parsing
        """
        if not response or not response.strip():
            return response
        
        # Quick check: if it doesn't start with '{', it's likely plain text
        stripped = response.strip()
        if not stripped.startswith('{'):
            return response
        
        # Try to parse as JSON log entries (one per line)
        extracted_parts: List[str] = []
        lines = response.split('\n')
        
        for line in lines:
            line = line.strip()
            if not line or not line.startswith('{'):
                continue
            
            try:
                entry = json.loads(line)
                # Look for text entries with part.text structure
                if isinstance(entry, dict):
                    entry_type = entry.get("type", "")
                    part = entry.get("part", {})
                    
                    if entry_type == "text" and isinstance(part, dict):
                        text_content = part.get("text", "")
                        if text_content:
                            extracted_parts.append(text_content)
                    # Also handle direct text field
                    elif "text" in entry and isinstance(entry["text"], str):
                        extracted_parts.append(entry["text"])
            except json.JSONDecodeError:
                # Not valid JSON, might be regular text - keep original
                continue
        
        if extracted_parts:
            # Join all extracted text parts
            return "\n".join(extracted_parts)
        
        # No JSON entries found or extracted, return original
        return response

    def _parse_response(self, response: str, project_name: str) -> DevPlan:
        # Extract text from JSON log entries if present
        response = self._extract_text_from_log_entries(response)
        
        phases = []
        current_phase = None
        current_items = []
        current_description = ""
        next_phase_number = 1
        phase_num = 0

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
                    phases.append(DevPlanPhase(number=(current_phase["number"] if current_phase and "number" in current_phase else 1), title=(current_phase["title"] if current_phase and "title" in current_phase else f"Phase {(current_phase.get('number',1) if isinstance(current_phase, dict) else 1)}"), description=description if description else None, steps=[]))

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
            phases.append(DevPlanPhase(number=(current_phase["number"] if current_phase and "number" in current_phase else 1), title=(current_phase["title"] if current_phase and "title" in current_phase else "Phase 1"), description=description if description else None, steps=[]))

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
        # Extract text from JSON log entries if present
        response = self._extract_text_from_log_entries(response)
        
        phases = []
        current_phase = None
        current_phase_groups = []
        current_group = None
        current_group_tasks = []
        current_description = ""
        next_phase_number = 1
        phase_num = 0
        
        # If the LLM included a machine-readable JSON block, prefer that for parsing.
        json_block = None
        m = re.search(r"```json\s*(\{.*?\})\s*```", response, re.S | re.IGNORECASE)
        if m:
            try:
                json_block = json.loads(m.group(1))
            except Exception:
                json_block = None

        if json_block:
            phases = []
            for p_idx, p in enumerate(json_block.get("phases", []) or []):
                title = p.get("title") or p.get("name") or f"Phase {p_idx+1}"
                task_groups = []
                for g_idx, g in enumerate(p.get("task_groups", []) or []):
                    files = g.get("estimated_files") or g.get("files") or []
                    # steps may be list of strings or objects
                    steps_raw = g.get("steps") or []
                    steps = []
                    for s_idx, s in enumerate(steps_raw):
                        if isinstance(s, dict):
                            desc = s.get("description") or s.get("title") or str(s)
                        else:
                            desc = str(s)
                        steps.append(DevPlanStep(number=f"{p_idx+1}.{s_idx+1}", description=desc))
                    task_groups.append(TaskGroup(group_number=(g_idx+1), description=g.get("description") or f"Task group {g_idx+1}", estimated_files=files, steps=steps))
                phases.append(DevPlanPhase(number=(p_idx+1), title=title, description=p.get("description"), steps=[], task_groups=task_groups))

            if not phases:
                phases.append(DevPlanPhase(number=1, title="Implementation", steps=[], task_groups=[]))
            summary = f"Development plan for {project_name} with {len(phases)} phases (grouped mode - from JSON)"
            return DevPlan(phases=phases, summary=summary)

        lines = response.split("\n")
        
        # Patterns for parsing
        phase_patterns = [
            re.compile(r"^\d+\.\s*\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^\*\*\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+?)\s*\*\*\s*$", re.IGNORECASE),
            re.compile(r"^Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
            re.compile(r"^#{1,6}\s*Phase\s+0*(\d+)\s*[:\-–—]\s*(.+)$", re.IGNORECASE),
        ]
        
        # Group pattern: accept several common header styles.
        # Examples matched:
        # - **Group 1** [estimated_files: src/*, tests/*]
        # - - **Group 1** [files: src/*]
        # - **Group 1** files: src/*
        # - - Group 1: files=src/*
        # We try multiple patterns: with explicit [files], with inline files:, or just the group header.
        group_pattern_bracket = re.compile(
            r'^-?\s*\*\*?\s*Group\s+(\d+)\s*\*\*?\s*\[(?:estimated_files|files)\s*[:=]?\s*(.*?)\]\s*$',
            re.IGNORECASE,
        )

        group_pattern_inline = re.compile(
            r'^-?\s*\*\*?\s*Group\s+(\d+)\s*\*\*?\s*[:\-–—]?\s*(?:\[(?:estimated_files|files)\s*[:=]?\s*(.*?)\]|(?:files|estimated_files)\s*[:=]\s*(.*?))\s*$',
            re.IGNORECASE,
        )

        group_pattern_simple = re.compile(r'^-?\s*\*\*?\s*Group\s+(\d+)\s*\*\*?\s*[:\-–—]?\s*(.*)?$', re.IGNORECASE)
        
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
                    # Safely get phase number for step numbering
                    phase_number_str = str(current_phase["number"]) if current_phase and "number" in current_phase else "1"
                    current_phase_groups.append(TaskGroup(
                        group_number=current_group["number"],
                        description=current_group["description"],
                        estimated_files=current_group["files"],
                        steps=[DevPlanStep(number=f"{phase_number_str}.{i+1}", description=t)
                               for i, t in enumerate(current_group_tasks)]
                    ))
                
                if current_phase is not None:
                    description = current_description.strip()
                    description = re.sub(r'\*+', '', description)
                    phases.append(DevPlanPhase(
                        number=(current_phase["number"] if current_phase and "number" in current_phase else 1),
                        title=(current_phase["title"] if current_phase and "title" in current_phase else f"Phase {(current_phase['number'] if current_phase and 'number' in current_phase else 1)}"),
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
            
            # Check for group header (try bracketed, then inline, then simple)
            group_match = None
            files_str = None
            m = group_pattern_bracket.match(stripped)
            if m:
                group_match = m
                files_str = m.group(2).strip()
            else:
                m = group_pattern_inline.match(stripped)
                if m:
                    group_match = m
                    # inline pattern may place files in group 2 or 3 depending on which branch matched
                    files_str = (m.group(2) or m.group(3) or "").strip()
                else:
                    m = group_pattern_simple.match(stripped)
                    if m:
                        group_match = m
                        files_str = ""

            if group_match:
                # If we see a group header but no phase yet, create a default phase
                if current_phase is None:
                    phase_num = next_phase_number
                    next_phase_number += 1
                    current_phase = {"number": phase_num, "title": "Phase 1"}
                    current_phase_groups = []

                # Save previous group
                if current_group is not None:
                    try:
                        phase_number_str = str(current_phase.get("number", 1))
                    except Exception:
                        phase_number_str = "1"
                    current_phase_groups.append(TaskGroup(
                        group_number=current_group["number"],
                        description=current_group["description"],
                        estimated_files=current_group["files"],
                        steps=[DevPlanStep(number=f"{phase_number_str}.{i+1}", description=t)
                               for i, t in enumerate(current_group_tasks)]
                    ))
                # (previous group already saved above if present)
                
                try:
                    group_num = int(group_match.group(1))
                except Exception:
                    # fallback: enumerate next group number
                    group_num = (current_group["number"] + 1) if current_group and "number" in current_group else (len(current_phase_groups) + 1)

                file_patterns = []
                if files_str:
                    # Normalize separators and split
                    files_str = re.sub(r"[;|\\]+", ",", files_str)
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
            phase_number_str = str(current_phase["number"]) if current_phase and "number" in current_phase else "1"
            current_phase_groups.append(TaskGroup(
                group_number=current_group["number"],
                description=current_group["description"],
                estimated_files=current_group["files"],
                steps=[DevPlanStep(number=f"{phase_number_str}.{i+1}", description=t)
                       for i, t in enumerate(current_group_tasks)]
            ))
        
        if current_phase is not None:
            description = current_description.strip()
            description = re.sub(r'\*+', '', description)
            phases.append(DevPlanPhase(
                number=(current_phase["number"] if current_phase and "number" in current_phase else 1),
                title=(current_phase["title"] if current_phase and "title" in current_phase else "Phase 1"),
                description=description if description else None,
                steps=[],
                task_groups=current_phase_groups
            ))
        
        if not phases:
            phases.append(DevPlanPhase(number=1, title="Implementation", steps=[], task_groups=[]))
        
        summary = f"Development plan for {project_name} with {len(phases)} phases (grouped mode)"
        return DevPlan(phases=phases, summary=summary)
