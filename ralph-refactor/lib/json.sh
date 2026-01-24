# JSON extraction helpers for parsing OpenCode output.

# Extract textual content from various OpenCode JSON shapes.
# STRATEGY: Always prefer LAST message (most recent agent response)
json_extract_text() {
    local json="$1"
    local text=""

    if command -v jq &> /dev/null; then
        # Try 1: OpenCode format - get last text message from part.text
        text=$(printf '%s' "$json" | jq -s -r '
            [.[] | select(.type == "text") | .part.text] | .[-1] // ""
        ' 2>/dev/null | tr -d '"') || text=""
        
        # Try 2: Alternative format - last text in messages array
        if [ -z "$text" ]; then
            text=$(printf '%s' "$json" | jq -s -r '
                [.[] | select(.type == "text") | .text] | .[-1] // ""
            ' 2>/dev/null) || text=""
        fi
        
        # Try 3: Anthropic format - content.text from last message
        if [ -z "$text" ]; then
            text=$(printf '%s' "$json" | jq -s -r '
                [.[] | select(.content) | .content[] | select(.type == "text") | .text] | .[-1] // ""
            ' 2>/dev/null) || text=""
        fi
    fi

    if [ -z "$text" ]; then
        # Fallback: grep-based extraction, take LAST match (not first!)
        # Filter out user messages, take only assistant responses
        text=$(printf '%s' "$json" | grep '"type":"text"' | grep -v '"role":"user"' | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | tail -1 | tr '\n' ' ' | sed 's/  */ /g')
    fi

    # Convert escaped newlines (\n) to actual newlines
    text=$(printf '%s' "$text" | sed 's/\\n/\n/g')

    printf '%s' "$text"
}

# Extract tool names used from JSON (dedupe, truncated)
json_extract_tools() {
    local json="$1"
    local tools=""
    if command -v jq &> /dev/null; then
        # Try all possible locations for tool calls across providers
        tools=$(printf '%s' "$json" | jq -r '
            (
              (.part.tool_calls[]?.name)
              // (.part.toolCalls[]?.name)
              // (.part.tool_use[]?.name)          # ADD: tool_use variant
              // (.tool_calls[]?.name)
              // (.toolCalls[]?.name)
              // (.tool_use[]?.name)                # ADD: tool_use variant
              // (.tools[]?.name)
              // (.metadata.tools[]?.name)
              // (.content[]?.tool_use?.name)      # ADD: Anthropic format
              // (.choices[]?.message?.tool_calls[]?.function?.name)  # ADD: OpenAI format
            ) // empty' 2>/dev/null | grep -v '^$' | sort -u | tr '\n' ' ' | head -c 200)
    else
        # Best-effort fallback: look for "name":"<tool>" occurrences
        tools=$(printf '%s' "$json" | grep -o '"name":"[^"]\+"' | sed 's/"name":"//;s/"$//' | sort -u | tr '\n' ' ' | head -c 200 || true)
    fi
    printf '%s' "$tools"
}
