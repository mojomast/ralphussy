"""Interview manager for continuous LLM chat-based devplan generation.

This is the main orchestrator that manages the entire interview flow,
from requirements gathering through to handoff prompt generation.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

# Set up paths for standalone execution
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

from .conversation_history import ConversationHistory, Message, MessageRole
from .json_extractor import JSONExtractor
from .stage_coordinator import Stage, StageCoordinator

# Import pipeline components (relative to parent)
# Use TYPE_CHECKING to avoid circular imports and runtime issues
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from llm_client import LLMClient as LLMClientType
    from models import ProjectDesign as ProjectDesignType, DevPlan as DevPlanType, HandoffPrompt as HandoffPromptType

# Runtime imports
try:
    from llm_client import LLMClient
    from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig
    from models import ProjectDesign, DevPlan, HandoffPrompt
    from concurrency import ConcurrencyManager
except ImportError:
    LLMClient = None  # type: ignore
    OpenCodeLLMClient = None  # type: ignore
    OpenCodeConfig = None  # type: ignore
    ProjectDesign = None  # type: ignore
    DevPlan = None  # type: ignore
    HandoffPrompt = None  # type: ignore
    ConcurrencyManager = None  # type: ignore


@dataclass
class InterviewConfig:
    """Configuration for the interview manager.
    
    Attributes:
        provider: LLM provider (e.g., "opencode", "anthropic")
        model: Model name (e.g., "claude-sonnet-4-5")
        streaming: Enable streaming responses
        save_dir: Directory to save outputs
        auto_save: Auto-save after each stage
        max_history: Maximum conversation messages to retain
    """
    provider: str = ""
    model: str = ""
    streaming: bool = True
    save_dir: Path = field(default_factory=lambda: Path.home() / ".ralph" / "devplans")
    auto_save: bool = True
    max_history: int = 100
    timeout: int = 300


@dataclass
class InterviewResult:
    """Result from interview completion.
    
    Contains all generated artifacts and conversation history.
    """
    project_name: str
    requirements: Dict[str, Any]
    design: Optional[Any] = None  # ProjectDesign when available
    devplan: Optional[Any] = None  # DevPlan when available
    handoff: Optional[Any] = None  # HandoffPrompt when available
    conversation_file: Optional[Path] = None
    output_dir: Optional[Path] = None


class InterviewManager:
    """Main orchestrator for continuous LLM chat interview.
    
    Manages the conversation flow across all pipeline stages:
    1. Interview - Gather requirements through chat
    2. Design - Generate project design
    3. DevPlan - Create high-level development plan
    4. Detailed - Generate detailed implementation steps
    5. Handoff - Create handoff prompt
    
    The user can chat naturally, provide feedback, and request changes
    at any stage. The manager maintains conversation history and
    coordinates with the stage coordinator and LLM client.
    
    Example:
        manager = InterviewManager(config)
        
        # Interactive loop
        while not manager.is_complete:
            user_input = input("> ")
            response = await manager.chat(user_input)
            print(response)
        
        # Get results
        result = manager.get_result()
    """
    
    # Slash commands
    COMMANDS = {
        "/done": "Signal that current stage is complete",
        "/skip": "Skip current question",
        "/back": "Go back to previous stage",
        "/status": "Show current progress",
        "/help": "Show available commands",
        "/save": "Save current progress",
        "/reset": "Reset to beginning",
        "/model": "Show or change model",
        "/stage": "Show current stage info",
    }
    
    def __init__(
        self,
        config: Optional[InterviewConfig] = None,
        llm_client: Optional[LLMClient] = None,
    ):
        """Initialize interview manager.
        
        Args:
            config: Interview configuration
            llm_client: LLM client to use. If None, creates OpenCodeLLMClient.
        """
        self.config = config or InterviewConfig()
        
        # Initialize components
        self.history = ConversationHistory(max_history=self.config.max_history)
        self.coordinator = StageCoordinator()
        self.extractor = JSONExtractor()
        
        # Set up LLM client
        if llm_client:
            self.llm_client = llm_client
        else:
            opencode_config = OpenCodeConfig(
                provider=self.config.provider,
                model=self.config.model,
                streaming_enabled=self.config.streaming,
                timeout=self.config.timeout,
            )
            self.llm_client = OpenCodeLLMClient(opencode_config)
        
        # State
        self._project_name: Optional[str] = None
        self._requirements: Dict[str, Any] = {}
        self._design: Optional[ProjectDesign] = None
        self._devplan: Optional[DevPlan] = None
        self._handoff: Optional[HandoffPrompt] = None
        self._output_dir: Optional[Path] = None
        
        # Callbacks
        self._on_token: Optional[Callable[[str], None]] = None
        self._on_stage_change: Optional[Callable[[Stage, Stage], None]] = None
        self._on_progress: Optional[Callable[[Dict[str, Any]], None]] = None
        
        # Wire up coordinator callback
        self.coordinator.set_on_stage_change(self._handle_stage_change)
    
    @property
    def current_stage(self) -> Stage:
        """Get current interview stage."""
        return self.coordinator.current_stage
    
    @property
    def is_complete(self) -> bool:
        """Check if interview is complete."""
        return self.coordinator.is_complete
    
    @property
    def project_name(self) -> Optional[str]:
        """Get project name if known."""
        return self._project_name
    
    def set_on_token(self, callback: Callable[[str], None]) -> None:
        """Set callback for streaming tokens."""
        self._on_token = callback
    
    def set_on_stage_change(self, callback: Callable[[Stage, Stage], None]) -> None:
        """Set callback for stage changes."""
        self._on_stage_change = callback
    
    def set_on_progress(self, callback: Callable[[Dict[str, Any]], None]) -> None:
        """Set callback for progress updates."""
        self._on_progress = callback
    
    async def start(self, initial_message: Optional[str] = None) -> str:
        """Start the interview.
        
        Args:
            initial_message: Optional initial user message
            
        Returns:
            Assistant's greeting/first question
        """
        # Add system prompt
        system_prompt = self.coordinator.get_system_prompt()
        self.history.add_system_message(system_prompt, stage=Stage.INTERVIEW.value)
        
        # Generate greeting
        if initial_message:
            return await self.chat(initial_message)
        else:
            # Generate initial greeting
            greeting_prompt = "Start the conversation by introducing yourself briefly and asking the user about their project."
            response = await self._generate_response(greeting_prompt)
            self.history.add_assistant_message(response, stage=Stage.INTERVIEW.value)
            return response
    
    async def chat(self, user_message: str) -> str:
        """Process a user message and generate response.
        
        Handles slash commands and regular conversation.
        
        Args:
            user_message: User's input
            
        Returns:
            Assistant's response
        """
        # Check for slash commands
        if user_message.startswith("/"):
            return await self._handle_command(user_message)
        
        # Add user message to history
        self.history.add_user_message(user_message, stage=self.current_stage.value)
        
        # Generate response based on current stage
        if self.current_stage == Stage.INTERVIEW:
            return await self._handle_interview(user_message)
        elif self.current_stage == Stage.DESIGN:
            return await self._handle_design(user_message)
        elif self.current_stage == Stage.DEVPLAN:
            return await self._handle_devplan(user_message)
        elif self.current_stage == Stage.DETAILED:
            return await self._handle_detailed(user_message)
        elif self.current_stage == Stage.HANDOFF:
            return await self._handle_handoff(user_message)
        else:
            return await self._generate_response(user_message)
    
    async def _handle_command(self, command: str) -> str:
        """Handle a slash command.
        
        Args:
            command: Command string starting with /
            
        Returns:
            Command response
        """
        parts = command.strip().split(maxsplit=1)
        cmd = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""
        
        if cmd == "/done":
            return await self._complete_current_stage()
        
        elif cmd == "/skip":
            return "Question skipped. Let me ask you something else."
        
        elif cmd == "/back":
            prev_stage = self.current_stage.prev_stage
            if prev_stage:
                self.coordinator.reset_from_stage(prev_stage)
                return f"Going back to {prev_stage.display_name}. What would you like to change?"
            return "You're already at the first stage."
        
        elif cmd == "/status":
            progress = self.coordinator.get_progress()
            return f"""Current Progress:
