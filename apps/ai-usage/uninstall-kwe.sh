#!/usr/bin/env bash
# Removes the AI Usage plugin from KineticWE's noctalia-kwe fork.
# noctalia-kwe installs plugins in ~/.local/share/noctalia-kwe/plugins and
# writes widget instances to ~/.local/state/noctalia-kwe/settings.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="noctalia-kwe"
CLI="noctalia-kwe"
DATA_HOME="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}"
STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
PLUGIN_ID="lukk17/ai-usage"
PLUGIN_DIR="$DATA_HOME/$APP_DIR/plugins/ai-usage"
SETTINGS="$STATE_HOME/$APP_DIR/settings.toml"
PLUGIN_DATA="$STATE_HOME/$APP_DIR/plugins/data/lukk17/ai-usage"
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Removes the AI Usage plugin from noctalia-kwe:
  $PLUGIN_DIR
  $PLUGIN_DATA
  its desktop-widget and bar-widget instances in $SETTINGS

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
    echo "This will remove the AI Usage plugin:"
    echo "  $PLUGIN_DIR"
    echo "  $PLUGIN_DATA"
    echo "  its widget instances in $SETTINGS"
    echo
    echo "Keys stored in the Secret Service under server=ai-usage are left alone."
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# Disable the plugin so noctalia-kwe stops the service and tears down its runtimes.
if [ -z "${NOCTALIA_DATA_HOME:-}" ] && [ -z "${NOCTALIA_STATE_HOME:-}" ] \
    && command -v "$CLI" >/dev/null 2>&1; then
    if "$CLI" msg plugins disable "$PLUGIN_ID" >/dev/null 2>&1; then
        echo "==> Disabled $PLUGIN_ID"
        sleep 0.5
    fi
fi

# Remove only this plugin's widget instances; other widgets stay.
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$SCRIPT_DIR/remove-plugin-widgets.py" ]; then
    python3 "$SCRIPT_DIR/remove-plugin-widgets.py" \
        "$SETTINGS" \
        "lukk17/ai-usage:card" "lukk17/ai-usage:usage" \
        --plugin-id lukk17/ai-usage || true
else
    echo "==> Skipping widget cleanup (no settings file, python3, or helper)"
fi

rm -rf "$PLUGIN_DIR" "$PLUGIN_DATA"
echo "==> Removed $PLUGIN_DIR"
echo "==> Removed $PLUGIN_DATA"
echo "Done."
