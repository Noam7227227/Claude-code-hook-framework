#!/usr/bin/env bash
# shellcheck disable=SC2317
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_ROOT/.claude/hooks/post_auto_backup.sh"
HOOK_DATA_DIR="$REPO_ROOT/.claude/hooks/data"
HOOK_CONFIG="$REPO_ROOT/.claude/hooks/config/hooks.conf"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-backup-test.XXXXXX")"

PASS=0
FAIL=0
DATA_BACKUP=""
CONFIG_BACKUP=""

cleanup() {
    if [[ -n "$DATA_BACKUP" && -d "$DATA_BACKUP" ]]; then
        rm -rf "$HOOK_DATA_DIR"
        mv "$DATA_BACKUP" "$HOOK_DATA_DIR"
    else
        rm -rf "$HOOK_DATA_DIR"
    fi

    if [[ -n "$CONFIG_BACKUP" && -f "$CONFIG_BACKUP" ]]; then
        cp "$CONFIG_BACKUP" "$HOOK_CONFIG"
    fi

    rm -rf "$WORKDIR"
}
trap cleanup EXIT

assert_exit() {
    local expected="$1"
    local actual="$2"
    local name="$3"

    if [[ "$actual" -eq "$expected" ]]; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (expected exit %d, got %d)\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_exists() {
    local path="$1"
    local name="$2"

    if [[ -e "$path" ]]; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (missing: %s)\n' "$name" "$path"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_exists() {
    local path="$1"
    local name="$2"

    if [[ ! -e "$path" ]]; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (unexpectedly exists: %s)\n' "$name" "$path"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local file_path="$1"
    local session_id="$2"
    local payload

    payload="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$file_path\"},\"session_id\":\"$session_id\"}"

    set +e
    bash "$HOOK_PATH" <<< "$payload" >/dev/null 2>&1
    local actual_exit=$?
    set -e

    printf '%s' "$actual_exit"
}

create_isolated_state() {
    if [[ -d "$HOOK_DATA_DIR" ]]; then
        DATA_BACKUP="$WORKDIR/original_data"
        mv "$HOOK_DATA_DIR" "$DATA_BACKUP"
    fi

    mkdir -p "$HOOK_DATA_DIR/.backups"

    if [[ -f "$HOOK_CONFIG" ]]; then
        CONFIG_BACKUP="$WORKDIR/hooks.conf.bak"
        cp "$HOOK_CONFIG" "$CONFIG_BACKUP"
    fi

    printf 'MAX_BACKUPS=5\n' > "$HOOK_CONFIG"
}

create_isolated_state

printf 'Auto-backup tests\n\n'

# 1) creates a backup when the target file exists
SOURCE_PATH="$WORKDIR/alpha.txt"
printf 'alpha\n' > "$SOURCE_PATH"
ACTUAL_EXIT="$(run_hook "$SOURCE_PATH" "session-1")"
assert_exit 0 "$ACTUAL_EXIT" "backup hook exits 0 for existing file"

COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'alpha.txt.*' | wc -l | tr -d ' ')
if [[ "$COUNT" -ge 1 ]]; then
    printf 'PASS  backup file created for edited file\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  backup file created for edited file (found %s backups)\n' "$COUNT"
    FAIL=$((FAIL + 1))
fi

LOG_PATH="$HOOK_DATA_DIR/session_session-1.log"
if grep -Fq 'BACKUP' "$LOG_PATH" 2>/dev/null; then
    printf 'PASS  backup entry written to session log\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  backup entry missing from session log\n'
    FAIL=$((FAIL + 1))
fi

# 2) non-existent file is a graceful no-op
MISSING_PATH="$WORKDIR/does-not-exist.txt"
BEFORE_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f | wc -l | tr -d ' ')
ACTUAL_EXIT="$(run_hook "$MISSING_PATH" "session-2")"
assert_exit 0 "$ACTUAL_EXIT" "missing file path exits 0"
AFTER_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f | wc -l | tr -d ' ')
if [[ "$BEFORE_COUNT" -eq "$AFTER_COUNT" ]]; then
    printf 'PASS  missing file did not create backup\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  missing file created an unexpected backup (%s -> %s)\n' "$BEFORE_COUNT" "$AFTER_COUNT"
    FAIL=$((FAIL + 1))
fi

# 3) invalid config values should fall back safely instead of crashing
printf 'MAX_BACKUPS=ABC\n' > "$HOOK_CONFIG"
INVALID_PATH="$WORKDIR/invalid-config.txt"
printf 'fallback\n' > "$INVALID_PATH"
ACTUAL_EXIT="$(run_hook "$INVALID_PATH" "session-invalid-config")"
assert_exit 0 "$ACTUAL_EXIT" "invalid MAX_BACKUPS falls back to default"
INVALID_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'invalid-config.txt.*' | wc -l | tr -d ' ')
if [[ "$INVALID_COUNT" -ge 1 ]]; then
    printf 'PASS  invalid MAX_BACKUPS still created a backup\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  invalid MAX_BACKUPS prevented backup creation\n'
    FAIL=$((FAIL + 1))
fi