- Stage: {progress['current_stage_name']}
- Completed: {progress['completed_count']}/{progress['total_stages']} stages
- Progress: {progress['progress_percent']}%
- Project: {self._project_name or 'Not yet named'}"""
        
        elif cmd == "/help":
            help_text = "Available commands:\n"
            for c, desc in self.COMMANDS.items():
                help_text += f"  {c} - {desc}\n"
            return help_text
        
        elif cmd == "/save":
            await self._save_progress()
            return f"Progress saved to {self._output_dir}"
        
        elif cmd == "/reset":
            self.coordinator.reset()
            self.history.clear()
            self._requirements = {}
            return "Reset complete. Let's start over. Tell me about your project."
        
        elif cmd == "/model":
            if args:
                # Change model
                if "/" in args:
                    provider, model = args.split("/", 1)
                else:
                    provider = self.config.provider
                    model = args
                
                self.config.provider = provider
                self.config.model = model
                
                # Recreate client
                opencode_config = OpenCodeConfig(
                    provider=provider,
                    model=model,
                    streaming_enabled=self.config.streaming,
                    timeout=self.config.timeout,
                )
                self.llm_client = OpenCodeLLMClient(opencode_config)
                
                return f"Model changed to {provider}/{model}"
            else:
                return f"Current model: {self.config.provider}/{self.config.model}"
        
        elif cmd == "/stage":
            stage = self.current_stage
            return f"""Current Stage: {stage.display_name}
