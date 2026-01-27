Handoff: Next Steps for Ralph Live Dashboard

## What I changed (this session)

### Continuous LLM Chat Interview Mode (NEW)

Created a complete interview module for continuous LLM chat-based devplan generation at `devussyout/src/interview/`:

1. **Core Components**:
   - `conversation_history.py` - Stores messages with role, timestamp, stage tracking; supports save/load
   - `json_extractor.py` - Extracts JSON from LLM responses (code blocks, log entries, regex fallback)
   - `stage_coordinator.py` - Manages stage transitions (interview → design → devplan → detailed → handoff)
   - `interview_manager.py` - Main orchestrator handling chat, slash commands, stage progression

2. **System Prompts** in `devussyout/prompts/`:
   - `interview_system_prompt.md` - Requirements gathering through conversation
   - `design_system_prompt.md` - Project design generation
   - `devplan_system_prompt.md` - High-level development plan
   - `detailed_system_prompt.md` - Detailed implementation steps
   - `handoff_system_prompt.md` - Handoff prompt for implementation agent

3. **CLI Entry Points**:
   - `devussyout/interview_cli.py` - CLI for running interviews
   - `devussyout/src/pipeline/interview_pipeline.py` - Integrates with existing pipeline generators

4. **Features**:
   - Single conversation spanning all 5 stages
   - Slash commands: `/done`, `/skip`, `/back`, `/status`, `/help`, `/save`, `/reset`, `/model`, `/stage`
   - Auto-save after each stage completion
   - Streaming support with callbacks
   - Progress tracking

**Usage:**
```bash
cd devussyout
python interview_cli.py --model opencode/claude-sonnet-4-5
```

### Previous: Dynamic OpenCode Model Selection

1. ✅ **(High) Dynamic Model Fetching from OpenCode** - Models are now fetched dynamically from OpenCode CLI:
   - Runs `opencode models` command on startup to get available models
   - Models are automatically organized by provider (e.g., `opencode/`, `firmware/`, `github-copilot/`)
   - Fallback to hardcoded models if CLI fails
   - Models can be refreshed via Settings > "Refresh Models" option

2. ✅ **(High) Provider-First Model Selection** - Improved UX in Options modal:
   - User first selects a provider, then selects from available models for that provider
   - Model lists update dynamically when provider changes
   - Shows count of available providers and models for each
   - When focused on model field, shows preview of available models

3. ✅ **(High) All Model Selectors Use OpenCode Models** - Applies to:
   - **SWARM** section: Provider and Model selection
   - **RALPH** section: Provider and Model selection
   - **DEVPLAN** section: All 5 stages (interview/design/devplan/phase/handoff)

4. ✅ **(Medium) Refresh Models Option** - In Settings section:
   - Shows current count: "X providers, Y models"
   - Press ENTER to refresh models from OpenCode CLI
   - Logs refresh results to Ralph Live console

## Where the code lives
- UI and logic: `swarm-dashboard2/src/index.ts`
- DevPlan pipeline: `devussyout/src/pipeline/` (Python)
- DB helper (source): `swarm-dashboard/src/database-bun.ts`
- DB helper (runtime): `swarm-dashboard/dist/database-bun.js`
- CLI used by UI: `ralph-refactor/ralph-swarm`

## How to run locally
1. From repo root run: `./run-swarm-dashboard2.sh` (this runs `bun swarm-dashboard2/src/index.ts`)
2. Use a real interactive terminal (the launcher refuses non-interactive TTYs).
3. To rebuild database module: `cd swarm-dashboard && bun run build`

## Quick verification (manual checks)

### Dynamic Model Selection (NEW)
- Press `o`: Options menu opens - models should be loaded from OpenCode
- Navigate to SWARM section: Should show "Provider" and "Model" with counts like "(X available)" and "(Y for provider)"
- Focus on Provider field, press ENTER: Should cycle through providers from OpenCode (e.g., opencode, firmware, github-copilot)
- Focus on Model field, press ENTER: Should cycle through models for the selected provider
- When Model field is focused, should show a preview list of available models
- Navigate to SETTINGS section: First field should be "Refresh Models" with count of providers/models
- Press ENTER on "Refresh Models": Should refresh from `opencode models` CLI and show confirmation in Ralph Live console

