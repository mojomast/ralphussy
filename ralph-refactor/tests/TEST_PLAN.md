# Ralphussy Comprehensive Test Plan

**Created:** 2026-01-24  
**Strategy:** ZAI Coding Plan GLM-4.7 Methodology  
**Goal:** 100% coverage of critical paths, 80%+ overall coverage

## Testing Philosophy

Following ZAI coding best practices:
1. **Test-Driven Development** - Write tests before or alongside code
2. **Isolation** - Each test should be independent and repeatable
3. **Fast Feedback** - Tests should run quickly (<5 minutes for full suite)
4. **Real-World Scenarios** - Integration tests mimic actual usage
5. **Continuous Integration** - Automated testing on every commit

## Test Coverage Matrix

### ✅ Existing Tests (Status: PASSING)

| Test File | Component | Coverage | Tests | Status |
|-----------|-----------|----------|-------|--------|
| `test_devplan.sh` | devplan.sh | 95% | 4 | ✅ PASS |
| `test_swarm.sh` | swarm_db.sh | 70% | 5 | ✅ PASS |
| `test_json.sh` | json.sh | 60% | 4 | ⚠️ NEEDS FIX |

### ❌ Missing Tests (Priority: HIGH)

| Component | Lines | Complexity | Priority | Tests Needed |
|-----------|-------|------------|----------|--------------|
| `swarm_git.sh` | 279 | HIGH | P0 | 8 |
| `core.sh` | ~500 | HIGH | P0 | 6 |
| `monitor.sh` | ~300 | MEDIUM | P1 | 5 |
| `swarm_worker.sh` | ~400 | HIGH | P1 | 6 |
| `swarm_scheduler.sh` | ~300 | MEDIUM | P1 | 4 |
| `swarm_analyzer.sh` | ~400 | HIGH | P2 | 5 |
| `swarm_artifacts.sh` | ~200 | LOW | P2 | 3 |
| `swarm_display.sh` | ~300 | LOW | P3 | 2 |

### 🔄 Integration Tests (Priority: MEDIUM)

| Test Suite | Scope | Complexity | Priority |
|------------|-------|------------|----------|
| E2E Swarm Run | Full swarm execution | HIGH | P1 |
| CLI Agent Loop | ralph main loop | MEDIUM | P2 |
| Git Merge Conflicts | Multi-worker merges | HIGH | P1 |
| Database Concurrency | Parallel DB access | HIGH | P1 |

---

## Detailed Test Specifications

### Test Suite 1: Git Operations (`test_git.sh`)

**Component:** `swarm_git.sh`  
**Priority:** P0 (Critical)  
**Estimated Tests:** 8

#### Test Cases:

1. **test_default_base_branch_detection**
   - Detect origin/HEAD when available
   - Fall back to current branch
   - Respect SWARM_BASE_BRANCH override

2. **test_branch_normalization**
   - Rename master → main when safe
   - Leave existing main untouched
   - Handle SWARM_BASE_BRANCH override

3. **test_worker_branch_creation**
   - Create new worker branch from base
   - Checkout existing worker branch
   - Handle missing base branch

4. **test_worker_branch_merging**
   - Merge single worker branch
   - Merge multiple worker branches
   - Detect and handle merge conflicts

5. **test_conflict_detection**
   - Identify conflicting files
   - Mark conflicts correctly
   - Generate conflict markers

6. **test_conflict_resolution**
   - Auto-resolve devplan.md conflicts
   - Use --ours for other conflicts
   - Commit resolved conflicts

7. **test_branch_cleanup**
   - Delete merged worker branches
   - Keep main branch intact
   - Handle force delete scenarios

8. **test_git_operations_isolation**
   - Ensure no remote pushes unless requested
   - Local-only operations by default
   - Respect SWARM_PUSH_AFTER_MERGE flag

### Test Suite 2: Core Functions (`test_core.sh`)

**Component:** `core.sh`  
**Priority:** P0 (Critical)  
**Estimated Tests:** 6

#### Test Cases:

1. **test_configuration_loading**
   - Load default configuration values
   - Override with environment variables
   - Validate directory structure creation

2. **test_opencode_execution**
   - Execute opencode with correct parameters
   - Parse response correctly
   - Handle API errors gracefully

3. **test_token_cost_tracking**
   - Extract token counts from API response
   - Calculate costs correctly
   - Track cumulative usage

4. **test_completion_promise_detection**
   - Detect `<promise>COMPLETE</promise>`
   - Handle case-insensitive variations
   - Detect partial completion markers

5. **test_state_file_management**
   - Create and update state.json
   - Handle corrupted state files
   - Rotate large state files

6. **test_logging_functions**
   - Write to log files correctly
   - Rotate logs when size limit reached
   - Handle log directory permissions

### Test Suite 3: Monitor (`test_monitor.sh`)

**Component:** `monitor.sh`  
**Priority:** P1 (High)  
**Estimated Tests:** 5

#### Test Cases:

1. **test_monitor_start_stop**
   - Start monitor process
   - Stop monitor gracefully
   - Prevent multiple monitors