Description: {stage.description}
Next Stage: {stage.next_stage.display_name if stage.next_stage else 'None (final stage)'}"""
        
        else:
            return f"Unknown command: {cmd}. Type /help for available commands."
    
    async def _handle_interview(self, user_message: str) -> str:
        """Handle conversation during interview stage.
        
        Continues gathering requirements until user signals done.
        """
        # Build context with conversation history
        messages = self.history.to_llm_format(recent_count=20)
        
        # Generate response
        response = await self._generate_response_with_history(messages)
        self.history.add_assistant_message(response, stage=Stage.INTERVIEW.value)
        
        # Try to extract any structured data
        extracted = self.extractor.extract_interview_data(response)
        if extracted:
            self._requirements.update(extracted)
            if "project_name" in extracted:
                self._project_name = extracted["project_name"]
        
        return response
    
    async def _handle_design(self, user_message: str) -> str:
        """Handle conversation during design stage.
        
        User can provide feedback and request changes to the design.
        """
        # If we have user feedback, regenerate with it
        if user_message.strip():
            context = self._build_stage_context(Stage.DESIGN)
            context["user_feedback"] = user_message
            
            prompt = f"""The user has provided feedback on the design:
"{user_message}"

Please update the project design based on this feedback.

Previous context:
{json.dumps(self._requirements, indent=2)}"""
            
            response = await self._generate_response(prompt)
            self.history.add_assistant_message(response, stage=Stage.DESIGN.value)
            
            # Update design
            design_data = self.extractor.extract_design_sections(response)
            self._design = self._create_design_from_data(design_data)
        
            return response
        
        return "Design stage ready. Type /done to proceed or provide feedback."
    
    async def _handle_devplan(self, user_message: str) -> str:
        """Handle conversation during devplan stage."""
        if user_message.strip():
            context = self._build_stage_context(Stage.DEVPLAN)
            
            prompt = f"""The user has feedback on the development plan:
"{user_message}"

Please update the devplan accordingly."""
            
            response = await self._generate_response(prompt)
            self.history.add_assistant_message(response, stage=Stage.DEVPLAN.value)
            return response
        
        return "DevPlan stage ready. Type /done to proceed or provide feedback."
    
    async def _handle_detailed(self, user_message: str) -> str:
        """Handle conversation during detailed stage."""
        if user_message.strip():
            prompt = f"""The user has feedback on the detailed steps:
"{user_message}"

Please update the detailed implementation steps accordingly."""
            
            response = await self._generate_response(prompt)
            self.history.add_assistant_message(response, stage=Stage.DETAILED.value)
            return response
        
        return "Detailed steps stage ready. Type /done to proceed or provide feedback."
    
    async def _handle_handoff(self, user_message: str) -> str:
        """Handle conversation during handoff stage."""
        if user_message.strip():
            prompt = f"""The user has feedback on the handoff prompt:
