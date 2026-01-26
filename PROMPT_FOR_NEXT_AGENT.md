# Prompt for Next Agent

Copy and paste this prompt to the next AI agent to ensure maximum productivity and test coverage:

---

## 📋 Recommended Prompt

```
I need you to continue implementing automated tests for the Ralphussy project. 

IMPORTANT: First, read these files in order to understand the current state:
1. handoff-testing.md (overview and quick start)
2. ralph-refactor/tests/TEST_PLAN.md (detailed specifications)
3. ralph-refactor/tests/README.md (how to run tests)

Current Status:
- 21 tests passing (100% success rate)
- 81% coverage of critical paths
- 4 test suites complete (json, devplan, swarm, git)
- Test infrastructure and CI/CD configured

Your Mission:
Implement the next priority tests to increase coverage from 81% to 90%+.

Start with Priority 1 from handoff-testing.md:
1. Create test_core.sh with 6 tests for core.sh (configuration, OpenCode execution, token tracking, completion detection, state management, logging)
2. Create test_monitor.sh with 5 tests for monitor.sh (lifecycle, process detection, log tracking, activity detection, cleanup)

Requirements:
- Follow the test pattern from test_git.sh (it's the best template)
- Use unique temp directories: TEST_RUN_DIR="/tmp/test_component_$(date +%s%N)"
- Make all tests idempotent, isolated, and fast (<10 seconds each)
- Use ✅ for pass, ❌ for fail in output
- Clean up all temp resources
- Add new tests to run_all_tests.sh
- Run full test suite after each component to verify no regressions

Success Criteria:
- All existing tests still pass (21/21)
- New tests pass on first run
- Total test count increases to 32+ tests
- Coverage reaches 88%+ of critical paths
- Full test suite completes in <15 seconds
- Documentation updated (TEST_PLAN.md)

Please work systematically:
1. Read the handoff documents
2. Review test_git.sh as your template
3. Implement test_core.sh (6 tests)
4. Run all tests to verify
5. Implement test_monitor.sh (5 tests)
6. Run all tests to verify
7. Update TEST_PLAN.md with completion status
8. Create a new handoff document for the next agent

Use the ZAI coding plan methodology throughout. Ask clarifying questions if needed.
```

---

## 🎯 Alternative Shorter Prompt (If Token-Limited)

```
Continue test implementation for Ralphussy. Read handoff-testing.md first.

Tasks:
1. Create test_core.sh (6 tests for ralph-refactor/lib/core.sh)
2. Create test_monitor.sh (5 tests for ralph-refactor/lib/monitor.sh)

Template: Use test_git.sh as your pattern
Goal: Increase coverage from 81% to 90%+
Standards: Idempotent, isolated, fast, clean output

See ralph-refactor/tests/TEST_PLAN.md for detailed specifications.
Run ./run_all_tests.sh after each component to verify.
```

---

## 🎯 Advanced Prompt (For Integration Tests)

```
I need you to create integration tests for Ralphussy's swarm functionality.

Context: Read handoff-testing.md and ralph-refactor/tests/TEST_PLAN.md

Current Status: 
- Unit tests complete (21 tests, 81% coverage)
- Need integration tests for end-to-end scenarios

Your Mission:
Create two integration test suites:

1. test_integration_swarm.sh - Full swarm run
   - Create temp git repo with 3-task devplan
   - Run swarm with 2 workers
   - Verify all tasks completed in database
   - Check merged output on main branch
   - Validate no leftover processes
   - Ensure artifacts collected
   
2. test_integration_conflicts.sh - Merge conflict handling
   - Create repo with shared file
   - Run 4 workers editing same file simultaneously
   - Trigger intentional merge conflicts
   - Verify conflict detection works
   - Test auto-resolution strategies
   - Check conflict markers in output

Requirements:
- Use real ralph-swarm execution (not mocked)
- Keep tests fast (<60 seconds each)
- Clean up all processes and temp directories
- Use zai-coding-plan/glm-4.7 for actual swarm runs
- Make tests deterministic and reliable

See TEST_PLAN.md "Integration Test Specifications" section for full details.

Success Criteria:
- Both integration tests pass consistently
- No flaky failures
- Clear pass/fail indicators
- Proper cleanup of all resources
- Tests added to run_all_tests.sh
```

