# Core configuration, logging, and state helpers for ralph.
#
# This file is sourced by ../ralph. It intentionally holds the stable, shared
# plumbing so that most edits don't touch the main entrypoint.

if [ -n "${RALPH_CORE_LOADED-}" ]; then
    return 0
fi
RALPH_CORE_LOADED=1

# ---------------------------------------------------------------------------
# Configuration

RALPH_DIR="${RALPH_DIR:-$HOME/.ralph}"
STATE_FILE="$RALPH_DIR/state.json"
HISTORY_FILE="$RALPH_DIR/history.json"
LOG_DIR="$RALPH_DIR/logs"
CONTEXT_FILE="$RALPH_DIR/context.md"
PROGRESS_FILE="$RALPH_DIR/progress.md"
HANDOFF_FILE="${HANDOFF_FILE:-./handoff.md}"
AGENT_FILE="${AGENT_FILE:-./agent.md}"
DEVPATH="${DEVPATH:-./devplan.md}"
DOCS_PATH="${DOCS_PATH:-./docs/progress.md}"
BLOCKERS_FILE="$RALPH_DIR/blockers.txt"

# Background runs (detach/attach)
RUNS_DIR="$RALPH_DIR/runs"
CURRENT_RUN_FILE="$RUNS_DIR/current"
PROMPT_FILE=""

# Default settings
MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
COMPLETION_PROMISE="${COMPLETION_PROMISE:-COMPLETE}"
VERBOSE="${VERBOSE:-false}"
MODEL="${MODEL:-}"
PROVIDER="${PROVIDER:-}"

# Simple task threshold - tasks estimated under this complexity can be batched
SIMPLE_TASK_THRESHOLD="${SIMPLE_TASK_THRESHOLD:-2}"

# ---------------------------------------------------------------------------
# Colors + logging

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[RALPH]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[RALPH]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[RALPH]${NC} $1"
}

log_error() {
    echo -e "${RED}[RALPH]${NC} $1"
}

# ---------------------------------------------------------------------------
# Init / shared helpers

