#!/usr/bin/env bash
# Static/logic tests for Weather & Time. LuaJIT tests use a mocked Noctalia API;
# Python then validates the manifest, translations and layout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/weather-time"

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
    echo "python3 is required for the manifest checks" >&2
    exit 1
fi

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
    if not repo_root.name.startswith("lgl-"):
        fail(f"repository directory does not start with lgl-: {repo_root.name!r}")
    for segment in (author, suffix):
        if not re.match(r"^[a-z0-9][a-z0-9_.-]*$", segment):
            fail(f"plugin id segment is not a valid lowercase token: {segment!r}")

for key in ("id", "name", "version", "plugin_api"):
    if key not in plugin:
        fail(f"plugin.toml is missing {key}")

if not isinstance(plugin.get("plugin_api"), int) or plugin.get("plugin_api", 0) < 24:
    fail("Weather & Time requires plugin_api >= 24")

entries: list[tuple[str, str]] = []
entry_ids: set[str] = set()
for kind, filename_key in (("service", "entry"), ("desktop_widget", "entry"), ("widget", "entry"), ("panel", "entry")):
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
        if filename_key in entry:
            entries.append((f"{kind}:{entry_id}", entry[filename_key]))
for label, filename in entries:
    if not (plugin_dir / filename).is_file():
        fail(f"entry {label} points at missing file {filename}")

for required_kind in ("service", "desktop_widget", "widget", "panel"):
    if not plugin.get(required_kind):
        fail(f"plugin.toml is missing a [[{required_kind}]] entry")

root_settings = plugin.get("setting", [])
desktop_settings = []
for widget in plugin.get("desktop_widget", []):
    desktop_settings.extend(widget.get("setting", []))
widget_settings = []
for widget in plugin.get("widget", []):
    widget_settings.extend(widget.get("setting", []))
panel_settings = []
for panel in plugin.get("panel", []):
    panel_settings.extend(panel.get("setting", []))

setting_keys: set[str] = set()
for setting in root_settings + desktop_settings + widget_settings + panel_settings:
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

desktop_keys = [setting.get("key") for setting in desktop_settings]
expected_prefix = [
    "background",
    "background_color",
    "background_opacity",
    "background_radius",
    "background_padding",
    "show_card_settings",
    "show_styling",
    "show_scaling",
    "show_sections",
]
if desktop_keys[: len(expected_prefix)] != expected_prefix:
    fail("desktop widget settings must start with the host background controls and the show_* toggles")

card_keys = {
    "title", "content_width", "card_gap", "card_padding", "card_radius",
    "card_fill_color", "card_fill_opacity", "card_border_color", "card_border_width",
}
styling_keys = {
    "text_color", "muted_text_color", "weather_color", "divider_color",
    "divider_width", "scene_auto_text",
}
scaling_keys = {"text_scale", "small_text_scale", "clock_size", "forecast_glyph_size"}
section_keys = {
    "show_header", "show_date", "show_condition_text", "show_forecast",
    "forecast_days", "show_details", "show_location", "show_updated",
    "show_attribution", "compact_layout",
}
for setting in desktop_settings:
    key = setting.get("key")
    visible = setting.get("visible_when", {})
    if key in card_keys and (visible.get("key") != "show_card_settings" or visible.get("values") != ["true"]):
        fail(f"card setting {key!r} must be gated by show_card_settings")
    if key in styling_keys and (visible.get("key") != "show_styling" or visible.get("values") != ["true"]):
        fail(f"styling setting {key!r} must be gated by show_styling")
    if key in scaling_keys and (visible.get("key") != "show_scaling" or visible.get("values") != ["true"]):
        fail(f"scaling setting {key!r} must be gated by show_scaling")
    if key in section_keys and (visible.get("key") != "show_sections" or visible.get("values") != ["true"]):
        fail(f"section setting {key!r} must be gated by show_sections")


required_files = (
    "weather-time/README.md",
    "weather-time/PRIVACY.md",
    "weather-time/LICENSE",
    "weather-time/thumbnail.webp",
    "dev/cleanup.py",
    "dev/weather-time/docs/noctalia.md",
    "dev/weather-time/tests/run.sh",
    "dev/weather-time/tests/support/mock.luau",
)
for required in required_files:
    if not (repo_root / required).is_file():
        fail(f"missing required file {required}")

thumbnail = plugin_dir / "thumbnail.webp"
if thumbnail.is_file():
    data = thumbnail.read_bytes()
    if not data.startswith(b"RIFF") or b"WEBP" not in data[:16]:
        fail("thumbnail.webp is not a WebP image")

for path in repo_root.rglob("*"):
    if path.is_file() and path.name in {"weather.json", "location.json", "accounts.json", "state.json"}:
        fail(f"unexpected persistent data file in the repo: {path}")
    if path.is_file() and ".bak" in path.name:
        fail(f"unexpected backup file in the repo: {path}")

# The public state contract must not grow coordinate fields.
for source in ("card.luau", "bar.luau", "panel.luau", "service.luau"):
    text = (plugin_dir / source).read_text()
    if "latitude" in text and source != "panel.luau":
        fail(f"{source} should not handle coordinates directly")

if errors:
    print("\n".join(f"error: {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)

print("MANIFEST TEST OK")
PY

echo "ALL TESTS PASSED"
