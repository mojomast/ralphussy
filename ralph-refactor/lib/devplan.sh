# Devplan helpers (task parsing, state updates, stall detection, devplan runs).

has_pending_tasks() {
    local devpath="$1"

    if [ ! -f "$devpath" ]; then
        return 1
    fi

    # Check for any pending tasks ([ ] or ⏳)
    if grep -qE '^[ ]*- \[ \]|^[ ]*- \[⏳\]|^[ ]*- ⏳' "$devpath" 2>/dev/null; then
        return 0  # Has pending tasks
    fi

    return 1  # No pending tasks
}

count_devplan_tasks() {
    local devpath="$1"

    if [ ! -f "$devpath" ]; then
        echo "0 0 0 0"
        return 1
    fi

    local pending
    pending=$(grep -cE '^[ ]*- \[ \]' "$devpath" 2>/dev/null || true)
    [ -z "$pending" ] && pending=0
    local in_progress
    in_progress=$(grep -cE '^[ ]*- \[⏳\]|^[ ]*- ⏳' "$devpath" 2>/dev/null || true)
    [ -z "$in_progress" ] && in_progress=0
    local completed
    completed=$(grep -cE '^[ ]*- \[✅\]|^[ ]*- ✅' "$devpath" 2>/dev/null || true)
    [ -z "$completed" ] && completed=0
    local needs_review
    needs_review=$(grep -cE '^[ ]*- \[🔄\]|^[ ]*- 🔄' "$devpath" 2>/dev/null || true)
    [ -z "$needs_review" ] && needs_review=0

    # Ensure all values are numbers
    pending=${pending//[^0-9]/}
    in_progress=${in_progress//[^0-9]/}
    completed=${completed//[^0-9]/}
    needs_review=${needs_review//[^0-9]/}

    echo "$pending $in_progress $completed $needs_review"
}

get_next_pending_task() {
    local devpath="$1"
    if [ ! -f "$devpath" ]; then
        echo ""
        return 1
    fi

    # Find first pending task (marked with ⏳ or unchecked)
    # Devplan uses format: - [✅] task or - ⏳ task or - [ ] task
    # Skip tasks marked with [🔄] (needs review)
    local task
    task=$(awk '
    /^[ ]*- \[🔄\]/ { next }
    /^[ ]*- 🔄/ { next }
    /^[ ]*- \[✅\]/ { next }
    /^[ ]*- \[⏳\]/ {
        sub(/^[ ]*- \[⏳\] /, "")
        gsub(/^\s+|\s+$/, "")
        print
        exit
    }
    /^[ ]*- ⏳/ {
        sub(/^[ ]*- ⏳ /, "")
        gsub(/^\s+|\s+$/, "")
        print
        exit
    }
    /^[ ]*- \[ \]/ {
        sub(/^[ ]*- \[ \] /, "")
        gsub(/^\s+|\s+$/, "")
        print
        exit
    }
    ' "$devpath")

    echo "$task"
}

get_all_tasks_with_states() {
    local devpath="$1"
    if [ ! -f "$devpath" ]; then
        echo ""
        return 1
    fi

    awk '
    /^[ ]*- \[✅\]/ {
        sub(/^[ ]*- \[✅\] /, "")
        gsub(/^\s+|\s+$/, "")
        print "complete: " $0
    }
    /^[ ]*- ✅/ {
        sub(/^[ ]*- ✅ /, "")
        gsub(/^\s+|\s+$/, "")
        print "complete: " $0
    }
    /^[ ]*- \[⏳\]/ {
        sub(/^[ ]*- \[⏳\] /, "")
        gsub(/^\s+|\s+$/, "")
        print "in_progress: " $0
    }
    /^[ ]*- ⏳/ {
        sub(/^[ ]*- ⏳ /, "")
        gsub(/^\s+|\s+$/, "")
        print "in_progress: " $0
    }
    /^[ ]*- \[🔄\]/ {
        sub(/^[ ]*- \[🔄\] /, "")
        gsub(/<!--.*-->/, "")
        gsub(/^\s+|\s+$/, "")
        print "needs_review: " $0
    }
    /^[ ]*- 🔄/ {
        sub(/^[ ]*- 🔄 /, "")
        gsub(/<!--.*-->/, "")
        gsub(/^\s+|\s+$/, "")
        print "needs_review: " $0
    }
    /^[ ]*- \[ \]/ {
        sub(/^[ ]*- \[ \] /, "")
        gsub(/^\s+|\s+$/, "")
        print "pending: " $0
    }
    ' "$devpath"
}

mark_task_in_progress() {
    local devpath="$1"
    local task="$2"

    if [ ! -f "$devpath" ]; then
        return 1
    fi

    # Use awk to perform an exact, literal match update to avoid sed regex pitfalls.
    # This replaces the first matching pending/completed line containing the exact
    # task text with the in-progress marker while preserving indentation.
    awk -v task="$task" '
    BEGIN { updated=0 }
    {
      line = $0
      if (!updated) {
        # strip leading indentation
        match(line, /^[ \t]*/)
        indent = substr(line, RSTART, RLENGTH)
        body = substr(line, RLENGTH+1)
        # possible prefixes: - [ ] , - ✅ , - ⏳ , - [🔄] etc.
        if (body ~ /^- (\[[ ]\]|\[⏳\]|⏳|\[🔄\]|🔄|\[✅\]|✅) /) {
          # remove checkbox/prefix for comparison
          gsub(/^(- (\[[^]]*\]|[⏳✅🔄]) )/, "", body)
          if (body == task) {
            print indent "- [⏳] " task
            updated=1
            next
          }
        }
      }
      print $0
    }
    END { if (updated==0) exit 0 }
    ' "$devpath" > "${devpath}.tmp" && mv "${devpath}.tmp" "$devpath" 2>/dev/null || true
}

mark_task_complete() {
    local devpath="$1"
    local task="$2"

    if [ ! -f "$devpath" ]; then
        return 1
    fi

    # Use awk to mark the exact task as complete in a safe way.
    awk -v task="$task" '
    BEGIN { updated=0 }
    {
      line = $0
      if (!updated) {
        match(line, /^[ \t]*/)
        indent = substr(line, RSTART, RLENGTH)
        body = substr(line, RLENGTH+1)
        if (body ~ /^- (\[[ ]\]|\[⏳\]|⏳|\[🔄\]|🔄|\[✅\]|✅) /) {
          gsub(/^(- (\[[^]]*\]|[⏳✅🔄]) )/, "", body)
          if (body == task) {
            print indent "- [✅] " task
            updated=1
            next
          }
        }
      }
      print $0
    }
    END { if (updated==0) exit 0 }
    ' "$devpath" > "${devpath}.tmp" && mv "${devpath}.tmp" "$devpath" 2>/dev/null || true
}

mark_task_needs_review() {
    local devpath="$1"
    local task="$2"
    local reason="${3:-}"

    if [ ! -f "$devpath" ]; then
        return 1
    fi

    # Use awk to mark the task as needing review and optionally append a reason
    awk -v task="$task" -v reason="$reason" '
    BEGIN { updated=0 }
    {
      line = $0
      if (!updated) {
        match(line, /^[ \t]*/)
        indent = substr(line, RSTART, RLENGTH)
        body = substr(line, RLENGTH+1)
        if (body ~ /^- (\[[ ]\]|\[⏳\]|⏳|\[🔄\]|🔄|\[✅\]|✅) /) {
          gsub(/^(- (\[[^]]*\]|[⏳✅🔄]) )/, "", body)
          if (body == task) {
            out = indent "- [🔄] " task
            if (reason != "") out = out " <!-- " reason " -->"
            print out
            updated=1
            next
          }
        }
      }
      print $0
    }
    END { if (updated==0) exit 0 }
    ' "$devpath" > "${devpath}.tmp" && mv "${devpath}.tmp" "$devpath" 2>/dev/null || true

    log_info "Task marked as needing review: $task"
}

get_tasks_needing_review() {
    local devpath="$1"
    if [ ! -f "$devpath" ]; then
        echo ""
        return 1
    fi

    # Find all tasks marked with 🔄
    local tasks
    tasks=$(awk '
    /^[ ]*- \[🔄\]/ {
        sub(/^[ ]*- \[🔄\] /, "")
        gsub(/<!--.*-->/, "")  # Remove comments
        gsub(/^\s+|\s+$/, "")
        print
    }
    /^[ ]*- 🔄/ {
        sub(/^[ ]*- 🔄 /, "")
        gsub(/<!--.*-->/, "")  # Remove comments
        gsub(/^\s+|\s+$/, "")
        print
    }
    ' "$devpath")

    echo "$tasks"
}

record_stall_attempt() {
    local task="$1"
    local stall_file="$RALPH_DIR/task_stalls.txt"
    
    # Add timestamp for cleanup (Unix timestamp for easy comparison)
    echo "$(date +%s)|$task" >> "$stall_file"
    
    # Cleanup: Remove entries older than 7 days (604800 seconds)
    if [ -f "$stall_file" ]; then
        local cutoff=$(($(date +%s) - 604800))
        local temp_file="${stall_file}.tmp"
        
        # Only keep recent entries
        if [ -s "$stall_file" ]; then
            while IFS='|' read -r timestamp task_text; do
                # Keep entries newer than cutoff
                if [ "$timestamp" -gt "$cutoff" ] 2>/dev/null; then
                    echo "$timestamp|$task_text" >> "$temp_file"
                fi
            done < "$stall_file"
            
            # Replace old file with cleaned version
            if [ -f "$temp_file" ]; then
                mv "$temp_file" "$stall_file"
            fi
        fi
    fi
}

clear_stall_record() {
    local task="$1"
    local stall_file="$RALPH_DIR/task_stalls.txt"
    local temp_file="$RALPH_DIR/task_stalls_temp.txt"

    if [ -f "$stall_file" ]; then
        # Remove all entries for this task (any timestamp)
        grep -v "|$task$" "$stall_file" > "$temp_file" 2>/dev/null || true
        mv "$temp_file" "$stall_file" 2>/dev/null || true
    fi
}

is_task_stalled() {
    local task="$1"
    local max_attempts="${2:-3}"
    local stall_file="$RALPH_DIR/task_stalls.txt"

    if [ ! -f "$stall_file" ]; then
        return 1
    fi

    # Count recent attempts (from last 7 days only)
    local cutoff=$(($(date +%s) - 604800))
    local attempts=0
    
    while IFS='|' read -r timestamp task_text; do
        if [ "$task_text" = "$task" ] && [ "$timestamp" -gt "$cutoff" ] 2>/dev/null; then
            attempts=$((attempts + 1))
        fi
    done < "$stall_file"

    if [ "$attempts" -ge "$max_attempts" ]; then
        return 0
    fi

    return 1
}

detect_stall() {
    local iteration="$1"
    local output="$2"
    local tools_used="$3"
    local duration="${4:-0}"  # ADD: Capture duration parameter

    # Check for multiple failure indicators
    local stall_indicators=0

    # 1. No file modifications in this iteration
    if ! echo "$tools_used" | grep -qE '(Write|Edit|task)'; then
        stall_indicators=$((stall_indicators + 1))
    fi

    # 2. Output contains stuck/stalled language or timeout
    if echo "$output" | grep -qiE '(cannot|unable|stuck|blocked|failing|error|failed|timeout|not found|command not found)'; then
        stall_indicators=$((stall_indicators + 1))
    fi

    # 3. Bash was used but no file changes (command may have failed/timed out)
    if echo "$tools_used" | grep -qE '(bash|Bash)' && ! echo "$tools_used" | grep -qE '(Write|Edit|task)'; then
        stall_indicators=$((stall_indicators + 1))
    fi

    # 4. No completion promise after multiple retries
    if ! echo "$output" | grep -qiE "<\s*promise\s*>COMPLETE<\s*/\s*promise\s*>"; then
        stall_indicators=$((stall_indicators + 1))
    fi

    # NEW: 5. Duration-based stall detection
    # If task took >300s (5 minutes) but no completion, likely stalled
    if [ "$duration" -gt 300 ] && ! echo "$output" | grep -qiE "<\s*promise\s*>COMPLETE<\s*/\s*promise\s*>"; then
        stall_indicators=$((stall_indicators + 1))
    fi

    # Return stall detected if 2+ indicators present
    if [ "$stall_indicators" -ge 2 ]; then
        return 0
    fi

    return 1
}

generate_stall_reason() {
    local output="$1"
    local tools_used="$2"

    if ! echo "$tools_used" | grep -qE '(Write|Edit|bash|Bash|task)'; then
        echo "no_file_changes"
    elif echo "$output" | grep -qiE '(cannot|unable|blocked)'; then
        echo "blocked_operation"
    elif echo "$output" | grep -qiE '(error|failing|failed|timeout)'; then
        echo "errors_detected"
    else
        echo "stalled_progress"
    fi
}

reset_task_state() {
    local devpath="$1"
    local task="$2"

    if [ ! -f "$devpath" ]; then
        log_error "Devplan file not found: $devpath"
        return 1
    fi

    # Use awk to reset the task state back to pending
    awk -v task="$task" '
    BEGIN { updated=0 }
    {
      line = $0
      if (!updated) {
        match(line, /^[ \t]*/)
        indent = substr(line, RSTART, RLENGTH)
        body = substr(line, RLENGTH+1)
        if (body ~ /^- (\[[^]]*\]|[⏳✅🔄]) /) {
          gsub(/^(- (\[[^]]*\]|[⏳✅🔄]) )/, "", body)
          if (body == task) {
            print indent "- [ ] " task
            updated=1
            next
          }
        }
      }
      print $0
    }
    END { if (updated==0) exit 0 }
    ' "$devpath" > "${devpath}.tmp" && mv "${devpath}.tmp" "$devpath" 2>/dev/null || true

    # Clear stall record
    clear_stall_record "$task"

    log_success "Task reset to pending: $task"
}

show_devplan_summary() {
    local devpath="${1:-./devplan.md}"

    if [ ! -f "$devpath" ]; then
        log_error "Devplan file not found: $devpath"
        return 1
    fi

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                  DevPlan Summary                         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    local tasks
    tasks=$(get_all_tasks_with_states "$devpath")

    # Compute counts using count_devplan_tasks helper
    local counts
    counts=$(count_devplan_tasks "$devpath" 2>/dev/null || echo "0 0 0 0")
    local pending_count
    local in_progress_count
    local complete_count
    local needs_review_count
    pending_count=$(echo "$counts" | cut -d' ' -f1)
    in_progress_count=$(echo "$counts" | cut -d' ' -f2)
    complete_count=$(echo "$counts" | cut -d' ' -f3)
    needs_review_count=$(echo "$counts" | cut -d' ' -f4)
    local total_count=$((pending_count + in_progress_count + complete_count + needs_review_count))

    echo "📋 Total tasks: $total_count"
    echo "   ✅ Complete: $complete_count"
    echo "   ⏳ In Progress: $in_progress_count"
    echo "   🔄 Needs Review: $needs_review_count"
    echo "   [ ] Pending: $pending_count"
    echo ""

    if [ "$needs_review_count" -gt 0 ]; then
        echo "⚠️  Tasks needing review:"
        echo "$tasks" | grep "^needs_review:" | while read -r line; do
            local task
            task=$(echo "$line" | cut -d':' -f2-)
            echo "   🔄 $task"
        done
        echo ""
        echo "   These tasks stalled. To retry:"
        echo "   1. Edit devplan.md and change [🔄] back to [ ]"
        echo "   2. Or use: ralph --reset-task \"task name\" --devplan $devpath"
        echo ""
    fi

    if [ "$in_progress_count" -gt 0 ]; then
        echo "🔄 Tasks in progress:"
        echo "$tasks" | grep "^in_progress:" | while read -r line; do
            local task
            task=$(echo "$line" | cut -d':' -f2-)
            echo "   ⏳ $task"
        done
        echo ""
    fi

    # Show active blockers
    if [ -f "$BLOCKERS_FILE" ] && [ -s "$BLOCKERS_FILE" ]; then
        echo "🚫 Active Blockers:"
        cat "$BLOCKERS_FILE" | while read -r line; do
            echo "   $line"
        done
        echo ""
    fi
}

run_devplan_iteration() {
    local prompt="$1"
    local iteration="$2"
    local devfile="$3"
    local task="$4"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_info "=========================================="
    log_info "=== Task $iteration: $task ==="
    log_info "=========================================="
    echo ""

    if ! _ralph_execute_opencode "$prompt" "$task" "$devfile"; then
        record_stall_attempt "$task"
        return 1
    fi

    local text_output="$RALPH_LAST_TEXT_OUTPUT"
    local tools_used="$RALPH_LAST_TOOLS_USED"
    local duration="$RALPH_LAST_DURATION"
    local total_tokens="$RALPH_LAST_TOTAL_TOKENS"

    # Check for completion (case-insensitive, space-tolerant)
    if echo "$text_output" | grep -qiE "<\s*promise\s*>${COMPLETION_PROMISE}<\s*/\s*promise\s*>"; then
        log_success "Task completed!"
        mark_task_complete "$devfile" "$task"
        clear_stall_record "$task"
        clear_blockers "$task"
        log_progress "$iteration" "$task" "completed" "$duration"
        update_docs "✅ Completed: $task (${duration}s, ${total_tokens} tokens)"
        return 0
    fi

    # Check if devplan was updated
    if grep -qE "✅.*$task" "$devfile" 2>/dev/null; then
        log_success "Task marked complete in devplan"
        clear_stall_record "$task"
        clear_blockers "$task"
        log_progress "$iteration" "$task" "completed" "$duration"
        update_docs "✅ Completed: $task (${duration}s, ${total_tokens} tokens)"
        return 0
    fi

    # If work was done, mark complete
    if echo "$tools_used" | grep -qE "(Write|Edit|bash|Bash|task)"; then
        log_info "Work detected - marking task as complete"
        mark_task_complete "$devfile" "$task"
        clear_stall_record "$task"
        clear_blockers "$task"
        log_progress "$iteration" "$task" "completed" "$duration"
        update_docs "✅ Completed: $task (${duration}s, ${total_tokens} tokens, tools: $tools_used)"
        return 0
    fi

    # Check for blockers in output
    if echo "$text_output" | grep -qiE '(cannot|blocked|error|failed|permission denied|not found|dependency)'; then
        local blocker
        blocker=$(echo "$text_output" | grep -oiE '(cannot|blocked|error|failed|permission denied|not found|dependency).*' | head -1 | tr '\n' ' ' | sed 's/  */ /g')
        record_blocker "$task" "$blocker"
        update_docs "🚫 Blocked: $task - $blocker"
    fi

    # Check for stall indicators
    record_stall_attempt "$task"

    if detect_stall "$iteration" "$text_output" "$tools_used" "$duration"; then
        local stall_reason
        stall_reason=$(generate_stall_reason "$text_output" "$tools_used")
        log_warning "Stall detected for task: $task (reason: $stall_reason)"
        mark_task_needs_review "$devfile" "$task" "$stall_reason"
        log_progress "$iteration" "$task" "stalled: $stall_reason" "$duration"
        update_docs "🔄 Stalled: $task - $stall_reason (${duration}s)"
        return 2  # Special return code for stalled task
    fi

    log_warning "Task not completed"
    log_progress "$iteration" "$task" "incomplete" "$duration"
    update_docs "⚠️ Incomplete: $task (${duration}s, tools: $tools_used)"
    return 1
}
