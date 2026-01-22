# Ralph Live Handoff

**Updated**: 2026-01-22
**Session**: Real-time CLI with streaming output + projects + ASCII UI

## Just Completed

Enhanced `ralph-live` (pure bash, non-TUI) with safer interactive input handling, project workflows, single-key menus, and upgraded ASCII banners.

## What Was Built

### Main Script: `ralph-refactor/ralph-live`

A pure-bash real-time CLI that replaces the need for a TUI while maintaining workflow features:

**Core Features:**
- Streaming verbose output from agents as they work (via named pipes)
- Real-time interactive commands while agent runs
- Full workflow support: devplan mode, iterations, context, history, progress
- Interactive model/provider selection wizard
- Swarm mode integration with separate worker model settings

**New in this session:**
- Project system under `~/.ralph/projects/` with current project tracking
- `New project (DevPlan -> swarm)` wizard
- Single-key interactive menus (no Enter) via `read_key`
- `ui_logo` + `ui_banner` for consistent, cooler ASCII branding
- Fix for model selection cancel/exit behavior under `set -euo pipefail`

**Provider/Model Management:**
- `select_model_step_by_step()` - Interactive wizard (select provider first, then model)
- `get_all_providers()` - Fetches providers from `opencode models`
- `get_models_for_provider()` - Lists models for a specific provider
- `select_provider_interactive()` - Numbered provider selection
- `select_model_interactive()` - Numbered model selection for provider
- `show_current_model()` - Display current model/provider settings
- `list_providers()` - List all available providers
- `list_models_for_provider()` - List models for current/effective provider

**Swarm-Specific Features:**
- `SWARM_PROVIDER` and `SWARM_MODEL` variables for worker settings
- `select_swarm_model()` - Interactive swarm model selection
- `show_swarm_model()` - Display swarm settings
- `get_swarm_model_string()` - Get formatted model string for swarm

**Interactive Commands (while agent runs):**
| Command | Alias | Description |
|---------|-------|-------------|
| `status` | `s` | Show agent status, iteration, elapsed time |
| `model` | `m` | Show current model/provider settings |
| `select` | `sel` | Launch interactive model selection wizard |
| `provider` | `pv` | List all available providers |
| `models` | `ml` | List models for current provider |
| `context` | `c` | Show pending context menu |
| `add` | `a` | Add context for next iteration |
| `progress` | `p` | Show recent progress log |
| `history` | `h` | Show iteration history with stats |
| `swarm` | `sw` | Show swarm commands menu |
| `sp` | - | Select swarm provider/model interactively |
| `sm` | - | Show swarm model settings |
| `interrupt` | `i` | Send interrupt signal (graceful stop) |
| `stop` | `x` | Force kill the agent |
| `help` | `?` | Show help message |

### Wrapper Script: `ralph-live`

Symlink resolver that calls the main script, allowing `./ralph-live` invocation.

### Documentation: `ralph-refactor/RALPH-LIVE.md`

Comprehensive documentation covering:
- Usage examples for all modes
- Interactive model selection workflow
- Swarm mode with separate worker models
- All interactive commands
- Comparison with TUI mode

### Main Script Update: `ralph-refactor/ralph`

Added reference to ralph-live in help text for users who want streaming CLI mode.

## Files Modified

| File | Change |
|------|--------|
| `ralph-refactor/ralph-live` | Main live CLI (projects, menus, input fixes, ASCII UI) |
| `ralph-live` | Wrapper script |
| `ralph-refactor/RALPH-LIVE.md` | Documentation |
| `ralph-refactor/ralph` | Help text references ralph-live |

## Usage Examples

```bash
# Simple task with streaming output
./ralph-live "Create a REST API"

# Interactive model selection first
./ralph-live --select-model "Task description"

# DevPlan mode
./ralph-live --devplan ./devplan.md

# Swarm mode for parallel workers
./ralph-live --swarm "Refactor entire codebase"

# Swarm with custom worker model
./ralph-live --swarm "Large task" \
  --provider anthropic \
  --model claude-sonnet-4-20250514 \
  --swarm-model claude-haiku-4-20250514

# Interactive projects
./ralph-live
# -> 7) Project menu
# -> 8) New project (DevPlan -> swarm)
```

## Key Technical Decisions

1. **Named Pipe Streaming**: Used FIFO (`$RALPH_DIR/live/output.fifo`) for streaming agent output while maintaining interactive input capability

2. **Bash-Only Dependencies**: No Python/Textual required - pure bash implementation

3. **Interactive Selection Pattern**: Users select provider first (1-N), then model for that provider (1-N), with cancel options at each step

4. **Swarm Model Inheritance**: If swarm worker model not explicitly set, inherits main agent's model settings

5. **Non-Blocking Input**: Used `read -t 1` for 1-second timeout to check for commands while agent runs

## Next Steps

1. **Test Interactive Selection**: Run `./ralph-live --select-model "test"` to verify provider/model selection works correctly

2. **Test Swarm Integration**: Test `--swarm` mode with custom models:
   ```bash
   ./ralph-live --swarm "Small task" --swarm-model claude-sonnet-4-20250514
   ```

3. **Add to Main Help**: Consider adding ralph-live to the main `./ralph --help` output

4. **Integration Testing**: Verify ralph-live works with existing Ralph infrastructure:
   - Context file (`~/.ralph/context.md`)
   - Progress file (`~/.ralph/progress.md`)
   - History file (`~/.ralph/history.json`)
   - State file (`~/.ralph/state.json`)

5. **Enhancement Ideas**:
   - Add `--workers N` flag for swarm mode
   - Add `--detach` support like main ralph
   - Add `--resume` support for interrupted runs
   - Consider saving selected model to config for defaults

## Context for Next Ralph Instance

You are taking over after creating ralph-live - a comprehensive CLI mode for Ralph. Key files to understand:
- `ralph-refactor/ralph-live` - Main implementation (1194 lines)
- `ralph-refactor/RALPH-LIVE.md` - Full documentation
- `ralph-refactor/lib/core.sh` - Shared dependencies (logging, state, etc.)

The user wanted:
1. Non-TUI CLI with streaming output ✅
2. Real-time interaction while agents run ✅
3. Interactive model selection (provider → model) ✅
4. Swarm mode with separate worker models ✅

Next testing/verification recommended before further development.

---

## Previous Session (Pre-ralph-live)

The following was the state before this session's work:

### Ralph Refactor Handoff

**Project State**: Ralph TUI (`ralph-refactor/tui/ralph_tui.py`) with backend shell scripts.

### Recent Changes (Prior Session)

1. **System Log Pane (LogPane)**: Added non-interactive system log pane showing task starts, completions, failures, tool calls, file edits, and process events with visual indicators.

2. **Enhanced Worker Status Display**: Fixed worker pane to show current task with status indicators (idle=🟡, working=🟢, error=🔴, stuck=⏳).

3. **TUI Layout Changes**: 3-column layout (LogPane | ChatPane | WorkerPane) with 2-row layout for active work and progress/file browser.

4. **Resume/Progress Persistence**: Added `source_hash` and `task_hash` columns, `completed_tasks` table, `--resume RUN_ID` flag, and auto-detection for same devplan.

5. **Swarm Containment**: Added `SWARM_MAX_WORKERS=8`, `SWARM_MAX_TOTAL_WORKERS=16`, `--emergency-stop`, and process resource limits.

**Key Files:**
- `ralph-refactor/tui/ralph_tui.py` - Main TUI application
- `ralph-refactor/lib/swarm_db.sh` - SQLite wrapper with resume
- `ralph-refactor/lib/swarm_worker.sh` - Worker agent logic
- `ralph-refactor/ralph-swarm` - Swarm orchestrator

**Known Issues:**
- Performance: Polls DB every 2 seconds, may need optimization
- Editor: Basic FileEditorScreen without syntax highlighting editing
- Shell Integration: Path resolution needs alignment
- Stuck Detection: Visual-only, no actual timeout detection

---

# Handoff: Token Aggregation Bug Fix

## Date
2026-01-22

## Context
When testing swarm with `zai-coding-plan/glm-4.7`, all API calls were showing "0→0 tokens | $0" which appeared to indicate model was returning empty responses. This was causing tasks to fail because completion promise `<promise>COMPLETE</promise>` was never generated.

## Root Cause Analysis

The token counting logic in `swarm_worker.sh` was using `head -1` to extract token values from JSON output:

```bash
# Before (buggy):
prompt_tokens=$(echo "$json_output" | jq -r '.part.tokens.input // .tokens.input // 0' 2>/dev/null | head -1)
completion_tokens=$(echo "$json_output" | jq -r '.part.tokens.output // .tokens.output // 0' 2>/dev/null | head -1)
```

OpenCode's JSON output format is a stream of JSON objects, one per line:
- `step_start` events - no tokens
- `tool_use` events - no tokens
- `step_finish` events - **contain token data**

The `head -1` was only processing the first line (a `step_start` event), which has 0 tokens. All subsequent lines containing actual token data were ignored.

## What Was Fixed

**File:** `lib/swarm_worker.sh:329-332`

### 1. Fixed Token Aggregation

Changed from extracting tokens from first line to summing all tokens from all events:

```bash
# After (fixed):
prompt_tokens=$(echo "$json_output" | jq -s 'map(select(.part.tokens.input)) | map(.part.tokens.input) | add // 0' 2>/dev/null)
completion_tokens=$(echo "$json_output" | jq -s 'map(select(.part.tokens.output)) | map(.part.tokens.output) | add // 0' 2>/dev/null)
```

This uses `jq -s` (slurp mode) to read all lines as an array, filters for events that have token data, then sums them up.

### 2. Added Debug Output for 0 Token Cases

Added warning and debug file when 0 tokens are detected:

```bash
if [ "${SWARM_OUTPUT_MODE:-}" = "live" ]; then
    echo -e "${BLUE}✓${NC} API call complete: ${prompt_tokens}→${completion_tokens} tokens | \$${cost}"
    if [ "$completion_tokens" -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} Warning: 0 tokens returned. Full response saved to: ${repo_dir}/.swarm_debug_${task_id}.json"
        echo "$json_output" > "${repo_dir}/.swarm_debug_${task_id}.json"
    fi
    echo ""
fi
```

## Testing

### Before Fix
```
✓ API call complete: 0→0 tokens | $0
Task execution did not return completion promise
⚠ Worker 1 task 1564 did not complete (no promise)
```

### After Fix
```
✓ API call complete: 68981→2018 tokens | $0
Worker 1 completed task 1565
✓ Worker 1 marked task 1565 as complete
```

## Files Modified

1. `lib/swarm_worker.sh:329-333` - Fixed token aggregation to sum all events
2. `lib/swarm_worker.sh:338-344` - Added debug warning for 0 token cases
