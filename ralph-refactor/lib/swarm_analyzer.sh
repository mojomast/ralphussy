#!/usr/bin/env bash

__SWARM_ANALYZER_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use the same JSON extraction logic as the main ralph runner.
# This also lets swarm use `opencode run --format json` consistently.
if ! command -v json_extract_text >/dev/null 2>&1; then
    # shellcheck source=ralph-refactor/lib/json.sh
    source "$__SWARM_ANALYZER_DIR__/json.sh"
fi

swarm_analyzer_parse_devplan_tasks() {
    local devplan_path="$1"
    local tasks_file="$2"

    if [ ! -f "$devplan_path" ]; then
        echo "Error: Devplan file not found: $devplan_path"
        return 1
    fi

    # Emit a single JSON array to tasks_file. We use python for robust string
    # escaping (task text may contain quotes) and to avoid depending on jq.
    python3 - "$devplan_path" >"$tasks_file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
tasks = []

with open(path, 'r', encoding='utf-8', errors='replace') as f:
    for idx, line in enumerate(f, start=1):
        # Match standard markdown checkboxes: - [ ] Task description
        # We only capture pending tasks (empty brackets)
        m = re.match(r'^\s*-\s*\[\s*\]\s+(.*)$', line)
        if not m:
            # Fallback: check for the old ## Task format just in case
            m = re.match(r'^\s*##\s+Task\s*(.*)\s*$', line)
            
        if not m:
            continue
            
        task = m.group(1).strip()
        if task:
            tasks.append({"task": task, "line": idx})

sys.stdout.write(json.dumps(tasks))
PY
}

swarm_analyzer_build_file_prediction_prompt() {
    local task_text="$1"
    local tree_output="$2"

    cat <<EOF
You are analyzing a coding task to predict which files will be modified.

Task: "$task_text"

Current codebase structure:
$tree_output

Rules:
1. Return only a JSON array of file patterns (no markdown, no explanation)
2. Use glob patterns for directories (e.g., "src/auth/*", "tests/**/*.ts")
3. Include documentation files if they will be created or modified
4. Include configuration files if they will be changed
5. Be specific: prefer "src/api/routes/*" over "src/*"

Examples of good responses:
- Single file: ["src/utils/helper.ts"]
- Directory: ["src/auth/*"]
- Multiple patterns: ["src/api/routes/*", "tests/api/*", "README.md"]

Return only the JSON array, nothing else:
EOF
}

swarm_analyzer_analyze_task_files() {
    local task_text="$1"
    local tree_file="$2"
    local llm_provider="${3:-${RALPH_PROVIDER:-}}"
    local llm_model="${4:-${RALPH_MODEL:-}}"

    # Default model if not specified via env var
    if [ -z "$llm_model" ]; then
        llm_model=""
    fi

    local prompt_file=$(mktemp)

    # NOTE: tree_file already points at a local file. The previous implementation
    # tried to "normalize" the path via sed and then overwrote the file in place.
    # That risks clobbering the tree output. Leave it untouched.

    swarm_analyzer_build_file_prediction_prompt "$task_text" "$(cat "$tree_file")" > "$prompt_file"

    local opencode_cmd="opencode run"
    local full_model=""
    
    if [ -n "$llm_model" ]; then
        if [[ "$llm_model" == *"/"* ]]; then
             full_model="$llm_model"
        elif [ -n "$llm_provider" ]; then
             full_model="${llm_provider}/${llm_model}"
        else
             full_model="$llm_model"
        fi
    fi

    if [ -n "$full_model" ]; then
        opencode_cmd="$opencode_cmd --model $full_model"
    fi

    local json_output
    json_output=$($opencode_cmd --format json "$(cat "$prompt_file")" 2>&1)
    local exit_code=$?

    rm -f "$prompt_file"

    if [ $exit_code -ne 0 ]; then
        echo "Error: opencode run failed (provider=${llm_provider:-default} model=${llm_model:-default})" 1>&2
        echo "$json_output" | head -c 200 1>&2
        return 1
    fi

    local text_output=""
    text_output=$(json_extract_text "$json_output") || text_output=""
    if [ -z "$text_output" ] || [ "$text_output" = "null" ]; then
        text_output="[]"
    fi

    echo "$text_output"
}

swarm_analyzer_extract_files_from_response() {
    local response="$1"

    local files
    files=$(echo "$response" | jq -r '.[]' 2>/dev/null || echo "")

    if [ -z "$files" ]; then
        echo "[]"
        return 0
    fi

    echo "$files"
}

swarm_analyzer_decompose_prompt() {
    local prompt="$1"
    local llm_provider="${2:-${RALPH_PROVIDER:-}}"
    local llm_model="${3:-${RALPH_MODEL:-}}"

    # Default model if not specified via env var
    if [ -z "$llm_model" ]; then
        llm_model=""
    fi

    local prompt_file=$(mktemp)

    cat <<EOF > "$prompt_file"
You are breaking down a development task into parallelizable subtasks.

Main task: "$prompt"

Rules:
1. Each subtask should be independently completable
2. Minimize file overlap between subtasks
3. Group related changes together
4. Prioritize foundation tasks first (they get lower priority numbers = run first)
5. Return ONLY a JSON array of objects (no markdown, no explanation)
6. Priority numbers must be integers starting from 1
7. Priority 1 runs first, then 2, etc.

Response format (JSON array only):
[
  {"task": "description", "priority": 1, "estimated_files": ["pattern1", "pattern2"]},
  {"task": "description", "priority": 2, "estimated_files": ["pattern3"]}
]

Lower priority numbers run before higher ones (1 runs before 2).
Tasks with the same priority can run in parallel.
EOF

    local opencode_cmd="opencode run"
    local full_model=""
    
    if [ -n "$llm_model" ]; then
        if [[ "$llm_model" == *"/"* ]]; then
             full_model="$llm_model"
        elif [ -n "$llm_provider" ]; then
             full_model="${llm_provider}/${llm_model}"
        else
             full_model="$llm_model"
        fi
    fi

    if [ -n "$full_model" ]; then
        opencode_cmd="$opencode_cmd --model $full_model"
    fi

    local json_output
    json_output=$($opencode_cmd --format json "$(cat "$prompt_file")" 2>&1)
    local exit_code=$?

    rm -f "$prompt_file"

    if [ $exit_code -ne 0 ]; then
        echo "Error: opencode run failed (provider=${llm_provider:-default} model=${llm_model:-default})" 1>&2
        echo "$json_output" | head -c 200 1>&2
        return 1
    fi

    local text_output=""
    text_output=$(json_extract_text "$json_output") || text_output=""
    if [ -z "$text_output" ] || [ "$text_output" = "null" ]; then
        text_output="[]"
    fi

    echo "$text_output"
}

swarm_analyzer_validate_file_patterns() {
    local patterns_file="$1"
    local tree_file="$2"

    local patterns
    patterns=$(cat "$patterns_file" | jq -r '.[]' 2>/dev/null || echo "")

    if [ -z "$patterns" ]; then
        echo "Error: No patterns provided"
        return 1
    fi

    echo "$patterns"
}

swarm_analyzer_generate_tree_output() {
    local tree_file="$1"
    local max_depth="${2:-3}"

    find . -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/.git/*' \
        | head -n 100 \
        | while read -r file; do
            local rel_path="${file#./}"
            local depth=$(echo "$rel_path" | tr -cd '/' | wc -c)
            if [ "$depth" -le "$max_depth" ]; then
                echo "$rel_path"
            fi
        done > "$tree_file"

    echo "Generated tree output"
}