"{user_message}"

Please update the handoff prompt accordingly."""
            
            response = await self._generate_response(prompt)
            self.history.add_assistant_message(response, stage=Stage.HANDOFF.value)
            return response
        
        return "Handoff stage ready. Type /done to finalize or provide feedback."
    
    async def _complete_current_stage(self) -> str:
        """Complete the current stage and advance to next.
        
        Returns:
            Message about stage completion and next steps
        """
        stage = self.current_stage
        
        if stage == Stage.INTERVIEW:
            # Extract final requirements
            if not self._requirements:
                # Try to extract from conversation
                all_messages = self.history.to_llm_format(include_system=False)
                extraction_prompt = f"""Based on this conversation, extract the project requirements as JSON:

{json.dumps(all_messages, indent=2)}

Output a JSON object with: project_name, description, languages, frameworks, apis, requirements, constraints"""
                
                extraction_response = await self._generate_response(extraction_prompt)
                extracted = self.extractor.extract_json(extraction_response)
                if isinstance(extracted, dict):
                    self._requirements = extracted
                else:
                    self._requirements = {}
            
            if not self._project_name:
                self._project_name = self._requirements.get("project_name", "untitled-project")
            
            # Mark complete and advance
            self.coordinator.mark_complete(stage, self._requirements)
            self.coordinator.advance_stage()
            
            # Auto-generate design
            return await self._generate_design()
        
        elif stage == Stage.DESIGN:
            self.coordinator.mark_complete(stage, self._design)
            self.coordinator.advance_stage()
            return await self._generate_devplan()
        
        elif stage == Stage.DEVPLAN:
            self.coordinator.mark_complete(stage, self._devplan)
            self.coordinator.advance_stage()
            return await self._generate_detailed()
        
        elif stage == Stage.DETAILED:
            self.coordinator.mark_complete(stage, self._devplan)
            self.coordinator.advance_stage()
            return await self._generate_handoff()
        
        elif stage == Stage.HANDOFF:
            self.coordinator.mark_complete(stage, self._handoff)
            
            # Save final results
            await self._save_progress()
            
            return f"""Interview complete!

All artifacts have been saved to: {self._output_dir}

Generated files:
- conversation.json - Full conversation history
- requirements.json - Extracted requirements
- design.json - Project design
- devplan.json - Development plan
- handoff.md - Handoff prompt for implementation

You can now use the handoff prompt with an implementation agent."""
        
        return f"Stage {stage.display_name} completed."
    
    async def _generate_design(self) -> str:
        """Generate project design from requirements."""
        self._notify_progress("Generating project design...")
        
        system_prompt = self.coordinator.get_system_prompt(Stage.DESIGN)
        self.history.add_system_message(system_prompt, stage=Stage.DESIGN.value)
        
        prompt = f"""Generate a comprehensive project design based on these requirements:

{json.dumps(self._requirements, indent=2)}

Include: architecture overview, tech stack recommendations, module structure, dependencies, challenges, and mitigations."""
        
        response = await self._generate_response(prompt)
        self.history.add_assistant_message(response, stage=Stage.DESIGN.value)
        
        # Parse design
        design_data = self.extractor.extract_design_sections(response)
        self._design = self._create_design_from_data(design_data)
        
        self._notify_progress("Design complete!")
        
        return f"""Project Design Generated:

{response}

Review the design above. You can:
- Provide feedback to refine it
- Type /done to accept and proceed to DevPlan generation"""
    
    async def _generate_devplan(self) -> str:
        """Generate development plan from design."""
        self._notify_progress("Generating development plan...")
        
        system_prompt = self.coordinator.get_system_prompt(Stage.DEVPLAN)
        self.history.add_system_message(system_prompt, stage=Stage.DEVPLAN.value)
        
        design_summary = self._design.architecture_overview if self._design else "No design available"
        
        prompt = f"""Create a high-level development plan for this project:

Project: {self._project_name}
Design: {design_summary}
Tech Stack: {self._requirements.get('languages', [])}

Break the project into 3-7 logical phases, each with clear deliverables."""
        
        response = await self._generate_response(prompt)
        self.history.add_assistant_message(response, stage=Stage.DEVPLAN.value)
        
        self._notify_progress("DevPlan complete!")
        
        return f"""Development Plan Generated:

