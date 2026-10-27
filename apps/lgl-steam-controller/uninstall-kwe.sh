#!/usr/bin/env bash
# Removes the Steam Controller plugin from KineticWE's noctalia-kwe fork.
# noctalia-kwe installs plugins in ~/.local/share/noctalia-kwe/plugins and
# writes widget instances to ~/.local/state/noctalia-kwe/settings.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="noctalia-kwe"
CLI="noctalia-kwe"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/steam-controller"
SETTINGS="$STATE_HOME/$APP_DIR/settings.toml"
PLUGIN_DATA="$STATE_HOME/$APP_DIR/plugins/data/jahrek/steam-controller"
LOCK="$RUNTIME_DIR/noctalia-sc-battery.lock"
STATE="$RUNTIME_DIR/noctalia-sc-battery.json"
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Removes the Steam Controller plugin from noctalia-kwe:
  $PLUGIN_DIR
  $PLUGIN_DATA
  its desktop widget instances in $SETTINGS
  $LOCK and $STATE

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
    echo "This will remove the Steam Controller plugin:"
    echo "  $PLUGIN_DIR"
    echo "  $PLUGIN_DATA"
    echo "  its desktop widget instances in $SETTINGS"
    echo "  $LOCK and $STATE"
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# Stop the service through the running shell so its onExit hook cleans up.
if [ -z "${NOCTALIA_DATA_HOME:-}" ] && [ -z "${NOCTALIA_STATE_HOME:-}" ] \
    && command -v "$CLI" >/dev/null 2>&1; then
    if "$CLI" msg plugins disable jahrek/steam-controller >/dev/null 2>&1; then
        echo "==> Disabled jahrek/steam-controller"
        sleep 0.5
    fi
fi

# Remove only this plugin's desktop-widget instances; other widgets stay.
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$SCRIPT_DIR/remove-plugin-widgets.py" ]; then
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" "jahrek/steam-controller:card" || true
else
    echo "==> Skipping widget cleanup (no settings file, python3, or helper)"
fi

# Kill a daemon left behind if the service was not running.
if [ -f "$LOCK" ]; then
    PID="$(tr -dc '0-9' < "$LOCK" || true)"
    if [ -n "$PID" ] && [ "$PID" -gt 1 ] 2>/dev/null; then
        if [ -r "/proc/$PID/cmdline" ] \
            && tr '\0' ' ' < "/proc/$PID/cmdline" | grep -q "sc_battery_daemon.py"; then
            kill "$PID" 2>/dev/null || true
            sleep 0.3
        fi
    fi
fi
rm -f "$LOCK" "$STATE"

rm -rf "$PLUGIN_DIR" "$PLUGIN_DATA"
echo "==> Removed $PLUGIN_DIR"
echo "==> Removed $PLUGIN_DATA"
echo "==> Removed runtime state and lock"
echo "Done."
