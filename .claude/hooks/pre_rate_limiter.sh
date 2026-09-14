#!/bin/bash
# =============================================================================
# Pre-Hook 2: Rate Limiter
# Purpose:    Track command count per session, block after exceeding limit.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"session_id":"..."}
# Exit codes: 0 = allow (possibly with warning), 2 = blocked (limit exceeded)
# State file: data/.command_count — format per line: session_id|total|type1:N,type2:N,...
# =============================================================================

# Extract the directory and the config file
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract tool_name from tool_name
TOOL_NAME="$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')"

# Check if not a Bash tool - if not, there's no need for the check
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Extract command from tool_input
COMMAND="$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')"

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Extract session_id from session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# If it's empty, assign a default value
if [ -z "$SESSION_ID" ]; then 
    SESSION_ID="default"
fi

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Extract the values from the config file using helper func with grep and cut
get_config() {
    grep "^$1=" "$CONFIG_FILE" | cut -d'=' -f2
}

MAX_COMMANDS=$(get_config "MAX_COMMANDS")
WARNING_THRESHOLD=$(get_config "WARNING_THRESHOLD")

# Extract state_file 
STATE_FILE="$HOOK_DIR/data/.command_count"

# Check if .claude/hooks/data/.reset_commands exists
RESET_FILE="$HOOK_DIR/data/.reset_commands"

if [ -f "$RESET_FILE" ]; then
    # Remove the session's line from the state file if they exists
    if [ -f "$STATE_FILE" ]; then
        grep -v "^$SESSION_ID|" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    # Remove the reset trigger so it doesn't reset next time
    rm -f "$RESET_FILE"
fi

# Search for sesion_id count in the state_file
CURRENT_LINE=$(grep "^$SESSION_ID|" "$STATE_FILE" 2>/dev/null)
COMMAND_TYPE=$(echo $COMMAND | awk '{print $1}') 

if [ -z "$CURRENT_LINE" ]; then
    NEW_COUNT=1
    NEW_BREAKDOWN="$COMMAND_TYPE:1"
else
    # Parse existing line
    OLD_TOTAL=$(echo "$CURRENT_LINE" | cut -d'|' -f2)
    OLD_BREAKDOWN=$(echo "$CURRENT_LINE" | cut -d'|' -f3)
    NEW_COUNT=$((OLD_TOTAL + 1))
    
    # Update the breakdown list manually
    NEW_BREAKDOWN=""
    FOUND_TYPE=false
    
    # Use IFS to split the comma-separated pairs
    IFS=','
    for pair in $OLD_BREAKDOWN; do
        name=$(echo "$pair" | cut -d':' -f1)
        count=$(echo "$pair" | cut -d':' -f2)
        
        if [ "$name" == "$COMMAND_TYPE" ]; then
            count=$((count + 1))
            FOUND_TYPE=true
        fi
        
        # Rebuild the string
        if [ -z "$NEW_BREAKDOWN" ]; then
            NEW_BREAKDOWN="$name:$count"
        else
            NEW_BREAKDOWN="$NEW_BREAKDOWN,$name:$count"
        fi
    done
    unset IFS

    # If the command type is new, append it
    if [ "$FOUND_TYPE" = false ]; then
        NEW_BREAKDOWN="$NEW_BREAKDOWN,$COMMAND_TYPE:1"
    fi
fi

# Update the state file by replacing the session line
touch "$STATE_FILE"
grep -v "^$SESSION_ID|" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null
echo "$SESSION_ID|$NEW_COUNT|$NEW_BREAKDOWN" >> "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

# Enforce limits
if [ "$NEW_COUNT" -gt "$MAX_COMMANDS" ]; then
    printf "BLOCKED: Limit exceeded (%d/%d). Breakdown: %s\n" "$NEW_COUNT" "$MAX_COMMANDS" "$NEW_BREAKDOWN" >&2
    exit 2
fi

if [ "$NEW_COUNT" -gt "$WARNING_THRESHOLD" ]; then
    printf "WARNING: Approaching limit (%d/%d)\n" "$NEW_COUNT" "$MAX_COMMANDS" >&2
fi

exit 0