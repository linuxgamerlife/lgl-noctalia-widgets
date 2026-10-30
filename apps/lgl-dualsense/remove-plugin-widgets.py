#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 deadYokai
# Copyright (C) 2026 Jarek

"""Remove desktop-widget instances of one plugin type from a Noctalia settings.toml.

Usage:
    remove-plugin-widgets.py <settings.toml> <widget-type> [--dry-run]

Example:
    remove-plugin-widgets.py ~/.local/state/noctalia-kwe/settings.toml \
        deadYokai/dualsense:card

The file is backed up as settings.toml.bak.YYYYMMDD-HHMMSS before writing.
Other widgets and settings are preserved; the result is validated with tomllib.
"""
from __future__ import annotations

import re
import shutil
import sys
import time
import tomllib
from pathlib import Path

WIDGET_START = re.compile(r'^ {0,4}\[desktop_widgets\.widget\.("?)([^"\]]+)\1\]\s*$')
TOP_LEVEL = re.compile(r'^\[[^\]]+\]\s*$')
TYPE_LINE = r'^\s*type\s*=\s*"%s"\s*$'

def remove_widgets(path: Path, widget_type: str, dry_run: bool) -> int:
    if not path.is_file():
        print(f"no settings file at {path}; skipping widget cleanup")
        return 0

    lines = path.read_text().splitlines(keepends=True)
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = WIDGET_START.match(line)
        if match:
            starts.append((index, match.group(2)))

    ranges: list[tuple[int, int]] = []
    remove_ids: set[str] = set()
    type_pattern = re.compile(TYPE_LINE % re.escape(widget_type), re.MULTILINE)

    for position, (start, widget_id) in enumerate(starts):
        if position + 1 < len(starts):
            end = starts[position + 1][0]
        else:
            end = len(lines)
            for index in range(start + 1, len(lines)):
                if TOP_LEVEL.match(lines[index]):
                    end = index
                    break
        if type_pattern.search("".join(lines[start:end])):
            ranges.append((start, end))
            remove_ids.add(widget_id)

    if not remove_ids:
        print(f"no '{widget_type}' widgets found in {path}")
        return 0

    for start, end in reversed(ranges):
        del lines[start:end]
    text = "".join(lines)

    def replace_order(match: re.Match[str]) -> str:
        values = re.findall(r'"([^"]*)"', match.group(1))
        kept = [value for value in values if value not in remove_ids]
        if not kept:
            return "widget_order = []"
        body = "".join(f'    "{value}",\n' for value in kept)
        return "widget_order = [\n" + body + "]"

    text = re.sub(r"widget_order\s*=\s*\[(.*?)\]", replace_order, text, flags=re.DOTALL)

    try:
        parsed = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        print(f"error: refusing to write invalid TOML: {error}", file=sys.stderr)
        return 1

    widgets = parsed.get("desktop_widgets", {}).get("widget", {})
    remaining = sorted(remove_ids & set(widgets))
    if remaining:
        print(f"error: failed to remove widget(s): {', '.join(remaining)}", file=sys.stderr)
        return 1

    if dry_run:
        print(f"would remove {len(remove_ids)} widget(s): {', '.join(sorted(remove_ids))}")
        return 0

    backup = path.with_name(path.name + ".bak." + time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(path, backup)
    path.write_text(text)
    print(f"removed {len(remove_ids)} widget(s) from {path}")
    print(f"backup: {backup}")
    return 0

def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    args = [arg for arg in argv if arg != "--dry-run"]
    if len(args) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return remove_widgets(Path(args[0]).expanduser(), args[1], dry_run)

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
