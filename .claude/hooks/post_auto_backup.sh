#!/bin/bash
# =============================================================================
# Post-Hook 4: Auto-Backup
# Purpose:    After a file edit, create a timestamped backup with rotation.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 always (post-hooks should not block)
# Backups:    data/.backups/<basename>.<timestamp>
# Log:        data/session.log
# =============================================================================

# Extract the directory and the config file
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"

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

# Normalize: convert backslashes to forward slashes, lowercase for comparison
normalize() {
    printf '%s' "$1" | tr '\\' '/'
}

NORMALIZED_PATH="$(normalize "$FILE_PATH")"

# If the file does not exist exit 0
if [ ! -f "$NORMALIZED_PATH" ]; then
    exit 0
fi

# Extract session_id from session_id
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

# If it's empty, assign a default value
if [ -z "$SESSION_ID" ]; then 
    SESSION_ID="default"
fi

#Create a timestamp
TIMESTAMP="$(date +"%Y-%m-%d_%H%M%S")"

# Check if .claude/hooks/data/.backups exists and if not create it
DATA_DIR="$HOOK_DIR/data"
BACKUP_DIR="$DATA_DIR/.backups"
mkdir -p "$BACKUP_DIR" 2>/dev/null || exit 0

if [ ! -d "$BACKUP_DIR" ] || [ ! -w "$BACKUP_DIR" ]; then
    exit 0
fi

# Extract file_name from the normalized path
FILE_NAME=$(basename "$NORMALIZED_PATH")

# Create a back-up path and copy the file to that location
BACKUP_PATH="$BACKUP_DIR/$FILE_NAME.$TIMESTAMP"

if ! cp "$NORMALIZED_PATH" "$BACKUP_PATH"; then
    exit 0
fi

# Get the file's size
FILE_SIZE=$(wc -c < "$BACKUP_PATH")

# Get log file path and write to it 
LOG_PATH="$DATA_DIR/session_$SESSION_ID.log"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] BACKUP: Created $BACKUP_PATH ($FILE_SIZE bytes)" > "$LOG_PATH"
# Get max backups from config file or set default in case it's missing
MAX_BACKUPS=5
if [ -f "$CONFIG_FILE" ]; then
    MAX_BACKUPS=$(grep "^MAX_BACKUPS=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
    MAX_BACKUPS=${MAX_BACKUPS:-5}
fi

# Ignore invalid values and use a safe default
case "$MAX_BACKUPS" in
    ''|*[!0-9]*) MAX_BACKUPS=5 ;;
    *) : ;;
esac

if [ "$MAX_BACKUPS" -lt 1 ]; then
    MAX_BACKUPS=5
fi

# Get a list of existing back-up files for the specific file, keeping spaces intact
mapfile -d '' -t EXISTING_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$FILE_NAME.*" -printf '%T@ %p\0' 2>/dev/null | sort -z -nr | cut -z -d' ' -f2-)

# Count how many current backups we have
BACKUP_COUNT=${#EXISTING_BACKUPS[@]}

# Check if we have more then the limit, if so- sort and delete the oldest ones
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then

    # After we sorted the list- the oldest files will be at the end of the array so we slice it
    FILES_TO_DELETE=("${EXISTING_BACKUPS[@]:$MAX_BACKUPS}")

    # Now we delete the old files
    for file_to_delete in "${FILES_TO_DELETE[@]}"; do
        rm -f "$file_to_delete"
    done
fi

# All is good
exit 0
