#!/usr/bin/env bash

# Ralphussy Test Suite Runner
# Runs all test suites and generates comprehensive report

set -e

__TEST_RUNNER_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test suites to run (in order)
TEST_SUITES=(
    "test_json.sh"
    "test_devplan.sh"
    "test_swarm.sh"
    "test_git.sh"
    "test_core.sh"
    "test_monitor.sh"
)

# Track results
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

# Print header
print_header() {
    echo ""
    echo "=========================================="
    echo "  RALPHUSSY TEST SUITE"
    echo "=========================================="
    echo ""
    echo "Running $(echo ${#TEST_SUITES[@]}) test suites..."
    echo ""
}

# Print footer with summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "  TEST SUMMARY"
    echo "=========================================="
    echo ""
    echo -e "${CYAN}Total Suites:${NC} ${#TEST_SUITES[@]}"
    echo -e "${GREEN}Passed:${NC} $((${#TEST_SUITES[@]} - ${#FAILED_SUITES[@]}))"
    echo -e "${RED}Failed:${NC} ${#FAILED_SUITES[@]}"
    echo ""
    
    if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}❌ SOME TESTS FAILED:${NC}"
        for suite in "${FAILED_SUITES[@]}"; do
            echo -e "   ${RED}✗${NC} $suite"
        done
        echo ""
        return 1
    fi
}

# Run a single test suite
run_suite() {
    local suite="$1"
    local suite_path="$__TEST_RUNNER_DIR__/$suite"
    
    if [ ! -f "$suite_path" ]; then
        echo -e "${RED}❌ Test suite not found: $suite${NC}"
        FAILED_SUITES+=("$suite")
        return 1
    fi
    
    echo -e "${BLUE}▶ Running:${NC} $suite"
    echo ""
    
    # Run the test and capture output
    local output
    local exit_code
    
    if output=$(bash "$suite_path" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Show output
    echo "$output"
    echo ""
    
    # Check result
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED:${NC} $suite"
    else
        echo -e "${RED}❌ FAILED:${NC} $suite (exit code: $exit_code)"
        FAILED_SUITES+=("$suite")
    fi
    
    echo ""
    echo "------------------------------------------"
    echo ""
    
    return $exit_code
}

# Main execution
main() {
    print_header
    
    # Run each test suite
    for suite in "${TEST_SUITES[@]}"; do
        run_suite "$suite" || true  # Don't exit on failure, continue running
    done
    
    # Print summary and exit with appropriate code
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Allow running specific suites
if [ $# -gt 0 ]; then
    # Run only specified suites
    TEST_SUITES=("$@")
fi

main
