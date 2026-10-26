#!/usr/bin/env bash
# Static/logic tests for the Noctalia port. They mock the Noctalia API and
# exercise the service, card and formatters with LuaJIT; no Noctalia session
# is needed. Python then validates the manifest, catalog, translations and
# repository structure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/modern-sysmonitor-plus"

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit is required to run these tests" >&2
    exit 1
fi

cd "$REPO_ROOT"

# Parse every Luau file before executing any of them.
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
import re
import sys
import tomllib
from pathlib import Path

plugin_dir = Path(__import__("os").environ["PLUGIN_DIR"])
repo_root = Path(__import__("os").environ["REPO_ROOT"])

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def load_toml(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except Exception as error:  # noqa: BLE001 - report the exact file
        fail(f"{path}: {error}")
        return {}


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception as error:  # noqa: BLE001 - report the exact file
        fail(f"{path}: {error}")
        return {}


plugin = load_toml(plugin_dir / "plugin.toml")
catalog = load_toml(repo_root / "catalog.toml")
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

if not isinstance(plugin.get("plugin_api"), int):
    fail("plugin_api must be an integer")

entries: list[tuple[str, str]] = []
entry_ids: set[str] = set()
for kind, filename_key in (("service", "entry"), ("desktop_widget", "entry"), ("widget", "entry"), ("panel", "entry")):
    for entry in plugin.get(kind, []) if isinstance(plugin.get(kind, []), list) else []:
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

# Every setting needs label/description translations; select options too.
root_settings = plugin.get("setting", [])
desktop_settings = []
for widget in plugin.get("desktop_widget", []):
    desktop_settings.extend(widget.get("setting", []))

settings_lookup = translations.get("settings", {})
setting_keys: set[str] = set()
for setting in root_settings + desktop_settings:
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
        if translation_key:
            node = translations
            for part in translation_key.split("."):
                if not isinstance(node, dict) or part not in node:
                    fail(f"missing translation key {translation_key} for setting {key}")
                    node = None
                    break
                node = node[part]
    for option in setting.get("options", []) or []:
        option_key = option.get("label_key")
        if option_key:
            node = translations
            for part in option_key.split("."):
                if not isinstance(node, dict) or part not in node:
                    fail(f"missing translation key {option_key} for setting {key}")
                    node = None
                    break
                node = node[part]

# Catalog must describe the same plugin.
rows = catalog.get("plugin", [])
if not rows:
    fail("catalog.toml has no [[plugin]] row")
else:
    row = rows[0]
    for key in ("id", "version", "plugin_api"):
        if row.get(key) != plugin.get(key):
            fail(f"catalog {key} {row.get(key)!r} does not match plugin.toml {plugin.get(key)!r}")
    if row.get("name") != plugin.get("name"):
        fail("catalog name does not match plugin.toml")
    if row.get("author") != plugin.get("author"):
        fail("catalog author does not match plugin.toml")
    if row.get("license") != plugin.get("license"):
        fail("catalog license does not match plugin.toml")
    if row.get("icon") != plugin.get("icon"):
        fail("catalog icon does not match plugin.toml")
    if row.get("description") != plugin.get("description"):
        fail("catalog description does not match plugin.toml")

for required in (
    "README.md",
    "LICENSE",
    "install.sh",
    "install-kwe.sh",
    "uninstall.sh",
    "uninstall-kwe.sh",
    "remove-plugin-widgets.py",
    "docs/noctalia.md",
    "tests/run.sh",
    "tests/support/mock.luau",
    "modern-sysmonitor-plus/thumbnail.webp",
):
    if not (repo_root / required).is_file():
        fail(f"missing required file {required}")

thumbnail = plugin_dir / "thumbnail.webp"
if thumbnail.is_file():
    data = thumbnail.read_bytes()
    if not data.startswith(b"RIFF") or b"WEBP" not in data[:16]:
        fail("thumbnail.webp is not a WebP image")

for path in repo_root.rglob("*"):
    if path.is_file() and path.name in {"accounts.json", "state.json"}:
        fail(f"unexpected persistent data file in the repo: {path}")
    if path.is_file() and ".bak" in path.name:
        fail(f"unexpected backup file in the repo: {path}")

if errors:
    print("\n".join(f"error: {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)

print("MANIFEST TEST OK")
PY

echo "ALL TESTS PASSED"
