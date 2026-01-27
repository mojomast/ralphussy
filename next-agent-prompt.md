# Task: Update Interview Mode to Continuous LLM Chat Mode

## Context

You are a senior developer working on the `devussyout` project - a devplan generation pipeline. The `ralphussy` project uses this pipeline to generate development plans from user requirements.

## What Was Just Done

Read `handoff.md` to understand the recent changes. The key change is that the TUI now uses **dynamic OpenCode models** instead of hardcoded provider/model lists.

### Summary of Changes:
- Added `fetchOpenCodeModels()` function that runs `opencode models` CLI
- Models are parsed from OpenCode output (format: `provider/model-name`)
- TUI now supports provider-first selection: user picks provider, then model
- Options modal shows available providers and models with counts
- Settings section has "Refresh Models" button

## Your Objective

Update the **interview mode** in `devussy` to be a **continuous LLM chat experience** with the same objective: **generating a development plan from user requirements**.

### Current State (What to Improve)

The current interview implementation has TWO modes:

1. **`llm_interview.py`** - LLM-driven conversational interview
   - Conversational chat that asks questions
   - Outputs structured JSON with project details
   - System prompt defines what to collect
   - Has slash commands: `/verbose`, `/settings`, `/model`, `/temp`, `/tokens`, `/help`, `/done`, `/quit`
   - Token tracking and streaming support
   - Can review existing design/devplan (mode="design_review")

2. **`interactive.py`** - Scripted questionnaire
   - Loads questions from YAML config (`config/questions.yaml`)
   - Question types: TEXT, CHOICE, MULTICHOICE, YESNO, NUMBER
   - Dependencies control which questions to ask
   - Uses `to_generate_design_inputs()` to convert answers to pipeline format

### What's Good to Keep:
- The **conversational nature** - Users like chatting with an LLM
- The **system prompt** approach - Defines what information to collect
- The **JSON extraction** - Converting conversation output to structured data
- The **conversation history** - Keeping track of what was discussed

### What Needs Improvement:
- The interview should be **continuous** across all pipeline stages, not just for gathering requirements
- After getting requirements, the LLM should continue the conversation to:
  1. Generate and review project design
  2. Refine based on feedback
  3. Generate basic devplan
  4. Generate detailed phases
  5. Create handoff prompt
- Use **stage-specific system prompts** (one for each stage) but maintain one conversation
- Leverage the **existing jinja templates** for formatting LLM output
- Use the **existing JSON extraction methods** (`_extract_text_from_log_entries()`, `_parse_response()`, etc.)

## What Devussy Files Should Contain

The devussy project structure already has the right components. Your job is to ensure:

### 1. Prompts Directory
```
devussyout/prompts/
├── design_system_prompt.md    # System prompt for project design stage
├── devplan_system_prompt.md   # System prompt for basic devplan generation
├── detailed_system_prompt.md  # System prompt for detailed devplan generation
├── handoff_system_prompt.md   # System prompt for handoff prompt generation
└── interview_system_prompt.md   # System prompt for initial requirements gathering
```

Each prompt should:
- Define the **role** and **objective** for that stage
- Reference **previous stages' output** (e.g., "Here is the project design: {...}")
- Include **formatting instructions** (JSON structure, markdown, etc.)
- Be concise and focused

### 2. Interview Logic Directory
```
devussyout/src/
└── interview/
    ├── interview_manager.py      # Manages interview conversation flow
    ├── conversation_history.py   # Stores conversation across stages
    ├── stage_coordinator.py    # Coordinates stage transitions
    └── json_extractor.py        # Extracts structured data from LLM responses
```

Key classes to implement:
- **InterviewManager**: Main entry point, maintains conversation state
- **StageCoordinator**: Handles moving from interview → design → devplan → phases → handoff
- **ConversationHistory**: Stores messages with role, content, timestamp
- **JSONExtractor**: Parses JSON from LLM responses (fallback to regex)

### 3. Jinja Templates (Already Exist, Just Use Better)
```
devussyout/templates/
├── project_design.jinja         # Design stage template
├── basic_devplan.jinja          # Basic devplan template
├── detailed_devplan.jinja        # Detailed devplan template
├── handoff_prompt.jinja           # Handoff prompt template
└── interview_response.jinja         # New: Format LLM responses as JSON
```

The `interview_response.jinja` template should:
- Take LLM conversation output and format as JSON
- Support multiple data types: strings, arrays, objects
- Handle errors gracefully (fallback to raw text if JSON fails)

### 4. JSON Extraction Logic
The pipeline already has good JSON extraction methods. Use them:

**From `basic_devplan.py`:**
- `_extract_text_from_log_entries()` - Extract text from log entries
- `_parse_response()` - Parse phase headers and bullet points
- `_parse_grouped_response()` - Parse task groups with file patterns

**From `detailed_devplan.py`:**
- `_parse_steps()` - Extract numbered steps: `1.1: Create module`
- `_parse_task_groups()` - Parse grouped format with file patterns

Your interview mode should:
- Call these existing methods to extract JSON after each stage
- Pass extracted data to the next stage's Jinja template
- Handle extraction failures with user-friendly retry prompts

## Implementation Plan

### Phase 1: Understand Current Code
1. Read `devussy/src/llm_interview.py` - Understand conversational flow
2. Read `devussy/src/interactive.py` - Understand questionnaire structure
3. Read `devussyout/src/pipeline/*.py` - Understand stage integration
4. Read `devussyout/templates/*.jinja` - Understand template structure

### Phase 2: Create Interview Components
1. Create `devussyout/src/interview/interview_manager.py`:
   - Main class managing conversation and state
   - Methods: `start_interview()`, `add_message()`, `get_context_for_stage()`, `transition_to_stage()`
   - Stores `ConversationHistory` object