### Options Menu
- Press `o`: Options menu opens with 5 tabs (MODE, SWARM, RALPH, DEVPLAN, SETTINGS)
- Use ←/→ or H/L to switch sections, ↑/↓ to navigate, ENTER/SPACE to change values
- Press ESC to close options (changes auto-save to `~/.ralph/config.json`)
- Header shows current mode: `Mode: SWARM` (or RALPH/DEVPLAN based on selection)

### DevPlan & Other Features
- Press `d`: DevPlan interview modal appears with 5 fields. Fill in project details and press Enter on last field to start generation.
- Watch progress modal show stages completing: Design → DevPlan → Phases → Handoff
- Check `~/.ralph/devplans/{project_name}/` for generated files after completion
- Press `s`: Start-run configuration modal appears (worker count defaults to config.swarmAgentCount)
- Press `v`: Run selector overlay appears
- Press `V`: Clears selection and returns to current run
- Press `e`: Emergency stop confirmation modal appears
- Check `~/.ralph/dashboard-ui.log` for debug entries

## Known issues / notes
- Editor/TypeScript diagnostics appear (missing `@types/react`, implicit `any`s). These are lint/LSP warnings and do not prevent runtime under Bun.
- The devplan pipeline requires Python 3 with access to `opencode` CLI for LLM calls
- If the pipeline fails, check that `devussyout/src/pipeline/` modules are accessible
- The interview modal supports multiline input in Requirements field (Enter adds newline, Ctrl+Enter submits)

## Config Structure (`~/.ralph/config.json`)
```json
{
  "mode": "swarm",                    // "ralph" | "devplan" | "swarm"
  "swarmModel": {
    "provider": "opencode",           // Provider from `opencode models` (e.g., opencode, firmware, github-copilot)
    "model": "opencode/claude-sonnet-4-5"  // Full model identifier (provider/model)
  },
  "ralphModel": {
    "provider": "opencode",
    "model": "opencode/claude-sonnet-4-5"
  },
  "devplanModels": {
    "interview": { "provider": "opencode", "model": "opencode/claude-sonnet-4-5" },
    "design": { "provider": "opencode", "model": "opencode/claude-sonnet-4-5" },
    "devplan": { "provider": "opencode", "model": "opencode/claude-sonnet-4-5" },
    "phase": { "provider": "opencode", "model": "opencode/claude-sonnet-4-5" },
    "handoff": { "provider": "opencode", "model": "opencode/claude-sonnet-4-5" }
  },
  "swarmAgentCount": 4,
  "commandTimeout": 300,
  "llmTimeout": 120,
  "pollInterval": 5,
  "autoRefresh": true,
  "showCosts": true,
  "maxLogLines": 200,
  "debugMode": false
}
```

Note: Models are now dynamically fetched from `opencode models` CLI. The provider/model values
should use the full format returned by OpenCode CLI (e.g., `opencode/claude-sonnet-4-5`).

### Interview Mode Integration

**New**: The DevPlan generation now supports a continuous LLM chat-based interview mode at `devussyout/interview_cli.py`.

This provides a more natural conversational approach compared to the older staged prompts:

#### How It Works

1. **Multi-Stage Conversation** - A single conversation spans all 5 stages:
   - **Interview Stage** - Requirements gathering through natural dialogue
   - **Design Stage** - Project design generation
   - **DevPlan Stage** - High-level development plan
   - **Phases Stage** - Detailed implementation steps
   - **Handoff Stage** - Handoff prompt creation

2. **Slash Commands** - Interactive control:
   - `/done` - Mark requirements gathering complete
   - `/skip` - Skip current question
   - `/back` - Go back to previous topic
   - `/status` - Show current progress
   - `/help` - Show available commands
   - `/save` - Save current state
   - `/reset` - Restart conversation
   - `/model <provider>` - Switch LLM model
   - `/stage` - Show current pipeline stage

3. **Model Selection** - Dynamic model switching:
   - Default model loaded from `~/.ralph/config.json`
   - Use `/model opencode` to switch to OpenCode provider
   - Use `/model openai` to switch to OpenAI provider
   - Use `/model anthropic` to switch to Anthropic provider
   - Models can also be changed via Options menu (`o` key)

4. **Progress Tracking** - Visual indicators for:
   - Stage completion (interview → design → devplan → phases → handoff)
   - Message streaming from LLM responses
   - Auto-save after each stage completes

#### Running Interview Mode