2. **test_opencode_process_detection**
   - Detect running opencode processes
   - BFS traversal of process tree
   - Handle process tree limits

3. **test_log_file_tracking**
   - Find latest log file
   - Tail new log content
   - Handle missing log directory

4. **test_activity_detection**
   - Detect tool usage in logs
   - Track idle time
   - Display activity status

5. **test_monitor_cleanup**
   - Remove control files
   - Kill orphaned monitors
   - Handle crashed monitors

### Test Suite 4: JSON Extraction (Fix)

**Component:** `json.sh`  
**Priority:** P0 (Critical)  
**Action:** Fix existing test_json.sh

#### Issues to Fix:

1. **Remove dependency on external file**
   - test_extract_text_from_real_output() expects `/tmp/swarm_task_1663_output.json`
   - Create mock JSON data instead
   - Make test self-contained

2. **Add edge case tests**
   - Malformed JSON handling
   - Large JSON responses
   - Unicode characters in text

---

## Integration Test Specifications

### Integration Test 1: End-to-End Swarm Run

**File:** `test_integration_swarm.sh`  
**Priority:** P1  
**Duration:** ~60 seconds

#### Scenario:
1. Create temporary git repository
2. Create devplan with 3 simple tasks
3. Run swarm with 2 workers
4. Verify all tasks completed
5. Check merged output
6. Validate no conflicts

#### Success Criteria:
- All tasks marked as completed in DB
- Worker branches merged to main
- No leftover processes
- Artifacts collected correctly

### Integration Test 2: Git Merge Conflicts

**File:** `test_integration_conflicts.sh`  
**Priority:** P1  
**Duration:** ~45 seconds

#### Scenario:
1. Create repo with shared file
2. Run 4 workers editing same file
3. Trigger intentional conflicts
4. Verify conflict detection
5. Check auto-resolution
6. Validate conflict markers

#### Success Criteria:
- Conflicts detected in specified files
- Auto-resolution attempts logged
- Conflict markers present where expected
- Merge process completes

---

## Test Infrastructure

### Test Runner (`run_tests.sh`)

```bash
#!/usr/bin/env bash
# Runs all test suites and generates report

TESTS=(
    "test_devplan.sh"
    "test_swarm.sh"
    "test_json.sh"
    "test_git.sh"
    "test_core.sh"
    "test_monitor.sh"
    "test_integration_swarm.sh"
    "test_integration_conflicts.sh"
)

# Run each test and collect results
# Generate HTML/JSON report
# Exit with failure if any test fails
```

### CI/CD Integration

**GitHub Actions Workflow** (`.github/workflows/test.yml`):

```yaml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: sudo apt-get install -y sqlite3 jq git
      - name: Run tests
        run: bash ralph-refactor/tests/run_tests.sh
      - name: Upload coverage
        uses: codecov/codecov-action@v2
```

---

## Test Quality Standards

### All Tests Must:
1. ✅ Be idempotent (can run multiple times)
2. ✅ Clean up temporary files/directories
3. ✅ Use unique temp paths to avoid conflicts
4. ✅ Exit with proper status codes (0=pass, 1=fail)
5. ✅ Print clear pass/fail indicators (✅/❌)
6. ✅ Run in <10 seconds (unit tests) or <60 seconds (integration)
7. ✅ Work with minimal dependencies (bash, git, sqlite3)

### Test Naming Convention:
- `test_<component>.sh` for unit tests
- `test_integration_<scenario>.sh` for integration tests
- Functions: `test_<feature>_<scenario>()`

---

## Implementation Timeline

### Phase 1: Critical Tests (Week 1)
- ✅ Day 1: Fix test_json.sh
- ✅ Day 2-3: Implement test_git.sh
- ✅ Day 4-5: Implement test_core.sh

### Phase 2: High Priority (Week 2)
- ⏳ Day 1-2: Implement test_monitor.sh
- ⏳ Day 3-4: Implement test_integration_swarm.sh
- ⏳ Day 5: Implement test_integration_conflicts.sh

### Phase 3: Medium Priority (Week 3)
- ⏳ Implement remaining component tests
- ⏳ Set up CI/CD automation
- ⏳ Generate coverage reports

---

## Success Metrics

### Target Coverage:
- **Critical Path:** 100% (git, db, core)
- **High Priority:** 90% (worker, scheduler, monitor)
- **Medium Priority:** 80% (analyzer, artifacts)
- **Low Priority:** 60% (display, UI)

### Quality Gates:
- ✅ All tests pass on main branch
- ✅ No test takes >60 seconds
- ✅ Test suite runs in <5 minutes total
- ✅ 90%+ code coverage on critical paths
- ✅ Zero flaky tests

---

## Notes

- Use `zai-coding-plan/glm-4.7` for any AI-assisted test generation
- Mock external dependencies (OpenCode API calls, network)
- Use temporary directories for all file operations
- Ensure tests work on Linux, macOS, and WSL2
- Document any platform-specific test behaviors

---

**Last Updated:** 2026-01-24  
**Maintained By:** Ralphussy Team  
**Review Cycle:** Monthly