---

## 💡 Prompt Optimization Tips

### For Maximum Coverage:

```
Primary goal: Maximize test coverage of critical paths to 95%+

Read these files first:
1. handoff-testing.md
2. ralph-refactor/tests/TEST_PLAN.md (see "Missing Tests" section)
3. ralph-refactor/tests/test_git.sh (use as template)

Priority order:
1. test_core.sh - 6 tests (highest impact, core functionality)
2. test_monitor.sh - 5 tests (high impact, process tracking)
3. test_worker.sh - 6 tests (medium impact, worker management)
4. test_scheduler.sh - 4 tests (medium impact, task scheduling)
5. Integration tests - 2 suites (validates end-to-end)

Work systematically through each component. After each test file:
- Run full test suite (./run_all_tests.sh)
- Verify all existing tests still pass
- Add new test to TEST_SUITES array in run_all_tests.sh
- Update coverage metrics in TEST_PLAN.md

Target: 40+ total tests, 95%+ coverage, all passing.
```

### For Speed (Quick Wins):

```
Quick task: Wire branch normalization into ralph-swarm (5 minutes)

1. Read handoff-testing.md "Priority 0" section
2. Open ralph-refactor/ralph-swarm
3. Find line ~236 (before worker branch creation)
4. Add the normalization code (see handoff-testing.md)
5. Test with: ./ralph-refactor/ralph-swarm --devplan test.md --workers 2

This completes a TODO from handoff1.md and improves branch handling.
Then continue with test_core.sh implementation.
```

### For Quality Focus:

```
Focus on test quality and maintainability.

Tasks:
1. Review all existing tests for consistency
2. Add edge case tests to existing suites
3. Implement test_core.sh with comprehensive scenarios
4. Add negative test cases (error handling)
5. Create stress tests for database concurrency
6. Document testing best practices

Goal: Not just coverage, but robust, maintainable test suite.
Read TEST_PLAN.md "Test Quality Standards" section.
```

---

## 🎓 Prompt Engineering Best Practices

### ✅ DO Include:
- **Context files to read first** (handoff-testing.md, TEST_PLAN.md)
- **Current status** (21 tests passing, 81% coverage)
- **Specific tasks** (create test_core.sh with 6 tests)
- **Success criteria** (all tests pass, coverage increases to X%)
- **Template to follow** (use test_git.sh as pattern)
- **Standards to maintain** (idempotent, isolated, fast)

### ❌ DON'T Include:
- Vague instructions ("improve testing")
- No context about current state
- Ambiguous goals ("make it better")
- No reference to existing patterns
- Unrealistic expectations ("100% coverage in 1 hour")

---

## 📊 Expected Outcomes by Prompt Type

### Unit Test Prompt → Expected Results:
- ✅ 2 new test files created (test_core.sh, test_monitor.sh)
- ✅ 11 new tests added (6 + 5)
- ✅ Total: 32 tests, ~88% coverage
- ✅ Time: 4-6 hours
- ✅ All tests passing

### Integration Test Prompt → Expected Results:
- ✅ 2 integration test files created
- ✅ End-to-end scenarios validated
- ✅ Confidence in production readiness
- ✅ Time: 4-5 hours
- ✅ May find integration bugs (good!)

### Quick Win Prompt → Expected Results:
- ✅ Branch normalization wired in
- ✅ 1 TODO from handoff1.md completed
- ✅ Time: 5-10 minutes
- ✅ Can proceed to larger tasks

---

