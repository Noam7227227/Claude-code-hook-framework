#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/.claude/hooks/pre_secrets_guard.sh"

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

run_case() {
    local name="$1"
    local payload="$2"
    local expected_exit="$3"
    local should_contain="${4:-}"

    local output
    set +e
    output="$(printf '%s' "$payload" | bash "$HOOK_PATH" 2>&1)"
    local actual_exit=$?
    set -e

    assert_exit "$expected_exit" "$actual_exit" "$name"

    if [[ -n "$should_contain" ]]; then
        assert_contains "$should_contain" "$output" "$name (stderr check)"
    fi
}

printf 'Secrets Guard tests\n\n'

run_case \
    "safe README read should be allowed" \
    '{"tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"s1"}' \
    0

run_case \
    "secret .env read should be blocked" \
    '{"tool_name":"Read","tool_input":{"file_path":".env"},"session_id":"s1"}' \
    2 \
    "BLOCKED"

run_case \
    "nested secret file path should be blocked" \
    '{"tool_name":"Read","tool_input":{"file_path":"folder/.env"},"session_id":"s1"}' \
    2 \
    "BLOCKED"

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

exit 0
