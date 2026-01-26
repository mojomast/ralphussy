#!/usr/bin/env bash
# End-to-end swarm test with real LLM execution
# This test:
# 1. Generates a fresh devplan using opencode (zai-coding-plan/glm-4.7)
# 2. Launches a swarm with 4 simultaneous workers
# 3. Runs to completion
# 4. Verifies artifacts are properly merged and generated in /projects folder
# 5. Tests a simple project: rudimentary IRC client in Python AND TypeScript

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_SWARM="$TEST_DIR/../ralph-swarm"
RALPH_LIVE="$TEST_DIR/../ralph-live"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEST_PROJECT_NAME="test-irc-client-$(date +%s)"
PROJECTS_BASE="${SWARM_PROJECTS_BASE:-$HOME/projects}"

# Configuration
export RALPH_DIR="${RALPH_DIR:-$HOME/projects/.ralph}"
export RALPH_LLM_PROVIDER="${RALPH_LLM_PROVIDER:-zai-coding-plan}"
export RALPH_LLM_MODEL="${RALPH_LLM_MODEL:-glm-4.7}"
# Ensure a sane default base branch for new git repos created during tests
export SWARM_BASE_BRANCH="${SWARM_BASE_BRANCH:-main}"
export SWARM_PROJECT_NAME="$TEST_PROJECT_NAME"
export SWARM_PROJECTS_BASE="$PROJECTS_BASE"
export SWARM_AUTO_MERGE="true"
export SWARM_COLLECT_ARTIFACTS="true"
export SWARM_OUTPUT_MODE="live"  # For visibility during test

WORKER_COUNT=4
TIMEOUT_SECONDS=1800
DEVPLAN_TIMEOUT=120  # 2 minutes for devplan generation

# Project description for devplan generation
PROJECT_DESCRIPTION="Create a minimal Hello World project with a tiny Python program and a tiny TypeScript program.

Requirements:
- Python: create `python/hello.py` that prints 'Hello, world!' and a short README with run instructions.
- TypeScript: create `typescript/src/index.ts` that prints 'Hello, world!' and a minimal `package.json` with a `start` script.

Keep everything minimal and easy to review. Each task should be trivial (1-10 minutes).
"

# Cleanup function
cleanup() {
    local exit_code=$?
    echo ""
    echo "=== Cleanup ==="
    
    # Stop any running workers
    "$RALPH_SWARM" --emergency-stop 2>/dev/null || true
    
    # Optionally remove test project (comment out to inspect)
    # rm -rf "$PROJECTS_BASE/$TEST_PROJECT_NAME"
    
    echo "Test project preserved at: $PROJECTS_BASE/$TEST_PROJECT_NAME"
    exit $exit_code
}
trap cleanup EXIT

