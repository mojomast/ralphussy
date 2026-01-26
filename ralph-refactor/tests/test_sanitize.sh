#!/usr/bin/env bash
# Unit tests for source file sanitization functions

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$TEST_DIR/../lib"

# Source the library
source "$LIB_DIR/swarm_artifacts.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to report test results
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
}

# Test: Go file sanitization
test_sanitize_go_file() {
    echo "Testing Go file sanitization..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.go)
    
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
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    # Check HTML comments removed
    if grep -q '<!--' "$temp_file"; then
        fail "Go file sanitization - HTML comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check SWARM annotation removed
    if grep -qi 'SWARM:' "$temp_file"; then
        fail "Go file sanitization - SWARM annotation not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check PROGRESS annotation removed
    if grep -qi 'PROGRESS:' "$temp_file"; then
        fail "Go file sanitization - PROGRESS annotation not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check file still has valid Go content
    if ! grep -q 'func main()' "$temp_file"; then
        fail "Go file sanitization - Valid content was removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "Go file sanitization"
    return 0
}

# Test: Python file sanitization
test_sanitize_python_file() {
    echo "Testing Python file sanitization..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.py)
    
    cat > "$temp_file" << 'EOF'
#!/usr/bin/env python3

# PROGRESS: Starting implementation
def hello():
    # SWARM: Worker 2
    print("Hello")

<!-- This should not be here -->
hello()
EOF
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    if grep -q '<!--' "$temp_file"; then
        fail "Python file sanitization - HTML comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '# PROGRESS:' "$temp_file"; then
        fail "Python file sanitization - Progress comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '# SWARM:' "$temp_file"; then
        fail "Python file sanitization - SWARM comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Valid content preserved
    if ! grep -q 'def hello():' "$temp_file"; then
        fail "Python file sanitization - Valid content removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "Python file sanitization"
    return 0
}

# Test: TypeScript file sanitization
test_sanitize_typescript_file() {
    echo "Testing TypeScript file sanitization..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.ts)
    
    cat > "$temp_file" << 'EOF'
// TypeScript IRC client
// PROGRESS: Starting implementation
// SWARM: Worker 1 working on this
// CHECKPOINT: Connection established

interface Config {
    server: string;
    port: number;
}

<!-- HTML comment should be removed -->

function connect(config: Config): void {
    // Worker 3 completed this
    console.log("Connecting...");
}

export { connect };
EOF
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    if grep -q '<!--' "$temp_file"; then
        fail "TypeScript file sanitization - HTML comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '// PROGRESS:' "$temp_file"; then
        fail "TypeScript file sanitization - PROGRESS comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '// SWARM:' "$temp_file"; then
        fail "TypeScript file sanitization - SWARM comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qi '// CHECKPOINT:' "$temp_file"; then
        fail "TypeScript file sanitization - CHECKPOINT comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    # Valid content preserved
    if ! grep -q 'interface Config' "$temp_file"; then
        fail "TypeScript file sanitization - Valid content removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "TypeScript file sanitization"
    return 0
}

# Test: Merge conflict detection
test_sanitize_detects_merge_conflicts() {
    echo "Testing merge conflict detection..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.ts)
    
    cat > "$temp_file" << 'EOF'
function hello() {
<<<<<<< HEAD
    console.log("version 1");
=======
    console.log("version 2");
>>>>>>> feature
}
EOF
    
    # Should return non-zero (conflict detected)
    if swarm_sanitize_source_file "$temp_file" 2>/dev/null; then
        # Function returned success - check if conflicts are still there
        if grep -q '<<<<<<<' "$temp_file"; then
            # Good - conflicts are preserved (not auto-removed)
            rm -f "$temp_file"
            pass "Merge conflict detection - conflicts preserved for manual resolution"
            return 0
        else
            fail "Merge conflict detection - conflicts incorrectly auto-removed"
            rm -f "$temp_file"
            return 1
        fi
    else
        # Function returned error - this is expected behavior
        if grep -q '<<<<<<<' "$temp_file"; then
            rm -f "$temp_file"
            pass "Merge conflict detection - returns error and preserves conflicts"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    fail "Merge conflict detection - unexpected behavior"
    return 1
}

