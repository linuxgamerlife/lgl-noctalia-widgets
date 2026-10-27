# Modern SysMonitor Plus — Noctalia plugin

A Noctalia v5 desktop widget and headless poller that shows CPU, GPU, RAM,
VRAM, network and physical-disk activity in the solid-bar and live-chart style
of the Modern SysMonitor Plus Plasma widget.

This is the standalone Noctalia port of
[Modern SysMonitor Plus](https://github.com/UnsaidSpeech/modern-sysmonitor-plus),
a KDE Plasma 6 widget. The Plasma widget stays in its repository; this one
contains the Noctalia port. The original Modern SysMonitor design and code are
by Joao Gabriel Medeiros; the Plus changes are by UnsaidSpeech.

| Field | Value |
| --- | --- |
| Plugin ID | `unsaidspeech/modern-sysmonitor-plus` |
| Version | `1.0.0` |
| Entries | Service `poller`, desktop widget `card` |
| Plugin API | 22 |
| License | GPL-2.0-or-later |

Targets KineticWE's `noctalia-kwe` v5.3.0 and upstream Noctalia v5. Both
install scripts use the same v5 plugin API and the `noctalia` / `noctalia-kwe`
app directories.

## Feature mapping

| KDE widget | Noctalia port |
| --- | --- |
| `contents/ui/data.py`, run every 2 s | Headless Luau `poller` service, no Python or helper daemon |
| `/proc/stat` CPU usage delta | `poller`: first `cpu` line, idle+iowait delta |
| `coretemp` / any hwmon CPU temperature | `poller`: `coretemp`, `k10temp`, `zenpower`, `cpu_thermal`, `soc_thermal`, then CPU thermal zones |
| CPU fan (`--cpu-fan N`, 0 = automatic) | `poller`: hwmon `fan<N>_input`, automatic label containing “cpu”; card shows the row when found |
| `/proc/meminfo` RAM used/total | `poller`: `MemTotal` − `MemAvailable`, with the free+buffers+cached fallback |
| `/proc/net/dev` download/upload | `poller`: non-`lo` byte deltas; the card keeps the 30-point history |
| CPU/GPU usage segmented bars | CPU/GPU usage area charts (`ui.graph`), auto or fixed scaling like the network chart with separate height/scale settings; RAM/VRAM/disks use solid bars |
| AMD GPU `/sys/class/drm` | `poller`: largest-VRAM AMD card (`gpu_busy_percent`, `mem_info_vram_*`, hwmon) |
| Nvidia `nvidia-smi` | `poller`: full query, then a short query if the driver rejects extra fields |
| (no Intel path) | Host `noctalia.systemStats()` GPU probe as a final fallback |
| VRAM card | `poller`: AMD sysfs or Nvidia memory fields |
| Hardware names | CPU from `/proc/cpuinfo`; AMD GPU exact model from `vulkaninfo --summary` (fallback `lspci -nn`) plus VRAM; Nvidia name/memory from `nvidia-smi`; shown beside the CPU/GPU titles |
| GPU “More” details | `ui.button` toggle: junction/memory temperature, clocks, fan, power |
| Disks card (`os.statvfs` + hwmon) | `poller`: `df -kPT`, grouped by physical disk; NVMe/drivetemp temperature |
| Custom glassmorphic background | Noctalia host panel (`background`, colour, opacity, radius, padding), plus translucent inner cards |
| Header cog | `ui.button` → `noctalia.openSettings()` |
| Fixed cyan/white/orange/red palette | Palette roles by default; every colour can be overridden with a hex value |
| Scroll when the tile is short | Not reproduced; resize the desktop-widget tile instead (see Limitations) |
| Show-card checkboxes, update interval, CPU fan number | Plugin and card settings, see [`modern-sysmonitor-plus/README.md`](modern-sysmonitor-plus/README.md#settings) |

The card order is CPU, GPU, VRAM, RAM, disks, network — the network card sits
at the bottom. The KDE widget only had a full desktop representation, so the
port has one `[[desktop_widget]]` entry and no bar widget or panel.

## Theming map

| KDE / original | Noctalia default |
| --- | --- |
| `Kirigami.Theme.textColor`, values | `on_surface` (`text_color`) |
| Disabled/muted labels | `on_surface_variant` (`muted_text_color`) |
| Cyan accent (`#00f0ff`), highlight | `primary` (`accent_color`) |
| `negativeTextColor`, hot temperature, full disk | `error` (`critical_color`) |
| Warning / warm stage | `tertiary` (`temp_warm_color`) |
| `backgroundColor`, outer glass | `surface` — Noctalia host panel |
| Inner card fill | `surface_variant` at `card_fill_opacity` |
| Separators / card border | `outline` |
| Bar track | `on_surface` at `track_opacity` (translucent role, not a fixed grey) |

The original cyan glass look is preserved as the default role mapping rather
than a fixed hex. To recreate the screenshot exactly, set **Accent colour** to
`#00f0ff`, **Panel opacity** to `0.22`, and **Primary text colour** to
`#ffffff`.

Safety states override presentation: a temperature at or above **Critical
temperature**, and a disk at or above **Disk warning**, switch the bar and value
to **Critical colour** and add an alert glyph, so colour is never the only
signal. The original temperature gradient is represented by a normal → warm →
critical severity bar.

The card deliberately draws **no outer surface**. Noctalia's host panel owns
the outer background, so the panel toggle and opacity slider always affect the
surface the user sees. The inner cards are translucent content surfaces, not a
second outer panel. With **Host panel background** off, the card adds a 6 px
content inset and draws no outer fill.

## Layout

| Path | What it is |
| --- | --- |
| `modern-sysmonitor-plus/` | The plugin: `plugin.toml`, `service.luau`, `card.luau`, `lib/`, translations, thumbnail |
| `install-kwe.sh` | Install for KineticWE's `noctalia-kwe` fork |
| `install.sh` | Install for upstream Noctalia |
| `uninstall-kwe.sh` | Remove from `noctalia-kwe` |
| `uninstall.sh` | Remove from upstream Noctalia |
| `remove-plugin-widgets.py` | Safely removes this plugin's desktop-widget instances from `settings.toml` |
| `catalog.toml` | Noctalia source catalog (the repo can be added as a plugin source) |
| `docs/noctalia.md` | API, state flow, install/reload and debugging notes |
| `tests/` | LuaJIT tests with a mocked Noctalia API, plus manifest checks |

Inside the plugin, `service.luau` is the composition entry; `lib/format.luau`,
`lib/hwmon.luau`, `lib/gpu.luau`, `lib/disks.luau` and `lib/sampler.luau` hold
one responsibility each. Only the service composes them; the card imports just
the formatter.

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then enable **Modern SysMonitor Plus** in **Settings → Plugins** if the
installer did not, and add it from **Settings → Desktop → Toggle Editor**.

`install-kwe.sh` links the plugin into
`~/.local/share/noctalia-kwe/plugins/modern-sysmonitor-plus`; `install.sh` uses
`~/.local/share/noctalia/plugins/modern-sysmonitor-plus`. Both honour
`NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`.

The desktop card is content-sized with no scrollbar. In the widget editor, set
the tile to roughly **Content width + 2 × Panel padding**; with the defaults
(320 px content, 10 px padding) that is about **340 px** wide. The height can be
whatever the cards need.

### Settings layout

Noctalia v5.3.0 renders plugin widget settings in a single column and has no
manifest field for columns, groups or sections. To keep that column usable, the
host panel **background toggle, colour, opacity, radius and padding are the
first rows** of the Widget section, followed by three collapsed groups, all
default off:

- **Show card settings** — card title, content width, gap, padding, radius, fill
  and border.
- **Show styling controls** — colours, bars, temperature thresholds, charts and
  dividers.
- **Show section toggles** — Show header/network/CPU/RAM/GPU/VRAM/disks/fan/
  details.

All stored values stay active while hidden. Noctalia also renders its own
Background section at the bottom of the inspector; it edits the same host-panel
keys as the first rows.

If you need a different layout, that is a shell-side change to the widget
inspector, not something a plugin manifest can request.

## Remove

```bash
./uninstall-kwe.sh   # KWE
./uninstall.sh       # upstream
```

The uninstall scripts disable the plugin, remove its desktop-widget instances
(with a timestamped `settings.toml` backup), and delete the plugin and its data
directory. Use `--yes` for non-interactive removal.

## Tests

```bash
./tests/run.sh
```

Requires LuaJIT and Python 3.11+ (for `tomllib`). The tests mock
`noctalia.*`, `ui.*` and `desktopWidget.*`, so no Noctalia session is needed.
They cover the formatters, the sampler (CPU/RAM/network deltas, AMD/Nvidia/host
GPU, fans, disk grouping), the card (every section, solid bars, usage charts, GPU details,
stale state, no-GPU state, role tokens vs. hex, host-panel padding) and a
service→card integration pass. Python then validates the manifest, catalog,
translations, entries and repository layout.

## Requirements

- Noctalia Shell with plugin API 22 or newer (upstream or `noctalia-kwe`)
- Linux `/proc`, `/sys/class/hwmon` (or `/sys/class/thermal`) and `df`
- AMD GPUs are read directly through `/sys/class/drm`
- Nvidia details need `nvidia-smi`; without it the host GPU probe is used
- Other GPUs (for example Intel) use the host probe, so Noctalia's system
  monitor must be enabled (`[system.monitor].enabled`, on by default)
- No Python, no helper daemon, no accounts or secrets
- `pciutils` for the AMD GPU fallback name; `vulkan-tools` for the exact AMD board name. Without them the GPU title falls back to a generic name.

## Limitations

- The KDE widget's QML glass shaders, blur and chromatic aberration cannot be
  reproduced by a Noctalia desktop widget. The card uses the host panel and
  exposes its colour, opacity, radius and padding.
- One GPU is shown. AMD picks the largest-VRAM card; otherwise `nvidia-smi` is
  used, then the host's single-GPU probe. A second GPU is not displayed.
- Disks are grouped by physical disk, like the KDE widget. LVM/RAID devices
  follow their first slave (the KDE widget did the same). Disk temperatures
  require an NVMe drive or the `drivetemp` module for SATA; otherwise the
  temperature is omitted and the sizes still show.
- CPU fan detection needs either a hwmon label containing “cpu” or an explicit
  fan number. Most motherboards do not label their fans.
- Desktop widgets cannot read their tile width in v5.3.0, so the card exposes
  **Content width**. Match it to the editor tile width.
- Desktop widgets cannot show tooltips; every value is visible on the card.
- The KDE widget scrolled inside a fixed-height tile. A Noctalia desktop widget
  is sized by its editor tile, so the port renders the full card and relies on
  the tile height. Use the show-card toggles to shorten the card when needed.
- The KDE temperature bar was a cyan→orange→red gradient. The port uses a
  severity-coloured bar with explicit warm/critical thresholds, which keeps the
  same meaning while respecting the user's palette.
- RAM, VRAM and disk usage use solid bars matching the temperature bar, so
  they no longer have the original 26-segment RAM look.
- A GPU with no probe is shown as **No GPU detected** instead of zeros, so an
  unknown GPU is never mistaken for an idle one.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE). Based on Modern SysMonitor Plus by
UnsaidSpeech and the original Modern SysMonitor by Joao Gabriel Medeiros.