{response}

Review the plan above. You can:
- Provide feedback to refine it
- Type /done to accept and proceed to detailed step generation"""
    
    async def _generate_detailed(self) -> str:
        """Generate detailed steps for each phase."""
        self._notify_progress("Generating detailed implementation steps...")
        
        system_prompt = self.coordinator.get_system_prompt(Stage.DETAILED)
        self.history.add_system_message(system_prompt, stage=Stage.DETAILED.value)
        
        prompt = """Generate detailed implementation steps for each phase in the development plan.

For each phase, provide 4-10 specific, actionable steps using the format:
N.X: [Action description]
- Detail 1
- Detail 2"""
        
        response = await self._generate_response(prompt)
        self.history.add_assistant_message(response, stage=Stage.DETAILED.value)
        
        self._notify_progress("Detailed steps complete!")
        
        return f"""Detailed Implementation Steps:

{response}

Review the steps above. You can:
- Provide feedback to refine them
- Type /done to accept and proceed to handoff prompt generation"""
    
    async def _generate_handoff(self) -> str:
        """Generate handoff prompt."""
        self._notify_progress("Generating handoff prompt...")
        
        system_prompt = self.coordinator.get_system_prompt(Stage.HANDOFF)
        self.history.add_system_message(system_prompt, stage=Stage.HANDOFF.value)
        
        # Gather all context
        context_summary = self.history.get_context_summary(max_tokens=3000)
        
        prompt = f"""Create a comprehensive handoff prompt for an autonomous coding agent.

Project: {self._project_name}
Requirements: {json.dumps(self._requirements, indent=2)}

The prompt should include everything the agent needs to implement this project:
- Project context and goals
- Tech stack and architecture
- Step-by-step implementation plan
- Quality requirements
- Testing strategy"""
        
        response = await self._generate_response(prompt)
        self.history.add_assistant_message(response, stage=Stage.HANDOFF.value)
        
        # Create handoff object
        self._handoff = HandoffPrompt(content=response, next_steps=[])
        
        self._notify_progress("Handoff prompt complete!")
        
        return f"""Handoff Prompt Generated:

{response}

