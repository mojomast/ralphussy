#!/usr/bin/env bash
#
# Unit tests for devussy integration
# Tests the devussy.sh library and pipeline integration
#

__TEST_DEVUSSY_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
. "$__TEST_DEVUSSY_DIR__/../lib/core.sh"
. "$__TEST_DEVUSSY_DIR__/../lib/devussy.sh"

TEST_RUN_DIR="/tmp/test_devussy_$(date +%s%N)"
mkdir -p "$TEST_RUN_DIR"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output (redefine in case core.sh doesn't have them)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# Test Helpers
# ==============================================================================

setup_test_env() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    export DEVUSSY_PATH="${DEVUSSY_PATH:-$HOME/projects/ralphussy/devussyout}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual: '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_success() {
    local exit_code="$1"
    local message="$2"
    
    if [ "$exit_code" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $message (exit code: $exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_failure() {
    local exit_code="$1"
    local message="$2"
    
    if [ "$exit_code" -ne 0 ]; then
        echo -e "  ${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $message (expected failure but got success)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Searched for: '$needle'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local message="$2"
    
    if [ -f "$filepath" ]; then
        echo -e "  ${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $message (file not found: $filepath)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ==============================================================================
# Test: devussy_check_dependencies
# ==============================================================================

test_devussy_check_dependencies() {
    echo ""
    echo -e "${CYAN}Testing devussy_check_dependencies...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_deps"
    setup_test_env "$test_env"
    
    # Test 1: All dependencies present
    local result
    result=$(devussy_check_dependencies 2>&1)
    local exit_code=$?
    
    assert_success "$exit_code" "devussy_check_dependencies returns success when deps present"
    
    # Test 2: Verify DEVUSSY_PATH check
    local old_path="$DEVUSSY_PATH"
    export DEVUSSY_PATH="/nonexistent/path"
    result=$(devussy_check_dependencies 2>&1)
    exit_code=$?
    
    assert_failure "$exit_code" "devussy_check_dependencies fails with invalid DEVUSSY_PATH"
    assert_contains "$result" "not found" "Error message mentions directory not found"
    
    # Restore
    export DEVUSSY_PATH="$old_path"
}

# ==============================================================================
# Test: devussy_json_to_markdown (flat mode)
# ==============================================================================

test_devussy_json_to_markdown_flat() {
    echo ""
    echo -e "${CYAN}Testing devussy_json_to_markdown (flat mode)...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_json_flat"
    setup_test_env "$test_env"
    
    # Sample JSON devplan (flat mode)
    local sample_json='{
        "phases": [
            {
                "number": 1,
                "title": "Setup",
                "description": "Initial setup phase",
                "steps": [
                    {"number": "1.1", "description": "Create directory structure", "details": ["Create src/", "Create tests/"]},
                    {"number": "1.2", "description": "Initialize git", "details": ["Run git init"]}
                ]
            },
            {
                "number": 2,
                "title": "Implementation",
                "description": "Core implementation",
                "steps": [
                    {"number": "2.1", "description": "Implement main module", "details": ["Create main.py"]}
                ]
            }
        ]
    }'
    
    # Test conversion
    local result
    result=$(devussy_json_to_markdown "$sample_json" "test-project" "Test goal" "flat")
    local exit_code=$?
    
    assert_success "$exit_code" "JSON to markdown conversion succeeds"
    assert_contains "$result" "# DevPlan: test-project" "Output contains project header"
    assert_contains "$result" "## Goal" "Output contains goal section"
    assert_contains "$result" "Test goal" "Output contains goal text"
    assert_contains "$result" "## Tasks" "Output contains tasks section"
    assert_contains "$result" "Phase 1: Setup" "Output contains phase 1 title"
    assert_contains "$result" "1.1" "Output contains step 1.1"
}

# ==============================================================================
# Test: devussy_json_to_markdown (grouped mode)
# ==============================================================================

test_devussy_json_to_markdown_grouped() {
    echo ""
    echo -e "${CYAN}Testing devussy_json_to_markdown (grouped mode)...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_json_grouped"
    setup_test_env "$test_env"
    
    # Sample JSON devplan (grouped mode)
    local sample_json='{
        "phases": [
            {
                "number": 1,
                "title": "Setup",
                "description": "Initial setup phase",
                "task_groups": [
                    {
                        "group_number": 1,
                        "description": "Configuration files",
                        "estimated_files": ["requirements.txt", "setup.py"],
                        "steps": [
                            {"number": "1.1", "description": "Create requirements.txt", "details": ["Add pytest"]},
                            {"number": "1.2", "description": "Create setup.py", "details": ["Add metadata"]}
                        ]
                    },
                    {
                        "group_number": 2,
                        "description": "Source files",
                        "estimated_files": ["src/*.py"],
                        "steps": [
                            {"number": "1.3", "description": "Create main.py", "details": ["Add entry point"]}
                        ]
                    }
                ]
            }
        ]
    }'
    
    # Test conversion
    local result
    result=$(devussy_json_to_markdown "$sample_json" "test-project" "Test goal" "grouped")
    local exit_code=$?
    
    assert_success "$exit_code" "JSON to markdown conversion succeeds (grouped)"
    assert_contains "$result" "# DevPlan: test-project" "Output contains project header"
    assert_contains "$result" "grouped by file patterns" "Output mentions grouped mode"
    assert_contains "$result" "Group 1" "Output contains Group 1 header"
    assert_contains "$result" "Group 2" "Output contains Group 2 header"
    assert_contains "$result" "requirements.txt" "Output contains estimated_files"
}

# ==============================================================================
# Test: Python imports work correctly
# ==============================================================================

test_python_imports() {
    echo ""
    echo -e "${CYAN}Testing Python module imports...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_imports"
    setup_test_env "$test_env"
    
    # Test that all required imports work
    local result
    result=$(python3 -c "
import sys
import os
sys.path.insert(0, os.path.join('$DEVUSSY_PATH', 'src'))

try:
    from llm_client import LLMClient
    from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig
    from models import ProjectDesign, DevPlan, DevPlanPhase
    from concurrency import ConcurrencyManager
    from templates import render_template
    from config import load_config
    from pipeline.project_design import ProjectDesignGenerator
    from pipeline.basic_devplan import BasicDevPlanGenerator
    from pipeline.detailed_devplan import DetailedDevPlanGenerator
    print('SUCCESS')
except Exception as e:
    print(f'FAILED: {e}')
" 2>&1)
    
    local exit_code=$?
    
    assert_success "$exit_code" "Python command executes"
    assert_contains "$result" "SUCCESS" "All Python imports succeed"
}

# ==============================================================================
# Test: Template rendering
# ==============================================================================

test_template_rendering() {
    echo ""
    echo -e "${CYAN}Testing Jinja2 template rendering...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_templates"
    setup_test_env "$test_env"
    
    # Test that templates render without errors
    local result
    result=$(python3 -c "
import sys
import os
sys.path.insert(0, os.path.join('$DEVUSSY_PATH', 'src'))

from templates import render_template
from models import ProjectDesign

# Create a test design
design = ProjectDesign(
    project_name='test-project',
    objectives=['Build a test app'],
    tech_stack=['Python', 'pytest'],
    architecture_overview='Simple architecture'
)

# Try rendering the project_design template
try:
    result = render_template('project_design.jinja', {
        'project_name': design.project_name,
        'languages': ['Python'],
        'frameworks': [],
        'apis': [],
        'requirements': 'Test requirements'
    })
    if result and len(result) > 100:
        print('SUCCESS')
    else:
        print('FAILED: Template rendered but output too short')
except Exception as e:
    print(f'FAILED: {e}')
" 2>&1)
    
    local exit_code=$?
    
    assert_success "$exit_code" "Python command executes"
    assert_contains "$result" "SUCCESS" "Template rendering succeeds"
}

# ==============================================================================
# Test: Config loading
# ==============================================================================

test_config_loading() {
    echo ""
    echo -e "${CYAN}Testing config module...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_config"
    setup_test_env "$test_env"
    
    local result
    result=$(python3 -c "
import sys
import os
sys.path.insert(0, os.path.join('$DEVUSSY_PATH', 'src'))

from config import load_config

config = load_config()
if hasattr(config, 'hivemind') and hasattr(config.hivemind, 'enabled'):
    print('SUCCESS')
else:
    print('FAILED: Config missing expected attributes')
" 2>&1)
    
    local exit_code=$?
    
    assert_success "$exit_code" "Config loading executes"
    assert_contains "$result" "SUCCESS" "Config has expected structure"
}

# ==============================================================================
# Test: OpenCodeLLMClient initialization
# ==============================================================================

test_opencode_llm_client() {
    echo ""
    echo -e "${CYAN}Testing OpenCodeLLMClient initialization...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_llm_client"
    setup_test_env "$test_env"
    
    local result
    result=$(python3 -c "
import sys
import os
sys.path.insert(0, os.path.join('$DEVUSSY_PATH', 'src'))

from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig

# Test config creation
config = OpenCodeConfig(
    provider='zai-coding-plan',
    model='glm-4.7',
    timeout=300
)

# Test client creation
client = OpenCodeLLMClient(config)

if client.provider == 'zai-coding-plan' and client.model == 'glm-4.7':
    print('SUCCESS')
else:
    print(f'FAILED: provider={client.provider}, model={client.model}')
" 2>&1)
    
    local exit_code=$?
    
    assert_success "$exit_code" "LLM client creation executes"
    assert_contains "$result" "SUCCESS" "LLM client initialized with correct settings"
}

# ==============================================================================
# Test: Command building
# ==============================================================================

test_opencode_command_building() {
    echo ""
    echo -e "${CYAN}Testing OpenCodeLLMClient command building...${NC}"
    
    local test_env="$TEST_RUN_DIR/test_command"
    setup_test_env "$test_env"
    
    local result
    result=$(python3 -c "
import sys
import os
sys.path.insert(0, os.path.join('$DEVUSSY_PATH', 'src'))

from llm_client_opencode import OpenCodeLLMClient, OpenCodeConfig

# Test with provider/model
config = OpenCodeConfig(provider='zai-coding-plan', model='glm-4.7')
client = OpenCodeLLMClient(config)
cmd = client._build_command()

expected = ['opencode', 'run', '--format', 'json', '--model', 'zai-coding-plan/glm-4.7']
if cmd == expected:
    print('SUCCESS')
else:
    print(f'FAILED: {cmd}')
" 2>&1)
    
    local exit_code=$?
    
    assert_success "$exit_code" "Command building executes"
    assert_contains "$result" "SUCCESS" "Command built correctly with provider/model"
}

# ==============================================================================
# Main test runner
# ==============================================================================

run_all_tests() {
    echo ""
    echo "=========================================="
    echo "    DEVUSSY INTEGRATION TESTS"
    echo "=========================================="
    echo ""
    echo "Test run directory: $TEST_RUN_DIR"
    echo "DEVUSSY_PATH: $DEVUSSY_PATH"
    echo ""
    
    # Run all test functions
    test_devussy_check_dependencies
    test_devussy_json_to_markdown_flat
    test_devussy_json_to_markdown_grouped
    test_python_imports
    test_template_rendering
    test_config_loading
    test_opencode_llm_client
    test_opencode_command_building
    
    # Summary
    echo ""
    echo "=========================================="
    echo "    TEST SUMMARY"
    echo "=========================================="
    echo ""
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo ""
    
    # Cleanup
    if [ "$TESTS_FAILED" -eq 0 ]; then
        rm -rf "$TEST_RUN_DIR"
        echo -e "${GREEN}All tests passed! Test directory cleaned up.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Test directory preserved for debugging: $TEST_RUN_DIR${NC}"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
