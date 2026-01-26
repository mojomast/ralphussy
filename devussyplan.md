# Devussy Integration Plan

## Executive Summary

Integrate devussy's structured devplan pipeline as a **new mode** in ralph-live that uses opencode for LLM calls. The integration will:
- Add "Devussy Mode" as a new devplan generation option in ralph-live
- Adapt devussy to use opencode's LLM interface (replacing custom LLM client)
- Support both **flat** and **grouped** task generation (user selectable)
- Grouped mode will intelligently divide phases into parallelizable task groups for swarm
- Maintain backward compatibility with existing devplan generation

---

## Phase 1: Core Architecture

### 1.1 Add Opencode LLM Client for Devussy
**File**: `devussyout/src/llm_client_opencode.py` (NEW)

Create a new LLM client that uses opencode CLI:

```python
class OpenCodeLLMClient(LLMClient):
    """LLM client using opencode CLI for devussy pipeline."""

    def __init__(self, provider: str = "", model: str = ""):
        self.provider = provider
        self.model = model
        self.streaming_enabled = False  # opencode streaming if available

    async def generate_completion(self, prompt: str, **kwargs) -> str:
        """
        Use opencode CLI to generate completion.
        Supports --provider and --model flags.
        """
        import asyncio.subprocess
        import json

        # Build opencode command
        cmd = ["opencode", "run", "--format", "json"]
        if self.provider:
            cmd.extend(["--provider", self.provider])
        if self.model:
            cmd.extend(["--model", self.model])

        # Run opencode command
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await process.communicate(prompt.encode())
        exit_code = await process.wait()

        if exit_code != 0:
            error_msg = stderr.decode() if stderr else "Unknown error"
            raise RuntimeError(f"opencode failed: {error_msg}")

        # Extract text from JSON response
        output = json.loads(stdout.decode())
        return output.get("text", "")

    async def generate_completion_streaming(self, prompt, callback, **kwargs):
        """
        Use opencode streaming if available.
        Falls back to non-streaming if not supported.
        """
        # For now, use non-streaming as fallback
        text = await self.generate_completion(prompt, **kwargs)
        if callback:
            callback(text)
        return text
```

### 1.2 Modify Devussy Templates for Grouped Tasks
**File**: `devussyout/templates/basic_devplan.jinja` (MODIFY)

Update template to support grouped mode:

```jinja
{% raw %}{% endraw %}
{% import "_circular_macros.jinja" as circ with context %}
{% import "_shared_macros.jinja" as shared with context %}

You are an expert project manager and software architect. You have been given a project design document and need to create a high-level development plan that breaks project into logical phases.

{% if task_grouping == 'grouped' %}
### 🎯 Task Grouping Mode: PARALLEL SWARM EXECUTION

This devplan will be used by Ralph Swarm for parallel execution. You must:

1. **Divide each phase into task groups** that can run in parallel
2. **Minimize file overlap** between groups in the same phase
3. **Provide estimated file patterns** for each group
4. **Keep group size reasonable**: 3-10 tasks per group
5. **Group related tasks**: tasks touching the same files should be in the same group

**Example of grouped output:**
```
Phase 1: Database Setup

