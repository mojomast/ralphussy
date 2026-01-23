#!/usr/bin/env bash

__TEST_JSON_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$__TEST_JSON_DIR__/../lib/json.sh"

TEST_DATA_DIR="/tmp/test_json_$(date +%s)"
mkdir -p "$TEST_DATA_DIR"

test_extract_text_with_completion_marker() {
    echo "Testing json_extract_text with completion marker..."

    local json_input
    json_input='{"type":"text","part":{"text":"I will initialize the Go module and create the project directory structure."}}
{"type":"text","part":{"text":"<promise>COMPLETE</promise>"}}'

    local result
    result=$(json_extract_text "$json_input")

    if [ "$result" = "<promise>COMPLETE</promise>" ]; then
        echo "✅ Extracted completion marker correctly"
        return 0
    else
        echo "❌ Expected '<promise>COMPLETE</promise>', got: '$result'"
        return 1
    fi
}

test_extract_text_multiple_messages() {
    echo "Testing json_extract_text with multiple text messages..."

    local json_input
    json_input='{"type":"text","part":{"text":"First message"}}
{"type":"text","part":{"text":"Task completed successfully"}}
{"type":"text","part":{"text":"<promise>COMPLETE</promise>"}}'

    local result
    result=$(json_extract_text "$json_input")

    if [ "$result" = "<promise>COMPLETE</promise>" ]; then
        echo "✅ Extracted last text message correctly"
        return 0
    else
        echo "❌ Expected '<promise>COMPLETE</promise>', got: '$result'"
        return 1
    fi
}

test_extract_text_empty_json() {
    echo "Testing json_extract_text with empty JSON..."
    
    local result
    result=$(json_extract_text "")
    
    if [ -z "$result" ]; then
        echo "✅ Handled empty JSON correctly"
        return 0
    else
        echo "❌ Expected empty string, got: '$result'"
        return 1
    fi
}

test_extract_text_from_real_output() {
    echo "Testing json_extract_text from real swarm output..."
    
    local result
    result=$(json_extract_text "$(cat /tmp/swarm_task_1663_output.json)")
    
    if [ "$result" = "<promise>COMPLETE</promise>" ]; then
        echo "✅ Extracted completion marker from real output correctly"
        return 0
    else
        echo "❌ Expected '<promise>COMPLETE</promise>', got: '$result'"
        return 1
    fi
}

run_all_tests() {
    echo "=========================================="
    echo "Running JSON Extraction Tests"
    echo "=========================================="
    echo ""
    
    local test_results=0
    
    if ! test_extract_text_with_completion_marker; then
        test_results=$((test_results + 1))
    fi
    
    if ! test_extract_text_multiple_messages; then
        test_results=$((test_results + 1))
    fi
    
    if ! test_extract_text_empty_json; then
        test_results=$((test_results + 1))
    fi
    
    if ! test_extract_text_from_real_output; then
        test_results=$((test_results + 1))
    fi
    
    rm -rf "$TEST_DATA_DIR"
    
    echo ""
    echo "=========================================="
    echo "Test Results: $test_results failed"
    echo "=========================================="
    
    return $test_results
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi
