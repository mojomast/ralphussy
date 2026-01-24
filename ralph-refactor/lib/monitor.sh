# Live Monitor - Background process to show real-time activity

# NOTE: This file is sourced by ../ralph. It expects color variables
# (RED/GREEN/YELLOW/BLUE/MAGENTA/CYAN/NC) to already be defined.

MONITOR_PID="${MONITOR_PID-}"
MONITOR_LOG="${MONITOR_LOG-}"
MONITOR_ENABLED="${MONITOR_ENABLED:-true}"
MONITOR_ACTIVITY_IDLE_SECONDS="${MONITOR_ACTIVITY_IDLE_SECONDS:-8}"
MONITOR_PROC_CHECK_EVERY_TICKS="${MONITOR_PROC_CHECK_EVERY_TICKS:-10}"
MONITOR_CONTROL_FILE="${MONITOR_CONTROL_FILE-}"  # ADD: Control file for graceful shutdown

monitor_is_opencode_running() {
    # Best-effort: check whether an opencode process exists in the current
    # process tree. This avoids showing "Waiting for activity..." while the
    # model is still working but not emitting tool/log output.
    local root_pid="${RALPH_MAIN_PID-}"
    if [ -z "$root_pid" ]; then
        return 1
    fi

    if ! command -v pgrep >/dev/null 2>&1; then
        return 1
    fi

    # BFS over descendants.
    local queue
    queue="$root_pid"
    local seen_guard=0

    while [ -n "$queue" ]; do
        # Pop first pid
        local pid="${queue%% *}"
        if [ "$queue" = "$pid" ]; then
            queue=""
        else
            queue="${queue#* }"
        fi

        # Safety guard against pathological process trees.
        seen_guard=$((seen_guard + 1))
        if [ "$seen_guard" -gt 200 ]; then
            return 1
        fi

        local children
        children=$(pgrep -P "$pid" 2>/dev/null || true)
        if [ -n "$children" ]; then
            local child
            for child in $children; do
                # ps is more portable than pgrep -a on older distros.
                if ps -p "$child" -o args= 2>/dev/null | grep -qE '(^|[[:space:]])opencode([[:space:]]|$)'; then
                    return 0
                fi
                queue="$queue $child"
            done
        fi
    done

    return 1
}

# Find latest opencode log
find_latest_log() {
    local log_dir="$HOME/.local/share/opencode/log"
    if [ -d "$log_dir" ]; then
        find "$log_dir" -name "*.log" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
    fi
}

