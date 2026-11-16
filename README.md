# LGL Noctalia Widgets

KDE Plasma widget ports and related adaptations for
[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) and KineticWE's
`noctalia-kwe` fork.

This repository is a standard Noctalia plugin source. Each plugin lives in its
own top-level directory with a `plugin.toml`, a community README, a thumbnail
and translations. The root `catalog.toml` indexes all seven.

## Apps

| App | What it does | Plugin API | Licence |
|---|---|---:|---|
| [**AI Usage**](ai-usage/) | AI limits, spend, balances and local OpenCode statistics in desktop, bar and panel views | 24 | GPL-3.0-or-later |
| [**DualSense Battery**](dualsense/) | DualSense and DualSense Edge battery, charging, lightbar and live input visualisation | 17 | MIT |
| [**LGL KBM Overlay**](kbm-overlay/) | A movable gaming keyboard and mouse input overlay with configurable layouts | 30 | MIT |
| [**Modern SysMonitor Plus**](modern-sysmonitor-plus/) | CPU, GPU, memory, disks, fans, temperatures and network monitoring | 22 | GPL-3.0-or-later |
| [**Steam Controller Battery**](steam-controller/) | Steam Controller 2 battery, charging, connection, signal and live input state | 17 | MIT |
| [**SteamDB Stats**](steamdb-stats/) | Live Steam player counts, 24-hour peak, all-time peak and a 24-hour graph | 24 | MIT |
| [**Weather & Time**](weather-time/) | Location-aware clock, current conditions and forecast with a procedural weather scene | 24 | MIT |

## Install

Add this repository as a git source, then enable the plugins you want:

```bash
noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia msg plugins enable linuxgamerlife/ai-usage
```

For KineticWE's `noctalia-kwe` fork, use the same commands with `noctalia-kwe`:

```bash
noctalia-kwe msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia-kwe msg plugins enable linuxgamerlife/ai-usage
```

Enable only the plugins you use:

```bash
noctalia msg plugins enable linuxgamerlife/dualsense
noctalia msg plugins enable linuxgamerlife/kbm-overlay
noctalia msg plugins enable linuxgamerlife/modern-sysmonitor-plus
noctalia msg plugins enable linuxgamerlife/steam-controller
noctalia msg plugins enable linuxgamerlife/steamdb-stats
noctalia msg plugins enable linuxgamerlife/weather-time
```

### Local path source

For development, clone the repository and add the checkout as a path source:

```bash
git clone https://github.com/linuxgamerlife/lgl-noctalia-widgets.git
cd lgl-noctalia-widgets

noctalia msg plugins source add lgl-dev path "$PWD"
noctalia msg plugins enable linuxgamerlife/ai-usage
```

The source is shared; one `source add` is enough for all seven plugins.

## Upgrading from the old `apps/` layout

The old per-app `apps/lgl-*` tree and its installer scripts have been removed.
Plugin IDs are now `linuxgamerlife/*`. Existing widget instances, plugin
settings and plugin data still use the old IDs until you migrate.

Run the migration tool after pulling:

```bash
./tools/migrate.py --dry-run
./tools/migrate.py
```

The tool rewrites old IDs in `settings.toml`, copies old plugin data to the new
data directories, moves stale local installs into a backup directory, and warns
about old sources in `config.toml` or `plugins.json`. It does not delete old data
unless you pass `--purge-old-data --yes`.

Then remove any old `apps/lgl-*` source, add the new source and enable the new
IDs:

```bash
noctalia msg plugins source list
noctalia msg plugins source remove <old-name>

noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia msg plugins enable linuxgamerlife/ai-usage
```

See [MIGRATION.md](MIGRATION.md) for the full mapping, manual steps, leftover
cleanup and rollback. The previous layout remains available in git history at
the `pre-community-reset` tag.

## Project layout

```text
ai-usage/                   plugin payload
dualsense/
kbm-overlay/
modern-sysmonitor-plus/
steam-controller/
steamdb-stats/
weather-time/
dev/<plugin>/               developer notes, technical docs and tests
tools/                      catalog, validation and migration helpers
catalog.toml                source catalog
```

Each plugin directory contains only what Noctalia needs at runtime. Developer
material lives under `dev/<plugin>/`.

## Development

```bash
./tools/validate-community.sh
./tools/update-catalog.py --check

bash dev/ai-usage/tests/run.sh
bash dev/kbm-overlay/tests/run.sh
bash dev/modern-sysmonitor-plus/tests/run.sh
bash dev/steam-controller/tests/run.sh
bash dev/weather-time/tests/run.sh
```

The tests mock the Noctalia API and do not need a live shell session.

## Origins and thanks

- AI Usage is based on the [AI Usage KDE Plasma widget](https://github.com/lukk17/ai-usage-widget) by Łukasz Sarna.
- DualSense uses the desktop-card approach inspired by Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget), with DualSense protocol and profile work informed by deadYokai's [ds4u](https://git.yokai.digital/deadYokai/ds4u).
- Modern SysMonitor Plus is based on UnsaidSpeech's widget, itself based on [Modern SysMonitor](https://github.com/joaogabrielmedeiros/kde_plasma_widgets) by Joao Gabriel Medeiros.
- Steam Controller is based on Jahrek's [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget).
- Weather data comes from [Open-Meteo](https://open-meteo.com/) under [CC BY 4.0](https://open-meteo.com/en/license).
- KBM Overlay is inspired by [univrsal/input-overlay](https://github.com/univrsal/input-overlay) and its mouse/keyboard presets.

## Licences

This repository is a collection of separately licensed plugins, not a single
work. Every plugin carries its own `LICENSE` and every source file declares its
licence with an SPDX header. Machine-readable metadata lives in
[`REUSE.toml`](REUSE.toml); licence texts are in [`LICENSES/`](LICENSES/).

| Licence | Plugins |
|---|---|
| MIT | DualSense, KBM Overlay, Steam Controller, SteamDB Stats, Weather & Time |
| GPL-3.0-or-later | AI Usage, Modern SysMonitor Plus |

Repository-level files and the `tools/` helpers are MIT, licensed by
LinuxGamerLife. Weather data is CC BY 4.0 and covers the data, not the plugin
code.

Made for [Noctalia](https://github.com/noctalia-dev/noctalia-shell) · adapted by
[LinuxGamerLife](https://www.youtube.com/@linuxgamerlife).
