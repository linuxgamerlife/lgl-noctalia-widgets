#!/usr/bin/env bash
# Static/logic tests for the Noctalia port. The tests mock the Noctalia API and
# exercise the service, the card, the bar widget and the panel with LuaJIT; no
# Noctalia session is needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/ai-usage"

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit is required to run these tests" >&2
    exit 1
fi

cd "$REPO_DIR"
for test in "$SCRIPT_DIR"/test_*.luau; do
    echo "==> $(basename "$test")"
    luajit "$test" "ai-usage"
done

echo
echo "All tests passed."
