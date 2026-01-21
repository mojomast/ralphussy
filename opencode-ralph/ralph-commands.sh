#!/bin/bash

# Ralph Slash Command Integration for OpenCode TUI
# Source this file to enable /ralph commands in OpenCode

RALPH_SCRIPT="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
RALPH_STATE_DIR=".ralph"

# Initialize Ralph state directory
_ralph_init() {
    mkdir -p "$RALPH_STATE_DIR" 2>/dev/null || true
}

# Main slash command handler
_ralph_command() {
    local cmd="$1"
    shift
    local args="$*"
    
    _ralph_init
    
    case "$cmd" in
        ralph)
            _ralph_start "$args"
            ;;
        ralph-status|rs)
            _ralph_status
            ;;
        ralph-stop|rq)
            _ralph_stop
            ;;
        ralph-context|rc)
            _ralph_add_context "$args"
            ;;
        ralph-clear|rx)
            _ralph_clear_context
            ;;
        ralph-help|rh)
            _ralph_help
            ;;
        *)
            return 1
            ;;
    esac
}

# Start Ralph loop
_ralph_start() {
    local prompt="$1"
    local max_iter=100
    local promise="COMPLETE"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-iterations)
                max_iter="$2"
                shift 2
                ;;
            --completion-promise)
                promise="$2"
                shift 2
                ;;
            *)
                prompt="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "$prompt" ]; then
        echo ""
        echo "⚠️  Usage: /ralph <task> [--max-iterations N] [--completion-promise TAG]"
        echo ""
        echo "Example: /ralph Build a REST API. Output <promise>COMPLETE</promise> when done."
        return 1
    fi
    
    echo ""
    echo "🚀 Starting Ralph autonomous loop..."
    echo ""
    echo "📝 Task: $(echo "$prompt" | head -c 60)..."
    echo "🔄 Iterations: $max_iter"
    echo "✅ Signal: <promise>$promise</promise>"
    echo ""
    
    if [ ! -f "$RALPH_SCRIPT" ]; then
        echo "❌ Ralph script not found: $RALPH_SCRIPT"
        return 1
    fi
    
    "$RALPH_SCRIPT" "$prompt" --max-iterations "$max_iter" --completion-promise "$promise"
    
    echo ""
    echo "✅ Ralph completed!"
}

# Show status
_ralph_status() {
    local state_file="$RALPH_STATE_DIR/state.json"
    
    if [ ! -f "$state_file" ]; then
        echo ""
        echo "🔄 No active Ralph loop"
        echo ""
        echo "Use /ralph <task> to start a loop"
        return
    fi
    
    local status=$(cat "$state_file" | jq -r '.status' 2>/dev/null || echo 'unknown')
    local iteration=$(cat "$state_file" | jq -r '.iteration' 2>/dev/null || echo '0')
    local prompt=$(cat "$state_file" | jq -r '.prompt' 2>/dev/null || echo '')
    local start_time=$(cat "$state_file" | jq -r '.start_time' 2>/dev/null || echo '')
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                    Ralph Status                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🔄 Status: $status"
    echo "📊 Iteration: $iteration"
    
    if [ "$start_time" != "null" ] && [ -n "$start_time" ]; then
        local elapsed=$(($(date +%s) - $(date -d "$start_time" 2>/dev/null +%s || echo "0")))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))
        echo "⏱️  Elapsed: ${mins}m ${secs}s"
    fi
    
    echo ""
    echo "📝 Prompt: $(echo "$prompt" | head -c 80)..."
    echo ""
    
    if [ -f "$RALPH_STATE_DIR/history.json" ]; then
        local count=$(cat "$RALPH_STATE_DIR/history.json" | jq '.iterations | length' 2>/dev/null || echo '0')
        if [ "$count" -gt 0 ]; then
            echo "📊 Recent iterations:"
            cat "$RALPH_STATE_DIR/history.json" | jq -r '.iterations[-5:] | .[] | "   🔄 #\(.iteration): \(.duration)s | \(.tools_used)"' 2>/dev/null || true
            echo ""
        fi
    fi
}

