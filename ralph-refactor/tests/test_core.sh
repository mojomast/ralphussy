#!/usr/bin/env bash

__TEST_CORE_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# We need to source dependent libs if core.sh relies on them
# core.sh uses json_extract_text/json_extract_tools which are in json.sh
. "$__TEST_CORE_DIR__/../lib/json.sh"
. "$__TEST_CORE_DIR__/../lib/core.sh"

TEST_RUN_DIR="/tmp/test_core_$(date +%s%N)"
mkdir -p "$TEST_RUN_DIR"

# Test counter
TESTS_FAILED=0

setup_mock_opencode() {
    local bin_dir="$TEST_RUN_DIR/bin"
    mkdir -p "$bin_dir"
    
    # Create mock opencode
    cat > "$bin_dir/opencode" << 'EOF'
#!/bin/bash
if [ "$1" = "run" ]; then
    # Return mock JSON response
    cat << JEOF
{
  "type": "text",
  "part": {
    "text": "Mock response text",
    "cost": 0.015,
    "tokens": {
      "input": 100,
      "output": 50
    }
  }
}
JEOF
fi
EOF
    chmod +x "$bin_dir/opencode"
    
    # Add to PATH
    export PATH="$bin_dir:$PATH"
}

test_configuration_loading() {
    echo "Testing configuration loading..."
    
    # Override RALPH_DIR for test
    export RALPH_DIR="$TEST_RUN_DIR/.ralph"
    export STATE_FILE="$RALPH_DIR/state.json"
    export HISTORY_FILE="$RALPH_DIR/history.json"
    export LOG_DIR="$RALPH_DIR/logs"
    export RUNS_DIR="$RALPH_DIR/runs"
    export BLOCKERS_FILE="$RALPH_DIR/blockers.txt"
    export PROGRESS_FILE="$RALPH_DIR/progress.md"
    
    # Call init_ralph
    init_ralph
    
    # Verify directories created
    if [ -d "$RALPH_DIR" ] && [ -d "$LOG_DIR" ] && [ -d "$RUNS_DIR" ]; then
        echo "✅ Directories created successfully"
    else
        echo "❌ Failed to create directories"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Verify files created
    if [ -f "$STATE_FILE" ] && [ -f "$HISTORY_FILE" ] && [ -f "$BLOCKERS_FILE" ] && [ -f "$PROGRESS_FILE" ]; then
        echo "✅ Config files created successfully"
    else
        echo "❌ Failed to create config files"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Verify default values
    local state_content
    state_content=$(cat "$STATE_FILE")
    if echo "$state_content" | grep -q "idle"; then
        echo "✅ State file initialized with default values"
    else
        echo "❌ State file content incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_opencode_execution() {
    echo "Testing OpenCode execution..."
    
    setup_mock_opencode
    
    # Mock start_monitor and stop_monitor to avoid side effects
    start_monitor() { :; }
    stop_monitor() { :; }
    
    # Mock log functions to avoid clutter
    log_info() { :; }
    log_error() { echo "ERROR: $1"; }
    
    # Execute
    local result
    _ralph_execute_opencode "Test prompt" "Task 1"
    local status=$?

    if [ $status -eq 0 ]; then
        echo "✅ _ralph_execute_opencode returned success"
    else
        echo "❌ _ralph_execute_opencode failed with status $status"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Verify output captured
    if [ "$RALPH_LAST_TEXT_OUTPUT" = "Mock response text" ]; then
        echo "✅ RALPH_LAST_TEXT_OUTPUT captured correctly"
    else
        echo "❌ Expected 'Mock response text', got: '$RALPH_LAST_TEXT_OUTPUT'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_token_cost_tracking() {
    echo "Testing token and cost tracking..."
    
    # Assuming _ralph_execute_opencode was run in previous test
    # If not, run it again or set variables manually
    
    # We'll rely on the state from previous test if available, or re-run
    if [ -z "$RALPH_LAST_TOTAL_TOKENS" ]; then
        setup_mock_opencode
        start_monitor() { :; }
        stop_monitor() { :; }
        log_info() { :; }
        _ralph_execute_opencode "Test prompt"
    fi
    
    # Mock returns input:100, output:50 -> total 150
    if [ "$RALPH_LAST_TOTAL_TOKENS" -eq 150 ]; then
        echo "✅ RALPH_LAST_TOTAL_TOKENS correct (150)"
    else
        echo "❌ Expected 150, got: '$RALPH_LAST_TOTAL_TOKENS'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Mock returns cost 0.015
    if [ "$RALPH_LAST_COST" = "0.015" ]; then
        echo "✅ RALPH_LAST_COST correct (0.015)"
    else
        echo "❌ Expected 0.015, got: '$RALPH_LAST_COST'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_completion_promise_detection() {
    echo "Testing completion promise detection..."
    
    # core.sh defines COMPLETION_PROMISE variable
    if [ "$COMPLETION_PROMISE" = "COMPLETE" ]; then
        echo "✅ COMPLETION_PROMISE variable is set correctly"
    else
        echo "❌ COMPLETION_PROMISE incorrect: '$COMPLETION_PROMISE'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Test helper logic (simulated)
    local output="Here is the result <promise>COMPLETE</promise>"
    if echo "$output" | grep -q "<promise>$COMPLETION_PROMISE</promise>"; then
        echo "✅ Detection logic works with grep"
    else
        echo "❌ Detection logic failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_state_file_management() {
    echo "Testing state file management..."
    
    export RALPH_DIR="$TEST_RUN_DIR/.ralph"
    export STATE_FILE="$RALPH_DIR/state.json"
    mkdir -p "$RALPH_DIR"
    
    # Test update_state
    update_state "running" 1 "test prompt" "test context"
    
    local content
    content=$(get_state)
    
    if echo "$content" | grep -q '"status": "running"'; then
        echo "✅ State updated: status=running"
    else
        echo "❌ State status incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if echo "$content" | grep -q '"iteration": 1'; then
        echo "✅ State updated: iteration=1"
    else
        echo "❌ State iteration incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if echo "$content" | grep -q '"prompt": "test prompt"'; then
        echo "✅ State updated: prompt"
    else
        echo "❌ State prompt incorrect"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_logging_functions() {
    echo "Testing logging functions..."
    
    # Restore original functions by re-sourcing
    unset RALPH_CORE_LOADED
    . "$__TEST_CORE_DIR__/../lib/core.sh"
    
    # Test log functions by capturing output
    local output
    output=$(log_info "Info message")
    if echo "$output" | grep -q "Info message"; then
        echo "✅ log_info output correct"
    else
        echo "❌ log_info failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    output=$(log_error "Error message")
    if echo "$output" | grep -q "Error message"; then
        echo "✅ log_error output correct"
    else
        echo "❌ log_error failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Test history rotation
    export RALPH_DIR="$TEST_RUN_DIR/.ralph"
    export HISTORY_FILE="$RALPH_DIR/history.json"
    mkdir -p "$RALPH_DIR"

    # Create large history file (6MB)
    dd if=/dev/zero of="$HISTORY_FILE" bs=1M count=6 2>/dev/null
    
    # Call rotation
    rotate_history_if_needed
    
    # Check if rotated
    if [ -f "$HISTORY_FILE" ] && [ $(wc -c < "$HISTORY_FILE") -lt 1000 ]; then
        echo "✅ History file rotated (new file is small)"
    else
        echo "❌ History file not rotated or too large"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    local archive_count
    archive_count=$(find "$RALPH_DIR/history_archive" -name "history_*.json" | wc -l)
    if [ "$archive_count" -ge 1 ]; then
        echo "✅ Archived history found"
    else
        echo "❌ No archived history found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_all_tests() {
    echo "=========================================="
    echo "Running Core Tests"
    echo "=========================================="
    echo ""
    
    test_configuration_loading
    test_opencode_execution
    test_token_cost_tracking
    test_completion_promise_detection
    test_state_file_management
    test_logging_functions
    
    # Cleanup
    rm -rf "$TEST_RUN_DIR"
    
    echo ""
    echo "=========================================="
    echo "Test Results: $TESTS_FAILED failed"
    echo "=========================================="
    
    return $TESTS_FAILED
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi
