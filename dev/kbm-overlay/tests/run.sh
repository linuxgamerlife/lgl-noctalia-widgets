#!/usr/bin/env bash
# Static/logic tests for LGL KBM Overlay. LuaJIT tests use a mocked Noctalia
# API; Python tests cover the evdev state machine and manifest contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/kbm-overlay"

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit is required to run these tests" >&2
    exit 1
fi

cd "$DEV_DIR"

while IFS= read -r -d '' file; do
    luajit -b "$file" /dev/null
done < <(find "$PLUGIN_DIR" -name '*.luau' -print0)

for test in "$SCRIPT_DIR"/test_*.luau; do
    echo "==> $(basename "$test")"
    luajit "$test" "$PLUGIN_DIR"
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for the helper and manifest checks" >&2
    exit 1
fi

echo "==> test_daemon.py"
python3 "$SCRIPT_DIR/test_daemon.py"

echo "==> manifest checks"
PLUGIN_DIR="$PLUGIN_DIR" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
import tomllib
from pathlib import Path

plugin_dir = Path(os.environ["PLUGIN_DIR"])
repo_root = Path(os.environ["REPO_ROOT"])
errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def load_toml(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except Exception as error:
        fail(f"{path}: {error}")
        return {}


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception as error:
        fail(f"{path}: {error}")
        return {}


def translation_exists(translations: dict, key: str) -> bool:
    node = translations
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return False
        node = node[part]
    return True


plugin = load_toml(plugin_dir / "plugin.toml")
translations = load_json(plugin_dir / "translations" / "en.json")

plugin_id = plugin.get("id", "")
if plugin_id.count("/") != 1:
    fail(f"plugin id must have exactly one slash: {plugin_id!r}")
else:
    author, suffix = plugin_id.split("/")
    if plugin_dir.name != suffix:
        fail(f"plugin directory {plugin_dir.name!r} does not match id suffix {suffix!r}")
    for segment in (author, suffix):
        if not re.match(r"^[a-z0-9][a-z0-9_.-]*$", segment):
            fail(f"plugin id segment is not a valid lowercase token: {segment!r}")

for key in ("id", "name", "version", "plugin_api", "license", "description"):
    if key not in plugin:
        fail(f"plugin.toml is missing {key}")

if plugin.get("plugin_api") != 30:
    fail("this version must target plugin_api 30 for Noctalia KWE 5.3.0")

entries: list[tuple[str, str]] = []
entry_ids: set[str] = set()
for kind in ("service", "desktop_widget", "widget", "panel"):
    rows = plugin.get(kind, [])
    if not isinstance(rows, list):
        continue
    for entry in rows:
        entry_id = entry.get("id", "")
        if not re.match(r"^[a-z0-9][a-z0-9_.-]*$", entry_id):
            fail(f"{kind} entry id is not a stable lowercase token: {entry_id!r}")
        if entry_id in entry_ids:
            fail(f"duplicate entry id: {entry_id!r}")
        entry_ids.add(entry_id)
        entries.append((f"{kind}:{entry_id}", entry.get("entry", "")))
for label, filename in entries:
    if not filename or not (plugin_dir / filename).is_file():
        fail(f"entry {label} points at missing file {filename!r}")

for required_kind in ("service", "desktop_widget", "widget", "panel"):
    if not plugin.get(required_kind):
        fail(f"plugin.toml is missing a [[{required_kind}]] entry")

# The visual must be a normal desktop widget. An overlay panel or layer entry
# would put it above every window and make it impossible to move normally.
if plugin.get("layer"):
    fail("layer entries are not allowed: the widget must be movable in desktop edit mode")
panels = plugin.get("panel", [])
if any(panel.get("id") == "overlay" or panel.get("layer") == "overlay" for panel in panels):
    fail("an overlay panel is not allowed: use the desktop widget")
if len(plugin.get("desktop_widget", [])) != 1:
    fail("exactly one desktop widget entry is required")

if plugin.get("setting"):
    fail("visual settings must live in the desktop widget, not plugin-level settings")

all_settings = list(plugin.get("setting", []))
desktop_settings = []
for entry in plugin.get("desktop_widget", []):
    desktop_settings.extend(entry.get("setting", []))
    all_settings.extend(entry.get("setting", []))
for entry in plugin.get("widget", []):
    all_settings.extend(entry.get("setting", []))
for entry in plugin.get("panel", []):
    all_settings.extend(entry.get("setting", []))

setting_keys: set[str] = set()
for setting in all_settings:
    key = setting.get("key")
    if not key:
        fail("a setting has no key")
        continue
    if not re.match(r"^[a-z][a-z0-9_]*$", key):
        fail(f"setting key is not snake_case: {key!r}")
    if key in setting_keys:
        fail(f"duplicate setting key: {key!r}")
    setting_keys.add(key)
    if setting.get("type") == "double" and "step" not in setting:
        fail(f"double setting {key!r} has no explicit step")
    if setting.get("type") == "color" and not setting.get("default"):
        fail(f"color setting {key!r} has an empty default")
    for field in ("label", "description"):
        translation_key = setting.get(f"{field}_key")
        if translation_key and not translation_exists(translations, translation_key):
            fail(f"missing translation key {translation_key} for setting {key}")
    for option in setting.get("options", []) or []:
        option_key = option.get("label_key")
        if option_key and not translation_exists(translations, option_key):
            fail(f"missing translation key {option_key} for setting {key}")

# Match the weather/dualsense desktop setting convention.
desktop_keys = [setting.get("key") for setting in desktop_settings]
expected_prefix = [
    "background",
    "background_color",
    "background_opacity",
    "background_radius",
    "background_padding",
    "show_layout_section",
    "show_mouse_section",
    "show_appearance_section",
    "show_scaling_section",
]
if desktop_keys[: len(expected_prefix)] != expected_prefix:
    fail("desktop settings must start with the host background controls and four main section toggles")

layout_keys = {
    "content_width", "keyboard_layout", "custom_keys", "show_keyboard", "show_key_labels",
}
mouse_keys = {
    "show_mouse", "show_mouse_labels", "mouse_show_wheel", "mouse_show_extra",
}
styling_keys = {
    "overlay_background", "overlay_background_color", "overlay_background_opacity",
    "overlay_radius", "overlay_border_color", "overlay_border_width",
    "key_idle_color", "key_idle_opacity", "key_border_color", "key_border_width",
    "key_text_color", "accent_color", "accent_text_color", "glow_color",
    "glow_opacity", "effects_glow", "effects_ripple", "mouse_body_color",
    "mouse_body_opacity", "mouse_border_color", "mouse_border_width",
    "motion_direction", "motion_arrow_size", "motion_arrow_scale", "motion_arrow_color", "motion_arrow_idle",
    "motion_dot_size", "motion_dot_scale", "motion_dot_color",
}
scaling_keys = {"key_size", "key_gap", "key_radius", "mouse_size", "label_scale"}
for setting in desktop_settings:
    key = setting.get("key")
    visible = setting.get("visible_when", {})
    if key in layout_keys and (visible.get("key") != "show_layout_section" or visible.get("values") != ["true"]):
        fail(f"layout setting {key!r} must be gated by show_layout_section")
    if key in mouse_keys and (visible.get("key") != "show_mouse_section" or visible.get("values") != ["true"]):
        fail(f"mouse setting {key!r} must be gated by show_mouse_section")
    if key in styling_keys and (visible.get("key") != "show_appearance_section" or visible.get("values") != ["true"]):
        fail(f"styling setting {key!r} must be gated by show_appearance_section")
    if key in scaling_keys and (visible.get("key") != "show_scaling_section" or visible.get("values") != ["true"]):
        fail(f"scaling setting {key!r} must be gated by show_scaling_section")


required_files = (
    "kbm-overlay/README.md",
    "kbm-overlay/PRIVACY.md",
    "kbm-overlay/LICENSE",
    "kbm-overlay/thumbnail.webp",
    "kbm-overlay/code/kbm_daemon.py",
    "kbm-overlay/code/setup-input-permissions.sh",
    "tools/migrate.py",
    "dev/kbm-overlay/docs/noctalia.md",
    "dev/kbm-overlay/tests/run.sh",
    "dev/kbm-overlay/tests/support/mock.luau",
)
for required in required_files:
    if not (repo_root / required).is_file():
        fail(f"missing required file {required}")

thumbnail = plugin_dir / "thumbnail.webp"
if thumbnail.is_file():
    data = thumbnail.read_bytes()
    if not data.startswith(b"RIFF") or b"WEBP" not in data[:16]:
        fail("thumbnail.webp is not a WebP image")

setup_script = plugin_dir / "code" / "setup-input-permissions.sh"
if setup_script.is_file() and not os.access(setup_script, os.X_OK):
    fail("setup-input-permissions.sh is not executable")

for path in repo_root.rglob("*"):
    if path.is_file() and path.name in {"devices.json", "runtime.json", "reader.pid"}:
        fail(f"unexpected persistent data file in the repo: {path}")
    if path.is_file() and path.name.startswith("frame-") and path.suffix == ".svg":
        fail(f"unexpected rendered frame in the repo: {path}")
    if path.is_file() and ".bak" in path.name:
        fail(f"unexpected backup file in the repo: {path}")

card_source = (plugin_dir / "card.luau").read_text()
if "desktopWidget.render" not in card_source:
    fail("card.luau must render a desktop widget")
if "noctalia.layer" in card_source:
    fail("card.luau must not use layer-shell APIs")

if errors:
    print("\n".join(f"error: {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)

print("MANIFEST TEST OK")
PY

echo "ALL TESTS PASSED"
