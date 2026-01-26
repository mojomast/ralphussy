#!/usr/bin/env bash

# Devussy mode for ralph-live - AI-powered devplan generation
# Supports both flat and grouped task generation for swarm execution

__DEVUSSY_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Devussy installation path
DEVUSSY_PATH="${DEVUSSY_PATH:-$HOME/projects/ralphussy/devussyout}"

# ============================================================================
# Dependency Checking
# ============================================================================

devussy_check_dependencies() {
    local missing=()

    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v opencode >/dev/null 2>&1 || missing+=("opencode")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing dependencies:${NC}"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi

    # Check for devussyout
    if [ ! -d "$DEVUSSY_PATH" ]; then
        echo -e "${RED}devussyout directory not found${NC}"
        echo "  Expected: $DEVUSSY_PATH"
        echo "  Set DEVUSSY_PATH environment variable to override"
        return 1
    fi

    # Check for Python packages
    if ! python3 -c "import jinja2, pydantic" 2>/dev/null; then
        echo -e "${RED}Missing Python packages. Install with:${NC}"
        echo "  pip install jinja2 pydantic"
        return 1
    fi

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
        echo "  ${GREEN}1${NC}) Create new project with Devussy"
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
    projects_init

    ui_banner "NEW PROJECT (DEVUSSY)"

    local name
    echo -n -e "${YELLOW}Project name: ${NC}"
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
    echo -e "${CYAN}Describe your project goal (Ctrl+D when done):${NC}"
    local goal
    goal=$(read_multiline_input)
    if [ -z "$goal" ]; then
        goal="$name"
    fi

    if devussy_generate_devplan "$name" "$goal" "$devplan_path" "$workdir"; then
        cat > "$dir/project.env" <<EOF
NAME="$name"
WORKDIR="$workdir"
DEVPLAN_PATH="$devplan_path"
EOF
        project_set_current "$name" || true
        echo -e "${GREEN}Created project: $name${NC}"
    else
        echo -e "${RED}Failed to generate devplan${NC}"
        return 1
    fi
}

