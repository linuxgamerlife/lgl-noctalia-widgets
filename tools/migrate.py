#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 LinuxGamerLife

"""Migrate LGL Noctalia plugins from the old apps/ IDs to linuxgamerlife/*.

The default run is non-destructive:

- rewrites old plugin ids in settings.toml, after a timestamped backup;
- copies old plugin data into the new id directory, keeping the old directory;
- moves stale local installs into a plugin-backups directory instead of deleting;
- warns about old ids and apps/lgl-* sources in config.toml/plugins.json.

Use --purge-old-data to remove the old data directory after a successful copy.
That option is opt-in and requires --yes.

Usage:
    ./tools/migrate.py --dry-run
    ./tools/migrate.py
    ./tools/migrate.py --app noctalia-kwe
    ./tools/migrate.py --plugin ai-usage --plugin dualsense
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
import tomllib
from dataclasses import dataclass
from pathlib import Path

APP_NAMES = ("noctalia", "noctalia-kwe")
REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Plugin:
    name: str
    old_id: str | None
    new_id: str

    @property
    def ids(self) -> tuple[str, ...]:
        if self.old_id and self.old_id != self.new_id:
            return (self.old_id, self.new_id)
        return (self.new_id,)


PLUGINS = (
    Plugin("ai-usage", "lukk17/ai-usage", "linuxgamerlife/ai-usage"),
    Plugin("dualsense", "deadYokai/dualsense", "linuxgamerlife/dualsense"),
    Plugin("kbm-overlay", None, "linuxgamerlife/kbm-overlay"),
    Plugin(
        "modern-sysmonitor-plus",
        "unsaidspeech/modern-sysmonitor-plus",
        "linuxgamerlife/modern-sysmonitor-plus",
    ),
    Plugin("steam-controller", "jahrek/steam-controller", "linuxgamerlife/steam-controller"),
    Plugin("steamdb-stats", None, "linuxgamerlife/steamdb-stats"),
    Plugin("weather-time", None, "linuxgamerlife/weather-time"),
)
PLUGINS_BY_NAME = {plugin.name: plugin for plugin in PLUGINS}


def data_home() -> Path:
    value = os.environ.get("NOCTALIA_DATA_HOME") or os.environ.get("XDG_DATA_HOME")
    return Path(value).expanduser() if value else Path.home() / ".local" / "share"


def state_home() -> Path:
    value = os.environ.get("NOCTALIA_STATE_HOME") or os.environ.get("XDG_STATE_HOME")
    return Path(value).expanduser() if value else Path.home() / ".local" / "state"


def config_home() -> Path:
    value = os.environ.get("XDG_CONFIG_HOME")
    return Path(value).expanduser() if value else Path.home() / ".config"


def selected_apps(requested: str) -> tuple[str, ...]:
    if requested != "all":
        return (requested,)
    detected = tuple(
        app
        for app in APP_NAMES
        if (data_home() / app).exists() or (state_home() / app).exists()
    )
    return detected or ("noctalia",)


def cli_path(app: str) -> str | None:
    if os.environ.get("NOCTALIA_DATA_HOME") or os.environ.get("NOCTALIA_STATE_HOME"):
        return None
    return shutil.which(app)


def backup_stamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def backup_file(path: Path, dry_run: bool) -> Path:
    backup = path.with_name(path.name + ".bak." + backup_stamp())
    suffix = 1
    while backup.exists():
        backup = path.with_name(f"{path.name}.bak.{backup_stamp()}.{suffix}")
        suffix += 1
    if dry_run:
        print(f"would back up {path} to {backup}")
    else:
        shutil.copy2(path, backup)
        print(f"backup: {backup}")
    return backup


def move_to_backup(path: Path, app: str, dry_run: bool) -> Path:
    destination = state_home() / app / "plugin-backups" / backup_stamp() / path.name
    if destination.exists():
        suffix = 1
        while destination.exists():
            destination = destination.with_name(f"{path.name}.{suffix}")
            suffix += 1
    if dry_run:
        print(f"would move {path} to {destination}")
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(destination))
    print(f"moved {path} to {destination}")
    return destination


def manifest_id(path: Path) -> str | None:
    manifest = path / "plugin.toml"
    if not manifest.is_file():
        return None
    try:
        data = tomllib.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return None
    value = data.get("id")
    return value if isinstance(value, str) else None


def belongs_to_plugin(local: Path, plugin: Plugin) -> tuple[bool, str]:
    if local.is_symlink():
        target = local.resolve(strict=False)
        if not target.exists():
            return True, "dangling symlink"
        if "lgl-noctalia-widgets" in str(target) and "/apps/" in str(target):
            return True, "old apps/ symlink"
        if target.is_relative_to(REPO_ROOT):
            return True, "this checkout"
    found = manifest_id(local)
    if found in plugin.ids:
        return True, found
    return False, found or "an unknown plugin"


def remove_local_install(plugin: Plugin, app: str, dry_run: bool) -> None:
    local = data_home() / app / "plugins" / plugin.name
    if not (local.is_symlink() or local.exists()):
        return
    belongs, reason = belongs_to_plugin(local, plugin)
    if not belongs:
        print(
            f"skip: {local} belongs to {reason}; remove it manually if needed",
            file=sys.stderr,
        )
        return
    move_to_backup(local, app, dry_run)


def dedupe_enabled(text: str) -> str:
    pattern = re.compile(r"(\benabled\s*=\s*\[)(.*?)(\])", re.DOTALL)

    def replace(match: re.Match[str]) -> str:
        values = re.findall(r'"([^"]*)"', match.group(2))
        seen: list[str] = []
        for value in values:
            if value not in seen:
                seen.append(value)
        body = "".join(f'    "{value}",\n' for value in seen)
        return f"{match.group(1)}\n{body}]"

    return pattern.sub(replace, text)


def rewrite_settings(plugin: Plugin, app: str, dry_run: bool) -> None:
    if not plugin.old_id or plugin.old_id == plugin.new_id:
        return
    settings = state_home() / app / "settings.toml"
    if not settings.is_file():
        return
    text = settings.read_text(encoding="utf-8")
    if plugin.old_id not in text:
        return

    # A global replace cannot merge two plugin_settings tables. If the user
    # already enabled the new id, leave that file for a manual merge.
    old_tables = (
        f'[plugin_settings."{plugin.old_id}"]',
        f"[plugin_settings.'{plugin.old_id}']",
    )
    new_tables = (
        f'[plugin_settings."{plugin.new_id}"]',
        f"[plugin_settings.'{plugin.new_id}']",
    )
    if any(table in text for table in old_tables) and any(table in text for table in new_tables):
        print(
            f"warning: {settings} has both {plugin.old_id} and {plugin.new_id} "
            f"plugin_settings tables; merge them by hand",
            file=sys.stderr,
        )
        return

    updated = dedupe_enabled(text.replace(plugin.old_id, plugin.new_id))
    try:
        tomllib.loads(updated)
    except tomllib.TOMLDecodeError as error:
        print(f"error: refusing to rewrite invalid TOML: {error}", file=sys.stderr)
        return
    if dry_run:
        print(f"would replace {plugin.old_id} with {plugin.new_id} in {settings}")
        return
    backup_file(settings, dry_run=False)
    settings.write_text(updated, encoding="utf-8")
    print(f"replaced {plugin.old_id} with {plugin.new_id} in {settings}")


def merge_tree(source: Path, destination: Path, dry_run: bool) -> int:
    copied = 0
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        target = destination / relative
        if path.is_dir():
            if not dry_run:
                target.mkdir(parents=True, exist_ok=True)
            continue
        if target.exists():
            print(f"keep existing {target}")
            continue
        if dry_run:
            print(f"would copy {path} to {target}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target, follow_symlinks=False)
        copied += 1
    if copied and not dry_run:
        print(f"copied {copied} file(s) into {destination}")
    return copied


def migrate_data(plugin: Plugin, app: str, dry_run: bool, purge_old: bool, yes: bool) -> None:
    if not plugin.old_id or plugin.old_id == plugin.new_id:
        return
    old_data = state_home() / app / "plugins" / "data" / plugin.old_id
    new_data = state_home() / app / "plugins" / "data" / plugin.new_id
    if not old_data.is_dir():
        return
    merge_tree(old_data, new_data, dry_run)
    if purge_old:
        if not yes:
            print(
                f"skip purge: pass --yes with --purge-old-data to remove {old_data}",
                file=sys.stderr,
            )
            return
        if dry_run:
            print(f"would remove old data {old_data}")
        else:
            shutil.rmtree(old_data)
            print(f"removed old data {old_data}")
    else:
        print(f"old data kept at {old_data}")


def warn_config(plugin: Plugin, app: str) -> None:
    config = config_home() / app / "config.toml"
    if config.is_file():
        text = config.read_text(encoding="utf-8")
        if plugin.old_id and plugin.old_id in text:
            print(
                f"warning: {config} still contains {plugin.old_id}; update it to "
                f"{plugin.new_id} or use Settings -> Plugins",
                file=sys.stderr,
            )
        if "apps/lgl-" in text:
            print(
                f"warning: {config} still references an apps/lgl-* path source; "
                f"remove it with '{app} msg plugins source list' and "
                f"'{app} msg plugins source remove <name>'",
                file=sys.stderr,
            )
    plugins_json = config_home() / app / "plugins.json"
    if plugins_json.is_file():
        text = plugins_json.read_text(encoding="utf-8")
        if plugin.old_id and plugin.old_id in text:
            print(
                f"warning: {plugins_json} still references {plugin.old_id}; "
                f"remove the old source or plugin entry",
                file=sys.stderr,
            )
        if "apps/lgl-" in text:
            print(
                f"warning: {plugins_json} still references an apps/lgl-* source; "
                f"remove it with '{app} msg plugins source list'",
                file=sys.stderr,
            )


def disable_old(plugin: Plugin, app: str, dry_run: bool) -> None:
    if not plugin.old_id or plugin.old_id == plugin.new_id:
        return
    executable = cli_path(app)
    if not executable:
        return
    command = (executable, "msg", "plugins", "disable", plugin.old_id)
    if dry_run:
        print(f"would run: {' '.join(command)}")
        return
    try:
        result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return
    if result.returncode == 0:
        print(f"disabled {plugin.old_id}")


def migrate_plugin(plugin: Plugin, apps: tuple[str, ...], args: argparse.Namespace) -> None:
    for app in apps:
        print(f"\n[{app}] {plugin.name}")
        disable_old(plugin, app, args.dry_run)
        remove_local_install(plugin, app, args.dry_run)
        rewrite_settings(plugin, app, args.dry_run)
        migrate_data(plugin, app, args.dry_run, args.purge_old_data, args.yes)
        warn_config(plugin, app)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", choices=(*APP_NAMES, "all"), default="all")
    parser.add_argument(
        "--plugin",
        action="append",
        choices=tuple(PLUGINS_BY_NAME),
        default=[],
        help="plugin to migrate (repeatable; default: all)",
    )
    parser.add_argument("--dry-run", action="store_true", help="print actions only")
    parser.add_argument(
        "--purge-old-data",
        action="store_true",
        help="remove the old data directory after copying (requires --yes)",
    )
    parser.add_argument("--yes", action="store_true", help="confirm --purge-old-data")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    plugins = (
        [PLUGINS_BY_NAME[name] for name in args.plugin]
        if args.plugin
        else list(PLUGINS)
    )
    apps = selected_apps(args.app)

    for plugin in plugins:
        if not (REPO_ROOT / plugin.name / "plugin.toml").is_file():
            print(
                f"error: {REPO_ROOT / plugin.name} is not a plugin directory",
                file=sys.stderr,
            )
            return 1

    for plugin in plugins:
        migrate_plugin(plugin, apps, args)

    if not args.dry_run:
        print("\nNext steps:")
        for app in apps:
            print(
                f"  {app} msg plugins source add lgl git "
                f"https://github.com/linuxgamerlife/lgl-noctalia-widgets"
            )
            for plugin in plugins:
                print(f"  {app} msg plugins enable {plugin.new_id}")
        print("\nThen reload Noctalia and verify the migrated widgets.")
        print("Old data was kept unless --purge-old-data was used.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
