#!/usr/bin/env bash
# Installs the AI Usage plugin for upstream Noctalia.
# Upstream Noctalia reads plugins from ~/.local/share/noctalia/plugins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/ai-usage"
APP_DIR="noctalia"
CLI="noctalia"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
PLUGIN_ID="lukk17/ai-usage"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/ai-usage"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "error: $SOURCE_DIR not found" >&2
    exit 1
fi

mkdir -p "$DATA_HOME/$APP_DIR/plugins"

if [ -e "$PLUGIN_DIR" ] && [ ! -L "$PLUGIN_DIR" ]; then
    echo "==> Replacing existing copy at $PLUGIN_DIR"
    rm -rf "$PLUGIN_DIR"
fi

ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR"

echo "==> Installed Noctalia plugin at $PLUGIN_DIR"

# Refresh and enable when the shell is running. Skip the live calls if
# NOCTALIA_DATA_HOME points at a non-default location.
if [ -n "${NOCTALIA_DATA_HOME:-}" ]; then
    echo "==> NOCTALIA_DATA_HOME is set; enable 'AI Usage' manually"
elif command -v "$CLI" >/dev/null 2>&1 && "$CLI" msg config-reload >/dev/null 2>&1; then
    sleep 0.3
    if "$CLI" msg plugins enable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Enabled $PLUGIN_ID"
    else
        echo "==> Enable 'AI Usage' in Settings -> Plugins"
    fi
else
    echo "==> $CLI is not running; enable 'AI Usage' in Settings -> Plugins"
fi

echo
echo "Next: open Settings -> Desktop -> Toggle Editor and add 'AI Usage'."
echo "Then click the card (or the bar widget) and press 'Add account'."
