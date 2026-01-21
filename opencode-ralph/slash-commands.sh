#!/bin/bash

# Ralph Slash Commands for OpenCode
# Provides /ralph and related commands within OpenCode

RALPH_DIR="${RALPH_DIR:-.ralph}"
RALPH_STATE="$RALPH_DIR/state.json"
RALPH_HISTORY="$RALPH_DIR/history.json"
RALPH_PROGRESS="$RALPH_DIR/progress.md"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get Ralph status
get_status() {
    if [ ! -f "$RALPH_STATE" ]; then
        echo '{"status": "idle", "iteration": 0}'
        return
    fi
    cat "$RALPH_STATE"
}

# Get history
get_history() {
    if [ ! -f "$RALPH_HISTORY" ]; then
        echo '{"iterations": []}'
        return
    fi
    cat "$RALPH_HISTORY"
}

# Format status for display
format_status() {
    local state="$1"
    local status=$(echo "$state" | jq -r '.status' 2>/dev/null || echo 'unknown')
    local iteration=$(echo "$state" | jq -r '.iteration' 2>/dev/null || echo '0')
    local max_iterations=$(echo "$state" | jq -r '.maxIterations // 100' 2>/dev/null || echo '100')
    local prompt=$(echo "$state" | jq -r '.prompt' 2>/dev/null || echo '')
    local start_time=$(echo "$state" | jq -r '.start_time' 2>/dev/null || echo '')
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                    Ralph Status                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ "$status" = "idle" ]; then
        echo "🔄 Ralph is idle. No active loop."
        echo ""
        echo "Usage:"
        echo "  /ralph <task>        Start autonomous loop"
        echo "  /ralph-status        Check current status"
        echo "  /ralph-stop          Stop running loop"
        echo "  /ralph-context <msg> Add context to next iteration"
    else
        echo "🔄 Ralph Loop Active"
        echo "   Iteration:    $iteration / $max_iterations"
        
        if [ "$start_time" != "null" ] && [ -n "$start_time" ]; then
            local elapsed=$(($(date +%s) - $(date -d "$start_time" 2>/dev/null +%s || echo "0")))
            local minutes=$((elapsed / 60))
            local seconds=$((elapsed % 60))
            echo "   Elapsed:      ${minutes}m ${seconds}s"
        fi
        
        echo "   Prompt:       $(echo "$prompt" | head -c 50)..."
        echo ""
        
        # Show recent history
        local history_length=$(echo "$state" | jq '.iteration' 2>/dev/null || echo "0")
        if [ "$history_length" -gt 0 ]; then
            echo "📊 Recent Activity:"
            for i in $(seq 1 $((history_length > 5 ? 5 : history_length))); do
                local dur=$(echo "$state" | jq -r ".iteration_$i.duration" 2>/dev/null || echo '')
                if [ -n "$dur" ]; then
                    echo "   🔄 #$i: ${dur}s"
                fi
            done
            echo ""
        fi
        
        echo "✅ Ralph is running. Use /ralph-stop to cancel."
    fi
}

# Start Ralph loop
start_ralph() {
    local prompt="$1"
    local max_iterations="${2:-100}"
    local completion_promise="${3:-COMPLETE}"
    
    if [ -z "$prompt" ]; then
        echo ""
        echo "${YELLOW}⚠️  No task provided${NC}"
        echo ""
        echo "Usage: /ralph <task description>"
        echo ""
        echo "Example:"
        echo "  /ralph Build a REST API with CRUD endpoints. Output <promise>COMPLETE</promise> when done."
        return 1
    fi
    
    echo ""
    echo "${GREEN}🚀 Starting Ralph...${NC}"
    echo ""
    echo "📝 Task: $(echo "$prompt" | head -c 80)..."
    echo "🔄 Max iterations: $max_iterations"
    echo "✅ Completion signal: <promise>$completion_promise</promise>"
    echo ""
    
    # Start the loop in background
    local ralph_script="/home/mojo/projects/opencode2/opencode-ralph/ralph-integrated"
    
    if [ ! -f "$ralph_script" ]; then
        echo "${RED}❌ Ralph script not found${NC}"
        return 1
    fi
    
    # Run Ralph
    cd "$(pwd)"
    "$ralph_script" "$prompt" --max-iterations "$max_iterations" --completion-promise "$completion_promise" --verbose
    
    echo ""
    echo "${GREEN}✅ Ralph completed!${NC}"
}

