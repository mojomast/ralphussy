"""Interview pipeline integration for continuous LLM chat devplan generation.

This module integrates the interview system with the existing pipeline stages,
providing a conversational interface to the entire devplan generation process.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

# Import interview components
from interview.conversation_history import ConversationHistory, MessageRole
from interview.json_extractor import JSONExtractor
from interview.stage_coordinator import Stage, StageCoordinator
from interview.interview_manager import InterviewManager, InterviewConfig, InterviewResult

# Import pipeline components
from llm_client import LLMClient
from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig
from models import ProjectDesign, DevPlan, DevPlanPhase, DevPlanStep, HandoffPrompt
from concurrency import ConcurrencyManager
from templates import render_template

# Import existing pipeline generators
from project_design import ProjectDesignGenerator
from basic_devplan import BasicDevPlanGenerator
from detailed_devplan import DetailedDevPlanGenerator
from handoff_prompt import HandoffPromptGenerator


class InterviewPipeline:
    """Full pipeline integration with interview-based input.
    
    This class combines the interview manager with the existing pipeline
    generators to provide a complete conversational devplan generation flow.
    
    It supports two modes:
    1. Interactive - User chats through each stage
    2. Automated - User provides requirements, pipeline runs automatically
    
    Example:
        # Interactive mode
        pipeline = InterviewPipeline(config)
        await pipeline.start_interactive()
        
        # Automated mode
        pipeline = InterviewPipeline(config)
        result = await pipeline.run_from_requirements(requirements)
    """
    
    def __init__(
        self,
        provider: str = "",
        model: str = "",
        save_dir: Optional[Path] = None,
        streaming: bool = True,
        on_progress: Optional[Callable[[Dict[str, Any]], None]] = None,
        on_token: Optional[Callable[[str], None]] = None,
    ):
        """Initialize the interview pipeline.
        
        Args:
            provider: LLM provider name
            model: Model name (can include provider prefix like "opencode/claude-sonnet-4-5")
            save_dir: Directory to save outputs
            streaming: Enable streaming responses
            on_progress: Callback for progress updates
            on_token: Callback for streaming tokens
        """
        # Handle model with provider prefix
        if "/" in model and not provider:
            parts = model.split("/", 1)
            provider = parts[0]
            model = parts[1] if len(parts) > 1 else model
        
        self.provider = provider
        self.model = model
        self.save_dir = save_dir or Path.home() / ".ralph" / "devplans"
        self.streaming = streaming
        
        # Callbacks
        self._on_progress = on_progress
        self._on_token = on_token
        
        # Create LLM client
        config = OpenCodeConfig(
            provider=provider,
            model=model if "/" not in model else f"{provider}/{model}",
            streaming_enabled=streaming,
            timeout=300,
        )
        self.llm_client = OpenCodeLLMClient(config)
        
        # Create concurrency manager for parallel phase processing
        self.concurrency_manager = ConcurrencyManager(max_concurrent=3)
        
        # Initialize pipeline generators
        self.design_generator = ProjectDesignGenerator(self.llm_client)
        self.devplan_generator = BasicDevPlanGenerator(self.llm_client)
        self.detailed_generator = DetailedDevPlanGenerator(self.llm_client, self.concurrency_manager)
        self.handoff_generator = HandoffPromptGenerator()
        
        # Interview manager for interactive mode
        self._interview_manager: Optional[InterviewManager] = None
        
        # Results
        self._requirements: Dict[str, Any] = {}
        self._design: Optional[ProjectDesign] = None
        self._devplan: Optional[DevPlan] = None
        self._handoff: Optional[HandoffPrompt] = None
        self._output_dir: Optional[Path] = None
    
    def _notify_progress(self, stage: str, progress: float, message: str) -> None:
        """Send progress update."""
        if self._on_progress:
            self._on_progress({
                "stage": stage,
                "progress": progress,
                "message": message,
            })
    
    async def run_from_requirements(
        self,
        project_name: str,
        languages: List[str],
        requirements: str,
        frameworks: Optional[List[str]] = None,
        apis: Optional[List[str]] = None,
        task_grouping: str = "flat",
        **kwargs: Any,
    ) -> InterviewResult:
        """Run the full pipeline from provided requirements.
        
        Skips the interview stage and runs design → devplan → detailed → handoff.
        
        Args:
            project_name: Name of the project
            languages: List of programming languages
            requirements: Requirements description
            frameworks: Optional list of frameworks
            apis: Optional list of APIs/services
            task_grouping: "flat" or "grouped" for swarm execution
            **kwargs: Additional arguments passed to generators
            
        Returns:
            InterviewResult with all generated artifacts
        """
        self._requirements = {
            "project_name": project_name,
            "languages": languages,
            "requirements": requirements,
            "frameworks": frameworks or [],
            "apis": apis or [],
        }
        
        # Stage 1: Generate design
        self._notify_progress("design", 0.1, "Generating project design...")
        
        self._design = await self.design_generator.generate(
            project_name=project_name,
            languages=languages,
            requirements=requirements,
            frameworks=frameworks,
            apis=apis,
            **kwargs,
        )
        
        self._notify_progress("design", 0.25, "Design complete")
        
        # Stage 2: Generate basic devplan
        self._notify_progress("devplan", 0.3, "Generating development plan...")
        
        basic_devplan = await self.devplan_generator.generate(
            project_design=self._design,
            task_grouping=task_grouping,
            **kwargs,
        )
        
        self._notify_progress("devplan", 0.5, "Basic devplan complete")
        
        # Stage 3: Generate detailed steps
        self._notify_progress("detailed", 0.55, "Generating detailed steps...")
        
        def on_phase_complete(result):
            phase_num = result.phase.number
            total_phases = len(basic_devplan.phases)
            progress = 0.55 + (0.25 * phase_num / total_phases)
            self._notify_progress("detailed", progress, f"Phase {phase_num} detailed")
        
        self._devplan = await self.detailed_generator.generate(
            basic_devplan=basic_devplan,
            project_name=project_name,
            tech_stack=languages,
            on_phase_complete=on_phase_complete,
            task_grouping=task_grouping,
            **kwargs,
        )
        
        self._notify_progress("detailed", 0.8, "Detailed steps complete")
        
        # Stage 4: Generate handoff prompt
        self._notify_progress("handoff", 0.85, "Generating handoff prompt...")
        
        self._handoff = self.handoff_generator.generate(
            devplan=self._devplan,
            project_name=project_name,
            **kwargs,
        )
        
        self._notify_progress("handoff", 0.95, "Handoff complete")
        
        # Save outputs
        await self._save_outputs(project_name)
        
        self._notify_progress("complete", 1.0, "Pipeline complete!")
        
        return InterviewResult(
            project_name=project_name,
            requirements=self._requirements,
            design=self._design,
            devplan=self._devplan,
            handoff=self._handoff,
            output_dir=self._output_dir,
        )
    
    async def start_interactive(self, initial_message: Optional[str] = None) -> InterviewManager:
        """Start interactive interview mode.
        
        Creates an InterviewManager and starts the conversation.
        
        Args:
            initial_message: Optional first user message
            
        Returns:
            The InterviewManager for continued interaction
        """
        config = InterviewConfig(
            provider=self.provider,
            model=self.model,
            streaming=self.streaming,
            save_dir=self.save_dir,
        )
        
        self._interview_manager = InterviewManager(config, self.llm_client)
        
        if self._on_token:
            self._interview_manager.set_on_token(self._on_token)
        
        if self._on_progress:
            self._interview_manager.set_on_progress(self._on_progress)
        
        # Start the interview
        await self._interview_manager.start(initial_message)
        
        return self._interview_manager
    
    async def chat(self, message: str) -> str:
        """Send a chat message in interactive mode.
        
        Args:
            message: User's message
            
        Returns:
            Assistant's response
        """
        if not self._interview_manager:
            raise RuntimeError("Interactive mode not started. Call start_interactive() first.")
        
        return await self._interview_manager.chat(message)
    
    @property
    def is_complete(self) -> bool:
        """Check if pipeline is complete."""
        if self._interview_manager:
            return self._interview_manager.is_complete
        return self._handoff is not None
    
    def get_result(self) -> InterviewResult:
        """Get the pipeline result."""
        if self._interview_manager:
            return self._interview_manager.get_result()
        
        return InterviewResult(
            project_name=self._requirements.get("project_name", "untitled"),
            requirements=self._requirements,
            design=self._design,
            devplan=self._devplan,
            handoff=self._handoff,
            output_dir=self._output_dir,
        )
    
    async def _save_outputs(self, project_name: str) -> None:
        """Save all outputs to files."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._output_dir = self.save_dir / f"{project_name}_{timestamp}"
        self._output_dir.mkdir(parents=True, exist_ok=True)
        
        # Save requirements
        with open(self._output_dir / "requirements.json", "w") as f:
            json.dump(self._requirements, f, indent=2)
        
        # Save design
        if self._design:
            with open(self._output_dir / "design.json", "w") as f:
                f.write(self._design.to_json())
            
            # Also save raw response if available
            if self._design.raw_llm_response:
                with open(self._output_dir / "design.md", "w") as f:
                    f.write(self._design.raw_llm_response)
        
        # Save devplan
        if self._devplan:
            with open(self._output_dir / "devplan.json", "w") as f:
                f.write(self._devplan.to_json())
        
        # Save handoff
        if self._handoff:
            with open(self._output_dir / "handoff.md", "w") as f:
                f.write(self._handoff.content)
            
            with open(self._output_dir / "handoff.json", "w") as f:
                f.write(self._handoff.to_json())


