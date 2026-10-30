#!/usr/bin/env bash
# Installs LGL KBM Overlay for upstream Noctalia.
# Upstream Noctalia reads plugins from ~/.local/share/noctalia/plugins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/kbm-overlay"
APP_DIR="noctalia"
CLI="noctalia"
PLUGIN_ID="linuxgamerlife/kbm-overlay"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/kbm-overlay"

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

if [ -n "${NOCTALIA_DATA_HOME:-}" ]; then
    echo "==> NOCTALIA_DATA_HOME is set; enable 'LGL KBM Overlay' manually"
elif command -v "$CLI" >/dev/null 2>&1 && "$CLI" msg config-reload >/dev/null 2>&1; then
    sleep 0.3
    if "$CLI" msg plugins enable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Enabled $PLUGIN_ID"
    else
        echo "==> Enable 'LGL KBM Overlay' in Settings -> Plugins"
    fi
else
    echo "==> $CLI is not running; enable 'LGL KBM Overlay' in Settings -> Plugins"
fi

echo
echo "Next:"
echo "  1. Open the device picker:"
echo "     $CLI msg panel-toggle $PLUGIN_ID:devices"
echo "  2. Select a keyboard and a mouse."
echo "  3. Install the narrow udev rule:"
echo "     bash $SOURCE_DIR/code/setup-input-permissions.sh"
echo "  4. Add 'LGL KBM Overlay' in Settings -> Desktop -> Desktop widgets."
echo "  5. Add the KBM bar widget for a quick device-picker shortcut."
