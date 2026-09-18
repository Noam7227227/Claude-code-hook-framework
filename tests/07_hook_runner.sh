#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER_PATH="$REPO_DIR/hook_runner.sh"
DATA_DIR="$REPO_DIR/.claude/hooks/data"

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

    if printf '%s' "$haystack" | grep -Fq "$needle"; then
        printf 'PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %s (expected output to contain: %s)\n' "$name" "$needle"
        printf '      got: %s\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

TEST_FILE="$(mktemp --suffix=.sh)"
SESSION_ID="hook-runner-test-$$"
trap 'rm -f "$TEST_FILE" "$DATA_DIR/session_$SESSION_ID.log"' EXIT
printf '#!/bin/bash\necho ok\n' > "$TEST_FILE"

printf 'Hook Runner tests\n\n'

SAFE_OUTPUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"runner-safe"}' | bash "$RUNNER_PATH" PreToolUse Bash 2>&1)"
SAFE_EXIT=$?
assert_exit 0 "$SAFE_EXIT" "safe command should pass all matching PreToolUse hooks"
assert_contains "Matched:  3 hooks" "$SAFE_OUTPUT" "PreToolUse/Bash should match three hooks"
assert_contains "Passed:   3" "$SAFE_OUTPUT" "all matching PreToolUse hooks should run"

BLOCK_OUTPUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /home"},"session_id":"runner-block"}' | bash "$RUNNER_PATH" PreToolUse Bash 2>&1)"
BLOCK_EXIT=$?
assert_exit 2 "$BLOCK_EXIT" "dangerous command should be blocked by the runner"
assert_contains "Matched:  1 hooks" "$BLOCK_OUTPUT" "blocking hook should stop the matching chain"
assert_contains "Chain stopped" "$BLOCK_OUTPUT" "runner should report the stopped chain"

POST_OUTPUT="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"tool_response":{"filePath":"%s"},"session_id":"%s"}' "$TEST_FILE" "$TEST_FILE" "$SESSION_ID" | bash "$RUNNER_PATH" PostToolUse Edit 2>&1)"
POST_EXIT=$?
assert_exit 0 "$POST_EXIT" "valid edit should pass all matching PostToolUse hooks"
assert_contains "Matched:  2 hooks" "$POST_OUTPUT" "PostToolUse/Edit should match two hooks"
assert_contains "Passed:   2" "$POST_OUTPUT" "all matching PostToolUse hooks should run"

STOP_OUTPUT="$(printf '{"session_id":"%s","stop_hook_active":false}' "$SESSION_ID" | bash "$RUNNER_PATH" Stop '*' 2>&1)"
STOP_EXIT=$?
assert_exit 0 "$STOP_EXIT" "Stop event should run the wildcard hook"
assert_contains "Matched:  1 hooks" "$STOP_OUTPUT" "Stop wildcard route should match one hook"

UNMATCHED_OUTPUT="$(printf '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}' | bash "$RUNNER_PATH" PreToolUse Write 2>&1)"
UNMATCHED_EXIT=$?
assert_exit 0 "$UNMATCHED_EXIT" "unmatched event and tool should be a no-op"
assert_contains "Matched:  0 hooks" "$UNMATCHED_OUTPUT" "unmatched route should run no hooks"

INVALID_OUTPUT="$(bash "$RUNNER_PATH" 2>&1)"
INVALID_EXIT=$?
assert_exit 1 "$INVALID_EXIT" "runner with missing arguments should exit non-zero"
assert_contains "Usage:" "$INVALID_OUTPUT" "missing arguments should print usage"

EMPTY_OUTPUT="$(printf '' | bash "$RUNNER_PATH" PreToolUse Bash 2>&1)"
EMPTY_EXIT=$?
assert_exit 1 "$EMPTY_EXIT" "runner with empty stdin should exit non-zero"
assert_contains "JSON payload is empty" "$EMPTY_OUTPUT" "empty stdin should report the payload error"

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

exit 0
