#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_DIR/.claude/hooks/pre_commit_validator.sh"

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
    local should_contain="${4:-}"

    local output
    set +e
    output="$(make_bash_json "$command" | bash "$HOOK_PATH" 2>&1)"
    local actual_exit=$?
    set -e

    assert_exit "$expected_exit" "$actual_exit" "$name"
    if [[ -n "$should_contain" ]]; then
        assert_contains "$should_contain" "$output" "$name (stderr check)"
    fi
}

printf 'Commit Validator tests\n\n'

run_case "valid conventional commit should pass" "git commit -m 'feat: add login page'" 0
run_case "valid fix commit should pass" "git commit -m 'fix: correct off-by-one error'" 0
run_case "non-commit command should pass" "ls -la" 0
run_case "git commit without -m should pass" "git commit" 0
run_case "git commit -am should pass" "git commit -am 'feat: add user auth module'" 0
run_case "git commit -a -m should pass" "git commit -a -m 'fix: handle null pointer case'" 0

run_case \
    "missing prefix should be blocked" \
    "git commit -m 'added stuff'" \
    2 \
    "Missing commit prefix. Based on your changes, try: 'feat: added stuff'"
run_case "message too short should be blocked" "git commit -m 'fix: bug'" 2
LONG_MSG="feat: this commit message is intentionally over seventy-two characters long"
run_case "message over 72 characters should be blocked" "git commit -m '$LONG_MSG'" 2
run_case "message ending with period should be blocked" "git commit -m 'feat: add user authentication.'" 2

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

exit 0