# 4) zero MAX_BACKUPS should fall back to a safe default instead of disabling backup creation
printf 'MAX_BACKUPS=0\n' > "$HOOK_CONFIG"
ZERO_PATH="$WORKDIR/zero-limit.txt"
printf 'zero\n' > "$ZERO_PATH"
ACTUAL_EXIT="$(run_hook "$ZERO_PATH" "session-zero")"
assert_exit 0 "$ACTUAL_EXIT" "zero MAX_BACKUPS falls back to default"
ZERO_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'zero-limit.txt.*' | wc -l | tr -d ' ')
if [[ "$ZERO_COUNT" -ge 1 ]]; then
    printf 'PASS  zero MAX_BACKUPS still created a backup\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  zero MAX_BACKUPS did not create a backup\n'
    FAIL=$((FAIL + 1))
fi

# 5) negative MAX_BACKUPS should fall back to a safe default instead of disabling backup creation
printf 'MAX_BACKUPS=-3\n' > "$HOOK_CONFIG"
NEGATIVE_PATH="$WORKDIR/negative-limit.txt"
printf 'negative\n' > "$NEGATIVE_PATH"
ACTUAL_EXIT="$(run_hook "$NEGATIVE_PATH" "session-negative")"
assert_exit 0 "$ACTUAL_EXIT" "negative MAX_BACKUPS falls back to default"
NEGATIVE_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'negative-limit.txt.*' | wc -l | tr -d ' ')
if [[ "$NEGATIVE_COUNT" -ge 1 ]]; then
    printf 'PASS  negative MAX_BACKUPS still created a backup\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  negative MAX_BACKUPS did not create a backup\n'
    FAIL=$((FAIL + 1))
fi

# 6) backup directory exists but is not writable should be treated as a no-op
printf 'MAX_BACKUPS=5\n' > "$HOOK_CONFIG"
chmod 0555 "$HOOK_DATA_DIR/.backups"
UNWRITABLE_PATH="$WORKDIR/unwritable.txt"
printf 'not writable\n' > "$UNWRITABLE_PATH"
BEFORE_UNWRITABLE_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f | wc -l | tr -d ' ')
ACTUAL_EXIT="$(run_hook "$UNWRITABLE_PATH" "session-unwritable")"
assert_exit 0 "$ACTUAL_EXIT" "unwritable backup dir exits 0 without crashing"
AFTER_UNWRITABLE_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f | wc -l | tr -d ' ')
if [[ "$BEFORE_UNWRITABLE_COUNT" -eq "$AFTER_UNWRITABLE_COUNT" ]]; then
    printf 'PASS  unwritable backup dir preserved the no-op behavior\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  unwritable backup dir created a backup unexpectedly (%s -> %s)\n' "$BEFORE_UNWRITABLE_COUNT" "$AFTER_UNWRITABLE_COUNT"
    FAIL=$((FAIL + 1))
fi
chmod 0777 "$HOOK_DATA_DIR/.backups"

# 7) backup directory is created automatically when it does not exist yet
rm -rf "$HOOK_DATA_DIR/.backups"
TARGET_PATH="$WORKDIR/beta.txt"
printf 'beta\n' > "$TARGET_PATH"
ACTUAL_EXIT="$(run_hook "$TARGET_PATH" "session-3")"
assert_exit 0 "$ACTUAL_EXIT" "creates backup dir on first use"
assert_exists "$HOOK_DATA_DIR/.backups" "backup directory exists after first backup"
COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'beta.txt.*' | wc -l | tr -d ' ')
if [[ "$COUNT" -ge 1 ]]; then
    printf 'PASS  backup file created after directory creation\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  backup dir was created but no backup file was written\n'
    FAIL=$((FAIL + 1))
fi

# 8) file names with spaces are preserved in backup names
printf 'MAX_BACKUPS=5\n' > "$HOOK_CONFIG"
SPACED_PATH="$WORKDIR/space name.txt"
printf 'spaced\n' > "$SPACED_PATH"
ACTUAL_EXIT="$(run_hook "$SPACED_PATH" "session-space")"
assert_exit 0 "$ACTUAL_EXIT" "paths with spaces still work"
SPACED_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'space name.txt.*' | wc -l | tr -d ' ')
if [[ "$SPACED_COUNT" -ge 1 ]]; then
    printf 'PASS  backup file created for a spaced filename\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  backup file missing for a spaced filename\n'
    FAIL=$((FAIL + 1))
fi

# 9) rotation keeps only MAX_BACKUPS copies
printf 'MAX_BACKUPS=2\n' > "$HOOK_CONFIG"
ROTATION_PATH="$WORKDIR/rotation.txt"
printf 'first\n' > "$ROTATION_PATH"
for i in 1 2 3 4; do
    printf 'v%s\n' "$i" > "$ROTATION_PATH"
    sleep 1
    run_hook "$ROTATION_PATH" "session-rotation" >/dev/null 2>&1
done
ROTATION_COUNT=$(find "$HOOK_DATA_DIR/.backups" -maxdepth 1 -type f -name 'rotation.txt.*' | wc -l | tr -d ' ')
if [[ "$ROTATION_COUNT" -le 2 ]]; then
    printf 'PASS  rotation kept only %s backups (MAX_BACKUPS=2)\n' "$ROTATION_COUNT"
    PASS=$((PASS + 1))
else
    printf 'FAIL  rotation exceeded max backups (%s found, expected <= 2)\n' "$ROTATION_COUNT"
    FAIL=$((FAIL + 1))
fi

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

exit 0
