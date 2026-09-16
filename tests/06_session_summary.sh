#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_ROOT/.claude/hooks/post_session_summary.sh"
HOOK_DATA_DIR="$REPO_ROOT/.claude/hooks/data"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/session-summary-test.XXXXXX")"

PASS=0
FAIL=0
DATA_BACKUP=""

cleanup() {
    if [[ -n "$DATA_BACKUP" && -d "$DATA_BACKUP" ]]; then
        rm -rf "$HOOK_DATA_DIR"
        mv "$DATA_BACKUP" "$HOOK_DATA_DIR"
    else
        rm -rf "$HOOK_DATA_DIR"
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

assert_output_contains() {
    local needle="$1"
    local output="$2"
    local name="$3"

    if [[ "$output" == *"$needle"* ]]; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (expected output to contain: %s)\n' "$name" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

if [[ -d "$HOOK_DATA_DIR" ]]; then
    DATA_BACKUP="$WORKDIR/original_data"
    mv "$HOOK_DATA_DIR" "$DATA_BACKUP"
fi
mkdir -p "$HOOK_DATA_DIR"

printf 'Session summary tests\n\n'

set +e
OUTPUT="$(printf '{"session_id":"s1","stop_hook_active":true}' | bash "$HOOK_PATH" 2>&1)"
HOOK_EXIT=$?
set -e
assert_exit 0 "$HOOK_EXIT" "stop_hook_active=true exits 0"
if [[ -z "$OUTPUT" ]]; then
    printf 'PASS  stop_hook_active=true produces no output\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  stop_hook_active=true produces unexpected output: %s\n' "$OUTPUT"
    FAIL=$((FAIL + 1))
fi

set +e
OUTPUT="$(printf '{"session_id":"s1","stop_hook_active":false}' | bash "$HOOK_PATH" 2>&1)"
HOOK_EXIT=$?
set -e
assert_exit 0 "$HOOK_EXIT" "missing log exits 0"
assert_output_contains "No session activity recorded" "$OUTPUT" "missing log reports no session activity"

NOW_TS="$(date '+%Y-%m-%d %H:%M:%S')"
cat > "$HOOK_DATA_DIR/session_test-session-abc.log" <<EOF
[$NOW_TS] BACKUP src/main.c -> $HOOK_DATA_DIR/.backups/main.c.20240101_120000 (512 bytes)
[$NOW_TS] SYNTAX_OK src/main.c (c)
[$NOW_TS] BACKUP src/main.c -> $HOOK_DATA_DIR/.backups/main.c.20240101_120001 (520 bytes)
[$NOW_TS] BACKUP src/utils.h -> $HOOK_DATA_DIR/.backups/utils.h.20240101_120002 (128 bytes)
[$NOW_TS] SYNTAX_ERROR src/broken.c (c)
[$NOW_TS] SYNTAX_OK src/utils.h (c)
EOF

set +e
OUTPUT="$(printf '{"session_id":"test-session-abc","stop_hook_active":false}' | bash "$HOOK_PATH" 2>&1)"
HOOK_EXIT=$?
set -e
assert_exit 0 "$HOOK_EXIT" "session summary exits 0"
assert_output_contains "SESSION SUMMARY REPORT" "$OUTPUT" "report contains header"
assert_output_contains "test-session-abc" "$OUTPUT" "report contains session ID"
assert_output_contains "Backups made: 3" "$OUTPUT" "report contains backup count"
assert_output_contains "Syntax checks: 3" "$OUTPUT" "report contains syntax check count"
assert_output_contains "Syntax errors: 1" "$OUTPUT" "report contains syntax error count"
assert_output_contains "Total actions: 6" "$OUTPUT" "report contains total action count"
assert_output_contains "main.c" "$OUTPUT" "report lists most-edited file"

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]