```bash
# From devussyout directory
cd devussyout
python interview_cli.py --model opencode/claude-sonnet-4-5
```

#### Key Differences from Previous System

| Feature | Previous (Staged Prompts) | New (Interview Mode) |
|----------|---------------------------|----------------------|
| Interface | Sequential prompts | Continuous conversation |
| Model Selection | Static config per stage | Dynamic `/model` command |
| State Management | Per-stage restarts | Single session with `/save`/`/reset` |
| User Experience | Fill forms one-by-one | Natural chat flow |
| Flexibility | Limited to predefined stages | Skip `/back`, change model anytime |

## Files created/modified this session

### Interview Module (NEW)
- `devussyout/src/interview/__init__.py` - Module exports
- `devussyout/src/interview/conversation_history.py` - Message storage with stage tracking
- `devussyout/src/interview/json_extractor.py` - JSON extraction from LLM responses
- `devussyout/src/interview/stage_coordinator.py` - Stage management and transitions
- `devussyout/src/interview/interview_manager.py` - Main orchestrator
- `devussyout/src/pipeline/interview_pipeline.py` - Pipeline integration
- `devussyout/interview_cli.py` - CLI entry point
- `devussyout/prompts/interview_system_prompt.md` - Interview stage prompt
- `devussyout/prompts/design_system_prompt.md` - Design stage prompt
- `devussyout/prompts/devplan_system_prompt.md` - DevPlan stage prompt
- `devussyout/prompts/detailed_system_prompt.md` - Detailed steps prompt
- `devussyout/prompts/handoff_system_prompt.md` - Handoff stage prompt

### Previous: Dashboard
- `swarm-dashboard2/src/index.ts` - Added dynamic OpenCode model selection:
  - `fetchOpenCodeModels()` - Fetches models from `opencode models` CLI command
  - `FALLBACK_PROVIDERS` - Fallback models if CLI fails
  - `cachedProviders` - Global cache of fetched providers/models
  - `openCodeModels` state - React state for dynamic models
  - `getProviders()` / `getModelsForProvider()` - Helper functions for model access
  - `refreshOpenCodeModels()` - Function to re-fetch models from CLI
  - Updated keyboard handlers to use dynamic models instead of hardcoded PROVIDERS
  - Updated Options modal UI to show available providers/models with counts
  - Added "Refresh Models" option in Settings section

### Previous session: Options Menu with Provider/Model Configuration
- Config types: `RalphConfig`, `ProviderModel`, `DevPlanModels` interfaces
- `loadConfig()` and `saveConfig()` functions for `~/.ralph/config.json`
- Config state: `config`, `optionsSection`, `optionsFocusedField`
- Helper functions: `updateConfig()`, `updateDevplanModel()`
- Keyboard handler for `o` key to open options modal
- Options modal keyboard handling (section navigation, field cycling)
- Options modal UI rendering with 5 tabbed sections
- Wired config values to: swarmAgentCount, pollInterval, maxLogLines
- Added mode indicator to header
- Updated keymap help line to show `[O] Options`

### Previous session: DevPlan Generation with Interview & Progress Tracking
- Devplan generation feature with interview modal and progress tracking
- `runDevplanPipeline()` function to spawn Python pipeline

## Build commands
```bash
# Rebuild database module after source changes
cd swarm-dashboard && bun run build

# Run the dashboard
./run-swarm-dashboard2.sh
# or: bun swarm-dashboard2/src/index.ts
```

## DevPlan Pipeline Stages
The pipeline runs through these stages with progress updates:

| Stage | Progress | Description |
|-------|----------|-------------|
| design | 10-25% | Generates project design from interview data |
| devplan | 35-50% | Creates basic devplan with phases |
| phases | 55-80% | Generates detailed steps for each phase |
| handoff | 85-95% | Creates handoff prompt |
| complete | 100% | Pipeline finished, files saved |

## OpenCode Model Format

Models returned by `opencode models` CLI follow this format:
```
opencode/claude-sonnet-4-5
opencode/gpt-5
opencode/gemini-3-pro
firmware/claude-sonnet-4-5
firmware/gpt-4o
github-copilot/claude-sonnet-4
```

The format is `provider/model-name`. The TUI parses this and:
1. Extracts the provider (everything before `/`)
2. Groups models by provider
3. Shows full model identifiers in the UI
4. Stores the full `provider/model` string in the config
