# Noctalia plugin notes

This is the Noctalia-specific companion to the main [README](../README.md). It
covers the plugin API surface, entries, install paths, live reload, state flow,
performance notes and debugging commands.

## Plugin API and entries

`plugin.toml` declares `plugin_api = 22` and two entries:

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `poller` | `[[service]]` | `service.luau` | Samples /proc, /sys, hwmon, AMD sysfs, nvidia-smi and `df`; publishes `stats` |
| `card` | `[[desktop_widget]]` | `card.luau` | Renders the solid-bar and chart desktop card |

API levels used:

| Level | Capability | Why it is needed |
| --- | --- | --- |
| 15 | `noctalia.openSettings()` | Header settings button |
| 17 | services start on enable | The poller is a service |
| 22 | relative module `require` | `lib/` modules |

The service and the card are separate Luau VMs. They exchange only plain values
through `noctalia.state` under the key `stats`; no functions, userdata or file
handles cross the boundary.

## Modules

| File | Responsibility |
| --- | --- |
| `service.luau` | Composition entry: settings, timers, async GPU/disk caches, publishing |
| `card.luau` | Declarative card, network and CPU/GPU usage history, formatting, GPU details toggle |
| `lib/format.luau` | Pure clamp/round/trim, speed and size formatters |
| `lib/hwmon.luau` | sysfs reads, hwmon discovery, CPU temperature, CPU fan, disk temperature |
| `lib/gpu.luau` | AMD sysfs reader, Nvidia CSV parser and command, host-probe fallback |
| `lib/disks.luau` | `df -kPT` parser, physical-disk grouping, LVM mapper resolution |
| `lib/sampler.luau` | CPU/RAM/network deltas |

Only `service.luau` composes the hardware modules. `card.luau` imports only
`lib/format.luau`; it never touches `/proc` or `/sys` itself. No module imports a
provider registry, because this plugin has no providers.

## Install locations

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/modern-sysmonitor-plus` | `~/.local/state/noctalia` | `noctalia` |
| KineticWE `noctalia-kwe` | `~/.local/share/noctalia-kwe/plugins/modern-sysmonitor-plus` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`. The install scripts create
a symlink to the repo's `modern-sysmonitor-plus/` directory, so repository edits
are visible to the shell immediately.

The plugin writes no persistent data. It has no accounts, secrets, generated
art, locks or temporary files, so `noctalia.pluginDataDir()` is not used. The
uninstallers still remove the would-be data directory
`~/.local/state/<app>/plugins/data/unsaidspeech/modern-sysmonitor-plus` in case a
future version creates one.

## Reloading during development

- **`.luau` changes** hot-reload the owning entry. A change in `lib/` reloads
  every entry that successfully required that module. The shell log shows
  messages such as `hot reload: reloaded 'card.luau'`.
- **`plugin.toml` changes** need a config reload:

  ```bash
  noctalia-kwe msg config-reload
  ```

  If a new setting is not recognised, disable and re-enable the plugin once so
  the service gets a fresh settings snapshot:

  ```bash
  noctalia-kwe msg plugins disable unsaidspeech/modern-sysmonitor-plus
  noctalia-kwe msg plugins enable unsaidspeech/modern-sysmonitor-plus
  ```

- **Desktop-widget settings controls** are built from the manifest when the
  widget editor opens. After changing a `[[desktop_widget.setting]]`, close and
  reopen the editor.
- **Do not edit `settings.toml` by hand to add a widget instance** unless you
  validate the TOML first. A missing comma in `widget_order` makes the shell
  reject the whole file and fall back to defaults. Prefer the editor, or a
  backup + `tomllib` validated script like `remove-plugin-widgets.py`.

## Settings

### Plugin-level

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `update_interval` | int | 2 | Seconds between samples (1–60) |
| `cpu_fan_number` | int | 0 | 0 = automatic label containing “cpu”; 1–16 = `fan<N>` on the board chip |

Changing `update_interval` calls `noctalia.setUpdateInterval()` in place through
`onConfigChanged()`; the service keeps its CPU/network deltas and disk cache.
Changing `cpu_fan_number` takes effect on the next sample.

### Desktop card

The card settings are grouped in the plugin README:

- sections: `title`, `show_card_settings`, `show_styling`, `show_scaling`, `show_sections`, `show_header`, `show_network`, `show_cpu`, `show_ram`,
  `show_gpu`, `show_vram`, `show_disks`, `show_cpu_fan`, `allow_gpu_details`
- layout: `content_width`, `card_gap`, `card_padding`, `card_radius`
- scaling: `text_scale`, `bar_height`, `chart_scale_mode`, `cpu_chart_height`, `cpu_chart_scale`,
  `gpu_chart_height`, `gpu_chart_scale`, `network_chart_height`, `network_scale_kbps`,
  `network_line_width`, `divider_width`, `history_points`
- colours: `accent_color`, `text_color`, `muted_text_color`,
  `card_fill_color`, `card_fill_opacity`, `card_border_color`,
  `card_border_width`, `track_color`, `track_opacity`, `temp_warm_color`,
  `critical_color`, `network_fill_opacity`, `divider_color`
- safety: `temp_warm`, `temp_hot`, `disk_warning`
- host surface: `background`, `background_color`, `background_opacity`,
  `background_radius`, `background_padding`