init_ralph() {
    mkdir -p "$RALPH_DIR" "$LOG_DIR" "$RUNS_DIR"

    # Initialize state file
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << EOF
{
  "status": "idle",
  "iteration": 0,
  "prompt": "",
  "start_time": null,
  "last_activity": null,
  "context": ""
}
EOF
    fi

    # Initialize history file
    if [ ! -f "$HISTORY_FILE" ]; then
        cat > "$HISTORY_FILE" << EOF
{
  "iterations": [],
  "total_time": 0,
  "success": false
}
EOF
    fi

    # Initialize progress file
    if [ ! -f "$PROGRESS_FILE" ]; then
        echo "# Ralph Progress Log" > "$PROGRESS_FILE"
        echo "" >> "$PROGRESS_FILE"
    fi

    # Initialize blockers file
    if [ ! -f "$BLOCKERS_FILE" ]; then
        touch "$BLOCKERS_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Background runs (detach/attach)

new_run_id() {
    date -u +"%Y%m%d_%H%M%S"
}

run_log_path() {
    local run_id="$1"
    echo "$RUNS_DIR/run_${run_id}.log"
}

run_pid_path() {
    local run_id="$1"
    echo "$RUNS_DIR/run_${run_id}.pid"
}

set_current_run() {
    local run_id="$1"
    mkdir -p "$RUNS_DIR" 2>/dev/null || true
    printf '%s' "$run_id" > "$CURRENT_RUN_FILE" 2>/dev/null || true
}

get_current_run() {
    if [ -f "$CURRENT_RUN_FILE" ]; then
        cat "$CURRENT_RUN_FILE" 2>/dev/null || true
    fi
}

attach_current_run() {
    local run_id
    run_id=$(get_current_run)
    if [ -z "$run_id" ]; then
        log_warning "No current run. Start one with: ralph2 --detach ..."
        return 1
    fi

    local log_path
    log_path=$(run_log_path "$run_id")
    if [ ! -f "$log_path" ]; then
        log_warning "Current run log not found: $log_path"
        return 1
    fi

    log_info "Attaching to run $run_id (Ctrl+C detaches, does not stop run)"
    tail -n 200 -f "$log_path"
}

stop_current_run() {
    local run_id
    run_id=$(get_current_run)
    if [ -z "$run_id" ]; then
        log_warning "No current run to stop."
        return 1
    fi

    local pid_path
    pid_path=$(run_pid_path "$run_id")
    if [ ! -f "$pid_path" ]; then
        log_warning "No pid file for run $run_id ($pid_path)"
        return 1
    fi

    local pid
    pid=$(cat "$pid_path" 2>/dev/null || true)
    if [ -z "$pid" ]; then
        log_warning "Empty pid file: $pid_path"
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping run $run_id (pid $pid)..."

        # Prefer process-group termination when possible (the nohup-launched
        # script often becomes its own process group leader).
        kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true

        # Give it a moment to exit cleanly.
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Run $run_id did not exit after SIGTERM; sending SIGKILL"
            kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        fi

        return 0
    fi

    log_warning "Run $run_id pid $pid is not running."
    return 1
}

list_runs() {
    mkdir -p "$RUNS_DIR" 2>/dev/null || true

    local current
    current=$(get_current_run)

    echo "[RALPH] Runs directory: $RUNS_DIR"
    if [ -n "$current" ]; then
        echo "[RALPH] Current run: $current"
    else
        echo "[RALPH] Current run: (none)"
    fi

    ls -1 "$RUNS_DIR" 2>/dev/null | grep -E '^run_.*\.(log|pid)$' | sort || true
}

# Escape special regex characters for sed patterns
escape_sed_pattern() {
    local text="$1"
    # Escape characters that are meaningful in sed regexes so the result can
    # be safely used in a sed search pattern. Escape backslash first.
    printf '%s' "$text" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/\./\\./g' \
        -e 's/\*/\\*/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/\^/\\^/g' \
        -e 's/\$/\\$/g' \
        -e 's/&/\\&/g' \
        -e 's/|/\\|/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/+/\\+/g' \
        -e 's/?/\\?/g' \
        -e 's,/,\\/,g'
}

# ---------------------------------------------------------------------------
# Blockers

record_blocker() {
    local task="$1"
    local blocker="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "[$timestamp] $task: $blocker" >> "$BLOCKERS_FILE"
    log_warning "🚫 Blocker recorded: $task - $blocker"
}

get_blockers() {
    cat "$BLOCKERS_FILE"
}

clear_blockers() {
    local task="$1"
    local temp_file="$BLOCKERS_FILE.tmp"

    if [ -f "$BLOCKERS_FILE" ]; then
        grep -v "^.*$task.*:" "$BLOCKERS_FILE" > "$temp_file" 2>/dev/null || true
        mv "$temp_file" "$BLOCKERS_FILE"
    fi
}

show_blockers() {
    if [ -f "$BLOCKERS_FILE" ] && [ -s "$BLOCKERS_FILE" ]; then
        echo ""
        echo "🚫 ACTIVE BLOCKERS:"
        cat "$BLOCKERS_FILE" | while read -r line; do
            echo "   $line"
        done
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Docs / progress

update_docs() {
    local message="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create docs directory if needed
    local docs_dir
    docs_dir=$(dirname "$DOCS_PATH")
    mkdir -p "$docs_dir" 2>/dev/null || true

    # Append to docs progress file
    echo "[$timestamp] $message" >> "$DOCS_PATH" 2>/dev/null || true

    log_info "📝 Documentation updated: $message"

    # Auto-commit agent.md on successful task completion
    if echo "$message" | grep -q "Completed.*task"; then
        if git rev-parse --git-dir >/dev/null 2>&1; then
            if [ -f "$AGENT_FILE" ]; then
                log_info "📦 Committing agent.md..."
                git add "$AGENT_FILE" 2>/dev/null || true
                git commit -m "Ralph: $message" 2>/dev/null && log_success "✅ agent.md committed" || log_warning "⚠️ Could not commit agent.md"
            fi
        fi
    fi
}

update_devplan_progress() {
    local devpath="$1"
    local iteration="$2"
    local status="$3"
    local task="$4"

    if [ ! -f "$devpath" ]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local progress_entry="- **$timestamp**: $status - $task"

    # Insert the progress entry after the first top-level '### ' heading, if present.
    # Otherwise append to the top of the file.
    local temp_file="${devpath}.progress.tmp"
    awk -v entry="$progress_entry" '
    BEGIN { inserted=0 }
    /^### / && !inserted {
      print
      print entry
      inserted=1
      next
    }
    { print }
    END { if (!inserted) print entry }
    ' "$devpath" > "$temp_file" && mv "$temp_file" "$devpath"
}

log_progress() {
    local iteration="$1"
    local task="$2"
    local result="$3"
    local duration="$4"

    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Iteration $iteration: $task - $result (${duration}s)" >> "$PROGRESS_FILE"
}

# ---------------------------------------------------------------------------
# Handoff system

create_handoff() {
    local completed_task="$1"
    local next_task="$2"
    local devfile="$3"
    local notes="${4:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_info "📋 Creating handoff for next Ralph..."

    cat > "$HANDOFF_FILE" << EOF
# Ralph Handoff

**Created**: $timestamp
**DevPlan**: $devfile

## Just Completed
- $completed_task

## Next Task
- $next_task

## Context & Notes
$notes

## Important Files Modified
$(git diff --name-only HEAD~1 2>/dev/null | head -20 | sed 's/^/- /' || echo "- (no git history available)")

## Current DevPlan Status
\`\`\`
$(grep -E '^[ ]*- \[' "$devfile" 2>/dev/null | head -20 || echo "No tasks found")
\`\`\`

## Instructions for Next Ralph
1. Read this handoff to understand context
2. Read the devplan at: $devfile
3. Work on the next task listed above
4. When complete, update devplan and create new handoff
5. Output \`<promise>COMPLETE</promise>\` when task is done

---
*This handoff was auto-generated by Ralph to maintain context across fresh sessions.*
EOF

    log_success "📋 Handoff created: $HANDOFF_FILE"
}

read_handoff() {
    if [ -f "$HANDOFF_FILE" ]; then
        cat "$HANDOFF_FILE"
    else
        echo ""
    fi
}

has_handoff() {
    [ -f "$HANDOFF_FILE" ] && [ -s "$HANDOFF_FILE" ]
}

archive_handoff() {
    if [ -f "$HANDOFF_FILE" ]; then
        local archive_dir="$RALPH_DIR/handoffs"
        mkdir -p "$archive_dir"
        local timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        cp "$HANDOFF_FILE" "$archive_dir/handoff_$timestamp.md"
    fi
}

# ---------------------------------------------------------------------------
# Dependencies

check_opencode() {
    if ! command -v opencode &> /dev/null; then
        log_error "OpenCode is not installed. Please install it first:"
        echo "  curl -fsSL https://opencode.ai/install | bash"
        exit 1
    fi
    log_success "OpenCode found: $(which opencode)"
}

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_warning "Optional tool 'jq' not found — JSON parsing will fall back to slower, less-robust methods. Install jq for best results (apt/yum/brew install jq)."
    else
        log_info "jq found: $(which jq)"
    fi
}

# ---------------------------------------------------------------------------
# State + context

get_state() {
    cat "$STATE_FILE"
}

update_state() {
    local status="$1"
    local iteration="$2"
    local prompt="$3"
    local context="$4"

    local start_time
    start_time=$(get_state | grep -o '"start_time": *"[^"]*"' | cut -d'"' -f4)
    if [ "$status" = "running" ] && [ -z "$start_time" ] || [ "$start_time" = "null" ]; then
        start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi

    cat > "$STATE_FILE" << EOF
{
  "status": "$status",
  "iteration": $iteration,
  "prompt": "$(echo "$prompt" | sed 's/"/\\"/g')",
  "start_time": "$start_time",
  "last_activity": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "context": "$(echo "$context" | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF
}

add_context() {
    local context="$1"
    echo "$context" >> "$CONTEXT_FILE"
    log_info "Context added for next iteration"
}

get_and_clear_context() {
    if [ -f "$CONTEXT_FILE" ] && [ -s "$CONTEXT_FILE" ]; then
        local context
        context=$(cat "$CONTEXT_FILE")
        rm -f "$CONTEXT_FILE"
        echo "$context"
    fi
}
