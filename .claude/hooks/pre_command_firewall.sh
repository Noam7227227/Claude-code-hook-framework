#!/bin/bash
# =============================================================================
# Pre-Hook 1: Command Firewall
# Purpose:    Block dangerous bash commands before execution.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (dangerous pattern matched)
# =============================================================================

# Extract the directory and the config file
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/dangerous_patterns.txt"

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

# Normalize: convert backslashes to forward slashes, lowercase for comparison
normalize() {
    printf '%s' "$1" | tr '\\' '/' | tr '[:upper:]' '[:lower:]'
}

NORMALIZED_COMMAND="$(normalize "$COMMAND")"

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Check command against each entry in the blacklist
while IFS= read -r entry; do
    # Skip comments and empty lines
    case "$entry" in
        '#'*|'') continue ;;
    esac

    NORMALIZED_ENTRY="$(normalize "$entry")"

    # Block if the command is in the blacklist (regex match)
    if printf '%s' "$NORMALIZED_COMMAND" | grep -qE "$NORMALIZED_ENTRY"; then
    printf "BLOCKED: executing '%s' is not allowed (matches dangerous pattern '%s').\n" "$COMMAND" "$entry" >&2
    exit 2
    fi
done < "$CONFIG_FILE"

# All is good
exit 0