# Start background monitor
start_monitor() {
    if [ "$MONITOR_ENABLED" != "true" ]; then
        return 0
    fi

    # Kill any existing monitor for this session first
    stop_monitor

    local log_dir="$HOME/.local/share/opencode/log"
    if [ ! -d "$log_dir" ]; then
        return 1
    fi

    # Create a monitor control file unique to this PID
    local monitor_control="$RALPH_DIR/monitor_control_$$"
    touch "$monitor_control"

    # Get initial newest log (before opencode starts)
    local initial_log
    initial_log=$(find "$log_dir" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

    # Start monitoring in background
    (
        # Monitor will exit when control file is removed OR after timeout
        local monitor_started=$(date +%s)
        local max_runtime=7200  # 2 hours max
        local monitor_started
        monitor_started=$(date +%s)
        local found_new_log=false
        local spinner_idx=0
        local last_msg=""

        # Spinner characters
        local spinner_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

        # Watch for new log file
         while [ "$found_new_log" = false ] && [ -f "$monitor_control" ]; do
             # Safety: Exit if running too long (prevents infinite orphans)
             local now=$(date +%s)
             if [ $((now - monitor_started)) -gt $max_runtime ]; then
                 rm -f "$monitor_control" 2>/dev/null || true
                 exit 0
             fi
            spinner_idx=$(( (spinner_idx + 1) % 10 ))
            sleep 0.1

            # Print searching spinner
            echo -ne "\r\033[K${CYAN}${spinner_chars[$spinner_idx]}${NC} Waiting for Ralph to start..." >&2

            local newest_log
            newest_log=$(find "$log_dir" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

            if [ -n "$newest_log" ] && [ "$newest_log" != "$initial_log" ]; then
                local newest_time
                newest_time=$(stat -c %Y "$newest_log" 2>/dev/null || echo "0")
                if [ "$newest_time" -ge "$monitor_started" ]; then
                    MONITOR_LOG="$newest_log"
                    found_new_log=true
                fi
            fi

            local current_time
            current_time=$(date +%s)
            if [ $((current_time - monitor_started)) -gt 10 ]; then
                if [ -n "$newest_log" ]; then
                    MONITOR_LOG="$newest_log"
                    found_new_log=true
                else
                    exit 0
                fi
            fi
        done

        if [ -f "$MONITOR_LOG" ]; then
            # Initial status
            echo -ne "\r\033[K${CYAN}${spinner_chars[$spinner_idx]}${NC} Connected to $(basename "$MONITOR_LOG")" >&2

            local last_file_size
            last_file_size=$(stat -c %s "$MONITOR_LOG" 2>/dev/null || echo "0")
            local last_activity_time=0
            local tool_output_dir="$HOME/.local/share/opencode/tool-output"
            local last_output_file=""
            local last_output_size=0
            local tick=0
            local opencode_running=false

             while [ -f "$MONITOR_LOG" ] && [ -f "$monitor_control" ]; do
                 spinner_idx=$(( (spinner_idx + 1) % 10 ))
                 tick=$((tick + 1))
                 
                 # Safety: Exit if running too long (prevents infinite orphans)
                 local now=$(date +%s)
                 if [ $((now - monitor_started)) -gt $max_runtime ]; then
                     rm -f "$monitor_control" 2>/dev/null || true
                     break
                 fi

                local current_size
                current_size=$(stat -c %s "$MONITOR_LOG" 2>/dev/null || echo "0")
                local current_display_msg=""

                # Treat either a growing log OR a new tool output file as "activity".
                # OpenCode can emit long tool outputs without appending much to the main
                # log file, so tying monitor updates to log growth causes the monitor to
                # look stuck.
                if [ "$current_size" -gt "$last_file_size" ]; then
                    last_file_size=$current_size
                    last_activity_time=$(date +%s)
                fi

                # Check latest tool output (any tool_* file, not just tool_b*)
                if [ -d "$tool_output_dir" ]; then
                    local latest_output
                    latest_output=$(ls -t "$tool_output_dir"/tool_* 2>/dev/null | head -1 || true)

                    if [ -n "$latest_output" ] && [ -f "$latest_output" ]; then
                        local current_output_size
                        current_output_size=$(stat -c %s "$latest_output" 2>/dev/null || echo "0")

                        if [ "$latest_output" != "$last_output_file" ] || [ "$current_output_size" != "$last_output_size" ]; then
                            last_output_file="$latest_output"
                            last_output_size="$current_output_size"
                            last_activity_time=$(date +%s)

                            # Read enough lines to detect tree listings + key errors.
                            local output_content
                            output_content=$(head -n 120 "$latest_output" 2>/dev/null)
                            local first_line
                            first_line=$(echo "$output_content" | head -1)
                            local output_lines
                            output_lines=$(wc -l < "$latest_output" 2>/dev/null || echo "0")

                            # Enhanced detection logic

                            # 1. Test Failures (Prioritize errors)
                            if echo "$output_content" | grep -qE "FAILED|ERROR|Error:|Exception:"; then
                                local error_detail
                                error_detail=$(echo "$output_content" | grep -E "FAILED|ERROR|Error:|Exception:" | head -1 | sed 's/^[[:space:]]*//' | head -c 80)
                                current_display_msg="${RED}💥 ERROR DETECTED: $error_detail${NC}"

                            # 2. Test Success
                            elif echo "$output_content" | grep -qE "PASSED"; then
                                local pass_detail
                                pass_detail=$(echo "$output_content" | grep "PASSED" | head -1 | sed 's/^[[:space:]]*//' | head -c 80)
                                current_display_msg="${GREEN}🧪 TESTS PASSED: $pass_detail${NC}"

                            # 3. Git Operations
                            elif echo "$first_line" | grep -q "^diff "; then
                                local file_diff
                                file_diff=$(echo "$first_line" | awk '{print $NF}')
                                local hunk_count
                                hunk_count=$(echo "$output_content" | grep -c "^@@")
                                current_display_msg="${MAGENTA}📝 Reviewing diffs: $file_diff ($hunk_count hunks)${NC}"

                            # 4. Recursive directory listings (common for Glob/ls outputs)
                            elif echo "$output_content" | grep -qE '^\.:$|^\./[^:]+:$'; then
                                # ls -R style output uses section headers like ".:" and "./dir:".
                                local section_count
                                section_count=$(echo "$output_content" | grep -cE '^\.:$|^\./[^:]+:$' || echo "0")
                                local dir_sections=0
                                if [ "$section_count" -gt 0 ]; then
                                    dir_sections=$((section_count - 1))
                                fi
                                local shown_items
                                shown_items=$(echo "$output_content" | grep -vE '^\.:$|^\./[^:]+:$|^$' | wc -l | tr -d ' ')
                                current_display_msg="${BLUE}📁 Listing tree ($shown_items items shown, $dir_sections dirs seen)${NC}"

                            # 5. Simple file listings / file-ish outputs
                            elif [ "$output_lines" -gt 5 ] && echo "$first_line" | grep -qvE '^\.$|^\.:$'; then
                                # If the first line looks like a filename, show that.
                                if echo "$first_line" | grep -qE '\.(py|ts|js|md|json|css|html|sh|txt)$'; then
                                    local file
                                    file=$(basename "$first_line" 2>/dev/null)
                                    current_display_msg="${YELLOW}📄 Touching: $file${NC}"
                                else
                                    local lines_shown
                                    lines_shown=$(echo "$output_content" | grep -vE '^$' | wc -l | tr -d ' ')
                                    current_display_msg="${BLUE}📦 Tool output ($lines_shown lines shown)${NC}"
                                fi
                            fi
                        fi
                    fi
                fi

                # Update display if message changed
                if [ -n "$current_display_msg" ] && [ "$current_display_msg" != "$last_msg" ]; then
                    # Print new significant event on its own line
                    echo -ne "\r\033[K" >&2
                    echo -e "${spinner_chars[$spinner_idx]} $current_display_msg" >&2
                    last_msg="$current_display_msg"
                fi

                # Always update the bottom status line (ephemeral)
                local status_line_content="$last_msg"
                if [ -z "$status_line_content" ]; then
                    status_line_content="Monitoring..."
                fi

                # If we've seen no activity recently, be explicit.
                local now
                now=$(date +%s)

                # Periodically check whether opencode is still running.
                # (tick increments every ~0.1s)
                if [ $((tick % MONITOR_PROC_CHECK_EVERY_TICKS)) -eq 0 ]; then
                    if monitor_is_opencode_running; then
                        opencode_running=true
                    else
                        opencode_running=false
                    fi
                fi

                if [ "$opencode_running" = true ]; then
                    status_line_content="OpenCode running..."
                elif [ "$last_activity_time" -gt 0 ] && [ $((now - last_activity_time)) -ge "$MONITOR_ACTIVITY_IDLE_SECONDS" ]; then
                    status_line_content="Waiting for activity..."
                fi

                # Strip colors for length calc
                local clean_msg
                clean_msg=$(echo "$status_line_content" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
                echo -ne "\r\033[K${CYAN}${spinner_chars[$spinner_idx]}${NC} [$(basename "$MONITOR_LOG")] $clean_msg" >&2

                sleep 0.1
            done
            # Cleanup status line
             echo -ne "\r\033[K" >&2
         fi
         
         # Cleanup on exit
         rm -f "$monitor_control" 2>/dev/null || true
     ) &

     MONITOR_PID=$!
     MONITOR_CONTROL_FILE="$monitor_control"
     
     # Register cleanup trap for this monitor
     trap "stop_monitor" EXIT

     sleep 0.3
 }

# Stop background monitor
stop_monitor() {
    # Remove control file first (signals monitor to exit gracefully)
    if [ -n "$MONITOR_CONTROL_FILE" ]; then
        rm -f "$MONITOR_CONTROL_FILE" 2>/dev/null || true
        MONITOR_CONTROL_FILE=""
    fi

    # Then kill process as backup
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        # Wait briefly for graceful exit
        local wait_count=0
        while kill -0 "$MONITOR_PID" 2>/dev/null && [ $wait_count -lt 10 ]; do
            sleep 0.1
            wait_count=$((wait_count + 1))
        done
        # Force kill if still alive
        kill -9 "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi

    # Cleanup any orphaned monitor control files (>10 min old)
    find "$RALPH_DIR" -name "monitor_control_*" -type f -mmin +10 -delete 2>/dev/null || true
}
