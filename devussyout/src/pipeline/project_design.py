"""Project design generator pipeline stage."""

from __future__ import annotations

from typing import Any, List, Optional
import asyncio
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
from llm_client import LLMClient
from models import ProjectDesign
from templates import render_template


class ProjectDesignGenerator:
    """Generate a structured project design document using an LLM."""

    def __init__(self, llm_client: LLMClient):
        self.llm_client = llm_client

    async def generate(self, project_name: str, languages: List[str], requirements: str, frameworks: Optional[List[str]] = None, apis: Optional[List[str]] = None, **llm_kwargs: Any,) -> ProjectDesign:
        """Generate a project design from user inputs."""

        context = {
            "project_name": project_name,
            "languages": languages,
            "frameworks": frameworks or [],
            "apis": apis or [],
            "requirements": requirements,
        }

        prompt = render_template("project_design.jinja", context)

        streaming_handler = llm_kwargs.pop("streaming_handler", None)

        streaming_enabled = hasattr(self.llm_client, "streaming_enabled") and getattr(self.llm_client, "streaming_enabled", False)

        if streaming_enabled and streaming_handler is not None:
            async with streaming_handler:
                response_chunks: list[str] = []

                async def token_callback(token: str) -> None:
                    response_chunks.append(token)
                    await streaming_handler.on_token_async(token)

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

        design = self._parse_response(response, project_name)
        design.raw_llm_response = response
        return design

    def _parse_response(self, response: str, project_name: str) -> ProjectDesign:
        objectives = []
        tech_stack = []
        dependencies = []
        challenges = []
        mitigations = []
        architecture_overview = None

        lines = response.split("\n")
        current_section = None

        for line in lines:
            stripped = line.strip()

            if "objective" in stripped.lower() and stripped.startswith("#"):
                current_section = "objectives"
                continue
            elif "technology stack" in stripped.lower() and stripped.startswith("#"):
                current_section = "tech_stack"
                continue
            elif "architecture" in stripped.lower() and stripped.startswith("#"):
                current_section = "architecture"
                architecture_lines = []
                continue
            elif "dependencies" in stripped.lower() and stripped.startswith("#"):
                current_section = "dependencies"
                continue
            elif "challenge" in stripped.lower() and stripped.startswith("#"):
                current_section = "challenges"
                continue
            elif "complexity" in stripped.lower() and stripped.startswith("#"):
                current_section = "complexity"
                continue
            elif stripped.startswith("#"):
                current_section = None
                continue

            if current_section and stripped.startswith("-"):
                content = stripped[1:].strip()
                if content:
                    if current_section == "objectives":
                        objectives.append(content)
                    elif current_section == "tech_stack":
                        tech_stack.append(content)
                    elif current_section == "dependencies":
                        dependencies.append(content)
                    elif current_section == "challenges":
                        if any(kw in content.lower() for kw in ["mitigation", "solution", "address"]):
                            mitigations.append(content)
                        else:
                            challenges.append(content)
                    elif current_section == "complexity":
                        lower_content = content.lower()
                        if "complexity rating" in lower_content:
                            parts = content.split(":", 1)
                            if len(parts) > 1:
                                complexity = parts[1].strip()
                        elif "estimated phases" in lower_content:
                            parts = content.split(":", 1)
                            if len(parts) > 1:
                                val_str = parts[1].strip()
                                import re
                                num_match = re.search(r'\d+', val_str)
                                if num_match:
                                    estimated_phases = int(num_match.group(0))

            elif current_section == "architecture" and stripped:
                if not stripped.startswith("#"):
                    architecture_lines.append(stripped)

        if "architecture_lines" in locals():
            architecture_overview = "\n".join(architecture_lines)

        if not architecture_overview and response:
            architecture_overview = response
        elif not response:
            architecture_overview = "ERROR: LLM returned empty response."

        return ProjectDesign(
            project_name=project_name,
            objectives=objectives if objectives else ["No objectives parsed"],
            tech_stack=tech_stack if tech_stack else ["No tech stack parsed"],
            architecture_overview=architecture_overview,
            dependencies=dependencies if dependencies else [],
            challenges=challenges if challenges else [],
            mitigations=mitigations if mitigations else [],
            complexity=locals().get("complexity"),
            estimated_phases=locals().get("estimated_phases"),
        )
