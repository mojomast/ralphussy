# Swarm E2E Test Implementation Handoff

## Objective

Create a comprehensive end-to-end test for the ralph swarm system that:
1. Generates a devplan using `zai-coding-plan/glm-4.7`
2. Launches a swarm with 4 simultaneous workers
3. Runs to completion
4. Verifies artifacts are properly merged and generated in `/projects` folder
5. Tests a simple project: **rudimentary IRC client in Python AND TypeScript**

---

## Test Requirements

### Test Project: Dual IRC Client

The test should create a simple IRC client implemented in **both Python and TypeScript**. This tests:
- Multi-language handling
- File isolation between workers
- Artifact merging from different workers

**Project Structure (expected output):**
```
~/projects/test-irc-client/
├── python/
│   ├── irc_client.py      # Basic IRC connection and messaging
│   ├── config.py          # Configuration handling
│   └── tests/
│       └── test_client.py
├── typescript/
│   ├── src/
│   │   ├── client.ts      # Basic IRC connection
│   │   ├── config.ts      # Configuration
│   │   └── index.ts       # Entry point
│   ├── package.json
│   └── tsconfig.json
├── README.md
└── devplan.md
```

### Configuration

```bash
# Required environment variables
export RALPH_LLM_PROVIDER="zai-coding-plan"
export RALPH_LLM_MODEL="glm-4.7"
export SWARM_PROJECT_NAME="test-irc-client"
export SWARM_PROJECTS_BASE="$HOME/projects"
export SWARM_AUTO_MERGE="true"
export SWARM_COLLECT_ARTIFACTS="true"

# Worker configuration
WORKER_COUNT=4
TIMEOUT_SECONDS=1800  # 30 minutes for safety
```

---

## Test Implementation Steps

### Step 1: Create Test Devplan

Create file: `ralph-refactor/tests/fixtures/test_irc_devplan.md`

```markdown
# Simple IRC Client - Development Plan

Build a basic IRC client in both Python and TypeScript for testing swarm coordination.

## Python Implementation

- [ ] Create Python IRC client with socket connection to IRC server
- [ ] Add Python configuration module for server/channel/nick settings
- [ ] Write basic unit tests for the Python IRC client

## TypeScript Implementation

- [ ] Create TypeScript IRC client using net module for socket connections
- [ ] Add TypeScript configuration module with type definitions
- [ ] Create package.json and tsconfig.json for the TypeScript project

## Documentation

- [ ] Create README.md with usage instructions for both implementations
```

### Step 2: Create Test Script

Create file: `ralph-refactor/tests/test_swarm_e2e.sh`

The test script should:

```bash
#!/usr/bin/env bash
# End-to-end swarm test with real LLM execution

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_SWARM="$TEST_DIR/../ralph-swarm"
FIXTURES_DIR="$TEST_DIR/fixtures"
TEST_PROJECT_NAME="test-irc-client-$(date +%s)"
PROJECTS_BASE="${SWARM_PROJECTS_BASE:-$HOME/projects}"

# Configuration
export RALPH_DIR="${RALPH_DIR:-$HOME/projects/.ralph}"
export RALPH_LLM_PROVIDER="zai-coding-plan"
export RALPH_LLM_MODEL="glm-4.7"
export SWARM_PROJECT_NAME="$TEST_PROJECT_NAME"
export SWARM_PROJECTS_BASE="$PROJECTS_BASE"
export SWARM_AUTO_MERGE="true"
export SWARM_COLLECT_ARTIFACTS="true"
export SWARM_OUTPUT_MODE="live"  # For visibility during test

WORKER_COUNT=4
TIMEOUT_SECONDS=1800

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

# Test functions to implement...
```

### Step 3: Test Function Specifications

Implement these test functions in the script:

