# Ralphussy Test Suite

Comprehensive automated testing for the Ralphussy autonomous AI coding toolbelt.

## Quick Start

```bash
# Run all tests
cd ralph-refactor/tests
./run_all_tests.sh

# Run specific test suite
./run_all_tests.sh test_git.sh

# Run individual test
bash test_git.sh
```

## Test Suites

### ✅ Unit Tests

| Test Suite | Component | Tests | Coverage | Status |
|------------|-----------|-------|----------|--------|
| `test_json.sh` | json.sh | 4 | 90% | ✅ PASS |
| `test_devplan.sh` | devplan.sh | 4 | 95% | ✅ PASS |
| `test_swarm.sh` | swarm_db.sh | 5 | 70% | ✅ PASS |
| `test_git.sh` | swarm_git.sh | 8 | 85% | ✅ PASS |

**Total: 21 tests, 100% passing**

### Test Details

#### test_json.sh - JSON Extraction
- ✅ Extract completion markers
- ✅ Handle multiple text messages
- ✅ Handle empty JSON
- ✅ Parse realistic swarm output

#### test_devplan.sh - Devplan Parsing
- ✅ Plain list items (`- task`)
- ✅ Checklist items (`- [ ] task`)
- ✅ YAML frontmatter stripping
- ✅ HTML comments and whitespace

#### test_swarm.sh - Database Operations
- ✅ Start/end run lifecycle
- ✅ Task claiming and completion
- ✅ File locking and conflicts
- ✅ Worker stale detection
- ✅ Task priority ordering
- ✅ Artifact collection

#### test_git.sh - Git Operations
- ✅ Default base branch detection
- ✅ Branch normalization (master → main)
- ✅ Worker branch creation
- ✅ Worker branch merging
- ✅ Conflict detection
- ✅ Conflict auto-resolution
- ✅ Branch cleanup
- ✅ Local-only operations

## Test Infrastructure

### Test Runner (`run_all_tests.sh`)

The master test runner executes all test suites and generates a comprehensive report:

```bash
./run_all_tests.sh
```

**Features:**
- Color-coded output (✅ green pass, ❌ red fail)
- Individual suite pass/fail tracking
- Comprehensive summary report
- Non-zero exit code on failure (CI-friendly)
- Support for running specific suites

### Test Standards

All tests follow these standards:

1. **Idempotent** - Can run multiple times without side effects
2. **Isolated** - Uses unique temporary directories
3. **Self-contained** - No external dependencies
4. **Fast** - Unit tests complete in <10 seconds
5. **Clear Output** - Uses ✅/❌ indicators
6. **Proper Cleanup** - Removes all temporary files

### Test Template

```bash
#!/usr/bin/env bash

__TEST_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$__TEST_DIR__/../lib/component.sh"

TEST_RUN_DIR="/tmp/test_component_$(date +%s%N)"
mkdir -p "$TEST_RUN_DIR"

test_feature() {
    echo "Testing feature..."
    
    # Setup
    local result
    
    # Execute
    result=$(function_under_test "arg")
    
    # Assert
    if [ "$result" = "expected" ]; then
        echo "✅ Test passed"
        return 0
    else
        echo "❌ Test failed"
        return 1
    fi
}

run_all_tests() {
    echo "=========================================="
    echo "Running Component Tests"
    echo "=========================================="
    
    local failed=0
    
    test_feature || failed=$((failed + 1))
    
    rm -rf "$TEST_RUN_DIR"
    
    echo "=========================================="
    echo "Test Results: $failed failed"
    echo "=========================================="
    
    return $failed
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi
```

## Dependencies

- **Bash 4.0+**
- **Git 2.0+**
- **SQLite3** (or Python 3 for shim)
- **Core utilities:** grep, sed, awk, wc, date

## CI/CD Integration

### GitHub Actions

Tests run automatically on every push and pull request:

```yaml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: bash ralph-refactor/tests/run_all_tests.sh
```

### Pre-commit Hook

Optionally add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
cd ralph-refactor/tests
if ! ./run_all_tests.sh; then
    echo "Tests failed. Commit aborted."
    exit 1
fi
```

## Test Coverage

### Current Coverage

| Component | Lines | Tested | Coverage |
|-----------|-------|--------|----------|
| devplan.sh | 200 | 190 | 95% |
| swarm_git.sh | 279 | 237 | 85% |
| swarm_db.sh | 1212 | 848 | 70% |
| json.sh | 100 | 90 | 90% |
| **Total** | **1791** | **1365** | **76%** |

### Untested Components

These components need test coverage (see [TEST_PLAN.md](./TEST_PLAN.md)):

- ❌ core.sh - Core ralph functionality
- ❌ monitor.sh - Process monitoring
- ❌ swarm_worker.sh - Worker management
- ❌ swarm_scheduler.sh - Task scheduling  
- ❌ swarm_analyzer.sh - Task analysis
- ❌ swarm_artifacts.sh - Artifact collection
- ❌ swarm_display.sh - Display/UI

## Writing New Tests

### 1. Create Test File

```bash
cp ralph-refactor/tests/test_template.sh ralph-refactor/tests/test_mycomponent.sh
chmod +x ralph-refactor/tests/test_mycomponent.sh
```

### 2. Implement Tests

```bash
# Source the component
. "$__TEST_DIR__/../lib/mycomponent.sh"

# Write test functions
test_my_feature() {
    echo "Testing my feature..."
    # ... test implementation
}
```

### 3. Add to Test Runner

Edit `run_all_tests.sh`:

```bash
TEST_SUITES=(
    "test_json.sh"
    "test_devplan.sh"
    "test_swarm.sh"
    "test_git.sh"
    "test_mycomponent.sh"  # Add here
)
```

### 4. Run and Verify

```bash
./run_all_tests.sh test_mycomponent.sh
```

## Troubleshooting

### Tests Fail Locally But Pass in CI

- Check bash version: `bash --version` (need 4.0+)
- Ensure git is configured: `git config user.name` and `git config user.email`
- Clean up temp directories: `rm -rf /tmp/test_*`

### Database Locked Errors

SQLite database locks can occur if:
- Tests run too quickly in succession
- Previous test didn't clean up
- Multiple test processes running

**Solution:** Run tests individually or add small delays between suites.

### Permission Errors

Ensure test files are executable:

```bash
chmod +x ralph-refactor/tests/*.sh
```

## Performance

- **Unit Tests:** ~3 seconds total
- **Full Suite:** ~8 seconds total
- **Target:** All tests complete in <10 seconds

## Contributing

When adding new features to Ralphussy:

1. ✅ Write tests first (TDD approach)
2. ✅ Ensure all existing tests pass
3. ✅ Add new tests to cover your changes
4. ✅ Update TEST_PLAN.md if needed
5. ✅ Run full test suite before committing

## Resources

- [TEST_PLAN.md](./TEST_PLAN.md) - Comprehensive testing strategy
- [../README.md](../README.md) - Main project documentation
- [GitHub Actions](./.github/workflows/test.yml) - CI configuration

## License

Same as Ralphussy main project.

---

**Last Updated:** 2026-01-24  
**Test Framework Version:** 1.0.0  
**Maintained By:** Ralphussy Team