2. Create `devussyout/src/interview/conversation_history.py`:
   - Class to store messages with `role`, `content`, `timestamp`
   - Methods: `add_message()`, `get_recent()`, `to_llm_format()`, `clear()`

3. Create `devussyout/src/interview/stage_coordinator.py`:
   - Manages stage transitions (interview → design → devplan → phases → handoff)
   - Each stage has its own system prompt
   - Maintains "stage_context" with outputs from previous stages

4. Create `devussyout/src/interview/json_extractor.py`:
   - Reuses existing `_parse_response()` methods
   - New: `extract_json_from_conversation()` - Gets JSON from chat history
   - Fallback to regex patterns if JSON fails

### Phase 3: Create System Prompts
Create `devussyout/prompts/*.md` files:

**`interview_system_prompt.md`:**
```
You are Ralph, an AI assistant specializing in gathering requirements for development planning.
Your goal is to collect the following information from the user through conversation:

- Project name and description
- Programming languages and frameworks
- Technical requirements and constraints
- APIs and integrations needed
- Deployment preferences
- Testing requirements

Ask questions one at a time. Be conversational and follow up on the user's answers.
When you have enough information, output a JSON object with the collected data.

JSON format:
{
  "project_name": "...",
  "languages": ["...", "..."],
  "frameworks": ["...", "..."],
  "apis": ["...", "..."],
  "requirements": "...",
  "constraints": "..."
}
```

**`design_system_prompt.md`:**
```
You are a Software Architect AI. Your goal is to generate a comprehensive project design.

Review the user's requirements and create a technical design that includes:
- Architecture overview
- Tech stack and technology choices
- Module structure
- Database design
- API design (if applicable)
- Security considerations
- Deployment strategy

Output in markdown format with clear sections.
```

**`devplan_system_prompt.md`:**
```
You are a DevPlan Generator AI. Create a high-level development plan from the project design.

Break down the project into 3-5 major phases. For each phase:
- Provide a clear title and objective
- List key deliverables
- Estimate complexity and dependencies

Keep the plan achievable and well-structured.
```

**`detailed_system_prompt.md`:**
```
You are a Technical Specifier AI. Expand each devplan phase into detailed, actionable steps.

For each phase, create 4-8 steps that:
- Are specific and actionable (use "Create X", "Implement Y", "Set up Z")
- Include file paths and locations
- Reference code examples where helpful
- Estimate effort

Format as a numbered list (1.1, 1.2, etc.).
```

**`handoff_system_prompt.md`:**
```
You are a Prompt Engineering AI. Create a comprehensive handoff prompt for an autonomous coding agent.

The handoff prompt should include:
- Project context and objectives
- Tech stack details
- Architecture overview
- Step-by-step implementation plan
- Quality requirements and testing strategy
- File locations and references

Format as a clear, executable prompt that guides an autonomous agent through the implementation.
```

### Phase 4: Update CLI Entry Point
1. Update `devussy/src/main.py` to add new interview command:
   ```bash
   python -m devussy interview --mode chat
   ```
   - Or integrate with existing `llm_interview.py` entry point

2. Add command-line options:
   - `--model provider/model` - Select OpenCode model
   - `--streaming` - Enable/disable streaming
   - `--temperature` - Set creativity level
   - `--save-to path` - Where to save output

### Phase 5: Integrate with Existing Pipeline
1. Update `devussyout/src/pipeline/project_design.py`:
   - Accept `ConversationHistory` as input
   - Extract design from conversation using `json_extractor`
   - Or prompt LLM with conversation context + design prompt

2. Similar updates for `basic_devplan.py`, `detailed_devplan.py`, `handoff_prompt.py`:
   - Each accepts conversation history and relevant system prompt
   - Extracts JSON output and passes to Jinja template

3. Create `devussyout/src/pipeline/interview_pipeline.py`:
   - Orchestrates the full conversation flow
   - Manages stage transitions automatically
   - Saves progress after each stage

## Key Requirements

1. **Single Conversation, Multiple Stages**: User chats with one LLM, but the conversation spans multiple generation stages
2. **Conversation Memory**: All previous stages' outputs are available as context
3. **Stage Prompts**: Each stage has its own system prompt loaded from `prompts/*.md`
4. **JSON Extraction**: Use existing parsing methods, wrap them in a unified interface
5. **Jinja Templates**: Continue using existing templates, ensure they accept structured data
6. **OpenCode Models**: Allow user to specify provider/model from the TUI's available models
7. **Progress Tracking**: Show which stage is active (like the existing progress modal)
8. **Save Points**: Auto-save conversation and outputs after each stage

## Success Criteria

The interview mode is successful when:
- ✅ User can chat naturally to gather requirements
- ✅ LLM automatically moves to design generation when ready
- ✅ User can provide feedback on design, LLM refines it
- ✅ User can request changes to devplan, LLM updates it
- ✅ Final handoff prompt is generated and saved
- ✅ All conversation history is preserved and can be resumed
- ✅ Output matches existing pipeline format (compatible with current devussy structure)

## What to Return

Please provide:
1. A **file structure** for the new interview components (showing which files to create)
2. **Code** for the main classes (`InterviewManager`, `StageCoordinator`, `ConversationHistory`, `JSONExtractor`)
3. **Prompt templates** for each stage (design, devplan, detailed, handoff)
4. **Integration instructions** for updating CLI entry point and pipeline modules
5. A summary of **how the new flow works** compared to the old approach

Be thorough but practical - this is a significant feature improvement.
