#!/usr/bin/env bash
#
# run_all.sh - discovers and runs every test file in tests/, in order.
# New hooks add a new tests/NN_<hook_name>.sh file
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
TEST_FILES=("$SCRIPT_DIR"/*.sh)
shopt -u nullglob

# Exclude this runner itself from the discovered list
FILTERED=()
for f in "${TEST_FILES[@]}"; do
    [[ "$(basename "$f")" == "run_all.sh" ]] && continue
    FILTERED+=("$f")
done

if [[ ${#FILTERED[@]} -eq 0 ]]; then
    echo "No test files found yet under tests/ — nothing to run."
    exit 0
fi

TOTAL_PASS=0
TOTAL_FAIL=0

for test_file in "${FILTERED[@]}"; do
    echo "=== Running $(basename "$test_file") ==="
    if bash "$test_file"; then
        echo "--- $(basename "$test_file") PASSED ---"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "--- $(basename "$test_file") FAILED ---"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo
done

echo "============================="
echo "Test files passed: $TOTAL_PASS"
echo "Test files failed: $TOTAL_FAIL"
echo "============================="

[[ $TOTAL_FAIL -eq 0 ]]