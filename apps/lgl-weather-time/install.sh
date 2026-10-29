#!/usr/bin/env bash
# Installs Weather & Time for upstream Noctalia.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/weather-time"
APP_DIR="noctalia"
CLI="noctalia"
PLUGIN_ID="linuxgamerlife/weather-time"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/weather-time"

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
    echo "==> NOCTALIA_DATA_HOME is set; enable 'Weather & Time' manually"
elif command -v "$CLI" >/dev/null 2>&1 && "$CLI" msg config-reload >/dev/null 2>&1; then
    sleep 0.3
    if "$CLI" msg plugins enable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Enabled $PLUGIN_ID"
    else
        echo "==> Enable 'Weather & Time' in Settings -> Plugins"
    fi
else
    echo "==> $CLI is not running; enable 'Weather & Time' in Settings -> Plugins"
fi

echo
echo "Next: open Settings -> Desktop -> Toggle Editor and add 'Weather & Time'."
echo "Then click the card and set a location."