# Stop Ralph
_ralph_stop() {
    echo ""
    echo "🛑 Stopping Ralph..."
    
    # Kill Ralph processes
    pkill -f "ralph-integrated" 2>/dev/null || true
    
    # Update state
    if [ -f "$RALPH_STATE_DIR/state.json" ]; then
        cat "$RALPH_STATE_DIR/state.json" | jq '.status = "stopped"' > "$RALPH_STATE_DIR/state.json.tmp" 2>/dev/null
        mv "$RALPH_STATE_DIR/state.json.tmp" "$RALPH_STATE_DIR/state.json" 2>/dev/null || true
    fi
    
    echo "✅ Ralph stopped"
}

# Add context
_ralph_add_context() {
    local context="$*"
    
    if [ -z "$context" ]; then
        echo ""
        echo "⚠️  Usage: /ralph-context <message>"
        echo ""
        echo "Example: /ralph-context Focus on the auth module"
        return 1
    fi
    
    echo "$context" >> "$RALPH_STATE_DIR/context.md"
    
    echo ""
    echo "✅ Context added"
    echo ""
    echo "📝 $context"
    echo ""
    echo "This will be included in the next iteration."
}

# Clear context
_ralph_clear_context() {
    rm -f "$RALPH_STATE_DIR/context.md" 2>/dev/null || true
    
    echo ""
    echo "✅ Context cleared"
}

# Show help
_ralph_help() {
    cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════╗
║              Ralph Slash Commands for OpenCode                    ║
╚═══════════════════════════════════════════════════════════════════╝

🤖 Ralph - Autonomous AI Coding Loop Agent

COMMANDS:
  
  /ralph <task>              Start autonomous loop
  /ralph-status              Check current status
  /ralph-stop                Stop running loop
  /ralph-context <msg>       Add context to next iteration
  /ralph-clear               Clear pending context
  /ralph-help                Show this help

SHORT FORMS:
  
  /r                         Same as /ralph
  /rs                        Same as /ralph-status
  /rq                        Same as /ralph-stop
  /rc                        Same as /ralph-context
  /rx                        Same as /ralph-clear
  /rh                        Same as /ralph-help

OPTIONS:

  --max-iterations N         Maximum iterations (default: 100)
  --completion-promise TAG   Completion signal (default: COMPLETE)

EXAMPLES:

  # Start a simple task
  /ralph Create hello.txt. Output <promise>COMPLETE</promise> when done.

  # Build with more iterations
  /ralph Build a REST API with tests. Output <promise>COMPLETE</promise> when done. --max-iterations 20

  # With custom completion signal
  /ralph Refactor the code. Output <promise>DONE</promise> when complete.

  # Add guidance mid-loop
  /rc Focus on fixing the authentication first

  # Check progress
  /rs

WRITING GOOD PROMPTS:

  ✅ Good:
     "Build a REST API with CRUD endpoints. Output <promise>COMPLETE</promise> when all tests pass."

  ❌ Bad:
     "Make the code better"

TIPS:

  • Set clear success criteria
  • Include verification steps
  • Use <promise>TAG</promise> to signal completion
  • Monitor with /ralph-status
  • Guide stuck agents with /ralph-context

EOF
}

# Export for use in OpenCode
export -f _ralph_command 2>/dev/null || true
export -f _ralph_init 2>/dev/null || true
export -f _ralph_start 2>/dev/null || true
export -f _ralph_status 2>/dev/null || true
export -f _ralph_stop 2>/dev/null || true
export -f _ralph_add_context 2>/dev/null || true
export -f _ralph_clear_context 2>/dev/null || true
export -f _ralph_help 2>/dev/null || true

# If run directly, show help
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _ralph_help
fi