# Generate devplan using opencode
generate_devplan_with_opencode() {
    local output_path="$1"
    local title="$2"
    local description="$3"
    
    echo "Generating DevPlan with opencode..."
    echo "Provider: $RALPH_LLM_PROVIDER"
    echo "Model: $RALPH_LLM_MODEL"
    echo ""
    
    local prompt
    prompt=$(cat <<EOF
You are a DevPlan generator. Write markdown output ONLY - no tools, no code blocks, no explanations.

Project name: $title

Project goal/requirements:
$description

REQUIREMENTS:
1. Output ONLY pure markdown - start with "# DevPlan:" header
2. Use these sections in order: Goal, Constraints, Tasks
3. Under Tasks, use format: "- [ ] task description"
4. Each task on a NEW LINE with "- [ ] " prefix
    5. Create 3-6 tasks suitable for parallel swarm agents
    6. Organize: setup -> implementation -> testing -> docs
    7. Each task completable in 1-10 minutes
8. Be specific: "Create Python IRC client with socket connection" not "Work on Python"
9. Group related tasks with blank lines

OUTPUT THIS EXACT FORMAT:

# DevPlan: $title

## Goal
[One-sentence goal]

## Constraints
[Key constraints]

## Tasks
- [ ] Setup task 1
- [ ] Setup task 2

- [ ] Core feature task 1
- [ ] Core feature task 2

- [ ] Testing task 1
- [ ] Testing task 2

DO NOT use tools, code blocks, or markdown fences. Just plain markdown text.
EOF
)

    local opencode_cmd="opencode run --model $RALPH_LLM_PROVIDER/$RALPH_LLM_MODEL"
    
    local json_output=""
    if ! json_output=$(timeout "$DEVPLAN_TIMEOUT" $opencode_cmd --format json "$prompt" 2>&1); then
        local exit_code=$?
        # Attempt to persist full opencode output for debugging
        local outdir
        outdir=$(dirname "$output_path" 2>/dev/null || echo "${PROJECTS_BASE:-$HOME/projects}/$TEST_PROJECT_NAME")
        mkdir -p "$outdir" 2>/dev/null || true
        if [ -n "$json_output" ]; then
            echo "$json_output" > "$outdir/.devplan_opencode_error.json" 2>/dev/null || true
            echo "Wrote opencode debug output to: $outdir/.devplan_opencode_error.json"
        fi

        if [ $exit_code -eq 124 ]; then
            echo "ERROR: DevPlan generation timed out after ${DEVPLAN_TIMEOUT}s"
        else
            echo "ERROR: DevPlan generation failed (exit code: $exit_code)"
        fi
        return 1
    fi
    
    # Extract text from NDJSON output (multiple JSON lines)
    # opencode --format json outputs newline-delimited JSON, with text parts having type="text"
    local text_output=""
    if command -v jq >/dev/null 2>&1; then
        # Extract all text parts from NDJSON and concatenate them
        text_output=$(echo "$json_output" | jq -r 'select(.type == "text") | .part.text // empty' 2>/dev/null | tr -d '\0' || echo "")
    fi
    
    # Fallback: try to extract text from type=text JSON lines
    if [ -z "$text_output" ]; then
        text_output=$(echo "$json_output" | grep '"type":"text"' | grep -oP '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | head -1 || echo "")
        # Unescape newlines if present
        if [ -n "$text_output" ]; then
            text_output=$(printf '%b' "$text_output")
        fi
    fi
    
    # Last resort: use raw output if it looks like markdown (non-JSON mode)
    if [ -z "$text_output" ] && echo "$json_output" | grep -q "^# DevPlan"; then
        text_output="$json_output"
    fi
    
    if [ -z "$text_output" ]; then
        # Save full opencode output for debugging
        local outdir
        outdir=$(dirname "$output_path" 2>/dev/null || echo "${PROJECTS_BASE:-$HOME/projects}/$TEST_PROJECT_NAME")
        mkdir -p "$outdir" 2>/dev/null || true
        if [ -n "$json_output" ]; then
            echo "$json_output" > "$outdir/.devplan_opencode_debug.json" 2>/dev/null || true
            echo "ERROR: DevPlan generation returned empty or unparseable output — full opencode JSON saved to: $outdir/.devplan_opencode_debug.json"
        else
            echo "ERROR: DevPlan generation returned empty or unparseable output and no raw JSON was captured"
        fi
        return 1
    fi
    
    # Sanitize devplan text to avoid prompt-injection tokens or explicit execution directives
    # Remove any lines that contain obvious agent instructions or XML/HTML-like tags
    local sanitized
    sanitized=$(printf '%s\n' "$text_output" | sed -E \
        -e '/CRITICAL INSTRUCTION/Id' \
        -e '/MUST end your response/Id' \
        -e '/You are a swarm worker/Id' \
        -e '/<[^>]+>/d' \
        -e '/END YOUR RESPONSE/Id')

    # Trim leading/trailing blank lines
    sanitized=$(printf '%s\n' "$sanitized" | sed -E '1{/^$/d};:a;/^$/{$d;};N;ba' || true)

    # Write sanitized devplan to file
    printf '%s\n' "$sanitized" > "$output_path"
    
    echo "DevPlan generated successfully: $output_path"
    return 0
}

# Test functions

test_devplan_generation() {
    echo "=== Test: Devplan Generation ==="
    
    local project_dir="$PROJECTS_BASE/$TEST_PROJECT_NAME"
    mkdir -p "$project_dir"
    
    local devplan_path="$project_dir/devplan.md"
    
    # Generate fresh devplan using opencode
    if ! generate_devplan_with_opencode "$devplan_path" "Simple IRC Client" "$PROJECT_DESCRIPTION"; then
        echo "FAIL: DevPlan generation failed"
        return 1
    fi
    
    # Verify devplan was created
    if [ ! -f "$devplan_path" ]; then
        echo "FAIL: DevPlan file not created: $devplan_path"
        return 1
    fi
    
    # Count tasks in devplan
    local task_count
    task_count=$(grep -c '^\s*- \[ \]' "$devplan_path" || echo "0")
    
    if [ "$task_count" -lt 2 ]; then
        echo "FAIL: Expected at least 2 tasks, found $task_count"
        echo "DevPlan contents:"
        cat "$devplan_path"
        return 1
    fi
    
    echo ""
    echo "Generated DevPlan ($task_count tasks):"
    echo "----------------------------------------"
    cat "$devplan_path"
    echo "----------------------------------------"
    echo ""
    
    echo "PASS: DevPlan generated with $task_count tasks"
    
    # Store devplan path for subsequent tests
    GENERATED_DEVPLAN_PATH="$devplan_path"
    return 0
}

test_swarm_execution() {
    echo "=== Test: Swarm Execution ==="
    
    if [ -z "${GENERATED_DEVPLAN_PATH:-}" ]; then
        echo "FAIL: No devplan path set (run test_devplan_generation first)"
        return 1
    fi
    
    local start_time=$(date +%s)
    
    # Run swarm
    echo "Starting swarm with $WORKER_COUNT workers..."
    echo "Provider: $RALPH_LLM_PROVIDER"
    echo "Model: $RALPH_LLM_MODEL"
    echo "Project: $TEST_PROJECT_NAME"
    echo "DevPlan: $GENERATED_DEVPLAN_PATH"
    echo ""
    
    if ! "$RALPH_SWARM" \
        --devplan "$GENERATED_DEVPLAN_PATH" \
        --workers "$WORKER_COUNT" \
        --timeout "$TIMEOUT_SECONDS" \
        --provider "$RALPH_LLM_PROVIDER" \
        --model "$RALPH_LLM_MODEL"; then
        echo "FAIL: Swarm execution failed"
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "PASS: Swarm completed in ${duration}s"
    return 0
}

test_artifacts_exist() {
    echo "=== Test: Artifact Verification ==="
    
    local project_dir="$PROJECTS_BASE/$TEST_PROJECT_NAME"
    local failures=0
    
    # Check project directory exists
    if [ ! -d "$project_dir" ]; then
        echo "FAIL: Project directory not created: $project_dir"
        return 1
    fi
    
    echo "Project directory: $project_dir"
    echo "Contents:"
    find "$project_dir" -type f -not -path "*/.git/*" | head -30
    echo ""
    
    # Check for expected Python files
    local python_files=(
        "python/irc_client.py"
        "python/config.py"
    )
    
    for file in "${python_files[@]}"; do
        if [ -f "$project_dir/$file" ]; then
            echo "PASS: Found $file"
        else
            echo "WARN: Missing $file (may have different structure)"
        fi
    done
    
    # Check for expected TypeScript files
    local ts_files=(
        "typescript/src/client.ts"
        "typescript/package.json"
    )
    
    for file in "${ts_files[@]}"; do
        if [ -f "$project_dir/$file" ]; then
            echo "PASS: Found $file"
        else
            echo "WARN: Missing $file (may have different structure)"
        fi
    done
    
    # Check for at least SOME files
    local file_count
    file_count=$(find "$project_dir" -type f -not -path "*/.git/*" -not -name "devplan.md" | wc -l)
    
    if [ "$file_count" -lt 3 ]; then
        echo "FAIL: Too few files created ($file_count)"
        return 1
    fi
    
    echo "PASS: Found $file_count files in project"
    return 0
}

test_source_file_cleanliness() {
    echo "=== Test: Source File Cleanliness ==="
    
    local project_dir="$PROJECTS_BASE/$TEST_PROJECT_NAME"
    local failures=0
    
    # Check for HTML comments in Python/TypeScript files
    if grep -r '<!--' "$project_dir" --include="*.py" --include="*.ts" 2>/dev/null; then
        echo "FAIL: Found HTML comments in source files"
        failures=$((failures + 1))
    else
        echo "PASS: No HTML comments in source files"
    fi
    
    # Check for merge conflict markers
    if grep -rE '^<<<<<<<|^=======|^>>>>>>>' "$project_dir" --include="*.py" --include="*.ts" 2>/dev/null; then
        echo "FAIL: Found merge conflict markers"
        failures=$((failures + 1))
    else
        echo "PASS: No merge conflict markers"
    fi
    
    # Check for progress annotations
    if grep -riE '// *(PROGRESS|SWARM|Worker [0-9]+)' "$project_dir" --include="*.py" --include="*.ts" 2>/dev/null; then
        echo "FAIL: Found progress annotations in source files"
        failures=$((failures + 1))
    else
        echo "PASS: No progress annotations"
    fi
    
    return $failures
}

test_database_state() {
    echo "=== Test: Database State ==="
    
    local db_path="$RALPH_DIR/swarm.db"
    
    if [ ! -f "$db_path" ]; then
        echo "FAIL: Database not found: $db_path"
        return 1
    fi
    
    # Get latest run
    local run_id
    run_id=$(sqlite3 "$db_path" "SELECT run_id FROM swarm_runs ORDER BY id DESC LIMIT 1;")
    
    if [ -z "$run_id" ]; then
        echo "FAIL: No run found in database"
        return 1
    fi
    
    echo "Latest run: $run_id"
    
    # Check run status
    local run_status
    run_status=$(sqlite3 "$db_path" "SELECT status FROM swarm_runs WHERE run_id = '$run_id';")
    
    if [ "$run_status" != "completed" ]; then
        echo "WARN: Run status is '$run_status' (expected 'completed')"
    else
        echo "PASS: Run status is 'completed'"
    fi
    
    # Check task stats
    echo ""
    echo "Task Statistics:"
    sqlite3 "$db_path" "SELECT status, COUNT(*) FROM tasks WHERE run_id = '$run_id' GROUP BY status;" | while IFS='|' read -r status count; do
        echo "  $status: $count"
    done
    
    # Verify no tasks are stuck in_progress
    local stuck_count
    stuck_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'in_progress';")
    
    if [ "$stuck_count" -gt 0 ]; then
        echo "FAIL: $stuck_count tasks stuck in 'in_progress'"
        return 1
    fi
    
    # Check completed count
    local completed_count
    completed_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM tasks WHERE run_id = '$run_id' AND status = 'completed';")
    
    if [ "$completed_count" -lt 3 ]; then
        echo "FAIL: Only $completed_count tasks completed (expected at least 3)"
        return 1
    fi
    
    echo "PASS: $completed_count tasks completed successfully"
    return 0
}

test_git_state() {
    echo "=== Test: Git State ==="
    
    local project_dir="$PROJECTS_BASE/$TEST_PROJECT_NAME"
    
    if [ ! -d "$project_dir/.git" ]; then
        echo "WARN: Project is not a git repository"
        return 0  # Not a failure, some modes don't use git
    fi
    
    cd "$project_dir"
    
    # Check for uncommitted changes
    if git status --porcelain | grep -q .; then
        echo "WARN: Uncommitted changes present"
        git status --short | head -10
    else
        echo "PASS: No uncommitted changes"
    fi
    
    # Check commit history
    local commit_count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    
    echo "Commit count: $commit_count"
    
    if [ "$commit_count" -gt 0 ]; then
        echo ""
        echo "Recent commits:"
        git log --oneline -5
    fi
    
    # Check for leftover swarm branches
    local swarm_branches
    swarm_branches=$(git branch -a 2>/dev/null | grep -c "swarm/" || echo "0")
    
    if [ "$swarm_branches" -gt 0 ]; then
        echo "INFO: $swarm_branches swarm branches remain (normal if not auto-cleaned)"
    fi
    
    cd - > /dev/null
    return 0
}

run_all_tests() {
    echo "=========================================="
    echo "Ralph Swarm End-to-End Test Suite"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Provider: $RALPH_LLM_PROVIDER"
    echo "  Model: $RALPH_LLM_MODEL"
    echo "  Workers: $WORKER_COUNT"
    echo "  Timeout: ${TIMEOUT_SECONDS}s"
    echo "  Project: $TEST_PROJECT_NAME"
    echo "  Projects Base: $PROJECTS_BASE"
    echo ""
    
    local failures=0
    
    # Pre-flight checks
    if ! command -v opencode &>/dev/null; then
        echo "FATAL: opencode not found in PATH"
        exit 1
    fi
    
    if ! command -v sqlite3 &>/dev/null; then
        echo "FATAL: sqlite3 not found in PATH"
        exit 1
    fi
    
    # Run tests
    if ! test_devplan_generation; then
        failures=$((failures + 1))
        echo "FATAL: DevPlan generation failed, cannot continue"
        return $failures
    fi
    
    echo ""
    
    if ! test_swarm_execution; then
        failures=$((failures + 1))
        echo "FATAL: Swarm execution failed, skipping remaining tests"
        return $failures
    fi
    
    echo ""
    
    if ! test_artifacts_exist; then
        failures=$((failures + 1))
    fi
    
    echo ""
    
    if ! test_source_file_cleanliness; then
        failures=$((failures + 1))
    fi
    
    echo ""
    
    if ! test_database_state; then
        failures=$((failures + 1))
    fi
    
    echo ""
    
    if ! test_git_state; then
        failures=$((failures + 1))
    fi
    
    echo ""
    echo "=========================================="
    echo "Test Results: $failures failures"
    echo "=========================================="
    
    return $failures
}

# Entry point
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_all_tests
    exit $?
fi
