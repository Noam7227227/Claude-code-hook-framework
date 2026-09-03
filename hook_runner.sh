#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: echo '<json>' | ./hook_runner.sh <EVENT> <TOOL_NAME>" >&2
}

event="${1:-}"
tool_name="${2:-}"

if [[ -z "$event" || -z "$tool_name" ]]; then
    usage
    exit 1
fi

case "$event" in
    PreToolUse|PostToolUse|Stop)
        ;;
    *)
        usage
        exit 1
        ;;
esac

payload="$(cat)"
if [[ -z "$payload" ]]; then
    echo "Error: JSON payload is empty" >&2
    exit 1
fi

echo "No hooks are registered yet for $event/$tool_name" >&2
exit 0