#!/bin/bash
# =============================================================================
# Post-Hook 5: Syntax Checker
# Purpose:    Run appropriate syntax checker based on file extension after edit.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = syntax OK (or no checker), 1 = syntax error (warn, don't block)
# Supported:  .sh/.bash (bash -n), .py (python3 -m py_compile), .c/.h (gcc -fsyntax-only)
# =============================================================================

# Extract the directory
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract tool_name from tool_name
TOOL_NAME="$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')"

# Check if not a Edit tool - if not, there's no need for the check
if [ "$TOOL_NAME" != "Edit" ]; then
    exit 0
fi

# Extract file_path from tool_input
FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')"

# If file_path is empty exit 0
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# If the file does not exist exit 0
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Extract session_id from session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# If it's empty, assign a default value
if [ -z "$SESSION_ID" ]; then 
    SESSION_ID="default"
fi

# Extract the extention from the path
EXTENSION="${FILE_PATH##*.}"

# Based on the ##*., if there's no . EXTENSION will be FILE_PATH, check and set "no_extention"
if [[ "$EXTENSION" == "$FILE_PATH" ]]; then 
    EXTENSION="no_extention"
fi

#Get data directory's file path 
DATA_DIR="$HOOK_DIR/data"
mkdir -p "$DATA_DIR"

# Get temp file for the error output if needed
TMP_ERR="$DATA_DIR/syntax_error_$SESSION_ID.tmp"

# Switch case for the extention, extract the exit code and remove the output
case "$EXTENSION" in
    "sh" | "bash" )
        bash -n "$FILE_PATH" > "$TMP_ERR" 2>&1
        STATUS=$?
        ;;
    "py" )
        python3 -m py_compile "$FILE_PATH" > "$TMP_ERR" 2>&1
        STATUS=$?
        ;;
    "c" | "h" )
        gcc -fsyntax-only "$FILE_PATH" > "$TMP_ERR" 2>&1
        STATUS=$?
        ;;
    *)
    # Default case- no match, delete the temp file and exit
    echo "No syntax checker for ."$EXTENSION"" >&2
    rm -f "$TMP_ERR"
    exit 0
    ;;
esac

# Get log file path and write to it 
LOG_PATH="$DATA_DIR/session_$SESSION_ID.log"

#Create a timestamp
TIMESTAMP="$(date +"%Y-%m-%d_%H%M%S")"

# If exit code is 0
if [ "$STATUS" -eq 0 ]; then
    echo "Syntax OK: "$FILE_PATH"" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SYNTAX_OK "$FILE_PATH" ("$EXTENSION")" >> "$LOG_PATH"
    # Cleanup
    rm -f "$TMP_ERR"
    exit 0
# If exit code is non-zero
else
    echo "SYNTAX ERROR in $FILE_PATH:" >&2
    # Print the error
    cat "$TMP_ERR" >&2 
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SYNTAX_ERROR $FILE_PATH ($EXTENSION)" >> "$LOG_PATH"
    # Cleanup
    rm -f "$TMP_ERR"
    exit 1
fi