#### `test_devplan_generation()`
```bash
test_devplan_generation() {
    echo "=== Test: Devplan Generation ==="
    
    local devplan_path="$FIXTURES_DIR/test_irc_devplan.md"
    
    # Verify devplan exists
    if [ ! -f "$devplan_path" ]; then
        echo "FAIL: Test devplan not found: $devplan_path"
        return 1
    fi
    
    # Count tasks in devplan
    local task_count
    task_count=$(grep -c '^\s*- \[ \]' "$devplan_path" || echo "0")
    
    if [ "$task_count" -lt 6 ]; then
        echo "FAIL: Expected at least 6 tasks, found $task_count"
        return 1
    fi
    
    echo "PASS: Devplan has $task_count tasks"
    return 0
}
```

#### `test_swarm_execution()`
```bash
test_swarm_execution() {
    echo "=== Test: Swarm Execution ==="
    
    local devplan_path="$FIXTURES_DIR/test_irc_devplan.md"
    local start_time=$(date +%s)
    
    # Run swarm
    echo "Starting swarm with $WORKER_COUNT workers..."
    echo "Provider: $RALPH_LLM_PROVIDER"
    echo "Model: $RALPH_LLM_MODEL"
    echo "Project: $TEST_PROJECT_NAME"
    echo ""
    
    if ! "$RALPH_SWARM" \
        --devplan "$devplan_path" \
        --workers "$WORKER_COUNT" \
        --timeout "$TIMEOUT_SECONDS" \
        --project "$TEST_PROJECT_NAME" \
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
```

#### `test_artifacts_exist()`
```bash
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
    file_count=$(find "$project_dir" -type f -not -path "*/.git/*" | wc -l)
    
    if [ "$file_count" -lt 3 ]; then
        echo "FAIL: Too few files created ($file_count)"
        return 1
    fi
    
    echo "PASS: Found $file_count files in project"
    return 0
}
```

#### `test_source_file_cleanliness()`
```bash
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
```

#### `test_database_state()`
```bash
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
```

#### `test_git_state()`
```bash
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
```

### Step 4: Main Test Runner

```bash
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
```

---

## Additional Tests to Add

### Unit Tests for New Sanitization Functions

Create: `ralph-refactor/tests/test_sanitize.sh`

```bash
#!/usr/bin/env bash

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../lib/swarm_artifacts.sh"

test_sanitize_go_file() {
    echo "Testing Go file sanitization..."
    
    local temp_file=$(mktemp --suffix=.go)
    
    # Create file with problematic content
    cat > "$temp_file" << 'EOF'
package main

import "fmt"

<!-- Progress checkpoint -->
// SWARM: Worker 3 completed this section
func main() {
    // PROGRESS: Task 5 done
    fmt.Println("Hello")
}
EOF
    
    swarm_sanitize_source_file "$temp_file"
    
    # Check HTML comments removed
    if grep -q '<!--' "$temp_file"; then
        echo "FAIL: HTML comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check SWARM annotation removed
    if grep -qi 'SWARM:' "$temp_file"; then
        echo "FAIL: SWARM annotation not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check file still has valid Go content
    if ! grep -q 'func main()' "$temp_file"; then
        echo "FAIL: Valid content was removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    echo "PASS: Go file sanitization"
    return 0
}

test_sanitize_python_file() {
    echo "Testing Python file sanitization..."
    
    local temp_file=$(mktemp --suffix=.py)
    
    cat > "$temp_file" << 'EOF'
#!/usr/bin/env python3

# PROGRESS: Starting implementation
def hello():
    # SWARM: Worker 2
    print("Hello")

<!-- This should not be here -->
hello()
EOF
    
    swarm_sanitize_source_file "$temp_file"
    
    if grep -q '<!--' "$temp_file"; then
        echo "FAIL: HTML comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '# PROGRESS:' "$temp_file"; then
        echo "FAIL: Progress comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Valid content preserved
    if ! grep -q 'def hello():' "$temp_file"; then
        echo "FAIL: Valid content removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    echo "PASS: Python file sanitization"
    return 0
}

test_sanitize_detects_merge_conflicts() {
    echo "Testing merge conflict detection..."
    
    local temp_file=$(mktemp --suffix=.ts)
    
    cat > "$temp_file" << 'EOF'
function hello() {
<<<<<<< HEAD
    console.log("version 1");
=======
    console.log("version 2");
>>>>>>> feature
}
EOF
    
    # Should return non-zero (warning, needs manual resolution)
    if swarm_sanitize_source_file "$temp_file"; then
        # Function returns success but should have warned
        if grep -q '<<<<<<<' "$temp_file"; then
            echo "PASS: Merge conflicts preserved (needs manual resolution)"
        else
            echo "FAIL: Merge conflicts incorrectly auto-removed"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    rm -f "$temp_file"
    return 0
}

# Run tests
test_sanitize_go_file
test_sanitize_python_file
test_sanitize_detects_merge_conflicts
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `ralph-refactor/tests/fixtures/test_irc_devplan.md` | Test devplan for IRC client |
| `ralph-refactor/tests/test_swarm_e2e.sh` | Main E2E test script |
| `ralph-refactor/tests/test_sanitize.sh` | Sanitization unit tests |

---

## Verification Commands

After implementing, run:

```bash
# Full E2E test
cd ~/projects/ralphussy
./ralph-refactor/tests/test_swarm_e2e.sh

