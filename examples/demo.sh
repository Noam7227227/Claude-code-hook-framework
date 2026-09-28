#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_DIR/hook_runner.sh"

PASS=0
FAIL=0

run_case() {
    local name="$1"
    local expected_exit="$2"
    local payload="$3"
    local event="$4"
    local tool="$5"
    local output
    local actual_exit

    printf '\n=== %s ===\n' "$name"
    set +e
    output="$(printf '%s' "$payload" | bash "$RUNNER" "$event" "$tool" 2>&1)"
    actual_exit=$?
    set -e
    printf '%s\n' "$output"

    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        PASS=$((PASS + 1))
    else
        printf 'FAIL: expected exit %d, got %d\n' "$expected_exit" "$actual_exit" >&2
        FAIL=$((FAIL + 1))
    fi
}

printf 'AI Agent Hook Framework demo\n'
printf 'This simulates decisions made before and after an agent action.\n'

run_case \
    "Safe command is allowed" \
    0 \
    '{"tool_name":"Bash","tool_input":{"command":"printf hello"},"session_id":"demo"}' \
    PreToolUse Bash

run_case \
    "Dangerous command is blocked" \
    2 \
    '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/demo"},"session_id":"demo"}' \
    PreToolUse Bash

run_case \
    "Secret file read is blocked" \
    2 \
    '{"tool_name":"Read","tool_input":{"file_path":"/workspace/.env"},"session_id":"demo"}' \
    PreToolUse Read

printf '\nDemo checks: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]