#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/.claude/hooks/pre_rate_limiter.sh"
DATA_DIR="$REPO_DIR/.claude/hooks/data"
CONFIG_PATH="$REPO_DIR/.claude/hooks/config/hooks.conf"

PASS=0
FAIL=0

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

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local name="$3"

    if printf '%s' "$haystack" | grep -Eq "$needle"; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (expected output to contain: %s)\n' "$name" "$needle"
        printf '      got: %s\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

make_bash_json() {
    local command="$1"
    local session_id="$2"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"%s"}' \
        "$command" "$session_id"
}

reset_state() {
    mkdir -p "$DATA_DIR"
    rm -f "$DATA_DIR/.command_count" "$DATA_DIR/.command_count.tmp" "$DATA_DIR/.reset_commands"
}

run_hook() {
    local command="$1"
    local session_id="$2"
    local output

    set +e
    output="$(make_bash_json "$command" "$session_id" | bash "$HOOK_PATH" 2>&1)"
    RUN_EXIT=$?
    set -e
    RUN_OUTPUT="$output"
}

ORIGINAL_CONFIG="$(mktemp)"
cp "$CONFIG_PATH" "$ORIGINAL_CONFIG"
cleanup() {
    cp "$ORIGINAL_CONFIG" "$CONFIG_PATH"
    rm -f "$ORIGINAL_CONFIG"
    reset_state
}
trap cleanup EXIT

printf 'Rate Limiter tests\n\n'

reset_state
run_hook "ls" "sess-rl-default"
assert_exit 0 "$RUN_EXIT" "Command 1 under the default limit should pass"
run_hook "pwd" "sess-rl-default"
assert_exit 0 "$RUN_EXIT" "Command 2 under the default limit should pass"
run_hook "echo hi" "sess-rl-default"
assert_exit 0 "$RUN_EXIT" "Command 3 under the default limit should pass"

printf 'MAX_COMMANDS=3\nWARNING_THRESHOLD=2\n' > "$CONFIG_PATH"
reset_state
run_hook "ls" "sess-rl-limited"
assert_exit 0 "$RUN_EXIT" "Command 1 of 3 should pass"
run_hook "pwd" "sess-rl-limited"
assert_exit 0 "$RUN_EXIT" "Command 2 of 3 should pass"
run_hook "echo third" "sess-rl-limited"
assert_exit 0 "$RUN_EXIT" "Command 3 at the limit should pass"
assert_contains 'WARNING|warning|limit|threshold' "$RUN_OUTPUT" \
    "Command 3 should emit a warning"
run_hook "echo fourth" "sess-rl-limited"
assert_exit 2 "$RUN_EXIT" "Command 4 over the limit should be blocked"

run_hook "ls" "sess-rl-other"
assert_exit 0 "$RUN_EXIT" "A different session should start fresh"

touch "$DATA_DIR/.reset_commands"
run_hook "ls" "sess-rl-limited"
assert_exit 0 "$RUN_EXIT" "Reset trigger should allow the previously blocked session"
if [[ ! -f "$DATA_DIR/.reset_commands" ]]; then
    printf 'PASS  Reset trigger should be removed after use\n'
    PASS=$((PASS + 1))
else
    printf 'FAIL  Reset trigger should be removed after use\n'
    FAIL=$((FAIL + 1))
fi

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]