## 🎯 Recommended Full Prompt (Copy This)

```
Please help me continue the automated testing implementation for Ralphussy.

STEP 1 - READ THESE FILES FIRST (CRITICAL):
1. /home/mojo/projects/ralphussy/handoff-testing.md (start here - overview)
2. /home/mojo/projects/ralphussy/ralph-refactor/tests/TEST_PLAN.md (detailed specs)
3. /home/mojo/projects/ralphussy/ralph-refactor/tests/test_git.sh (your template)

STEP 2 - UNDERSTAND CURRENT STATE:
- Branch: fix/swarm-devplan-branch-handling
- Tests passing: 21/21 (100%)
- Coverage: 81% of critical paths
- Test suites complete: json, devplan, swarm, git
- Infrastructure: test runner, CI/CD, docs all ready

STEP 3 - YOUR MISSION:
Implement the next priority test suites to reach 90%+ coverage:

Priority 1: test_core.sh (6 tests, ~2-3 hours)
- Test configuration loading and defaults
- Test OpenCode execution wrapper (_ralph_execute_opencode)
- Test token/cost tracking (RALPH_LAST_*)
- Test completion promise detection
- Test state file management (state.json, history.json)
- Test logging functions and log rotation

Priority 2: test_monitor.sh (5 tests, ~2 hours)
- Test monitor start/stop lifecycle
- Test OpenCode process detection (monitor_is_opencode_running)
- Test log file tracking (find_latest_log)
- Test activity detection and idle timeout
- Test monitor cleanup and control files

STEP 4 - REQUIREMENTS:
✅ Follow the pattern from test_git.sh exactly
✅ Use unique temp directories: TEST_RUN_DIR="/tmp/test_$(date +%s%N)"
✅ Make tests idempotent (can run multiple times)
✅ Make tests fast (<10 seconds each)
✅ Use ✅ for pass, ❌ for fail
✅ Clean up all temp resources
✅ Add new tests to run_all_tests.sh TEST_SUITES array
✅ Run full suite after each file: ./run_all_tests.sh

STEP 5 - SUCCESS CRITERIA:
✅ All 21 existing tests still pass
✅ 11 new tests added (6 + 5)
✅ Total: 32 tests passing
✅ Coverage reaches ~88-90%
✅ Full suite completes in <15 seconds
✅ TEST_PLAN.md updated with completion status

STEP 6 - DELIVERABLES:
1. ralph-refactor/tests/test_core.sh (working and passing)
2. ralph-refactor/tests/test_monitor.sh (working and passing)
3. Updated ralph-refactor/tests/run_all_tests.sh (new tests added)
4. Updated ralph-refactor/tests/TEST_PLAN.md (mark completed)
5. New handoff document for next agent

METHODOLOGY:
- Use ZAI coding plan approach (zai-coding-plan/glm-4.7)
- Work systematically (core first, then monitor)
- Test incrementally (run suite after each component)
- Document as you go
- Ask questions if specifications unclear

Please start by reading handoff-testing.md, then proceed with test_core.sh implementation.
```

---

## 🚀 Copy-Paste Ready

**For immediate use, copy this exact prompt:**

```
Read /home/mojo/projects/ralphussy/handoff-testing.md and implement the Priority 1 tasks:

1. Create ralph-refactor/tests/test_core.sh (6 tests for core.sh)
2. Create ralph-refactor/tests/test_monitor.sh (5 tests for monitor.sh)

Use ralph-refactor/tests/test_git.sh as your template. Follow the test pattern exactly.

Requirements: idempotent, isolated, fast (<10s each), clean output (✅/❌)

Success: 32 total tests passing, 88%+ coverage, full suite <15 seconds

See ralph-refactor/tests/TEST_PLAN.md for detailed test specifications.

Run ./run_all_tests.sh after each component to verify no regressions.
```

---

This ensures the next agent has maximum context and clear direction! 🎯
