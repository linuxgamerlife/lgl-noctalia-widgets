#!/usr/bin/env bash
# Static/logic tests for the DualSense Noctalia plugin. They mock the Noctalia
# API and exercise the service and card scripts with LuaJIT; no Noctalia
# session needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../dualsense" && pwd)"

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit is required to run these tests" >&2
    exit 1
fi

echo "==> test_daemon.py"
python3 "$SCRIPT_DIR/test_daemon.py"

for test in "$SCRIPT_DIR"/test_*.luau; do
    echo "==> $(basename "$test")"
    luajit "$test" "$PLUGIN_DIR"
done
