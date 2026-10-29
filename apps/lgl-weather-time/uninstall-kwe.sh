#!/usr/bin/env bash
# Removes Weather & Time from KineticWE's noctalia-kwe fork.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="noctalia-kwe"
CLI="noctalia-kwe"
PLUGIN_ID="linuxgamerlife/weather-time"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/weather-time"
SETTINGS="$STATE_HOME/$APP_DIR/settings.toml"
PLUGIN_DATA="$STATE_HOME/$APP_DIR/plugins/data/linuxgamerlife/weather-time"
ASSUME_YES=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--yes]

Removes Weather & Time:
  $PLUGIN_DIR
  $PLUGIN_DATA
  its desktop and bar widget instances in $SETTINGS

Options:
  -y, --yes   Do not ask for confirmation
  -h, --help  Show this help
USAGE
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will remove Weather & Time:"
    echo "  $PLUGIN_DIR"
    echo "  $PLUGIN_DATA"
    echo "  its desktop and bar widget instances in $SETTINGS"
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

if [ -z "${NOCTALIA_DATA_HOME:-}" ] && [ -z "${NOCTALIA_STATE_HOME:-}" ] \
    && command -v "$CLI" >/dev/null 2>&1; then
    if "$CLI" msg plugins disable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Disabled $PLUGIN_ID"
        sleep 0.5
    fi
fi

if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$SCRIPT_DIR/remove-plugin-widgets.py" ]; then
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" "$PLUGIN_ID:card" "$PLUGIN_ID:bar" --plugin-id "$PLUGIN_ID" || true
else
    echo "==> Skipping widget cleanup (no settings file, python3, or helper)"
fi

rm -rf "$PLUGIN_DIR" "$PLUGIN_DATA"
echo "==> Removed $PLUGIN_DIR"
echo "==> Removed $PLUGIN_DATA"
echo "Done."
