#!/bin/bash
# =============================================================================
# Hook Runner
# Purpose:    Standalone simulator of Claude Code's hook execution for testing.
#             Reads hooks_config.txt, matches event+tool, runs hooks in order.
# Usage:      echo '<json>' | ./hook_runner.sh <event_type> <tool_name>
# Examples:
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
#       | ./hook_runner.sh PreToolUse Bash
#   echo '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' \
#       | ./hook_runner.sh PostToolUse Edit
# =============================================================================

# ── Colour codes ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$RUNNER_DIR/hooks_config.txt"

# Argument validation 
if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    printf '%bUsage:%b echo '\''<json>'\'' | %s <event_type> <tool_name>\n' "$BOLD" "$RESET" "$0"
    printf '\n'
    printf 'event_type examples: PreToolUse, PostToolUse, Stop\n'
    printf 'tool_name  examples: Bash, Edit, Write, MultiEdit, *\n'
    printf '\n'
    printf 'Config file: %s\n' "$CONFIG_FILE"
    exit 1
fi

EVENT_TYPE="$1"
TOOL_NAME="$2"

case "$EVENT_TYPE" in
    PreToolUse|PostToolUse|Stop)
        ;;
    *)
        printf '%bUsage:%b echo '\''<json>'\'' | %s <event_type> <tool_name>\n' "$BOLD" "$RESET" "$0" >&2
        exit 1
        ;;
esac

# Validate config file 
if [ ! -f "$CONFIG_FILE" ]; then
    printf '%bERROR:%b Config file not found: %s\n' "$RED" "$RESET" "$CONFIG_FILE" >&2
    exit 1
fi

# Read stdin into temp file (hooks need to re-read it) 
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT
cat > "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
    echo "Error: JSON payload is empty" >&2
    exit 1
fi

printf '%b─── Hook Runner (%s / %s) ───%b\n' "$BOLD" "$EVENT_TYPE" "$TOOL_NAME" "$RESET"
printf '\n'

# Statistics 
MATCHED=0
PASSED=0
BLOCKED=0
WARNINGS=0
FINAL_EXIT=0

# Process config file 
while IFS= read -r line; do
    # Skip comments and empty lines
    case "$line" in
        '#'*|'') continue ;;
    esac

    # Split on ':' — fields: event:matcher:script
    CONF_EVENT="$(printf '%s' "$line" | cut -d':' -f1)"
    CONF_MATCHER="$(printf '%s' "$line" | cut -d':' -f2)"
    CONF_SCRIPT="$(printf '%s' "$line" | cut -d':' -f3-)"

    # Match event type
    if [ "$CONF_EVENT" != "$EVENT_TYPE" ]; then
        continue
    fi

    # Match tool name (exact match or wildcard *)
    if [ "$CONF_MATCHER" != "$TOOL_NAME" ] && [ "$CONF_MATCHER" != "*" ]; then
        continue
    fi

    MATCHED=$((MATCHED + 1))

    # Resolve script path relative to runner dir if it starts with ./
    SCRIPT_PATH="$CONF_SCRIPT"
    case "$SCRIPT_PATH" in
        ./*) SCRIPT_PATH="$RUNNER_DIR/${SCRIPT_PATH#./}" ;;
    esac

    printf '%b▶ Running:%b %s\n' "$CYAN" "$RESET" "$CONF_SCRIPT"

    # Execute hook, feeding the saved stdin; capture stderr separately
    STDERR_FILE="$(mktemp)"
    cat "$TEMP_FILE" | bash "$SCRIPT_PATH" 2>"$STDERR_FILE"
    EXIT_CODE=$?
    STDERR_OUTPUT="$(cat "$STDERR_FILE")"
    rm -f "$STDERR_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        printf '  %b✓ Passed%b\n' "$GREEN" "$RESET"
        PASSED=$((PASSED + 1))

    elif [ $EXIT_CODE -eq 2 ]; then
        printf '  %b✗ BLOCKED%b\n' "$RED" "$RESET"
        if [ -n "$STDERR_OUTPUT" ]; then
            printf '  %b%s%b\n' "$RED" "$STDERR_OUTPUT" "$RESET"
        fi
        BLOCKED=$((BLOCKED + 1))
        FINAL_EXIT=2

        # Stop chain on block (mirrors Claude Code PreToolUse behaviour)
        printf '\n%b[Chain stopped — hook returned exit 2]%b\n' "$YELLOW" "$RESET"
        break

    else
        printf '  %b⚠ Warning (exit %d)%b\n' "$YELLOW" "$EXIT_CODE" "$RESET"
        if [ -n "$STDERR_OUTPUT" ]; then
            printf '  %b%s%b\n' "$YELLOW" "$STDERR_OUTPUT" "$RESET"
        fi
        WARNINGS=$((WARNINGS + 1))
    fi

    printf '\n'

done < "$CONFIG_FILE"

# Summary 
printf '%b─── Hook Execution Summary ──────────%b\n' "$BOLD" "$RESET"
printf 'Matched:  %d hooks\n' "$MATCHED"
printf '%bPassed:   %d%b\n' "$GREEN" "$PASSED" "$RESET"
if [ "$BLOCKED" -gt 0 ]; then
    printf '%bBlocked:  %d%b\n' "$RED" "$BLOCKED" "$RESET"
else
    printf 'Blocked:  %d\n' "$BLOCKED"
fi
if [ "$WARNINGS" -gt 0 ]; then
    printf '%bWarnings: %d%b\n' "$YELLOW" "$WARNINGS" "$RESET"
else
    printf 'Warnings: %d\n' "$WARNINGS"
fi

exit $FINAL_EXIT