devussy_generate_for_current_project() {
    if [ -z "$CURRENT_PROJECT" ] || [ -z "$CURRENT_PROJECT_DEVPLAN" ]; then
        echo -e "${RED}No current project/devplan selected${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}Enter project goal (Ctrl+D when done, empty to use project name):${NC}"
    local goal
    goal=$(read_multiline_input)

    if [ -z "$goal" ]; then
        # Try to extract goal from existing devplan
        if [ -f "$CURRENT_PROJECT_DEVPLAN" ]; then
            goal=$(grep -A 5 "^## Goal" "$CURRENT_PROJECT_DEVPLAN" 2>/dev/null | head -6 | tail -1 || echo "")
            goal="${goal#- }"
        fi
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
    local workdir="${4:-$(pwd)}"

    echo ""
    echo -e "${CYAN}Choose task organization mode:${NC}"
    echo "  ${GREEN}1${NC}) Flat list (tasks in priority order)"
    echo "  ${GREEN}2${NC}) Grouped by file patterns (parallelizable for swarm)"
    echo ""
    echo -n -e "  ${YELLOW}Choice [2]: ${NC}"
    local task_grouping_choice
    read_user_input task_grouping_choice
    task_grouping_choice="${task_grouping_choice:-2}"

    local task_grouping
    case "$task_grouping_choice" in
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
    echo ""
    echo -e "${CYAN}Select model for devplan generation:${NC}"
    
    # Use existing model selection if available
    local provider=""
    local model=""
    
    if declare -f select_model_step_by_step >/dev/null 2>&1; then
        SELECTED_PROVIDER=""
        SELECTED_MODEL=""
        if select_model_step_by_step; then
            provider="$SELECTED_PROVIDER"
            model="$SELECTED_MODEL"
        fi
    else
        # Fallback: use existing RALPH_PROVIDER/RALPH_MODEL
        provider="${RALPH_PROVIDER:-}"
        model="${RALPH_MODEL:-}"
    fi

    if [ -z "$model" ]; then
        echo -e "${YELLOW}Using default model${NC}"
    fi

    echo ""
    echo -e "${CYAN}Generating devplan with Devussy...${NC}"
    echo -e "  ${CYAN}Mode:${NC} $task_grouping"
    [ "$task_grouping" = "grouped" ] && echo -e "  ${CYAN}Group size:${NC} $task_group_size"
    echo -e "  ${CYAN}Model:${NC} ${model:-default}"
    echo ""

    # Generate using Python script
    local devplan_json
    devplan_json=$(DEVUSSY_PROJECT_NAME="$project_name" \
        DEVUSSY_GOAL="$goal" \
        DEVUSSY_TASK_GROUPING="$task_grouping" \
        DEVUSSY_GROUP_SIZE="$task_group_size" \
        DEVUSSY_PROVIDER="$provider" \
        DEVUSSY_MODEL="$model" \
        DEVUSSY_PATH="$DEVUSSY_PATH" \
        python3 - 2>&1 <<'PYTHON_SCRIPT'
import asyncio
import sys
import os

# Add devussyout to path
devussy_path = os.environ.get("DEVUSSY_PATH", os.path.expanduser("~/projects/ralphussy/devussyout"))
sys.path.insert(0, os.path.join(devussy_path, "src"))
sys.path.insert(0, devussy_path)

async def main():
    try:
        from pipeline.project_design import ProjectDesignGenerator
        from pipeline.basic_devplan import BasicDevPlanGenerator
        from pipeline.detailed_devplan import DetailedDevPlanGenerator
        from concurrency import ConcurrencyManager
        from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig
        
        # Configuration from environment
        project_name = os.environ.get("DEVUSSY_PROJECT_NAME", "")
        goal = os.environ.get("DEVUSSY_GOAL", "")
        task_grouping = os.environ.get("DEVUSSY_TASK_GROUPING", "flat")
        task_group_size = int(os.environ.get("DEVUSSY_GROUP_SIZE", "5"))
        provider = os.environ.get("DEVUSSY_PROVIDER", "")
        model = os.environ.get("DEVUSSY_MODEL", "")
        
        print(f"[devussy] Starting generation for: {project_name}", file=sys.stderr)
        print(f"[devussy] Mode: {task_grouping}, Group size: {task_group_size}", file=sys.stderr)
        
        # Create OpenCode LLM client
        config = OpenCodeConfig(provider=provider, model=model, timeout=600)
        llm = OpenCodeLLMClient(config)
        
        # Generate project design
        print("[devussy] Generating project design...", file=sys.stderr)
        pdg = ProjectDesignGenerator(llm)
        design = await pdg.generate(project_name, [], goal)
        
        # Generate basic devplan
        print("[devussy] Generating basic devplan...", file=sys.stderr)
        bdg = BasicDevPlanGenerator(llm)
        basic = await bdg.generate(
            design,
            task_grouping=task_grouping,
            task_group_size=task_group_size
        )
        
        # Generate detailed devplan
        print("[devussy] Generating detailed devplan...", file=sys.stderr)
        cm = ConcurrencyManager({'max_concurrent_requests': 3})
        ddg = DetailedDevPlanGenerator(llm, cm)
        detailed = await ddg.generate(
            basic,
            project_name,
            tech_stack=design.tech_stack,
            task_grouping=task_grouping,
            task_group_size=task_group_size
        )
        
        print("[devussy] Generation complete!", file=sys.stderr)
        
        # Output as JSON for bash processing
        print(detailed.to_json())
        
    except Exception as e:
        print(f"[devussy] Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

asyncio.run(main())
PYTHON_SCRIPT
    )
    
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Failed to generate devplan${NC}"
        echo "$devplan_json" | head -30
        return 1
    fi

    # Convert JSON to swarm devplan format
    devussy_json_to_markdown "$devplan_json" "$project_name" "$goal" "$task_grouping" > "$devplan_path"

    echo ""
    echo -e "${GREEN}Devplan generated: $devplan_path${NC}"

    # Show preview and options
    devussy_devplan_menu "$devplan_path" "$project_name" "$goal" "$workdir" "$task_grouping"
}

devussy_json_to_markdown() {
    local devplan_json="$1"
    local project_name="$2"
    local goal="$3"
    local task_grouping="$4"

    python3 - "$devplan_json" "$project_name" "$goal" "$task_grouping" <<'PY'
import json
import sys

devplan_json = sys.argv[1]
project_name = sys.argv[2]
goal = sys.argv[3]
task_grouping = sys.argv[4]

try:
    devplan = json.loads(devplan_json)
except json.JSONDecodeError:
    # If parsing fails, output a minimal devplan
    print(f"# DevPlan: {project_name}")
    print()
    print("## Goal")
    print(f"- {goal}")
    print()
    print("## Tasks")
    print()
    print("- [ ] Review and update this devplan")
    sys.exit(0)

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
        if phase.get('description'):
            print(f"{phase['description']}")
        print()
        
        task_groups = phase.get('task_groups', [])
        if task_groups:
            for group in task_groups:
                files_str = ', '.join(group.get('estimated_files', ['various'])) or 'various'
                print(f"**Group {group['group_number']}** [files: {files_str}]")
                print()
                for step in group.get('steps', []):
                    print(f"- [ ] {step['number']}: {step['description']}")
                    for detail in step.get('details', []):
                        print(f"  - {detail}")
                print()
        else:
            # Fallback to flat steps if no groups
            for step in phase.get('steps', []):
                print(f"- [ ] {step['number']}: {step['description']}")
                for detail in step.get('details', []):
                    print(f"  - {detail}")
            print()
else:
    # Flat mode: flatten all steps
    for phase in devplan.get('phases', []):
        print(f"### Phase {phase['number']}: {phase['title']}")
        print()
        for step in phase.get('steps', []):
            print(f"- [ ] {step['number']}: {step['description']}")
            for detail in step.get('details', []):
                print(f"  - {detail}")
        print()
PY
}

devussy_devplan_menu() {
    local devplan_path="$1"
    local project_name="$2"
    local goal="$3"
    local workdir="$4"
    local task_grouping="$5"

    while true; do
        echo ""
        echo -e "${CYAN}═════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}DevPlan Preview: $devplan_path${NC}"
        echo -e "${CYAN}═════════════════════════════════════════════════════════${NC}"
        cat "$devplan_path" | head -60
        if [ "$(wc -l < "$devplan_path")" -gt 60 ]; then
            echo -e "${YELLOW}... (truncated, use 'e' to view full)${NC}"
        fi
        echo -e "${CYAN}═════════════════════════════════════════════════════════${NC}"
        echo ""

        echo -e "${CYAN}Options:${NC}"
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
                local editor_cmd="${EDITOR:-}"
                if [ -n "$editor_cmd" ]; then
                    "$editor_cmd" "$devplan_path" || true
                else
                    echo -e "${RED}No EDITOR set. Set EDITOR environment variable.${NC}"
                fi
                ;;
            r|R)
                devussy_generate_devplan "$project_name" "$goal" "$devplan_path" "$workdir"
                return $?
                ;;
            s|S)
                # Offer model selection before starting swarm
                echo ""
                echo -n -e "  ${YELLOW}Select a swarm provider/model before starting? (Y/n): ${NC}"
                local _selm
                read_user_input _selm
                if [[ ! "${_selm:-}" =~ ^[Nn]$ ]]; then
                    if declare -f select_swarm_model >/dev/null 2>&1; then
                        select_swarm_model || true
                    fi
                fi
                
                if declare -f project_start_swarm_devplan >/dev/null 2>&1; then
                    project_start_swarm_devplan
                else
                    echo -e "${YELLOW}Swarm start function not available${NC}"
                fi
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

# Function to generate devplan for an existing project directory
devussy_generate_for_project() {
    local name="$1"
    local workdir="$2"
    local devplan_path="$3"

    echo ""
    echo -e "${CYAN}Describe the project goal (Ctrl+D when done):${NC}"
    local goal
    goal=$(read_multiline_input)
    if [ -z "$goal" ]; then
        goal="$name"
    fi

    devussy_generate_devplan "$name" "$goal" "$devplan_path" "$workdir"
}
