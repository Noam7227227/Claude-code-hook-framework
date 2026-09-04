#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/.claude/hooks/pre_command_firewall.sh"

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

make_bash_json() {
    local command="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"test-session-1"}' "$command"
}

run_case() {
    local name="$1"
    local command="$2"
    local expected_exit="$3"

    set +e
    make_bash_json "$command" | "$HOOK_PATH" >/dev/null 2>&1
    local actual_exit=$?

    assert_exit "$expected_exit" "$actual_exit" "$name"
}

run_non_bash_case() {
    set +e
    printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' | "$HOOK_PATH" >/dev/null 2>&1
    local actual_exit=$?

    assert_exit 0 "$actual_exit" "non-Bash tool should pass without inspection"
}

printf 'Command Firewall tests\n\n'

run_case "safe command should be allowed" "ls -la" 0
run_non_bash_case
run_case "rm -rf should be blocked" "rm -rf /home/user" 2
run_case "force push should be blocked" "git push origin main --force" 2
run_case "recursive chmod 777 should be blocked" "chmod -R 777 /etc" 2
run_case "git reset --hard should be blocked" "git reset --hard HEAD~1" 2

error_output="$(make_bash_json "rm -rf /tmp/x" | "$HOOK_PATH" 2>&1 1>/dev/null)"
assert_contains "BLOCKED" "$error_output" "blocked message should contain BLOCKED"

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

exit 0