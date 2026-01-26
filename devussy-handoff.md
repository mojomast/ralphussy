# Handoff: Devussy Integration into Ralph-Live

**Date**: 2026-01-26  
**Previous Agent**: Claude (completed Phases 1-3)  
**Next Priority**: Phase 7 (E2E Integration Test)

---

## TL;DR - What You Need to Do

1. **Run the E2E test** using `zai-coding-plan/glm-4.7` model
2. **Generate a Hello World Python app** through Devussy interview
3. **Execute with 2 swarm workers**
4. **Validate** the generated code works
5. **Create/adapt unit tests** in `ralph-refactor/tests/test_devussy.sh`

---

## Current State Summary

### What's DONE (Phases 1-3)

| Component | Status | Location |
|-----------|--------|----------|
| OpenCode LLM Client | COMPLETE | `devussyout/src/llm_client_opencode.py` |
| TaskGroup Model | COMPLETE | `devussyout/src/models.py` |
| Basic Devplan Template (grouped) | COMPLETE | `devussyout/templates/basic_devplan.jinja` |
| Detailed Devplan Template (grouped) | COMPLETE | `devussyout/templates/detailed_devplan.jinja` |
| Basic Devplan Generator | COMPLETE | `devussyout/src/pipeline/basic_devplan.py` |
| Detailed Devplan Generator | COMPLETE | `devussyout/src/pipeline/detailed_devplan.py` |
| Devussy Shell Library | COMPLETE | `ralph-refactor/lib/devussy.sh` |
| Ralph-Live Integration | COMPLETE | `ralph-refactor/ralph-live` |

### What's PENDING

| Task | Priority | Description |
|------|----------|-------------|
| Phase 7: E2E Test | **HIGH** | Run full pipeline with hello world app |
| Phase 4: Swarm Integration | MEDIUM | Atomic group execution (optional enhancement) |
| Phase 5: Unit Tests | MEDIUM | Automated test suite |
| Phase 6: Documentation | LOW | User guides and docs |

---

## How to Run the E2E Test (Phase 7)

### Step 1: Set Up Environment

```bash
cd /home/mojo/projects/ralphussy/ralph-refactor

# Verify devussy dependencies
source lib/devussy.sh
source lib/core.sh
devussy_check_dependencies
# Should show no errors
```

### Step 2: Launch Devussy Mode

```bash
./ralph-live
# Press 'p' for Project Menu
# Press '6' for "Generate devplan with Devussy"
```

### Step 3: Create Hello World Project

When prompted, enter:
- **Project name**: `hello-world-python`
- **Project goal** (copy this exactly):
```
Create a simple Python hello world application with:
- A main.py that prints "Hello, World!"
- A greeter module with a Greeter class that has a greet(name) method
- Unit tests for the Greeter class using pytest
- A requirements.txt with pytest
- A README.md explaining how to run the app
```
- **Task organization**: Select `2` (grouped)
- **Tasks per group**: Press Enter (default 5)
- **Model**: Select `zai-coding-plan/glm-4.7`

### Step 4: Review and Start Swarm

- Review the generated devplan
- Press `s` to start swarm
- When prompted for model, select `zai-coding-plan/glm-4.7`
- Configure **2 workers**

Non-interactive option (start swarm with 2 workers from shell):

```bash
# From the project directory where devplan.md was created
cd "$SWARM_PROJECTS_BASE/hello-world-python" || cd ~/projects/hello-world-python
export RALPH_PROVIDER="zai-coding-plan"
export RALPH_MODEL="glm-4.7"
# Run ralph-swarm directly with 2 workers
${RALPH_REFACTOR:-/home/mojo/projects/ralphussy/ralph-refactor}/ralph-swarm --devplan devplan.md --project hello-world-python --workers 2
```

### Step 5: Validate Results

```bash
cd ~/projects/hello-world-python  # or wherever the project was created

# Install dependencies
pip install -r requirements.txt

# Run tests
pytest

# Run the app
python main.py
# Should print "Hello, World!"
```

---

## Key Files You'll Need to Reference

### Core Devussy Files

| File | Purpose |
|------|---------|
| `devussyout/src/llm_client_opencode.py` | LLM client using opencode CLI |
| `devussyout/src/models.py` | TaskGroup and DevPlanPhase models |
| `devussyout/src/pipeline/basic_devplan.py` | Basic devplan generation with grouping |
| `devussyout/src/pipeline/detailed_devplan.py` | Detailed step generation with grouping |
| `ralph-refactor/lib/devussy.sh` | Bash library for ralph-live integration |

### Template Files

| File | Purpose |
|------|---------|
| `devussyout/templates/basic_devplan.jinja` | High-level phase generation prompt |
| `devussyout/templates/detailed_devplan.jinja` | Detailed step generation prompt |

### Existing Test Files (for reference)

| File | Purpose |
|------|---------|
| `ralph-refactor/tests/test_swarm.sh` | Swarm test patterns |
| `ralph-refactor/tests/test_devplan.sh` | Devplan test patterns |
| `ralph-refactor/tests/test_core.sh` | Core function tests |

---

## Architecture Overview

```
User Input (goal description)
        │
        ▼
┌─────────────────────────────────────┐
│  devussy_generate_devplan()         │  ralph-refactor/lib/devussy.sh
│  - Selects flat/grouped mode        │
│  - Selects model                    │
│  - Calls Python pipeline            │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  ProjectDesignGenerator             │  devussyout/src/pipeline/
│  BasicDevPlanGenerator              │  Uses OpenCodeLLMClient
│  DetailedDevPlanGenerator           │  Supports task_grouping param
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  DevPlan JSON                       │  Contains phases, task_groups,
│  (with TaskGroups)                  │  estimated_files, steps
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  devussy_json_to_markdown()         │  Converts to swarm-compatible
│                                     │  markdown devplan format
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│  Swarm Execution                    │  project_start_swarm_devplan()
│  (2 workers)                        │  Executes tasks in parallel
└─────────────────────────────────────┘
```

