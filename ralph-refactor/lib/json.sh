# JSON extraction helpers for parsing OpenCode output.

# Extract textual content from various OpenCode JSON shapes.
# Uses jq when available; falls back to greps if not.
json_extract_text() {
    local json="$1"
    local text=""

     if command -v jq &> /dev/null; then
        # Try several common fields used by different providers / versions.
        # This covers OpenCode (.part.messages[].text), OpenAI chat/completions,
        # Anthropic (.completion), Google (.candidates[].content), and other shapes.
        # Get last text message which contains completion marker
        text=$(printf '%s' "$json" | jq -s -r '[.[] | select(.type == "text") | .part.text] | .[-1] // ""' 2>/dev/null | tr -d '"') || text=
    fi

    if [ -z "$text" ]; then
        # Fallback 1: Extract from JSON array of messages
        text=$(printf '%s' "$json" | jq -r '[.[] | select(.type == "text") | .text] | join("\n")' 2>/dev/null) || text=""
    fi

    if [ -z "$text" ]; then
        # Fallback 2: Best-effort grep/sed extraction for older/unknown shapes
        text=$(printf '%s' "$json" | grep '"type":"text"' | grep -v '"role":"user"' | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | head -1 | tr '\n' ' ' | sed 's/  */ /g')
        if [ -z "$text" ]; then
            text=$(printf '%s' "$json" | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | tail -1 | tr '\n' ' ' | sed 's/  */ /g')
        fi
    fi

    # Convert escaped newlines (\n) to actual newlines for models that output escaped strings
    text=$(printf '%s' "$text" | sed 's/\\n/\n/g')

    printf '%s' "$text"
}

# Extract tool names used from JSON (dedupe, truncated)
json_extract_tools() {
    local json="$1"
    local tools=""
    if command -v jq &> /dev/null; then
        # Try several possible locations for tool calls across providers
        tools=$(printf '%s' "$json" | jq -r '
            (
              (.part.tool_calls[]?.name)
              // (.tool_calls[]?.name)
              // (.toolCalls[]?.name)
              // (.tools[]?.name)
              // (.metadata.tools[]?.name)
            ) // empty' 2>/dev/null | grep -v '^$' | sort -u | tr '\n' ' ' | head -c 200)
    else
        # Best-effort fallback: look for "name":"<tool>" occurrences
        tools=$(printf '%s' "$json" | grep -o '"name":"[^"]\+"' | sed 's/"name":"//;s/"$//' | sort -u | tr '\n' ' ' | head -c 200 || true)
    fi
    printf '%s' "$tools"
}