- **Group 1** [estimated_files: src/db/migrations/*, src/db/schema.sql]
  - Create database connection module
  - Define user table schema
  - Create initial migration

- **Group 2** [estimated_files: src/db/repositories/*, tests/db/*]
  - Implement user repository
  - Add repository tests
  - Create repository factory
```

**Requirements for grouped mode:**
- Each group starts with "- **Group N** [estimated_files: pattern1/*, pattern2/*]"
- Groups in the same phase can run in parallel
- Different groups should have minimal file overlap
- Provide specific file patterns (glob syntax preferred)

{% else %}
### 🎯 Task Grouping Mode: SEQUENTIAL EXECUTION

This devplan will be executed sequentially (one task at a time).

{% endif %}

{% if repo_context %}
{{ shared.section_repo_context(repo_context, detail_level='verbose') }}

**Important:** Your devplan should respect existing project structure, follow detected patterns, and integrate smoothly with the current codebase.

{% if code_samples %}

### 📝 Code Samples from Repository

The following code samples illustrate existing architecture, patterns, and conventions:

{{ code_samples }}

**Use these samples to:**
- Understand current code style and conventions
- Identify existing patterns to follow
- See how similar features are implemented
- Ensure consistency with existing codebase

{% endif %}

{% endif %}

{% if interactive_session %}
## 🎯 Interactive Session Context

This project was defined through an interactive guided questionnaire. The user provided responses to targeted questions about their requirements, technology preferences, and project goals. This context should inform your development plan to ensure it aligns with their stated needs and experience level.

**Session Details:**
- Questions asked: {{ interactive_session.question_count if interactive_session.question_count else "Multiple" }}
- Project approach: Interactive, user-guided design
{% endif %}

## Project Design

{{ shared.project_header(project_design.project_name) }}

{{ shared.section_objectives(project_design.objectives) }}

{{ shared.section_tech_stack(project_design.tech_stack) }}

{{ shared.section_architecture(project_design.architecture_overview) }}

### Key Dependencies
{% for dep in project_design.dependencies %}
- {{ dep }}
{% endfor %}

{{ shared.section_challenges(project_design.challenges, project_design.mitigations) }}

{% if project_design.complexity %}
### Complexity Assessment
- **Rating**: {{ project_design.complexity }}
- **Estimated Phases**: {{ project_design.estimated_phases }}
{% endif %}

## Your Task

Create a high-level development plan that organizes project implementation into **{{ project_design.estimated_phases if project_design.estimated_phases else "5-10" }} logical phases**.

### Requirements

1. **Phase Structure**: Each phase should have:
   - A clear, descriptive title
   - A brief summary of what will be accomplished
   - 3-7 major components or work items

2. **Logical Ordering**: Phases should be ordered such that:
   - Dependencies are respected (foundational work comes first)
   - Each phase builds on previous phases
   - The project can be developed incrementally

3. **Comprehensive Coverage**: The phases should cover:
   - Project initialization and setup
   - Interactive features (if building an interactive application)
   - Core functionality implementation
   - Testing and quality assurance
   - Documentation
   - Deployment and distribution (if applicable)

4. **Scope**: Phases may vary in scope as needed—do not artificially balance their sizes. Prefer completeness and clarity over uniformity.

{% if task_grouping == 'grouped' %}

5. **Grouped Task Structure** (CRITICAL for parallel swarm execution):
   - Within each phase, create 2-4 task groups
   - Each group contains 3-10 related tasks
   - Groups should have minimal file overlap
   - Specify estimated file patterns for each group using glob syntax
   - Format: `- **Group N** [estimated_files: pattern1/*, pattern2/*]`

{% else %}

5. **User Experience**: If project involves user interaction (CLI, web, mobile), ensure phases include:
   - Interactive UI/UX design and implementation
   - User input validation and error handling
   - Help text, examples, and guidance for users
   - Session management (if applicable)

{% endif %}

### Example Structure (DO NOT COPY - adapt to specific project)

{% if task_grouping == 'grouped' %}
```
Phase 1: Project Initialization

- **Group 1** [estimated_files: package.json, tsconfig.json, .gitignore]
  - Set up version control repository
  - Configure development environment
  - Create basic project structure

- **Group 2** [estimated_files: src/*, tests/setup/*]
  - Install dependencies and tools
  - Create base application skeleton
  - Set up test framework

Phase 2: Core Data Models

- **Group 1** [estimated_files: src/models/*, src/db/migrations/*]
  - Define data schemas
  - Create database migration files
  - Implement data validation

- **Group 2** [estimated_files: src/repositories/*, tests/unit/models/*]
  - Build data access layer
  - Create repository tests
  - Add data factory utilities
```
{% else %}
```
Phase 1: Project Initialization
- Set up version control repository
- Configure development environment
- Install dependencies and tools
- Create basic project structure

Phase 2: Core Data Models
- Define data schemas
- Implement data validation
- Create database migrations
- Build data access layer

Phase 3: Business Logic
- Implement core algorithms
- Build service layer
- Add error handling
- Create utility functions

... (continue with additional phases as needed)
```
{% endif %}

## Output Format

{% if task_grouping == 'grouped' %}
Please structure your response as a numbered list of phases. For each phase:

1. Start with "**Phase N: [Phase Title]**"
2. Add a brief description (1-2 sentences)
3. Divide the phase into 2-4 task groups:
   - Start with "- **Group N** [estimated_files: pattern1/*, pattern2/*]"
   - List 3-10 tasks as bullet points
   - Ensure groups have minimal file overlap
{% else %}
Please structure your response as a numbered list of phases. For each phase:

1. Start with "**Phase N: [Phase Title]**"
2. Add a brief description (1-2 sentences)
3. List major components as bullet points
{% endif %}

Focus on creating a roadmap that a development team can follow to build the project systematically.

---

## Output Instructions

Provide ONLY numbered list of phases in format specified above. Do not include:
- Questions about proceeding to next steps
- Execution workflow rituals or update instructions
- Progress logs or task group planning
- Handoff notes or status updates
- References to updating devplan.md, phase files, or handoff prompts
- Anchor markers or file update instructions

Simply output complete list of development phases for this project, then stop. Each phase should have a clear title, summary, and {% if task_grouping == 'grouped' %}task groups with file pattern estimates{% else %}list of major components{% endif %}.
```

### 1.3 Update Detailed Devplan Generator
**File**: `devussyout/src/pipeline/detailed_devplan.py` (MODIFY)

Add `task_grouping` parameter and file conflict analysis:

```python
from ..concurrency import ConcurrencyManager
from ..llm_client import LLMClient
from ..models import DevPlan, DevPlanPhase, DevPlanStep, TaskGroup
from ..templates import render_template
from .hivemind import HiveMindManager
from ..config import load_config

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
        task_grouping: str = 'flat',
        task_group_size: int = 5,
        repo_analysis: Optional[Any] = None,
        **llm_kwargs: Any,
    ) -> DevPlan:
        """Generate detailed devplan with optional task grouping."""
        unique_phases = []
        seen_numbers: Dict[int, DevPlanPhase] = {}
        for phase in basic_devplan.phases:
            if phase.number in seen_numbers:
                continue
            seen_numbers[phase.number] = phase
            unique_phases.append(phase)

        tasks = [
            asyncio.create_task(
                self.concurrency_manager.run_with_limit(
                    self._generate_phase_details(
                        phase, project_name, tech_stack or [], feedback_manager,
                        task_grouping=task_grouping,
                        task_group_size=task_group_size,
                        repo_analysis=repo_analysis,
                        **llm_kwargs
                    )
                )
            )
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
        task_grouping: str = 'flat',
        task_group_size: int = 5,
        repo_analysis: Optional[Any] = None,
        **llm_kwargs: Any,
    ) -> PhaseDetailResult:
        """Generate detailed steps for a phase, optionally grouped."""
        context = {
            "phase_number": phase.number,
            "phase_title": phase.title,
            "phase_description": "",
            "project_name": project_name,
            "tech_stack": tech_stack,
            "task_grouping": task_grouping,
            "task_group_size": task_group_size,
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

            response = await self.hivemind.run_swarm(
                prompt,
                count=config.hivemind.drone_count,
                temperature_jitter=config.hivemind.temperature_jitter,
                **llm_kwargs
            )
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

            response = await self.llm_client.generate_completion_streaming(
                prompt, callback=token_callback, **llm_kwargs
            )
            response_used = response
        else:
            response = await self.llm_client.generate_completion(prompt, **llm_kwargs)
            response_used = response

        # Parse steps or groups based on task_grouping mode
        if task_grouping == 'grouped':
            groups = self._parse_task_groups(response, phase.number)
            if not groups:
                # Fallback to flat steps if parsing fails
                steps = self._parse_steps(response, phase.number)
                # Convert steps to single group
                groups = [TaskGroup(
                    group_number=1,
                    description="All tasks for this phase",
                    estimated_files=[],
                    steps=steps
                )]
        else:
            steps = self._parse_steps(response, phase.number)
            # Wrap steps in single group for consistency
            groups = [TaskGroup(
                group_number=1,
                description="All tasks for this phase",
                estimated_files=[],
                steps=steps
            )]

        phase_model = DevPlanPhase(
            number=phase.number,
            title=phase.title,
            task_groups=groups,
            steps=[step for group in groups for step in group.steps]
        )
        return PhaseDetailResult(
            phase=phase_model,
            raw_response=response_used,
            response_chars=len(response_used or "")
        )

    def _parse_task_groups(self, response: str, phase_number: int) -> List[TaskGroup]:
        """
        Parse grouped task format:
        - **Group 1** [estimated_files: pattern1/*, pattern2/*]
          - 1.1: step description
          - detail
          - detail
        """
        groups = []
        lines = response.split("\n")

        group_pattern = re.compile(r'^\*\*Group\s+(\d+)\*\*\s*\[estimated_files:\s*(.*?)\]', re.IGNORECASE)
        step_pattern = re.compile(rf'^{phase_number}\.(\d+):?\s*(.+)$', re.IGNORECASE)

        current_group = None
        group_num = 0

        for line in lines:
            stripped = line.strip()
            group_match = group_pattern.match(stripped)

            if group_match:
                # Save previous group
                if current_group:
                    groups.append(current_group)

                # Start new group
                group_num = int(group_match.group(1))
                files_str = group_match.group(2).strip()
                file_patterns = [f.strip() for f in files_str.split(',') if f.strip()]

                current_group = TaskGroup(
                    group_number=group_num,
                    description=f"Task group {group_num}",
                    estimated_files=file_patterns,
                    steps=[]
                )

            elif stripped.startswith("-") and current_group:
                detail = stripped[1:].strip()
                if detail and current_group.steps:
                    # Add as sub-detail to last step
                    if current_group.steps[-1].details:
                        current_group.steps[-1].details.append(detail)

            elif step_pattern.match(stripped) and current_group:
                sub_num = int(step_pattern.group(1))
                description = step_pattern.group(2).strip()

                current_group.steps.append(DevPlanStep(
                    number=f"{phase_number}.{sub_num}",
                    description=description,
                    details=[]
                ))

        # Don't forget the last group
        if current_group:
            groups.append(current_group)

        return groups

    def _parse_steps(self, response: str, phase_number: int) -> List[DevPlanStep]:
        """Parse flat step format (existing implementation)."""
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
                    steps.append(DevPlanStep(
                        number=current_step["number"],
                        description=current_step["description"],
                        details=current_details[:]
                    ))

                sub_num = int(step_match.group(1))
                description = step_match.group(2).strip()

                current_step = {"number": f"{phase_number}.{sub_num}", "description": description}
                current_details = []

            elif stripped.startswith("-") and current_step:
                detail = stripped[1:].strip()
                if detail:
                    current_details.append(detail)

        if current_step is not None:
            steps.append(DevPlanStep(
                number=current_step["number"],
                description=current_step["description"],
                details=current_details[:]
            ))

        if not steps:
            steps.append(DevPlanStep(
                number=f"{phase_number}.1",
                description="Implement phase requirements"
            ))

        return steps
```

### 1.4 Update Models
**File**: `devussyout/src/models.py` (MODIFY)

Add TaskGroup model and update DevPlanPhase:

```python
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


class TaskGroup(BaseModel):
    """
    A group of steps that can be executed in parallel by swarm workers.

    Tasks in the same group:
    - Touch related files (specified in estimated_files)
    - Should be executed by the same worker to avoid conflicts
    - Can be completed atomically as a unit
    """
    group_number: int
    description: str
    estimated_files: List[str] = Field(
        default_factory=list,
        description="File patterns (glob) this group will modify"
    )
    steps: List[DevPlanStep] = Field(default_factory=list)


class DevPlanStep(BaseModel):
    """An actionable, numbered step within a phase."""

    number: str  # e.g., "2.7"
    description: str
    details: list[str] = Field(default_factory=list)
    done: bool = False


class DevPlanPhase(BaseModel):
    """A development plan phase containing multiple steps or task groups."""

    number: int
    title: str
    description: Optional[str] = None
    steps: List[DevPlanStep] = Field(default_factory=list)
    task_groups: List[TaskGroup] = Field(
        default_factory=list,
        description="For grouped mode: parallel-executable task units"
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
```

---

## Phase 2: Ralph-Live Integration

### 2.1 Add Devussy Mode Entry Point
**File**: `ralph-refactor/ralph-live` (MODIFY)

Add to project menu (around line 1320):

```bash
project_menu() {
    projects_init

    while true; do
        clear
        echo ""
        ui_logo | while IFS= read -r line; do echo -e "${MAGENTA}$line${NC}"; done
        echo ""
        ui_banner "PROJECT MENU"
        project_print_current
        echo ""
        echo -e "  ${CYAN}1${NC}) Switch project"
        echo -e "  ${CYAN}2${NC}) New project (create DevPlan)"
        echo -e "  ${CYAN}3${NC}) Start swarm on current DevPlan"
        echo -e "  ${CYAN}4${NC}) View all projects with swarm progress"
        echo -e "  ${CYAN}5${NC}) Resume swarm for a project"
        echo -e "  ${CYAN}6${NC}) ${MAGENTA}Generate devplan with Devussy (AI-powered, structured)${NC}"
        echo ""
        echo -e "  ${CYAN}b${NC}) Back"
        echo ""
        echo -n -e "  ${YELLOW}Select an option: ${NC}"

        local sel
        read_key sel
        echo ""

        case "$sel" in
            1)
                project_select_interactive || true
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            2)
                new_project_wizard || true
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            3)
                echo ""
                echo -n -e "  ${YELLOW}Select a swarm provider/model before starting? (Y/n): ${NC}"
                local _selm
                read_user_input _selm
                if [[ ! "${_selm:-}" =~ ^[Nn]$ ]]; then
                    select_swarm_model || true
                fi

                project_start_swarm_devplan || true
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            4)
                projects_list_with_progress
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            5)
                project_swarm_select_resume || true
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            6)
                devussy_mode_wizard || true
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
            b|B)
                return 0
                ;;
            "")
                ;;
            *)
                echo -e "${RED}Invalid option: $sel${NC}"
                echo ""
                echo -e "${CYAN}Press Enter to continue...${NC}"
                read_user_input
                ;;
        esac
    done
}
```

Add to new_project_wizard (around line 920):

```bash
new_project_wizard() {
    projects_init

    ui_banner "NEW PROJECT"

    local name
    echo -n -e "${YELLOW}Project name (folder name): ${NC}"
    read_user_input name
    if [ -z "$name" ]; then
        echo -e "${YELLOW}Cancelled${NC}"
        return 1
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}Invalid name (use letters/numbers/._-)${NC}"
        return 1
    fi

    local dir
    dir=$(project_dir "$name")
    if [ -e "$dir" ]; then
        echo -e "${RED}Project already exists: $dir${NC}"
        return 1
    fi

    mkdir -p "$dir"

    local workdir
    workdir=$(pwd)

    local devplan_path="$dir/devplan.md"

    echo ""
    echo "Choose devplan generation method:"
    echo "  ${CYAN}1${NC}) Quick template"
    echo "  ${CYAN}2${NC}) Simple LLM generation"
    echo "  ${CYAN}3${NC}) ${MAGENTA}Devussy (AI-powered, structured, parallel-aware)${NC}"
    echo ""
    echo -n "Choice [1/2/3]: "
    local gen_choice
    read_user_input gen_choice

    case "$gen_choice" in
        1)
            project_write_devplan_template "$devplan_path" "$name"
            ;;
        2)
            echo ""
            echo -e "${CYAN}Describe project goal/requirements (Ctrl+D when done):${NC}"
            local goal
            goal=$(read_multiline_input)
            if [ -z "$goal" ]; then
                goal="$name"
            fi
            project_generate_devplan_with_opencode "$devplan_path" "$name" "$goal" || true
            ;;
        3)
            devussy_generate_for_project "$name" "$workdir" "$devplan_path"
            ;;
        *)
            echo -e "${YELLOW}Invalid choice, using template${NC}"
            project_write_devplan_template "$devplan_path" "$name"
            ;;
    esac

    cat > "$dir/project.env" <<EOF
NAME="$name"
WORKDIR="$workdir"
DEVPLAN_PATH="$devplan_path"
EOF

    project_set_current "$name" || true

    echo ""
    echo -e "${GREEN}Created project:${NC} $name"

    # ... rest of existing wizard code continues
}
```

### 2.2 Create Devussy Mode Library
**File**: `ralph-refactor/lib/devussy.sh` (NEW)

```bash
#!/usr/bin/env bash

# Devussy mode for ralph-live - AI-powered devplan generation
# Supports both flat and grouped task generation for swarm execution

__DEVUSSY_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$__DEVUSSY_DIR__/core.sh"
source "$__DEVUSSY_DIR__/json.sh"

# ============================================================================
# Dependency Checking
# ============================================================================

devussy_check_dependencies() {
    local missing=()

    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v opencode >/dev/null 2>&1 || missing+=("opencode")

    if [ -n "$missing" ]; then
        echo -e "${RED}Missing dependencies:${NC}"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi

    # Check for devussyout
    if [ ! -d "/home/mojo/projects/ralphussy/devussyout" ]; then
        echo -e "${RED}devussyout directory not found${NC}"
        echo "  Expected: /home/mojo/projects/ralphussy/devussyout"
        return 1
    fi

    # Check for Python packages
    python3 -c "import jinja2, pydantic, ruamel.yaml" 2>/dev/null || {
        echo -e "${RED}Missing Python packages. Install with:${NC}"
        echo "  pip install jinja2 pydantic python-dotenv ruamel.yaml"
        return 1
    }

    return 0
}

# ============================================================================
# Devussy Mode Wizard
# ============================================================================

devussy_mode_wizard() {
    if ! devussy_check_dependencies; then
        echo ""
        echo -e "${YELLOW}Install missing dependencies and try again${NC}"
        return 1
    fi

    ui_banner "DEVUSSY MODE - AI-POWERED DEVPLANS"

    # Ask if creating new project or using existing
    if [ -z "$CURRENT_PROJECT" ]; then
        echo ""
        echo -e "${CYAN}No current project selected${NC}"
        echo "  ${GREEN}1${NC}) Create new project"
        echo "  ${GREEN}2${NC}) Select existing project"
        echo "  ${GREEN}0${NC}) Cancel"
        echo ""
        echo -n -e "  ${YELLOW}Choice: ${NC}"
        local choice
        read_user_input choice

        case "$choice" in
            1)
                new_project_devussy_wizard
                return $?
                ;;
            2)
                project_select_interactive || return 1
                if [ -n "$CURRENT_PROJECT" ]; then
                    devussy_generate_for_current_project
                fi
                return $?
                ;;
            0|*)
                echo -e "${YELLOW}Cancelled${NC}"
                return 1
                ;;
        esac
    else
        echo ""
        echo -e "${CYAN}Current project: ${GREEN}$CURRENT_PROJECT${NC}"
        echo -e "${CYAN}DevPlan: ${GREEN}$CURRENT_PROJECT_DEVPLAN${NC}"
        echo ""
        echo -n -e "  ${YELLOW}Generate new devplan for this project? (Y/n): ${NC}"
        local yn
        read_user_input yn
        if [[ ! "${yn:-}" =~ ^[Nn]$ ]]; then
            devussy_generate_for_current_project
        fi
        return 0
    fi
}

new_project_devussy_wizard() {
    echo ""
    local name
    echo -n -e "${YELLOW}Project name: ${NC}"
    read_user_input name
    if [ -z "$name" ]; then
        echo -e "${YELLOW}Cancelled${NC}"
        return 1
    fi

    if ! [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}Invalid name${NC}"
        return 1
    fi

    local dir
    dir=$(project_dir "$name")
    if [ -e "$dir" ]; then
        echo -e "${RED}Project exists: $dir${NC}"
        return 1
    fi

    mkdir -p "$dir"

    local workdir
    workdir=$(pwd)

    local devplan_path="$dir/devplan.md"

    echo ""
    echo -e "${CYAN}Describe your project goal (Ctrl+D when done):${NC}"
    local goal
    goal=$(read_multiline_input)
    if [ -z "$goal" ]; then
        goal="$name"
    fi

    devussy_generate_devplan "$name" "$goal" "$devplan_path" "$workdir"

    if [ $? -eq 0 ]; then
        cat > "$dir/project.env" <<EOF
NAME="$name"
WORKDIR="$workdir"
DEVPLAN_PATH="$devplan_path"
EOF
        project_set_current "$name" || true
        echo -e "${GREEN}Created project: $name${NC}"
    fi
}

devussy_generate_for_current_project() {
    if [ -z "$CURRENT_PROJECT" ] || [ -z "$CURRENT_PROJECT_DEVPLAN" ]; then
        echo -e "${RED}No current project/devplan${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}Update project goal (Ctrl+D when done, empty to keep current):${NC}"
    local goal
    goal=$(read_multiline_input)

    if [ -z "$goal" ]; then
        # Try to extract goal from existing devplan
        goal=$(grep -A 5 "^## Goal" "$CURRENT_PROJECT_DEVPLAN" | head -6 | tail -1 || echo "")
        goal="${goal#- }"
    fi

    if [ -z "$goal" ]; then
        goal="$CURRENT_PROJECT"
    fi

    devussy_generate_devplan "$CURRENT_PROJECT" "$goal" "$CURRENT_PROJECT_DEVPLAN" "$CURRENT_PROJECT_WORKDIR"
}

devussy_generate_devplan() {
    local project_name="$1"
    local goal="$2"
    local devplan_path="$3"
    local workdir="${4:-}"

    echo ""
    echo -e "${CYAN}Choose task organization mode:${NC}"
    echo "  ${GREEN}1${NC}) Flat list (tasks in priority order)"
    echo "  ${GREEN}2${NC}) Grouped by file patterns (parallelizable for swarm)"
    echo ""
    echo -n -e "  ${YELLOW}Choice [2]: ${NC}"
    local task_grouping
    read_user_input task_grouping
    task_grouping="${task_grouping:-2}"

    case "$task_grouping" in
        1) task_grouping="flat" ;;
        2|*) task_grouping="grouped" ;;
    esac

    local task_group_size="5"
    if [ "$task_grouping" = "grouped" ]; then
        echo ""
        echo -n -e "  ${YELLOW}Tasks per group [3-10] [5]: ${NC}"
        read_user_input task_group_size
        task_group_size="${task_group_size:-5}"

        if ! [[ "$task_group_size" =~ ^[0-9]+$ ]] || [ "$task_group_size" -lt 3 ] || [ "$task_group_size" -gt 10 ]; then
            echo -e "${YELLOW}Invalid size, using 5${NC}"
            task_group_size=5
        fi
    fi

    # Select model
    SELECTED_PROVIDER=""
    SELECTED_MODEL=""
    echo ""
    if ! select_model_step_by_step; then
        echo -e "${YELLOW}Devplan cancelled${NC}"
        return 1
    fi

    local provider="$SELECTED_PROVIDER"
    local model="$SELECTED_MODEL"

    if [ -z "$model" ]; then
        echo -e "${YELLOW}Using default model${NC}"
    fi

    echo ""
    echo -e "${CYAN}Generating devplan with:${NC}"
    echo -e "  ${CYAN}Mode:${NC} $task_grouping"
    [ "$task_grouping" = "grouped" ] && echo -e "  ${CYAN}Group size:${NC} $task_group_size"
    echo -e "  ${CYAN}Model:${NC} ${model:-default}"

    # Generate using Python script
    local devussy_script=$(cat <<'PYTHON_SCRIPT'
import asyncio
import sys
import json
import os

# Add devussyout to path
devussy_path = os.path.expanduser("~/projects/ralphussy/devussyout")
sys.path.insert(0, os.path.join(devussy_path, "src"))
sys.path.insert(0, devussy_path)

from pipeline.project_design import ProjectDesignGenerator
from pipeline.basic_devplan import BasicDevPlanGenerator
from pipeline.detailed_devplan import DetailedDevPlanGenerator
from concurrency import ConcurrencyManager
from llm_client_opencode import OpenCodeLLMClient

async def main():
    # Configuration from environment
    project_name = os.getenv("DEVUSSY_PROJECT_NAME", "")
    goal = os.getenv("DEVUSSY_GOAL", "")
    task_grouping = os.getenv("DEVUSSY_TASK_GROUPING", "flat")
    task_group_size = int(os.getenv("DEVUSSY_GROUP_SIZE", "5"))
    provider = os.getenv("DEVUSSY_PROVIDER", "")
    model = os.getenv("DEVUSSY_MODEL", "")

    # Use opencode for LLM calls
    llm = OpenCodeLLMClient(provider=provider, model=model)

    # Generate project design
    pdg = ProjectDesignGenerator(llm)
    design = await pdg.generate(project_name, [], goal)

    # Generate basic devplan
    bdg = BasicDevPlanGenerator(llm)
    basic = await bdg.generate(
        design,
        task_grouping=task_grouping,
        task_group_size=task_group_size
    )

    # Generate detailed devplan
    cm = ConcurrencyManager(config={'max_concurrent_requests': 3})
    ddg = DetailedDevPlanGenerator(llm, cm)
    detailed = await ddg.generate(
        basic,
        project_name,
        tech_stack=design.tech_stack,
        task_grouping=task_grouping,
        task_group_size=task_group_size
    )

    # Output as JSON for bash processing
    print(detailed.to_json())

asyncio.run(main())
PYTHON_SCRIPT
    )

    # Export environment variables for Python script
    export DEVUSSY_PROJECT_NAME="$project_name"
    export DEVUSSY_GOAL="$goal"
    export DEVUSSY_TASK_GROUPING="$task_grouping"
    export DEVUSSY_GROUP_SIZE="$task_group_size"
    export DEVUSSY_PROVIDER="$provider"
    export DEVUSSY_MODEL="$model"

    # Run Python script and capture output
    local devplan_json
    if ! devplan_json=$(echo "$devussy_script" | python3 2>&1); then
        echo -e "${RED}Failed to generate devplan${NC}"
        echo "$devplan_json" | head -20
        return 1
    fi

    # Convert JSON to swarm devplan format
    devussy_to_swarm_markdown "$devplan_json" "$project_name" "$goal" "$task_grouping" > "$devplan_path"

    echo ""
    echo -e "${GREEN}Devplan generated: $devplan_path${NC}"

    # Show preview
    echo ""
    echo -e "${CYAN}Press Enter to preview devplan...${NC}"
    read_user_input
    cat "$devplan_path"
    echo ""
    echo -e "${CYAN}═════════════════════════════════════════════════════════${NC}"

    # Options
    while true; do
        echo ""
        echo -e "  ${GREEN}e${NC}) Edit devplan manually"
        echo -e "  ${GREEN}r${NC}) Regenerate with different settings"
        echo -e "  ${GREEN}s${NC}) Start swarm on this devplan"
        echo -e "  ${GREEN}q${NC}) Save and return to menu"
        echo ""
        echo -n -e "  ${YELLOW}Choose option (e/r/s/q): ${NC}"
        local choice
        read_user_input choice

        case "$choice" in
            e|E)
                local editor_cmd="${EDITOR-}"
                if [ -n "$editor_cmd" ]; then
                    "$editor_cmd" "$devplan_path" || true
                else
                    echo -e "${RED}No EDITOR set${NC}"
                fi
                ;;
            r|R)
                devussy_generate_devplan "$project_name" "$goal" "$devplan_path" "$workdir"
                return $?
                ;;
            s|S)
                # Set as current project's devplan if not already
                if [ -n "$project_name" ]; then
                    project_set_current "$project_name" || true
                fi
                project_start_swarm_devplan
                return 0
                ;;
            q|Q)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

devussy_to_swarm_markdown() {
    local devplan_json="$1"
    local project_name="$2"
    local goal="$3"
    local task_grouping="$4"

    python3 - <<PY
import json
import sys

devplan = json.loads('$devplan_json')
project_name = "$project_name"
goal = "$goal"
task_grouping = "$task_grouping"

print(f"# DevPlan: {project_name}")
print()
print("## Goal")
print(f"- {goal}")
print()
print("## Constraints")
print("- Use swarm for parallel execution")
if task_grouping == "grouped":
    print("- Tasks are grouped by file patterns to minimize conflicts")
else:
    print("- Tasks execute sequentially")
print()
print("## Tasks")
print()

if task_grouping == "grouped":
    # Grouped mode: print groups with file estimates
    for phase in devplan.get('phases', []):
        print(f"### Phase {phase['number']}: {phase['title']}")
        print()
        for group in phase.get('task_groups', []):
            files_str = ', '.join(group.get('estimated_files', ['various']))
            print(f"- [ ] {group['description']} [files: {files_str}]")
            for step in group.get('steps', []):
                print(f"  - [ ] {step['number']}: {step['description']}")
            print()
else:
    # Flat mode: flatten all steps
    task_num = 1
    for phase in devplan.get('phases', []):
        for group in phase.get('task_groups', []):
            for step in group.get('steps', []):
                print(f"- [ ] {step['number']}: {step['description']}")
                task_num += 1
PY
}
```

---

## Phase 3: Task Grouping Logic

### 3.1 File Conflict-Aware Grouping
**File**: `devussyout/src/pipeline/detailed_devplan.py` (continued)

Add file conflict analysis methods:

```python
def _group_steps_for_parallel_execution(
    self,
    steps: List[DevPlanStep],
    repo_files: List[str],
    group_size: int = 5
) -> List[TaskGroup]:
    """
    Group steps by estimated file patterns to minimize conflicts.

    Strategy:
    1. Predict files for each step using LLM
    2. Cluster steps by file overlap
    3. Each group becomes a unit of parallel execution
    """
    if not steps:
        return []

    # Step 1: Predict files for each step
    step_files = self._predict_step_files(steps, repo_files)

    # Step 2: Cluster steps by file overlap
    groups = self._cluster_by_file_overlap(step_files, group_size)

    # Step 3: Create TaskGroup objects
    task_groups = []
    for i, (group_steps, file_patterns) in enumerate(groups, 1):
        # Get unique file patterns for the group
        all_patterns = []
        for step in group_steps:
            all_patterns.extend(step_files.get(step.number, []))

        # Remove duplicates and sort
        unique_patterns = sorted(set(all_patterns))

        task_groups.append(TaskGroup(
            group_number=i,
            description=f"Parallel work unit {i} ({len(group_steps)} tasks)",
            estimated_files=unique_patterns,
            steps=group_steps
        ))

    return task_groups

async def _predict_step_files(
    self,
    steps: List[DevPlanStep],
    repo_files: List[str]
) -> Dict[str, List[str]]:
    """
    Use LLM to predict which files each step will modify.

    Returns: Dict mapping step_number to list of file patterns.
    """
    step_files = {}

    # Group predictions by batches for efficiency
    for step in steps:
        prompt = f"""
You are analyzing a development step to predict which files will be modified.

Step: "{step.description}"

Repository files:
{self._format_file_list(repo_files)}

Rules:
1. Return ONLY a JSON array of file patterns (no markdown, no explanation)
2. Use glob patterns for directories (e.g., "src/auth/*", "tests/**/*.ts")
3. Be specific: prefer "src/api/routes/*" over "src/*"
4. Return patterns in format: ["pattern1", "pattern2"]

Respond with JSON array only:
"""

        try:
            response = await self.llm_client.generate_completion(prompt, max_tokens=200)
            # Parse JSON from response
            patterns = json.loads(response) if response else []
            step_files[step.number] = patterns
        except Exception:
            # Fallback: empty patterns
            step_files[step.number] = []

    return step_files

def _format_file_list(self, files: List[str]) -> str:
    """Format file list for LLM prompt."""
    if not files:
        return "(no files found)"

    # Limit to 100 files to avoid token limits
    sample = files[:100] if len(files) > 100 else files
    return "\n".join(f"  - {f}" for f in sample)

def _cluster_by_file_overlap(
    self,
    step_files: Dict[str, List[str]],
    group_size: int = 5
) -> List[Tuple[List[DevPlanStep], List[str]]]:
    """
    Cluster steps by file pattern overlap.

    Returns: List of (steps, unique_patterns) tuples.
    """
    if not step_files:
        return []

    # Convert step_files dict to list of tuples
    step_list = list(step_files.items())  # [(step_num, [patterns]), ...]

    # Simple greedy clustering algorithm
    groups = []
    remaining = step_list[:]

    while remaining:
        # Start new group with first remaining step
        current_group_steps = [remaining[0][0]]
        current_patterns = set(remaining[0][1])

        remaining = remaining[1:]

        # Try to add more steps until group size or no overlap
        for step_num, patterns in remaining[:]:
            if len(current_group_steps) >= group_size:
                break

            # Check if this step's patterns overlap with group
            has_overlap = bool(current_patterns.intersection(set(patterns)))

            # If overlap, add to same group (better to run together)
            if has_overlap:
                current_group_steps.append(step_num)
                current_patterns.update(patterns)
                remaining.remove((step_num, patterns))

        # Also consider non-overlapping steps if group is small
        if len(current_group_steps) < group_size:
            for step_num, patterns in remaining[:]:
                if len(current_group_steps) >= group_size:
                    break

                # No overlap - safe to run in parallel
                if not current_patterns.intersection(set(patterns)):
                    current_group_steps.append(step_num)
                    current_patterns.update(patterns)
                    remaining.remove((step_num, patterns))

        # Create group
        groups.append((current_group_steps, list(current_patterns)))

    return groups
```

---

## Phase 4: User Experience

### 4.1 Devussy Wizard Flow

The complete user flow when selecting Devussy mode:

```
[From ralph-live Project Menu]
  6) Generate devplan with Devussy (AI-powered, structured)

──────────────────────────────────────
DEVUSSY MODE - AI-POWERED DEVPLANS
──────────────────────────────────────

Current project: (none)

Options:
  1) Create new project
  2) Select existing project
  0) Cancel

Choice: 1

──────────────────────────────────────
NEW PROJECT WIZARD (DEVUSSY)
──────────────────────────────────────

Project name: my-app

Describe your project goal (Ctrl+D when done):
I want to build a REST API with authentication,
rate limiting, and database persistence.

──────────────────────────────────────
CHOOSE TASK ORGANIZATION MODE
──────────────────────────────────────

  1) Flat list (tasks in priority order)
  2) Grouped by file patterns (parallelizable for swarm)

Choice [2]: 2

Tasks per group [3-10] [5]: 4

──────────────────────────────────────
SELECT MODEL FOR DEVPLAN
──────────────────────────────────────

  [1] zai-coding-plan/glm-4.7
  [2] openai/gpt-4o
  [3] anthropic/claude-sonnet-4
  ...

Choice: 1

──────────────────────────────────────
GENERATING DEVPLAN...
──────────────────────────────────────

Generating project design...
Generating basic devplan...
Generating detailed devplan...
[====================] 100%

Devplan generated: ~/projects/my-app/devplan.md

Press Enter to preview devplan...

# DevPlan: my-app

## Goal
- I want to build a REST API with authentication, rate limiting, and database persistence.

## Constraints
- Use swarm for parallel execution
- Tasks are grouped by file patterns to minimize conflicts

## Tasks

### Phase 1: Project Setup

- [ ] Parallel work unit 1 (4 tasks) [files: package.json, tsconfig.json, .gitignore]
  - [ ] 1.1: Initialize Node.js project
  - [ ] 1.2: Configure TypeScript
  - [ ] 1.3: Set up ESLint
  - [ ] 1.4: Create .gitignore

- [ ] Parallel work unit 2 (3 tasks) [files: src/server.ts, src/index.ts]
  - [ ] 1.5: Create Express server
  - [ ] 1.6: Set up middleware
  - [ ] 1.7: Configure CORS

...

──────────────────────────────────────
DEVPLAN OPTIONS
──────────────────────────────────────

  e) Edit devplan manually
  r) Regenerate with different settings
  s) Start swarm on this devplan
  q) Save and return to menu

Choice: s
```

---

## Phase 5: Implementation Tasks

### Priority 1: Core Infrastructure
1. **Create `devussyout/src/llm_client_opencode.py`**
   - Implement async `generate_completion()` using opencode CLI
   - Implement `generate_completion_streaming()` if available
   - Handle opencode model selection flags
   - Error handling and retry logic
   - **Estimated time**: 2-3 hours

2. **Update `devussyout/src/models.py`**
   - Add `TaskGroup` model with fields:
     - `group_number: int`
     - `description: str`
     - `estimated_files: List[str]`
     - `steps: List[DevPlanStep]`
   - Add `task_groups` field to `DevPlanPhase`
   - **Estimated time**: 1 hour

3. **Update `devussyout/templates/basic_devplan.jinja`**
   - Add conditional `{% if task_grouping == 'grouped' %}` blocks
   - Provide examples of grouped vs flat output
   - Include instructions for file pattern estimation
   - **Estimated time**: 2 hours

4. **Update `devussyout/templates/detailed_devplan.jinja`**
   - Add file pattern analysis instructions
   - Explain parallel execution requirements
   - Provide grouped output format examples
   - **Estimated time**: 1-2 hours

### Priority 2: Devussy Pipeline
5. **Modify `devussyout/src/pipeline/basic_devplan.py`**
   - Add `task_grouping` parameter to `generate()`
   - Pass task_grouping to template context
   - Parse grouped output from LLM response
   - **Estimated time**: 2 hours

6. **Modify `devussyout/src/pipeline/detailed_devplan.py`**
   - Add `task_grouping` and `task_group_size` parameters
   - Implement `_group_steps_for_parallel_execution()`
   - Implement `_predict_step_files()`
   - Implement `_cluster_by_file_overlap()`
   - Update `_parse_steps()` to handle group structure
   - Add `_parse_task_groups()` method
   - **Estimated time**: 4-6 hours

### Priority 3: Ralph-Live Integration
7. **Create `ralph-refactor/lib/devussy.sh`**
   - `devussy_check_dependencies()` - check Python, opencode, packages
   - `devussy_mode_wizard()` - interactive wizard
   - `devussy_generate_devplan()` - Python driver script
   - `devussy_to_swarm_markdown()` - format converter
   - `new_project_devussy_wizard()` - project creation flow
   - `devussy_generate_for_current_project()` - update flow
   - **Estimated time**: 6-8 hours

8. **Modify `ralph-refactor/ralph-live`**
   - Add source for `lib/devussy.sh`
   - Add option 6 to `project_menu()`
   - Add devussy to `new_project_wizard()` choices
   - Update project menu banner/color coding
   - **Estimated time**: 1-2 hours

### Priority 4: Swarm Integration
9. **Modify `ralph-refactor/lib/swarm_analyzer.sh`**
   - Update `swarm_analyzer_parse_devplan_tasks()` to handle nested groups
   - Parse `estimated_files` from group metadata
   - Support both flat and grouped parsing modes
   - **Estimated time**: 2-3 hours

10. **Modify `ralph-refactor/lib/swarm_scheduler.sh`**
    - Handle `is_group` flag in task assignment
    - Atomic group execution logic
    - Lock management for grouped files
    - **Estimated time**: 3-4 hours

11. **Update `ralph-refactor/lib/swarm_db.sh`**
    - Add `is_group` column to `tasks` table
    - Add `group_id` column for sub-task association
    - Update schema migration
    - **Estimated time**: 1-2 hours

### Priority 5: Testing & Polish
12. **Create tests** (`ralph-refactor/tests/test_devussy.sh`)
    - Test flat task generation
    - Test grouped task generation
    - Test file conflict detection in grouping
    - Test swarm execution of grouped tasks
    - Test opencode LLM client
    - **Estimated time**: 4-6 hours

13. **Documentation updates**
    - Update `swarmplan.md` with devussy integration notes
    - Create `devussy-integration.md` usage guide
    - Add examples of grouped vs flat execution
    - Update ralph-live help text
    - **Estimated time**: 2-3 hours

---

## Phase 6: File Structure Summary

```
ralphussy/
├── devussyout/
│   ├── src/
│   │   ├── llm_client_opencode.py    [NEW] - Opencode LLM client
│   │   ├── models.py                   [MOD] - Add TaskGroup model
│   │   └── pipeline/
│   │       ├── basic_devplan.py        [MOD] - task_grouping parameter
│   │       └── detailed_devplan.py   [MOD] - grouping logic
│   └── templates/
│       ├── basic_devplan.jinja         [MOD] - grouped format
│       └── detailed_devplan.jinja     [MOD] - file pattern instructions
│
├── ralph-refactor/
│   ├── lib/
│   │   ├── devussy.sh                 [NEW] - wizard + generation
│   │   ├── swarm_analyzer.sh          [MOD] - parse grouped tasks
│   │   ├── swarm_scheduler.sh         [MOD] - group execution
│   │   └── swarm_db.sh               [MOD] - add group columns
│   ├── tests/
│   │   └── test_devussy.sh           [NEW] - devussy tests
│   └── ralph-live                   [MOD] - add devussy option
│
├── devussy-integration.md              [NEW] - usage guide
└── devussyplan.md                   [THIS FILE] - integration plan
```

---

## Success Criteria

- [ ] Devussy mode accessible from ralph-live Project Menu
- [ ] User can select flat vs grouped task generation
- [ ] Grouped mode creates task groups with `estimated_files`
- [ ] Swarm can execute grouped tasks without file conflicts
- [ ] Flat mode works identically to current devplans
- [ ] Devussy uses opencode for LLM calls (model selection works)
- [ ] Interactive wizard guides user through generation process
- [ ] Generated devplans are compatible with existing swarm execution
- [ ] File grouping minimizes conflicts in parallel execution
- [ ] All tests pass

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| LLM model compatibility | Test with multiple opencode providers/models |
| File grouping quality | Implement fallback to flat mode if grouping fails |
| Breaking existing swarm | Add as NEW feature only, preserve current paths |
| Complex Python dependency | Keep devussy self-contained, check in wizard |
| Database schema changes | Use migration pattern, add columns with defaults |
| Task grouping performance | Cache file predictions, use batch LLM calls |
| Parse failures | Add robust error handling, clear error messages |

---

## Implementation Estimate

| Phase | Tasks | Estimated Time |
|--------|--------|----------------|
| Phase 1: Core Infrastructure | 1-4 | 6-8 hours |
| Phase 2: Ralph-Live Integration | 7-8 | 7-10 hours |
| Phase 3: Task Grouping Logic | (included in 5-6) | 4-6 hours |
| Phase 4: User Experience | (included in 7-8) | 4-6 hours |
| Phase 5: Full Implementation | 5-11 | 24-30 hours |
| Phase 6: Testing & Polish | 12-13 | 6-9 hours |
| **Total** | | **51-69 hours** |

**Recommended Implementation Order:**

1. Start with Phase 1 (Core Infrastructure) - 6-8 hours
2. Implement Phase 5.1-5.2 (Devussy Pipeline) - 6-8 hours
3. Implement Phase 5.3 (Ralph-Live Integration) - 6-8 hours
4. Test with flat mode first
5. Add grouping logic (Phase 3) - 4-6 hours
6. Integrate with swarm (Phase 4) - 5-7 hours
7. Testing and polish (Phase 6) - 6-9 hours

---

## Next Steps

1. **Start with Priority 1**: Create `devussyout/src/llm_client_opencode.py`
2. **Review templates**: Update basic_devplan.jinja with grouped format
3. **Implement wizard**: Create `ralph-refactor/lib/devussy.sh`
4. **Test flat mode**: Ensure basic functionality works before adding grouping
5. **Add grouping**: Implement file conflict analysis and clustering
6. **Integrate with swarm**: Update analyzer and scheduler
7. **Test thoroughly**: Create comprehensive test suite
8. **Document**: Write usage guide and update existing docs

---

## Appendix: Example Devplan Outputs

### Flat Mode Output
```markdown
# DevPlan: my-api

## Goal
- Build a REST API with authentication

## Constraints
- Use swarm for parallel execution
- Tasks execute sequentially

## Tasks

- [ ] 1.1: Initialize project structure
- [ ] 1.2: Set up TypeScript configuration
- [ ] 1.3: Install dependencies
- [ ] 1.4: Create base server
- [ ] 2.1: Implement authentication middleware
- [ ] 2.2: Create user model
- [ ] 2.3: Add login endpoint
- [ ] 2.4: Implement token validation
...
```

### Grouped Mode Output
```markdown
# DevPlan: my-api

## Goal
- Build a REST API with authentication

## Constraints
- Use swarm for parallel execution
- Tasks are grouped by file patterns to minimize conflicts

## Tasks

### Phase 1: Project Setup

- [ ] Parallel work unit 1 (4 tasks) [files: package.json, tsconfig.json, .gitignore]
  - [ ] 1.1: Initialize project structure
  - [ ] 1.2: Set up TypeScript configuration
  - [ ] 1.3: Install dependencies
  - [ ] 1.4: Create base server

- [ ] Parallel work unit 2 (3 tasks) [files: src/config/*, src/utils/*]
  - [ ] 1.5: Create configuration module
  - [ ] 1.6: Implement utility functions
  - [ ] 1.7: Set up logging

### Phase 2: Authentication

- [ ] Parallel work unit 1 (3 tasks) [files: src/models/*, src/db/migrations/*]
  - [ ] 2.1: Create user model
  - [ ] 2.2: Define database schema
  - [ ] 2.3: Create migration files

- [ ] Parallel work unit 2 (4 tasks) [files: src/middleware/*, src/auth/*]
  - [ ] 2.4: Implement authentication middleware
  - [ ] 2.5: Create token utilities
  - [ ] 2.6: Add password hashing
  - [ ] 2.7: Implement login endpoint
...
```

---

*Document version: 1.0*
*Last updated: 2026-01-25*
*Status: Ready for implementation*