async def run_pipeline_cli(
    project_name: str,
    languages: str,
    requirements: str,
    provider: str = "",
    model: str = "",
    frameworks: str = "",
    apis: str = "",
    interactive: bool = False,
) -> InterviewResult:
    """Run pipeline from CLI.
    
    Args:
        project_name: Name of the project
        languages: Comma-separated list of languages
        requirements: Requirements description
        provider: LLM provider
        model: Model name
        frameworks: Comma-separated list of frameworks
        apis: Comma-separated list of APIs
        interactive: Use interactive mode
        
    Returns:
        InterviewResult with outputs
    """
    # Parse comma-separated values
    lang_list = [l.strip() for l in languages.split(",") if l.strip()]
    framework_list = [f.strip() for f in frameworks.split(",") if f.strip()] if frameworks else []
    api_list = [a.strip() for a in apis.split(",") if a.strip()] if apis else []
    
    def on_progress(data: Dict[str, Any]) -> None:
        stage = data.get("stage", "")
        progress = data.get("progress", 0)
        message = data.get("message", "")
        print(f"[{stage}] {progress*100:.0f}% - {message}")
    
    pipeline = InterviewPipeline(
        provider=provider,
        model=model,
        on_progress=on_progress,
    )
    
    if interactive:
        # Interactive mode
        manager = await pipeline.start_interactive()
        
        # Interactive loop
        while not manager.is_complete:
            try:
                user_input = input("> ").strip()
                if not user_input:
                    continue
                
                response = await manager.chat(user_input)
                print(f"\n{response}\n")
                
            except KeyboardInterrupt:
                print("\nUse /save to save progress or /done to finish current stage.")
            except EOFError:
                break
        
        return manager.get_result()
    else:
        # Automated mode
        return await pipeline.run_from_requirements(
            project_name=project_name,
            languages=lang_list,
            requirements=requirements,
            frameworks=framework_list,
            apis=api_list,
        )


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Run devplan generation pipeline")
    parser.add_argument("--project", required=True, help="Project name")
    parser.add_argument("--languages", required=True, help="Comma-separated languages")
    parser.add_argument("--requirements", required=True, help="Requirements description")
    parser.add_argument("--provider", default="", help="LLM provider")
    parser.add_argument("--model", default="", help="Model name")
    parser.add_argument("--frameworks", default="", help="Comma-separated frameworks")
    parser.add_argument("--apis", default="", help="Comma-separated APIs")
    parser.add_argument("--interactive", "-i", action="store_true", help="Use interactive mode")
    
    args = parser.parse_args()
    
    result = asyncio.run(run_pipeline_cli(
        project_name=args.project,
        languages=args.languages,
        requirements=args.requirements,
        provider=args.provider,
        model=args.model,
        frameworks=args.frameworks,
        apis=args.apis,
        interactive=args.interactive,
    ))
    
    print(f"\nPipeline complete!")
    print(f"Output saved to: {result.output_dir}")
