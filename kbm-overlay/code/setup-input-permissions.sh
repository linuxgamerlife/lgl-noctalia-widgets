#!/usr/bin/env bash
# Create or remove the udev rule for keyboards and mice selected in the LGL KBM
# Overlay device picker.
#
# The rule uses TAG+="uaccess", which grants read access to the active seat
# user for the matched vendor/product only. It does not add the user to the
# broad "input" group and does not run a root daemon.
#
# Running the helper again adds the current selection to the rule instead of
# replacing earlier entries, so switching back to a previously used device
# keeps working. Use --reset to keep only the current selection.
set -euo pipefail

RULE="${KBM_UDEV_RULE:-/etc/udev/rules.d/70-lgl-kbm-overlay.rules}"
ASSUME_YES=0
REMOVE=0
PRINT_ONLY=0
RESET=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--yes] [--print] [--remove] [--reset]

Creates $RULE from the keyboard and mouse selected in the plugin's
Device picker. Devices allowed by an existing rule are kept, so switching
between them does not need another root step. --remove deletes the rule.
The rule is scoped to each device's vendor/product ID and grants access only
to the active user.

Options:
  -y, --yes    Do not ask for confirmation
  --print      Print the rule without installing it (no root needed)
  --remove     Remove the rule instead of creating it
  --reset      Regenerate the rule from the current selection only, dropping
               devices allowed by an earlier run
  -h, --help   Show this help
USAGE
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --print) PRINT_ONLY=1 ;;
        --remove) REMOVE=1 ;;
        --reset) RESET=1 ;;
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
OLD_TMP=""
cleanup() {
    rm -f "$TMP" ${OLD_TMP:+"$OLD_TMP"}
}
trap cleanup EXIT

# The installed rule is normally world-readable. When it is not, read it with
# root so previously allowed devices are still carried over.
EXISTING=""
if [ -e "$RULE" ]; then
    if [ -r "$RULE" ]; then
        EXISTING="$RULE"
    elif [ "$PRINT_ONLY" -eq 0 ]; then
        OLD_TMP="$(mktemp)"
        $SUDO cat "$RULE" >"$OLD_TMP"
        EXISTING="$OLD_TMP"
    else
        echo "note: cannot read $RULE without root; the preview leaves out devices allowed by the installed rule" >&2
    fi
fi

python3 - "$CONFIG" "$EXISTING" "$RESET" >"$TMP" <<'PY'
import json
import re
import sys

config_path, rule_path = sys.argv[1], sys.argv[2]
reset = sys.argv[3] == "1"

USB_ID = re.compile(r"^[0-9a-f]{4}$")
# Only lines with our shape are treated as managed. Other lines in the file are
# preserved, so a hand-written rule in the same file survives.
MANAGED = re.compile(r'^SUBSYSTEM=="input".*TAG\+="uaccess"$')
VENDOR = re.compile(r'ATTRS\{id/vendor\}=="([0-9a-fA-F]{4})"')
PRODUCT = re.compile(r'ATTRS\{id/product\}=="([0-9a-fA-F]{4})"')

def fail(message):
    raise SystemExit(f"error: {message}")

try:
    with open(config_path, encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, ValueError) as error:
    fail(f"could not read {config_path}: {error}")

if not isinstance(data, dict):
    fail("devices.json must contain an object")

pairs = []
foreign = []
if rule_path:
    try:
        with open(rule_path, encoding="utf-8", errors="replace") as handle:
            existing_lines = handle.read().splitlines()
    except OSError as error:
        fail(f"could not read {rule_path}: {error}")
    for line in existing_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("# LGL KBM Overlay:"):
            continue
        if MANAGED.match(stripped):
            vendor_match = VENDOR.search(stripped)
            product_match = PRODUCT.search(stripped)
            if vendor_match and product_match:
                if not reset:
                    pairs.append((vendor_match.group(1).lower(), product_match.group(1).lower()))
                continue
        foreign.append(line.rstrip())

for kind in ("keyboard", "mouse"):
    vendor = str(data.get(f"{kind}_vendor") or "").lower()
    product = str(data.get(f"{kind}_product") or "").lower()
    if not USB_ID.fullmatch(vendor) or not USB_ID.fullmatch(product):
        fail(
            f"{kind} has invalid USB vendor/product IDs; "
            "select the device again in the plugin panel"
        )
    pairs.append((vendor, product))

while foreign and not foreign[-1].strip():
    foreign.pop()

for line in foreign:
    print(line)
if foreign and pairs:
    print()
for vendor, product in sorted(set(pairs)):
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
echo "Devices allowed by an earlier run were kept. If the overlay still reports"
echo "permission denied, replug the selected keyboard/mouse or log out and back in"
echo "so the ACL is applied. Use --reset to drop devices you no longer use."