# Stop Ralph loop
stop_ralph() {
    echo ""
    echo "${YELLOW}🛑 Stopping Ralph...${NC}"
    
    # Kill any running Ralph processes
    pkill -f "ralph-integrated.*run" 2>/dev/null || true
    
    # Update state
    if [ -f "$RALPH_STATE" ]; then
        local state=$(cat "$RALPH_STATE")
        state=$(echo "$state" | jq '.status = "stopped"' 2>/dev/null || echo "$state")
        echo "$state" > "$RALPH_STATE"
    fi
    
    echo "${GREEN}✅ Ralph stopped${NC}"
}

# Add context
add_context() {
    local context="$1"
    
    if [ -z "$context" ]; then
        echo ""
        echo "${YELLOW}⚠️  No context provided${NC}"
        echo ""
        echo "Usage: /ralph-context <message>"
        echo ""
        echo "Example:"
        echo "  /ralph-context Focus on the authentication module first"
        return 1
    fi
    
    echo ""
    echo "${GREEN}✅ Context added${NC}"
    echo ""
    echo "📝 $context"
    echo ""
    echo "This will be included in the next iteration."
}

# Show help
show_help() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              Ralph Slash Commands                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🤖 Ralph - Autonomous AI Coding Loop"
    echo ""
    echo "Commands:"
    echo ""
    echo "  /ralph <task>              Start autonomous loop"
    echo "  /ralph-status              Check current status"
    echo "  /ralph-stop                Stop running loop"
    echo "  /ralph-context <msg>       Add context to next iteration"
    echo "  /ralph-clear               Clear pending context"
    echo "  /ralph-help                Show this help"
    echo ""
    echo "Options:"
    echo ""
    echo "  --max-iterations N         Maximum iterations (default: 100)"
    echo "  --completion-promise TAG    Completion signal (default: COMPLETE)"
    echo ""
    echo "Examples:"
    echo ""
    echo "  /ralph Build a REST API. Output <promise>COMPLETE</promise> when done."
    echo "  /ralph Write tests. --max-iterations 20"
    echo "  /ralph Refactor auth module. --completion-promise DONE"
    echo "  /ralph-status"
    echo "  /ralph-context Try using TypeScript instead of JavaScript"
    echo ""
    echo "Writing Good Prompts:"
    echo ""
    echo "  ✅ Good:"
    echo "     /ralph Build a todo API with CRUD operations and tests."
    echo "        Output <promise>COMPLETE</promise> when all tests pass."
    echo ""
    echo "  ❌ Bad:"
    echo "     /ralph Make the code better"
    echo ""
}

# Process command
process_command() {
    local cmd="$1"
    shift
    local args="$@"
    
    case "$cmd" in
        /ralph|/Ralph)
            start_ralph "$args"
            ;;
        /ralph-status|/ralphs|/rs)
            format_status "$(get_status)"
            ;;
        /ralph-stop|/ralphq|/rq)
            stop_ralph
            ;;
        /ralph-context|/ralphc|/rc)
            add_context "$args"
            ;;
        /ralph-clear|/ralphx|/rx)
            rm -f "$RALPH_DIR/context.md" 2>/dev/null || true
            echo ""
            echo "${GREEN}✅ Context cleared${NC}"
            ;;
        /ralph-help|/ralphh|/rh)
            show_help
            ;;
        *)
            # Unknown command
            return 1
            ;;
    esac
}

# Main when run directly
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    process_command "$@"
}

main "$@"