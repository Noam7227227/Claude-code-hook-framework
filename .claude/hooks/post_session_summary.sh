#!/bin/bash
# =============================================================================
# Post-Hook 6: Session Summary
# Purpose:    Generate a formatted summary from session.log when Claude stops.
# Input:      JSON on stdin: {"session_id":"...","cwd":"...","stop_hook_active":false}
# Exit codes: 0 always
# IMPORTANT:  Checks stop_hook_active first to prevent infinite loops.
# =============================================================================

# Extract the directory
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract stop_tool_active from input and check 
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | sed -E 's/.*"stop_hook_active":[[:space:]]*"?([^",}]+)"?.*/\1/')
if [ "$STOP_HOOK_ACTIVE" == true ]; then
    exit 0
fi

# Extract session_id from session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# If it's empty, assign a default value
if [ -z "$SESSION_ID" ]; then 
    SESSION_ID="default"
fi

# Get log file path
DATA_DIR="$HOOK_DIR/data"
LOG_PATH="$DATA_DIR/session_$SESSION_ID.log"

# If the log doesn't exist or is empty
if [ ! -s "$LOG_PATH" ]; then
    echo "No session activity recorded." >&1
    exit 0
fi

# Extract stats from the log file
TOTAL_ACTIONS=$(wc -l < "$LOG_PATH")
BACKUPS_MADE=$(grep -c "BACKUP" "$LOG_PATH")
SYNTAX_CHECKS=$(grep -c "SYNTAX" "$LOG_PATH")
SYNTAX_ERRORS=$(grep -c "SYNTAX_ERROR" "$LOG_PATH")
FIRST_TIMESTAMP=$(head -n 1 "$LOG_PATH" | cut -d'[' -f2 | cut -d']' -f1)
LAST_TIMESTAMP=$(tail -n 1 "$LOG_PATH" | cut -d'[' -f2 | cut -d']' -f1)

# Get three most edited files
THREE_MOST_EDITED=$(grep "BACKUP" "$LOG_PATH" | sed 's/.*BACKUP //' | cut -d' ' -f1 | sort | uniq -c | sort -nr | head -n 3)
# Get type counts
EXT_COUNTS=$(grep -E "BACKUP|SYNTAX" "$LOG_PATH" | sed -E 's/.*(BACKUP|SYNTAX_OK|SYNTAX_ERROR) //' | cut -d' ' -f1 | sed 's/.*\.//' | sort | uniq -c | sort -nr)

# Print the report
echo "╔══════════════════════════════════════╗"
echo "║        SESSION SUMMARY REPORT        ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Session: $SESSION_ID"
echo "Period: $FIRST_TIMESTAMP -> $LAST_TIMESTAMP"
echo ""
echo "── Activity ─────────────────────────"
echo  "Total actions: $TOTAL_ACTIONS"
echo  "Backups made: $BACKUPS_MADE"
echo  "Syntax checks: $SYNTAX_CHECKS"
echo  "Syntax errors: $SYNTAX_ERRORS"
echo ""
echo "── Most Edited Files ────────────────"
# Loop to print the three most edited files
rank=1
echo "$THREE_MOST_EDITED" | while read -r count file; do
    if [ -n "$file" ]; then 
        # If we have more then one edit or one
        suffix="edits"
        [ "$count" -eq 1 ] && suffix="edit"
        echo "$rank. $file ($count $suffix)"
        ((rank++))
    fi
done
echo ""

# Print file types
echo "── File Types ───────────────────────"
echo "$EXT_COUNTS" | while read -r count ext; do
    if [ -n "$ext" ]; then
        echo ".$ext files: $count"
    fi
done

# All is good
exit 0
