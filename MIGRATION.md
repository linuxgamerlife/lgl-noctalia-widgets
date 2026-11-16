# Migrating from the old `apps/` layout

v2.0.0 moves every plugin to the repository root and renames four plugin IDs to
`linuxgamerlife/*`. The old `apps/` tree and installers are gone from the
working tree; the old code remains available at the `pre-community-reset` tag.

## Who needs this

You need to migrate if you installed any plugin from the old layout:

- you ran an `apps/lgl-*/install.sh` or `install-kwe.sh` script;
- you added an `apps/lgl-*` directory as a Noctalia path source;
- you have widget instances whose `type` starts with one of the old IDs.

If you never installed v1, skip to [Install](#install).

## ID mapping

| Old ID | New ID |
|---|---|
| `lukk17/ai-usage` | `linuxgamerlife/ai-usage` |
| `deadYokai/dualsense` | `linuxgamerlife/dualsense` |
| `jahrek/steam-controller` | `linuxgamerlife/steam-controller` |
| `unsaidspeech/modern-sysmonitor-plus` | `linuxgamerlife/modern-sysmonitor-plus` |
| `linuxgamerlife/kbm-overlay` | unchanged |
| `linuxgamerlife/weather-time` | unchanged |
| `linuxgamerlife/steamdb-stats` | unchanged |

Entry IDs are unchanged. A migrated `card`, `panel`, `battery`, `poller`, `bar`,
`devices` or `setup` entry keeps its position and settings.

## Recommended migration

1. Pull the new checkout:

   ```bash
   cd /path/to/lgl-noctalia-widgets
   git pull
   ```

2. Preview the changes:

   ```bash
   ./tools/migrate.py --dry-run
   ```

3. Run the migration:

   ```bash
   ./tools/migrate.py
   ```

   The tool:
   - rewrites old IDs in `settings.toml`, with a timestamped backup;
   - copies old plugin data to the new ID directories and keeps the old copy;
   - moves stale local installs into
     `~/.local/state/<app>/plugin-backups/<timestamp>/`;
   - warns about old IDs and `apps/lgl-*` sources in `config.toml` and
     `plugins.json`.

4. Remove any old source. List the sources first:

   ```bash
   noctalia msg plugins source list
   ```

   If an old source points at an `apps/lgl-*` directory, remove it:

   ```bash
   noctalia msg plugins source remove <old-name>
   ```

5. Add the new source and enable the plugins you use:

   ```bash
   noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
   noctalia msg plugins enable linuxgamerlife/ai-usage
   noctalia msg plugins enable linuxgamerlife/dualsense
   noctalia msg plugins enable linuxgamerlife/kbm-overlay
   noctalia msg plugins enable linuxgamerlife/modern-sysmonitor-plus
   noctalia msg plugins enable linuxgamerlife/steam-controller
   noctalia msg plugins enable linuxgamerlife/steamdb-stats
   noctalia msg plugins enable linuxgamerlife/weather-time
   ```

6. Reload the shell if the plugin list does not refresh:

   ```bash
   noctalia msg config-reload
   ```

For KineticWE's fork, use `noctalia-kwe` for every command. The state and config
directories are separate, so run the migration once per shell you use.

## Manual migration

If you prefer not to run the tool:

1. Back up `~/.local/state/<app>/settings.toml`.
2. Replace every old ID in that file with the new ID. This covers desktop and
   bar widget `type` values, `[plugin_settings."<id>"]` tables and enabled
   arrays.
3. Copy
   `~/.local/state/<app>/plugins/data/<old-id>/` to
   `~/.local/state/<app>/plugins/data/<new-id>/`.
4. Remove the old install from `~/.local/share/<app>/plugins/<slug>` after the
   new plugin is enabled. If it is a symlink into the old `apps/` directory, it
   is already broken.
5. Remove the old source and add the new one as above.

Keep the old `~/.local/state/<app>/plugins/data/<old-id>/` directory until you
have verified the new plugins. It is the rollback path.

## What survives

- Widget entry IDs, positions and per-instance layout survive when the settings
  rewrite is applied.
- Plugin-level settings survive when `[plugin_settings."<old-id>"]` is
  rewritten to the new ID.
- AI Usage Secret Service keys survive. They use `server=ai-usage`; the migrated
  `accounts.json` points the new plugin at them.
- Old plugin data is copied, not moved, so the old directory remains until you
  remove it.

## What changes

- Plugin IDs and source URLs.
- Plugin data directory names.
- The installed plugin path: the new source is a git or path source at the
  repository root, not a per-app symlink.
- Old IPC commands, keybinds and scripts must use the new IDs.

## Leftovers

These commands only inspect. Removing files is optional and destructive; do it
only after the new plugins work.

```bash
# Old-style symlinks into the removed apps/ tree.
find ~/.local/share/noctalia/plugins -maxdepth 1 -type l \
  -lname '*lgl-noctalia-widgets/apps/*' -printf '%p -> %l\n'
find ~/.local/share/noctalia-kwe/plugins -maxdepth 1 -type l \
  -lname '*lgl-noctalia-widgets/apps/*' -printf '%p -> %l\n'

# Old IDs in config and source metadata.
grep -n "lukk17\|deadYokai\|jahrek\|unsaidspeech\|apps/lgl-" \
  ~/.config/noctalia/config.toml ~/.config/noctalia/plugins.json \
  ~/.config/noctalia-kwe/config.toml ~/.config/noctalia-kwe/plugins.json 2>/dev/null

# Old data directories. Keep for rollback until verified.
ls ~/.local/state/noctalia/plugins/data/{lukk17,deadYokai,jahrek,unsaidspeech} 2>/dev/null
ls ~/.local/state/noctalia-kwe/plugins/data/{lukk17,deadYokai,jahrek,unsaidspeech} 2>/dev/null
```

The migration tool moves stale local installs to
`~/.local/state/<app>/plugin-backups/<timestamp>/`. You can remove that backup
directory once the new plugins are verified.

If you want to delete old data explicitly:

```bash
# Only after verifying the new plugins.
rm -rf ~/.local/state/noctalia/plugins/data/lukk17
rm -rf ~/.local/state/noctalia/plugins/data/deadYokai
rm -rf ~/.local/state/noctalia/plugins/data/jahrek
rm -rf ~/.local/state/noctalia/plugins/data/unsaidspeech
```

Use the matching `noctalia-kwe` paths if you use KWE.

## Sparse checkouts

If you used a sparse checkout of `apps/lgl-*`, add the new root directories or
disable sparse checkout:

```bash
git sparse-checkout add ai-usage dualsense kbm-overlay \
  modern-sysmonitor-plus steam-controller steamdb-stats weather-time
```

or:

```bash
git sparse-checkout disable
```

## Rollback

The previous layout is available at the `pre-community-reset` tag:

```bash
git checkout pre-community-reset
```

The migration tool backs up `settings.toml` before rewriting it and keeps the
old data directories by default. To roll back a migration, restore the
timestamped `settings.toml.bak.*` backup, re-enable the old plugin from the old
tag, and point the old source at the old checkout.

Do not run `git reset --hard` or `git clean` on a checkout with uncommitted
work.

## Install

For a fresh install, add the repository as a source and enable the plugin:

```bash
noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia msg plugins enable linuxgamerlife/ai-usage
```

For KWE, use `noctalia-kwe` instead of `noctalia`.
