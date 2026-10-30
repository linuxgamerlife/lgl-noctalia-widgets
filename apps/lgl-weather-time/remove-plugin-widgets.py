#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 LinuxGamerLife

"""Remove one plugin's widget instances (and settings table) from settings.toml.

Usage:
    remove-plugin-widgets.py <settings.toml> <widget-type>... [--plugin-id ID] [--dry-run]

Example:
    remove-plugin-widgets.py ~/.local/state/noctalia-kwe/settings.toml \
        "lukk17/ai-usage:card" "lukk17/ai-usage:usage" \
        --plugin-id lukk17/ai-usage

Both `[desktop_widgets.widget.<id>]` and `[widget.<name>]` sections are handled,
along with their child tables. The widget names are also removed from
`widget_order`, `start`, `center` and `end` arrays. The file is backed up as
settings.toml.bak.YYYYMMDD-HHMMSS before writing, other widgets and settings are
preserved, and the result is validated with tomllib.
"""
from __future__ import annotations

import re
import shutil
import sys
import time
import tomllib
from pathlib import Path

SECTION = re.compile(r'^(\s*)\[([^\]]+)\]\s*$')
TYPE_LINE = re.compile(r'^\s*type\s*=\s*"([^"]+)"\s*$', re.MULTILINE)
ARRAY = re.compile(r'\b(widget_order|start|center|end)\s*=\s*\[(.*?)\]', re.DOTALL)

def section_end(lines: list[str], start: int, header_path: str) -> int:
    """Return the first line after this table and all of its child tables."""
    for index in range(start + 1, len(lines)):
        match = SECTION.match(lines[index])
        if not match:
            continue
        path = match.group(2).strip()
        if path == header_path or path.startswith(header_path + "."):
            continue
        return index
    return len(lines)

def find_ranges(lines: list[str], types: set[str], plugin_id: str | None) -> tuple[list[tuple[int, int]], set[str], set[str]]:
    ranges: list[tuple[int, int]] = []
    remove_ids: set[str] = set()
    plugin_tables: set[str] = set()

    for index, line in enumerate(lines):
        match = SECTION.match(line)
        if not match:
            continue
        path = match.group(2).strip()
        if plugin_id and (path == f'plugin_settings."{plugin_id}"' or path == f"plugin_settings.'{plugin_id}'"):
            end = section_end(lines, index, path)
            ranges.append((index, end))
            plugin_tables.add(path)
            continue
        if path.startswith("desktop_widgets.widget."):
            name = path[len("desktop_widgets.widget."):]
            is_start = "." not in name
        elif path.startswith("widget."):
            name = path[len("widget."):]
            is_start = "." not in name
        else:
            continue
        if not is_start:
            continue
        end = section_end(lines, index, path)
        body = "".join(lines[index:end])
        found = TYPE_LINE.search(body)
        if found and found.group(1) in types:
            ranges.append((index, end))
            remove_ids.add(name.strip('"'))

    # Merge overlapping ranges (a child table can be matched more than once).
    ranges.sort()
    merged: list[tuple[int, int]] = []
    for start, end in ranges:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged, remove_ids, plugin_tables

def remove_arrays(text: str, remove_ids: set[str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        values = re.findall(r'"([^"]*)"', match.group(2))
        kept = [value for value in values if value not in remove_ids]
        if not kept:
            return f"{key} = []"
        body = "".join(f'    "{value}",\n' for value in kept)
        return f"{key} = [\n{body}]"

    return ARRAY.sub(replace, text)

def remove_widgets(
    path: Path,
    types: set[str],
    plugin_id: str | None,
    dry_run: bool,
) -> int:
    if not path.is_file():
        print(f"no settings file at {path}; skipping cleanup")
        return 0

    lines = path.read_text().splitlines(keepends=True)
    ranges, remove_ids, plugin_tables = find_ranges(lines, types, plugin_id)

    if not ranges and not remove_ids and not plugin_tables:
        print(f"no widgets of {', '.join(sorted(types))} found in {path}")
        return 0

    for start, end in reversed(ranges):
        del lines[start:end]
    text = "".join(lines)
    if remove_ids:
        text = remove_arrays(text, remove_ids)

    try:
        parsed = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        print(f"error: refusing to write invalid TOML: {error}", file=sys.stderr)
        return 1

    widgets = parsed.get("desktop_widgets", {}).get("widget", {})
    remaining = sorted(remove_ids & set(widgets))
    if remaining:
        print(f"error: failed to remove desktop widget(s): {', '.join(remaining)}", file=sys.stderr)
        return 1
    if remove_ids:
        order = parsed.get("desktop_widgets", {}).get("widget_order", [])
        if remove_ids & set(order):
            print("error: failed to remove widget order entries", file=sys.stderr)
            return 1
    if plugin_id and f"plugin_settings" in parsed and plugin_id in parsed["plugin_settings"]:
        print(f"error: failed to remove plugin settings for {plugin_id}", file=sys.stderr)
        return 1

    label = ", ".join(sorted(remove_ids)) or "plugin settings"
    if dry_run:
        print(f"would remove {label} from {path}")
        return 0

    backup = path.with_name(path.name + ".bak." + time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(path, backup)
    path.write_text(text)
    print(f"removed {label} from {path}")
    print(f"backup: {backup}")
    return 0

def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    args = [arg for arg in argv if arg != "--dry-run"]
    plugin_id = None
    if "--plugin-id" in args:
        index = args.index("--plugin-id")
        if index + 1 >= len(args):
            print("error: --plugin-id needs a value", file=sys.stderr)
            return 2
        plugin_id = args[index + 1]
        del args[index:index + 2]
    if len(args) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return remove_widgets(Path(args[0]).expanduser(), set(args[1:]), plugin_id, dry_run)

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
