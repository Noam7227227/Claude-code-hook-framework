#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================

# Extract the directory and the config file
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/commit_prefixes.txt"

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

# If there's nothing there
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Get two first words in the command, normalize them - if they are not "git" and "commit" exit 0
COMMAND_ARRAY=($COMMAND)
COMMAND_GIT="${COMMAND_ARRAY[0]}"
COMMAND_COMMIT="${COMMAND_ARRAY[1]}"

normalize() {
    printf '%s' "$1" | tr '\\' '/' | tr '[:upper:]' '[:lower:]'
}

NORMALIZED_COMMAND_GIT="$(normalize "$COMMAND_GIT")"
NORMALIZED_COMMAND_COMMIT="$(normalize "$COMMAND_COMMIT")"

if [[ ! ( "$NORMALIZED_COMMAND_GIT" == "git" && "$NORMALIZED_COMMAND_COMMIT" == "commit" ) ]]; then 
    exit 0
fi

# If the command has no -m or a flag similar to it, exit 0
if [[ ! "$COMMAND" =~ -[a-z]*m ]]; then
    exit 0
fi

# Extract commit message from the git commit command
COMMIT_MSG=""
if [[ "$COMMAND" =~ -[a-z]*m[[:space:]]*\"([^\"]*)\" ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -[a-z]*m[[:space:]]*\'([^\']*)\' ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -[a-z]*m[[:space:]]+([^[:space:]]+) ]]; then
    COMMIT_MSG="${BASH_REMATCH[1]}"
fi

# If empty
if [ -z "$COMMIT_MSG" ]; then
    exit 0
fi

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Check 1
# Extract the prefixes from the config file
PREFIXES=$(paste -sd "|" "$CONFIG_FILE")

# Create the regex
PREFIX_REGEX="^($PREFIXES): .*"

# If prefix is missing - block and suggest a prefix
if [[ ! "$COMMIT_MSG" =~ $PREFIX_REGEX ]]; then
    # Get git diff stats
    DIFF_STAT=$(git diff --cached --stat | tail -n 1)
    # Extract from it the insertions and deletions
    INSERTIONS=$(echo "$DIFF_STAT" | grep -oP '\d+(?= insertion)' || echo 0)
    DELETIONS=$(echo "$DIFF_STAT" | grep -oP '\d+(?= deletion)' || echo 0)

    # Get staged files
    STAGED_FILES=$(git diff --cached --name-status)

    # Set our Heuristics
    # Default
    SUGGESTED_PREFIX="feat"

    # Our cases for the suggested prefix
    if echo "$STAGED_FILES" | grep -qEi "test|spec"; then
        SUGGESTED_PREFIX="test"
    elif echo "$STAGED_FILES" | grep -qEi "README|\.md"; then
        SUGGESTED_PREFIX="docs"
    elif echo "$STAGED_FILES" | grep -qP "^A\t"; then
        SUGGESTED_PREFIX="feat"
    elif [ "$DELETIONS" -gt "$INSERTIONS" ]; then
        SUGGESTED_PREFIX="refactor"
    fi

    # Format the prefixes for the exit message
    CLEAN_PREFIXES=$(echo "$PREFIXES" | tr '|' ', ')

    printf "Missing commit prefix. Based on your changes, try: '%s: %s'. Valid prefixes: %s\n" "$SUGGESTED_PREFIX" "$COMMIT_MSG" "$CLEAN_PREFIXES" >&2    
    exit 2
fi

# Check 2
# Get the message length
MSG_LENGTH=${#COMMIT_MSG}

# Check if the length is in the correct range 10-72
if [ "$MSG_LENGTH" -lt 10 -o "$MSG_LENGTH" -gt 72 ]; then
    exit 2
fi

# Check 3
# Extract the last character in the message
LAST_CHAR="${COMMIT_MSG: -1}"

if [ "$LAST_CHAR" == "." ]; then
    exit 2
fi

# All is good
exit 0
