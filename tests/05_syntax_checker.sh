#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_PATH="$REPO_ROOT/.claude/hooks/post_syntax_checker.sh"
HOOK_DATA_DIR="$REPO_ROOT/.claude/hooks/data"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/syntax-checker-test.XXXXXX")"

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

run_hook() {
    local file_path="$1"
    local session_id="$2"
    local payload
    payload="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$file_path\"},\"session_id\":\"$session_id\"}"

    set +e
    HOOK_OUTPUT="$(printf '%s' "$payload" | bash "$HOOK_PATH" 2>&1)"
    HOOK_EXIT=$?
    set -e
}

if [[ -d "$HOOK_DATA_DIR" ]]; then
    DATA_BACKUP="$WORKDIR/original_data"
    mv "$HOOK_DATA_DIR" "$DATA_BACKUP"
fi
mkdir -p "$HOOK_DATA_DIR"

printf 'Syntax checker tests\n\n'

VALID_SH="$WORKDIR/valid.sh"
printf '#!/bin/bash\necho "hello world"\n' > "$VALID_SH"
run_hook "$VALID_SH" "syntax-session"
assert_exit 0 "$HOOK_EXIT" "valid .sh file passes syntax check"
assert_output_contains "Syntax OK" "$HOOK_OUTPUT" "valid .sh output says Syntax OK"

INVALID_SH="$WORKDIR/invalid.sh"
printf '#!/bin/bash\nif [ -z "" \n  echo "unclosed"\n' > "$INVALID_SH"
run_hook "$INVALID_SH" "syntax-session"
assert_exit 1 "$HOOK_EXIT" "invalid .sh file returns warning exit 1"
assert_output_contains "SYNTAX ERROR" "$HOOK_OUTPUT" "invalid .sh output says SYNTAX ERROR"

LOG_PATH="$HOOK_DATA_DIR/session_syntax-session.log"
assert_output_contains "SYNTAX_OK" "$(cat "$LOG_PATH" 2>/dev/null)" "log contains SYNTAX_OK entry"
assert_output_contains "SYNTAX_ERROR" "$(cat "$LOG_PATH" 2>/dev/null)" "log contains SYNTAX_ERROR entry"

UNKNOWN_FILE="$WORKDIR/unknown.xyz"
printf 'some content\n' > "$UNKNOWN_FILE"
run_hook "$UNKNOWN_FILE" "syntax-session"
assert_exit 0 "$HOOK_EXIT" "unknown extension exits 0"

run_hook "$WORKDIR/missing.sh" "syntax-session"
assert_exit 0 "$HOOK_EXIT" "missing file exits 0"

if command -v python3 >/dev/null 2>&1; then
    VALID_PY="$WORKDIR/valid.py"
    printf 'def hello():\n    print("hello")\n' > "$VALID_PY"
    run_hook "$VALID_PY" "python-session"
    assert_exit 0 "$HOOK_EXIT" "valid .py file passes syntax check"
    assert_output_contains "Syntax OK" "$HOOK_OUTPUT" "valid .py output says Syntax OK"

    INVALID_PY="$WORKDIR/invalid.py"
    printf 'def hello(\n    print("unclosed")\n' > "$INVALID_PY"
    run_hook "$INVALID_PY" "python-session"
    assert_exit 1 "$HOOK_EXIT" "invalid .py file returns warning exit 1"
else
    printf 'SKIP  python3 not found - skipping Python syntax tests\n'
fi

if command -v gcc >/dev/null 2>&1; then
    VALID_C="$WORKDIR/valid.c"
    printf '#include <stdio.h>\nint main() { return 0; }\n' > "$VALID_C"
    run_hook "$VALID_C" "c-session"
    assert_exit 0 "$HOOK_EXIT" "valid .c file passes syntax check"
    assert_output_contains "Syntax OK" "$HOOK_OUTPUT" "valid .c output says Syntax OK"

    INVALID_C="$WORKDIR/invalid.c"
    printf 'int main() { return\n' > "$INVALID_C"
    run_hook "$INVALID_C" "c-session"
    assert_exit 1 "$HOOK_EXIT" "invalid .c file returns warning exit 1"
else
    printf 'SKIP  gcc not found - skipping C syntax tests\n'
fi

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]