# Test: Non-source files are ignored
test_sanitize_ignores_non_source() {
    echo "Testing non-source file handling..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.md)
    
    cat > "$temp_file" << 'EOF'
# README

<!-- This is a valid markdown comment -->

## PROGRESS: Implementation complete
EOF
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    # Markdown files should NOT be sanitized (comments are valid)
    if ! grep -q '<!--' "$temp_file"; then
        fail "Non-source file handling - markdown comment was incorrectly removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "Non-source file handling"
    return 0
}

# Test: Empty file handling
test_sanitize_empty_file() {
    echo "Testing empty file handling..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.py)
    
    # Create empty file
    > "$temp_file"
    
    # Should not error on empty file
    if swarm_sanitize_source_file "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        pass "Empty file handling"
        return 0
    else
        fail "Empty file handling - errored on empty file"
        rm -f "$temp_file"
        return 1
    fi
}

# Test: Directory sanitization
test_sanitize_directory() {
    echo "Testing directory sanitization..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create test files
    cat > "$temp_dir/clean.py" << 'EOF'
def hello():
    print("Hello")
EOF
    
    cat > "$temp_dir/dirty.py" << 'EOF'
# PROGRESS: Starting
def world():
    # SWARM: Worker 1
    print("World")
EOF
    
    mkdir -p "$temp_dir/subdir"
    cat > "$temp_dir/subdir/nested.ts" << 'EOF'
// CHECKPOINT: Done
export function test() {}
EOF
    
    swarm_sanitize_directory "$temp_dir" 2>/dev/null
    
    # Check dirty.py was sanitized
    if grep -qi 'PROGRESS:' "$temp_dir/dirty.py" 2>/dev/null; then
        fail "Directory sanitization - dirty.py not sanitized"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check nested file was sanitized
    if grep -qi 'CHECKPOINT:' "$temp_dir/subdir/nested.ts" 2>/dev/null; then
        fail "Directory sanitization - nested.ts not sanitized"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check clean file still has content
    if ! grep -q 'def hello():' "$temp_dir/clean.py" 2>/dev/null; then
        fail "Directory sanitization - clean.py was corrupted"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    pass "Directory sanitization"
    return 0
}

# Test: Jinja comment removal
test_sanitize_jinja_comments() {
    echo "Testing Jinja comment removal..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.py)
    
    cat > "$temp_file" << 'EOF'
def render():
    {# This is a Jinja comment #}
    return "Hello"
EOF
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    if grep -q '{#' "$temp_file"; then
        fail "Jinja comment removal - Jinja comment not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if ! grep -q 'def render():' "$temp_file"; then
        fail "Jinja comment removal - Valid content removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "Jinja comment removal"
    return 0
}

# Test: Worker annotation variations
test_sanitize_worker_annotations() {
    echo "Testing worker annotation variations..."
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local temp_file
    temp_file=$(mktemp --suffix=.js)
    
    cat > "$temp_file" << 'EOF'
// Worker 1 started this
// Worker 2 completed this
// Worker 3
function test() {
    // Task completed
    // Task in progress
    // Task in_progress
    console.log("test");
}
EOF
    
    swarm_sanitize_source_file "$temp_file" 2>/dev/null
    
    if grep -qiE '// *Worker [0-9]+' "$temp_file"; then
        fail "Worker annotation variations - Worker annotation not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if grep -qiE '// *Task (completed|in.progress)' "$temp_file"; then
        fail "Worker annotation variations - Task annotation not removed"
        rm -f "$temp_file"
        return 1
    fi
    
    if ! grep -q 'function test()' "$temp_file"; then
        fail "Worker annotation variations - Valid content removed"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    pass "Worker annotation variations"
    return 0
}

# Main test runner
run_all_tests() {
    echo "=========================================="
    echo "Sanitization Function Unit Tests"
    echo "=========================================="
    echo ""
    
    test_sanitize_go_file
    echo ""
    
    test_sanitize_python_file
    echo ""
    
    test_sanitize_typescript_file
    echo ""
    
    test_sanitize_detects_merge_conflicts
    echo ""
    
    test_sanitize_ignores_non_source
    echo ""
    
    test_sanitize_empty_file
    echo ""
    
    test_sanitize_directory
    echo ""
    
    test_sanitize_jinja_comments
    echo ""
    
    test_sanitize_worker_annotations
    echo ""
    
    echo "=========================================="
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    echo "=========================================="
    
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    fi
    return 0
}

# Entry point
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_all_tests
    exit $?
fi