Noctalia v5.3.0 renders the desktop-widget inspector as a single column and has no manifest field for columns, groups or sections. To keep that column usable, the host background controls are declared first, `show_card_settings` (default off) hides the card title/width/layout/fill/border controls, `show_styling` (default off) hides the colour/temperature/disk-warning list, `show_scaling` (default off) hides the text size, bar/divider dimensions and chart size/scale list, and `show_sections` (default off) hides the nine section visibility toggles; the stored values stay active. **Background transparency** is the host panel's `background_opacity`, shown at the top of the Widget section and in the host's own Background section.

Every `double` that ranges 0–1 has an explicit `step` (`0.01` for the host
opacity, `0.05` for the other opacities), so the sliders move continuously.
`background_opacity` is host-handled and updates the host panel live without
recreating the card. The card reads the host keys only to honour lint's
declared-key contract and to add a 6 px inset when the panel is off; it never
draws an outer surface of its own.

## State flow

The service publishes `stats` once per update interval:

```text
{
  ts, seq,
  cpu = { name, usage, temp_c, fan_rpm },
  ram = { used_gb, total_gb, pct },
  net = { down_bps, up_bps },
  gpu = { present, vendor, usage, temp_c, vram_*, temp_junction, temp_mem,
          clock_mhz, mem_clock_mhz, fan_rpm, fan_pct, power_w, power_cap_w } | nil,
  disks = { { key, name, temp_c, used_gb, total_gb, pct }, ... }
}
```

The card:

- appends one history point per distinct `ts:seq` for the network, CPU usage
  and GPU usage charts (so a plain `update()` never duplicates a point);
- normalises network charts against `network_scale_kbps`, and CPU/GPU usage
  against `cpu_chart_scale` / `gpu_chart_scale`; in `Auto` mode the largest
  visible sample raises the top, in `Fixed` mode the scale setting is the
  fixed top and larger samples clip (useful for a more zig-zaggy line);
- treats a state older than `max(3, update_interval * 3)` seconds as stale;
- blanks values with `—`, keeps the history, dims the content and shows
  **Waiting for system data** when stale;
- shows **No GPU detected** when `gpu` is nil, instead of zeros.

No notifications are sent; the KDE widget had none.

## Sampling and performance

- The CPU name is read once from `/proc/cpuinfo`; the AMD GPU name comes from
  `vulkaninfo --summary` (exact board name), with a one-shot `lspci -nn`
  fallback. Nvidia names come from `nvidia-smi`. `vulkan-tools` and `pciutils`
  are optional; without them the AMD GPU title shows just "GPU".
- CPU, RAM, network and temperatures are read synchronously from `/proc` and
  `/sys`. They are small text files and the sampler runs once per update
  interval (2 s by default).
- `df -kPT` runs through `noctalia.runAsync()` and is refreshed every 10 s, the
  same cadence as the KDE widget. A missing/failed `df` keeps the previous disk
  cache.
- `nvidia-smi` runs through `noctalia.runAsync()` only when no AMD card was
  found and `nvidia-smi` is on `PATH`. Results are cached for 15 s and refreshed
  at most every 5 s. The full query is retried as a short query if the driver
  rejects clock/fan/power fields; repeated failures pause Nvidia sampling for
  60 s and fall back to the host probe.
- AMD GPU data comes from `/sys/class/drm` and its hwmon; it is read every
  sample and does not spawn a process.
- RAM, VRAM and disk bars are `ui.progress` nodes; the CPU, GPU and network
  charts are `ui.graph` nodes. There are no per-segment boxes to keep in sync.
- The card renders on state changes, once per second for the stale check, and
  on the GPU More/Less toggle. It does not request frame ticks.

## Manual checks

```bash
# Discover / lint the installed plugin
noctalia-kwe plugins lint modern-sysmonitor-plus

# Check the live plugin list after enabling
noctalia-kwe msg plugins list

# Force a config reload after editing plugin.toml
noctalia-kwe msg config-reload

# Open the desktop-widget editor
noctalia-kwe msg desktop-widgets-edit
noctalia-kwe msg desktop-widgets-exit

# Inspect the log for script errors or undeclared-setting warnings
journalctl --user -n 200 --no-pager | grep -iE 'modern-sysmonitor|plugin'
```

The service has no IPC handler; it is a pure poller. To test the service-entry
runtime, use the shell's config reload or disable/enable cycle.

## Tests

`tests/run.sh` parses every `.luau` file with LuaJIT, runs the mocked tests and
then checks the manifest, catalog, translations, entry files, thumbnail and
repository layout with Python. It does not need a live shell.

The mock covers:

- `test_format.luau` — clamp, rounding, speed/size/percent formatting.
- `test_service.luau` — CPU/RAM/network deltas, CPU temperature/fan selection,
  AMD GPU fields, Nvidia full/short query fallback, host GPU fallback, disk
  grouping (including LVM and duplicate mounts), missing sensors, malformed
  `/proc/stat`, disk refresh cadence and config changes.
- `test_card.luau` — every section, CPU/GPU usage charts, solid bar fills,
  GPU details, stale state, no-GPU state, hidden sections, host-panel inset,
  role tokens vs. hex, text scaling (independent of bar/chart sizes),
  opacity/stroke/width settings and the settings callback.
- `test_integration.luau` — real service + real card, initial waiting state,
  live values, network and usage history cadence, stale handling and recovery.

## Related

- [README](../README.md) — install, feature mapping, theming, limitations
- [plugin README](../modern-sysmonitor-plus/README.md) — full settings and data sources
- [catalog.toml](../catalog.toml) — source catalog metadata
- [install-kwe.sh](../install-kwe.sh) / [install.sh](../install.sh) — installers