# Just sanitization tests
./ralph-refactor/tests/test_sanitize.sh

# Check test project manually
ls -la ~/projects/test-irc-client-*
cat ~/projects/test-irc-client-*/SWARM_SUMMARY.md
```

---

## Expected Test Output

```
==========================================
Ralph Swarm End-to-End Test Suite
==========================================

Configuration:
  Provider: zai-coding-plan
  Model: glm-4.7
  Workers: 4
  Timeout: 1800s
  Project: test-irc-client-1737849600

=== Test: Devplan Generation ===
PASS: Devplan has 7 tasks

=== Test: Swarm Execution ===
Starting swarm with 4 workers...
Provider: zai-coding-plan
Model: glm-4.7
Project: test-irc-client-1737849600

[... swarm output ...]

PASS: Swarm completed in 245s

=== Test: Artifact Verification ===
Project directory: /home/user/projects/test-irc-client-1737849600
Contents:
python/irc_client.py
python/config.py
typescript/src/client.ts
typescript/package.json
README.md
PASS: Found 8 files in project

=== Test: Source File Cleanliness ===
PASS: No HTML comments in source files
PASS: No merge conflict markers
PASS: No progress annotations

=== Test: Database State ===
Latest run: 20260126_120000
PASS: Run status is 'completed'
Task Statistics:
  completed: 7
PASS: 7 tasks completed successfully

=== Test: Git State ===
PASS: No uncommitted changes
Commit count: 3
Recent commits:
abc1234 Merge swarm run 20260126_120000 (4 workers, 8 files)
def5678 Task 3: Create TypeScript IRC client
ghi9012 Task 1: Create Python IRC client

==========================================
Test Results: 0 failures
==========================================
```

---

## Notes for Implementation

1. **Timeout Handling**: The test has a 30-minute timeout. Real LLM calls can be slow; adjust if needed.

2. **Cleanup**: The test preserves the project directory for inspection. Uncomment the cleanup line in `cleanup()` for CI environments.

3. **Flakiness**: LLM outputs are non-deterministic. Tests check for *reasonable* outputs, not exact matches.

4. **Model Access**: Ensure you have API access to `zai-coding-plan/glm-4.7`. If not, update the provider/model.

5. **Cost**: This test makes real LLM calls. Expect ~$1-5 in API costs per run.

6. **Parallelism**: The 4-worker setup tests concurrent execution. Reduce to 2 if hitting rate limits.

---

## Related Changes Already Made

The following fixes were already implemented in this session:

1. **`swarm_worker.sh:475-508`**: Added explicit instructions to workers about source file cleanliness

2. **`swarm_artifacts.sh:1-110`**: Added `swarm_sanitize_source_file()` and `swarm_sanitize_directory()` functions

3. **`swarm_artifacts.sh:351-365`**: Added sanitization call in `swarm_merge_to_project()`

4. **`swarm_artifacts.sh:800-815`**: Added sanitization call in `swarm_extract_merged_artifacts()`

5. **`SWARM_AGENT_RULES.md`**: Created reference document for source file cleanliness rules
