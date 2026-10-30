#!/usr/bin/env bash
# Create or remove a narrow udev rule for the keyboard and mouse selected in
# the LGL KBM Overlay device picker.
#
# The rule uses TAG+="uaccess", which grants read access to the active seat
# user for the matched vendor/product only. It does not add the user to the
# broad "input" group and does not run a root daemon.
set -euo pipefail

RULE="/etc/udev/rules.d/70-lgl-kbm-overlay.rules"
ASSUME_YES=0
REMOVE=0
PRINT_ONLY=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--yes] [--print] [--remove]

Creates $RULE from the keyboard and mouse selected in the plugin's
Device picker. --remove deletes the rule. The rule is scoped to the selected
devices' vendor/product IDs and grants access only to the active user.

Options:
  -y, --yes    Do not ask for confirmation
  --print      Print the rule without installing it (no root needed)
  --remove     Remove the rule instead of creating it
  -h, --help   Show this help
USAGE
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --print) PRINT_ONLY=1 ;;
        --remove) REMOVE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$PRINT_ONLY" -eq 0 ]; then
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "error: root or sudo is required to install the udev rule" >&2
        exit 1
    fi
fi

if [ "$REMOVE" -eq 1 ]; then
    if [ ! -e "$RULE" ]; then
        echo "No rule at $RULE"
        exit 0
    fi
    if [ "$ASSUME_YES" -ne 1 ]; then
        read -r -p "Remove $RULE? [y/N] " reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *) echo "Cancelled."; exit 0 ;;
        esac
    fi
    $SUDO rm -f "$RULE"
    $SUDO udevadm control --reload-rules
    $SUDO udevadm trigger --subsystem-match=input
    echo "Removed $RULE"
    exit 0
fi

STATE_HOME="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
CONFIG=""
for candidate in \
    "$STATE_HOME/noctalia-kwe/plugins/data/linuxgamerlife/kbm-overlay/devices.json" \
    "$STATE_HOME/noctalia/plugins/data/linuxgamerlife/kbm-overlay/devices.json"; do
    if [ -f "$candidate" ]; then
        CONFIG="$candidate"
        break
    fi
done

if [ -z "$CONFIG" ]; then
    echo "error: no device selection found." >&2
    echo "Open the KBM Overlay Device picker, select a keyboard and mouse, then run this again." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required" >&2
    exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
python3 - "$CONFIG" >"$TMP" <<'PY'
import json
import re
import sys

path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError) as error:
    raise SystemExit(f"error: could not read {path}: {error}")

if not isinstance(data, dict):
    raise SystemExit("error: devices.json must contain an object")

USB_ID = re.compile(r"^[0-9a-f]{4}$")
entries = []
for kind in ("keyboard", "mouse"):
    vendor = str(data.get(f"{kind}_vendor") or "").lower()
    product = str(data.get(f"{kind}_product") or "").lower()
    if not USB_ID.fullmatch(vendor) or not USB_ID.fullmatch(product):
        raise SystemExit(
            f"error: {kind} has invalid USB vendor/product IDs; "
            "select the device again in the plugin panel"
        )
    entries.append((vendor, product))

seen = set()
for vendor, product in entries:
    key = (vendor, product)
    if key in seen:
        continue
    seen.add(key)
    print(f"# LGL KBM Overlay: {vendor}:{product}")
    print(
        f'SUBSYSTEM=="input", KERNEL=="event*", '
        f'ATTRS{{id/vendor}}=="{vendor}", ATTRS{{id/product}}=="{product}", '
        f'TAG+="uaccess"'
    )
PY

if ! grep -q '^SUBSYSTEM==' "$TMP"; then
    echo "error: no valid udev rule was generated." >&2
    exit 1
fi

if [ "$PRINT_ONLY" -eq 1 ]; then
    cat "$TMP"
    exit 0
fi

echo "Rule to install at $RULE:"
echo
cat "$TMP"
echo

if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Install this rule? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

$SUDO install -m 0644 "$TMP" "$RULE"
$SUDO udevadm control --reload-rules
$SUDO udevadm trigger --subsystem-match=input
echo
echo "Installed $RULE"
echo "If the overlay still reports permission denied, replug the selected"
echo "keyboard/mouse or log out and back in so the ACL is applied."
