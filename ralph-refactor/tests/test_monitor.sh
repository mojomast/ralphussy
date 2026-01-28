#!/usr/bin/env bash

__TEST_MONITOR_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

export RALPH_MAIN_PID="$$"

# Setup test env
TEST_RUN_DIR="/tmp/test_monitor_$(date +%s%N)"
mkdir -p "$TEST_RUN_DIR"
export HOME="$TEST_RUN_DIR"
export RALPH_DIR="$TEST_RUN_DIR/.ralph"
mkdir -p "$RALPH_DIR"

# Create log dir expected by monitor
LOG_DIR="$HOME/.local/share/opencode/log"
mkdir -p "$LOG_DIR"

. "$__TEST_MONITOR_DIR__/../lib/monitor.sh"

TESTS_FAILED=0

# Helper to mock pgrep/ps
setup_mock_proc_tools() {
    local bin_dir="$TEST_RUN_DIR/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/pgrep" << 'EOF'
#!/bin/bash
if [ "$1" = "-P" ]; then
    if [ "$2" = "12345" ]; then echo "12346"; fi
fi
EOF
    chmod +x "$bin_dir/pgrep"
    
    cat > "$bin_dir/ps" << 'EOF'
#!/bin/bash
if [ "$1" = "-p" ]; then
    if [ "$2" = "12346" ]; then echo "opencode run"; fi
fi
EOF
    chmod +x "$bin_dir/ps"
    
    export PATH="$bin_dir:$PATH"
}

test_monitor_start_stop() {
    echo "Testing monitor start/stop..."
    
    # Start monitor
    start_monitor 2> "$TEST_RUN_DIR/monitor.err"
    
    if [ -n "$MONITOR_PID" ]; then
        echo "✅ MONITOR_PID set ($MONITOR_PID)"
    else
        echo "❌ MONITOR_PID not set"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo "✅ Monitor process running"
    else
        echo "❌ Monitor process not running"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if [ -f "$MONITOR_CONTROL_FILE" ]; then
        echo "✅ Control file created"
    else
        echo "❌ Control file not created"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    stop_monitor
    
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo "❌ Monitor process still running"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        kill "$MONITOR_PID" 2>/dev/null
    else
        echo "✅ Monitor process stopped"
    fi
    
    if [ ! -f "$MONITOR_CONTROL_FILE" ]; then
         echo "✅ Control file removed"
    else
         echo "❌ Control file not removed"
         TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_opencode_process_detection() {
    echo "Testing opencode process detection..."
    
    setup_mock_proc_tools
    
    local RALPH_MAIN_PID=12345
    if monitor_is_opencode_running; then
        echo "✅ Detected running opencode process"
    else
        echo "❌ Failed to detect opencode process"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    local RALPH_MAIN_PID=99999
    if monitor_is_opencode_running; then
        echo "❌ False positive detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        echo "✅ Correctly detected no process"
    fi
}

test_log_file_tracking() {
    echo "Testing log file tracking..."
    
    # Create logs
    touch -t 202401011200 "$LOG_DIR/old.log"
    touch -t 202401011300 "$LOG_DIR/new.log"
    
    local result
    result=$(find_latest_log)
    
    if echo "$result" | grep -q "new.log"; then
        echo "✅ Found latest log file"
    else
        echo "❌ Failed to find latest log. Got: '$result'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Cleanup logs for other tests
    rm "$LOG_DIR"/*.log
}

test_activity_detection() {
    echo "Testing activity detection..."
    
    # Ensure log dir empty
    rm -f "$LOG_DIR"/*.log
    
    monitor_is_opencode_running() { return 0; }
    export MONITOR_ACTIVITY_IDLE_SECONDS=1
    
    local output_file="$TEST_RUN_DIR/monitor_activity.log"
    start_monitor 2> "$output_file"
    
    sleep 0.5
    
    # Create NEW log to trigger connection
    local log_file="$LOG_DIR/active.log"
    touch "$log_file"
    
    sleep 0.5
    
    # Trigger activity
    echo "Activity" >> "$log_file"
    sleep 0.5

    stop_monitor
    
    # Check output
    if grep -q "active.log" "$output_file"; then
        echo "✅ Monitor picked up active log"
    else
        echo "❌ Monitor didn't pick up active log"
        # cat "$output_file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_monitor_cleanup() {
    echo "Testing monitor cleanup..."
    
    local orphan="$RALPH_DIR/monitor_control_orphan1"
    touch "$orphan"
    # Make it old
    if date -v -11M >/dev/null 2>&1; then
        local old_time
        old_time=$(date -v -11M +%Y%m%d%H%M)
        touch -t "$old_time" "$orphan"
    else
        touch -d "11 minutes ago" "$orphan"
    fi
    
    touch "$RALPH_DIR/monitor_control_fresh"
    
    stop_monitor
    
    if [ ! -f "$orphan" ]; then
        echo "✅ Orphaned control file cleaned up"
    else
        echo "❌ Orphaned control file REMAINED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    if [ -f "$RALPH_DIR/monitor_control_fresh" ]; then
        echo "✅ Fresh control file preserved"
        rm "$RALPH_DIR/monitor_control_fresh"
    else
        echo "❌ Fresh control file deleted unexpectedly"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_all_tests() {
    echo "=========================================="
    echo "Running Monitor Tests"
    echo "=========================================="
    echo ""
    
    test_monitor_start_stop
    test_opencode_process_detection
    test_log_file_tracking
    test_activity_detection
    test_monitor_cleanup
    
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