---

## Grouped Mode Output Format

When `task_grouping='grouped'`, the devplan looks like:

```markdown
# DevPlan: hello-world-python

## Goal
- Create a simple Python hello world application...

## Constraints
- Use swarm for parallel execution
- Tasks are grouped by file patterns to minimize conflicts

## Tasks

### Phase 1: Project Setup

**Group 1** [files: requirements.txt, setup.py, pyproject.toml]

- [ ] 1.1: Create requirements.txt with pytest dependency
  - Add pytest>=7.0.0
  - Add any other dependencies
- [ ] 1.2: Create project configuration files
  - Set up pyproject.toml if needed

**Group 2** [files: README.md, .gitignore]

- [ ] 1.3: Create README.md
  - Document how to install and run
- [ ] 1.4: Create .gitignore
  - Ignore __pycache__, .pytest_cache, venv

### Phase 2: Core Implementation
...
```

---

## Common Issues & Solutions

### Issue: "opencode command not found"
```bash
# Ensure opencode is in PATH
which opencode
# If not found, install it or add to PATH
```

### Issue: "Missing Python packages"
```bash
pip install jinja2 pydantic
```

### Issue: Model not found
```bash
# List available models
opencode models | grep zai-coding-plan
# Should show zai-coding-plan/glm-4.7
```

### Issue: Devplan generation hangs
- The pipeline makes multiple LLM calls (design, basic, detailed)
- Each phase is detailed concurrently
- Total time: 2-5 minutes depending on model speed
- Check stderr for `[devussy]` progress messages

### Issue: "Import could not be resolved" errors
- These are LSP/IDE warnings, not runtime errors
- The code runs fine with `python3`
- Install deps in your venv: `pip install jinja2 pydantic`

---

## Unit Test Requirements (Task 7.5)

Create `ralph-refactor/tests/test_devussy.sh` with tests for:

1. `devussy_check_dependencies()` - Should return 0 when deps present
2. `devussy_json_to_markdown()` with flat mode - Verify output format
3. `devussy_json_to_markdown()` with grouped mode - Verify group headers
4. Mock-based pipeline test (if possible)

Reference existing tests in:
- `ralph-refactor/tests/test_devplan.sh`
- `ralph-refactor/tests/test_core.sh`

Use `zai-coding-plan/glm-4.7` for any tests that require LLM calls.

---

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `RALPH_PROVIDER` | Default LLM provider | `zai-coding-plan` |
| `RALPH_MODEL` | Default LLM model | `glm-4.7` |
| `DEVUSSY_PATH` | Path to devussyout | `~/projects/ralphussy/devussyout` |
| `SWARM_PROJECTS_BASE` | Projects directory | `~/projects` |

Set these before running:
```bash
export RALPH_PROVIDER="zai-coding-plan"
export RALPH_MODEL="glm-4.7"
```

---

## Quick Command Reference

```bash
# Navigate to project
cd /home/mojo/projects/ralphussy

# Run ralph-live
./ralph-refactor/ralph-live

# Test devussy dependencies only
source ralph-refactor/lib/devussy.sh
source ralph-refactor/lib/core.sh
devussy_check_dependencies

# List available models
opencode models

# Run existing tests
./ralph-refactor/tests/run_all_tests.sh
```

---

## Files Modified in This Session

| File | Changes Made |
|------|--------------|
| `devussyout/src/llm_client_opencode.py` | NEW - OpenCode LLM client |
| `devussyout/src/models.py` | Added TaskGroup model, updated DevPlanPhase |
| `devussyout/templates/basic_devplan.jinja` | Added grouped mode conditionals |
| `devussyout/templates/detailed_devplan.jinja` | Added grouped mode conditionals |
| `devussyout/src/pipeline/basic_devplan.py` | Added task_grouping param, _parse_grouped_response |
| `devussyout/src/pipeline/detailed_devplan.py` | Added task_grouping param, _parse_task_groups |
| `ralph-refactor/lib/devussy.sh` | NEW - Full devussy library |
| `ralph-refactor/ralph-live` | Added devussy.sh source, menu options |
| `devplan.md` | Updated with progress, added Phase 7 |

---

## Next Steps After E2E Test

1. **If E2E succeeds**: 
   - Document any issues in devplan.md progress notes
   - Move to Phase 5 (unit tests) or Phase 6 (documentation)
   - Mark Phase 7 tasks complete in devplan.md

2. **If E2E fails**:
   - Check the stderr output for `[devussy]` messages
   - Verify the model is available: `opencode models | grep zai-coding-plan`
   - Try with a different model first to isolate issues
   - Check generated devplan.md for parsing issues
   - Add blocker notes to devplan.md

3. **Optional enhancements** (Phase 4):
   - Swarm atomic group execution
   - File locking for grouped tasks
   - These are nice-to-have, not required for basic functionality

---

## Contact & Resources

- **Main devplan**: `/home/mojo/projects/ralphussy/devplan.md`
- **Original spec**: `/home/mojo/projects/ralphussy/devussyplan.md`
- **This handoff**: `/home/mojo/projects/ralphussy/devussy-handoff.md`
- **Ralph-live**: `/home/mojo/projects/ralphussy/ralph-refactor/ralph-live`

---

Good luck! The core integration is solid - you mainly need to validate it works end-to-end and create the test suite.