Review the handoff prompt above. You can:
- Provide feedback to refine it
- Type /done to finalize and save all artifacts"""
    
    async def _generate_response(self, prompt: str) -> str:
        """Generate LLM response for a prompt.
        
        Args:
            prompt: The prompt to send
            
        Returns:
            Generated response text
        """
        if self.config.streaming and self._on_token:
            response = await self.llm_client.generate_completion_streaming(
                prompt,
                callback=self._on_token,
            )
        else:
            response = await self.llm_client.generate_completion(prompt)
        
        return response
    
    async def _generate_response_with_history(self, messages: List[Dict[str, str]]) -> str:
        """Generate response using conversation history.
        
        Args:
            messages: List of message dicts with role and content
            
        Returns:
            Generated response
        """
        # Build prompt from messages
        prompt_parts = []
        for msg in messages:
            role = msg["role"]
            content = msg["content"]
            if role == "system":
                prompt_parts.append(f"[SYSTEM]\n{content}\n")
            elif role == "user":
                prompt_parts.append(f"[USER]\n{content}\n")
            elif role == "assistant":
                prompt_parts.append(f"[ASSISTANT]\n{content}\n")
        
        prompt_parts.append("[ASSISTANT]\n")
        full_prompt = "\n".join(prompt_parts)
        
        return await self._generate_response(full_prompt)
    
    def _build_stage_context(self, stage: Stage) -> Dict[str, Any]:
        """Build context dictionary for a stage."""
        context = self.coordinator.get_context_for_stage(stage)
        context["project_name"] = self._project_name
        context["requirements"] = self._requirements
        
        if self._design:
            context["design"] = self._design.model_dump() if hasattr(self._design, 'model_dump') else {}
        
        return context
    
    def _create_design_from_data(self, data: Dict[str, Any]) -> ProjectDesign:
        """Create ProjectDesign from extracted data."""
        try:
            return ProjectDesign(
                project_name=self._project_name or "untitled",
                objectives=data.get("objectives", []),
                tech_stack=data.get("tech_stack", []),
                architecture_overview=data.get("architecture_overview", ""),
                dependencies=data.get("dependencies", []),
                challenges=data.get("challenges", []),
                mitigations=data.get("mitigations", []),
            )
        except Exception:
            # Fallback to minimal design
            return ProjectDesign(
                project_name=self._project_name or "untitled",
                objectives=["Project objectives not parsed"],
                tech_stack=self._requirements.get("languages", []),
                architecture_overview=str(data),
            )
    
    async def _save_progress(self) -> None:
        """Save current progress to files."""
        if not self._project_name:
            self._project_name = "untitled-project"
        
        # Create output directory
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._output_dir = self.config.save_dir / f"{self._project_name}_{timestamp}"
        self._output_dir.mkdir(parents=True, exist_ok=True)
        
        # Save conversation
        self.history.save(self._output_dir / "conversation.json")
        
        # Save requirements
        with open(self._output_dir / "requirements.json", "w") as f:
            json.dump(self._requirements, f, indent=2)
        
        # Save design
        if self._design:
            with open(self._output_dir / "design.json", "w") as f:
                f.write(self._design.to_json())
        
        # Save devplan
        if self._devplan:
            with open(self._output_dir / "devplan.json", "w") as f:
                f.write(self._devplan.to_json())
        
        # Save handoff
        if self._handoff:
            with open(self._output_dir / "handoff.md", "w") as f:
                f.write(self._handoff.content)
    
    def _handle_stage_change(self, old_stage: Stage, new_stage: Stage) -> None:
        """Handle stage change event."""
        if self._on_stage_change:
            self._on_stage_change(old_stage, new_stage)
        
        if self._on_progress:
            self._on_progress(self.coordinator.get_progress())
    
    def _notify_progress(self, message: str) -> None:
        """Notify progress callback."""
        if self._on_progress:
            progress = self.coordinator.get_progress()
            progress["message"] = message
            self._on_progress(progress)
    
    def get_result(self) -> InterviewResult:
        """Get the interview result.
        
        Returns:
            InterviewResult with all generated artifacts
        """
        return InterviewResult(
            project_name=self._project_name or "untitled",
            requirements=self._requirements,
            design=self._design,
            devplan=self._devplan,
            handoff=self._handoff,
            conversation_file=self._output_dir / "conversation.json" if self._output_dir else None,
            output_dir=self._output_dir,
        )
    
    def get_progress(self) -> Dict[str, Any]:
        """Get current progress information."""
        return self.coordinator.get_progress()


# CLI entry point
async def run_interview_cli(
    provider: str = "",
    model: str = "",
    project_name: Optional[str] = None,
) -> InterviewResult:
    """Run interview in CLI mode.
    
    Args:
        provider: LLM provider
        model: Model name
        project_name: Optional initial project name
        
    Returns:
        InterviewResult with generated artifacts
    """
    config = InterviewConfig(
        provider=provider,
        model=model,
        streaming=True,
    )
    
    manager = InterviewManager(config)
    
    # Set up streaming output
    def on_token(token: str) -> None:
        print(token, end="", flush=True)
    
    manager.set_on_token(on_token)
    
    # Start interview
    initial_msg = f"I want to build a project called {project_name}" if project_name else None
    response = await manager.start(initial_msg)
    print(f"\n{response}\n")
    
    # Interactive loop
    while not manager.is_complete:
        try:
            user_input = input("> ").strip()
            if not user_input:
                continue
            
            response = await manager.chat(user_input)
            print(f"\n{response}\n")
            
        except KeyboardInterrupt:
            print("\nInterrupted. Use /save to save progress or /quit to exit.")
        except EOFError:
            break
    
    return manager.get_result()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Run interactive devplan interview")
    parser.add_argument("--provider", default="", help="LLM provider")
    parser.add_argument("--model", default="", help="Model name")
    parser.add_argument("--project", default=None, help="Initial project name")
    
    args = parser.parse_args()
    
    result = asyncio.run(run_interview_cli(
        provider=args.provider,
        model=args.model,
        project_name=args.project,
    ))
    
    print(f"\nInterview complete!")
    print(f"Output saved to: {result.output_dir}")
