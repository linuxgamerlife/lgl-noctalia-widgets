#!/usr/bin/env bash
# Removes Modern SysMonitor Plus from upstream Noctalia.
# Upstream Noctalia installs plugins in ~/.local/share/noctalia/plugins and
# writes widget instances to ~/.local/state/noctalia/settings.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="noctalia"
CLI="noctalia"
PLUGIN_ID="unsaidspeech/modern-sysmonitor-plus"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/modern-sysmonitor-plus"
SETTINGS="$STATE_HOME/$APP_DIR/settings.toml"
PLUGIN_DATA="$STATE_HOME/$APP_DIR/plugins/data/unsaidspeech/modern-sysmonitor-plus"
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Removes Modern SysMonitor Plus from upstream Noctalia:
  $PLUGIN_DIR
  $PLUGIN_DATA
  its desktop widget instances in $SETTINGS

Options:
  -y, --yes   Do not ask for confirmation
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will remove Modern SysMonitor Plus:"
    echo "  $PLUGIN_DIR"
    echo "  $PLUGIN_DATA"
    echo "  its desktop widget instances in $SETTINGS"
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# Stop the service through the running shell so no poller is left running.
if [ -z "${NOCTALIA_DATA_HOME:-}" ] && [ -z "${NOCTALIA_STATE_HOME:-}" ] \
    && command -v "$CLI" >/dev/null 2>&1; then
    if "$CLI" msg plugins disable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Disabled $PLUGIN_ID"
        sleep 0.5
    fi
fi

# Remove only this plugin's desktop-widget instances; other widgets stay.
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$SCRIPT_DIR/remove-plugin-widgets.py" ]; then
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" "$PLUGIN_ID:card" || true
else
    echo "==> Skipping widget cleanup (no settings file, python3, or helper)"
fi

rm -rf "$PLUGIN_DIR" "$PLUGIN_DATA"
echo "==> Removed $PLUGIN_DIR"
echo "==> Removed $PLUGIN_DATA"
echo "Done."
