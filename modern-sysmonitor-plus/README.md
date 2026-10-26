# Modern SysMonitor Plus

Noctalia v5 plugin with a headless sampler (`poller` service) and a desktop
card (`card` widget entry). The service reads the sources the KDE widget used,
publishes one plain `stats` table, and the card watches it, keeps the network
and CPU/GPU usage history, and renders a `ui.*` tree. There is no QML and no
external daemon. The card order is **CPU, GPU, VRAM, RAM, disks, network**.

## How the data is collected

| Metric | Source | Notes |
| --- | --- | --- |
| CPU usage | `/proc/stat`, first `cpu` line | Busy time from the delta between samples, 0–100%. The first sample primes the delta and publishes `nil`, so the card shows `—` for one interval. |
| CPU temperature | `hwmon` and thermal zones | Hottest valid `coretemp` / `k10temp` / `zenpower` / `cpu_thermal` / `soc_thermal` sensor, then any non-GPU hwmon temperature, then `x86_pkg_temp` / CPU / package thermal zones. Absent when no sensor exists. |
| CPU fan | `hwmon` `fan<N>_input` | With **CPU fan number** 0, a fan whose label contains “cpu” is used. With 1–16, `fan<N>` on the motherboard chip with the most fan inputs is used, matching `sensors`. A known fan that reads 0 RPM is shown as 0. |
| RAM | `/proc/meminfo` | `MemTotal − MemAvailable`, falling back to `MemFree + Buffers + Cached`; published in 1024-based GB. |
| Network | `/proc/net/dev` | Receive/transmit deltas across every interface except `lo`. Uses `noctalia.nowMs()` for sub-second rate accuracy. |
| GPU usage / temperature / VRAM | AMD `sysfs`, then `nvidia-smi`, then the host probe | AMD: the largest-VRAM `card*` with `gpu_busy_percent` and `mem_info_vram_total`; hwmon `temp*_label` (`edge`, `junction`, `mem`), `freq*_label` (`sclk`, `mclk`), `fan1_input`, `pwm1`, `power1_*`. Nvidia: `nvidia-smi --query-gpu=…`; if the driver rejects the full field list, a short usage/temp/VRAM query is retried. The host's `noctalia.systemStats()` GPU probe is the final fallback for Intel or NVML-only setups. |
| Disks | `df -kPT` plus sysfs | Every 10 s. Physical filesystems are grouped by physical disk; btrfs subvolumes and repeated mounts of the same source are counted once. LUKS/LVM/RAID devices follow their first slave, as the KDE widget did. Model from `/sys/class/block/<disk>/device/model`; temperature from the disk's own hwmon (NVMe, or SATA with `drivetemp`). |

Missing sensors are published as `nil`, not `0`. The card renders `—` for
unknown values and an explicit **No GPU detected** line when no GPU probe is
available.

## State flow

The service publishes `stats` through `noctalia.state`:

```lua
{
  ts = os.time(),
  seq = 1, -- increases once per published sample
  cpu = { usage, temp_c, fan_rpm },
  ram = { used_gb, total_gb, pct },
  net = { down_bps, up_bps },
  gpu = {
    present = true, vendor = "amd" | "nvidia" | "host",
    usage, temp_c, vram_used_gb, vram_total_gb, vram_pct,
    temp_junction, temp_mem, clock_mhz, mem_clock_mhz,
    fan_rpm, fan_pct, power_w, power_cap_w,
  } or nil,
  disks = {
    { key, name, temp_c, used_gb, total_gb, pct }, ...
  },
}
```

The card appends one history point per distinct `ts:seq` for the network, CPU
usage and GPU usage charts, so a stalled service does not duplicate points and
the chart cadence follows **Update every**. A state older than three update intervals is stale: the card dims the
content, blanks the values, keeps the history and shows **Waiting for system
data**.

`gpu` is `nil` when no probe is available. A GPU can be present with
`vram_used_gb = nil` (for example an Intel GPU through the host probe); the VRAM
card then shows `—`.

## Settings

### Plugin settings

Edited under **Settings → Plugins** (the gear on the plugin row). They are
shared by the service and the card.

| Setting | Default | What it does |
| --- | --- | --- |
| Update every | 2 s | Sampling cadence (1–60 s). The card's stale timeout is three intervals. |
| CPU fan number | 0 | `0` = automatic (label containing “cpu”); `1`–`16` = `fan<N>` on the motherboard sensor chip. |

### Card sections

The inspector starts with the host background controls and three collapsed
groups: **Show card settings**, **Show styling controls** and **Show section
toggles**. Hidden values stay active; the toggles only control visibility in
the editor.

| Setting | Default | What it does |
| --- | --- | --- |
| Show card settings | off | Reveal the card title, content width, gap, padding, radius, fill and border controls. Their values stay active while hidden. |
| Show styling controls | off | Reveal the colour, bar, temperature, chart and divider controls. Their values stay active while hidden. |
| Show section toggles | off | Reveal the nine section visibility controls below. Their values stay active while hidden. |
| Card title | System Monitor | Header heading. |
| Show header | on | Title and settings button. |
| Show network | on | Download/upload values and charts. |
| Show CPU | on | CPU usage, temperature and optional fan. |
| Show RAM | on | RAM summary and bar. |
| Show GPU | on | GPU usage/temperature and the More details. |
| Show VRAM | on | VRAM summary and bar. |
| Show disks | on | One block per physical disk. Hides when no disks are found. |
| Show CPU fan | on | Show the CPU fan row when a fan is found. |
| Allow GPU details | on | Show the GPU More/Less button. |

### Layout

| Setting | Default | What it does |
| --- | --- | --- |
| Content width | 320 px | Card content width (240–900). Match the editor tile width minus the host padding. |
| Card gap | 10 px | Space between header/cards and between cards. |
| Card padding | 10 px | Inner padding of each card. |
| Card corner radius | 8 px | Inner-card radius. |
| Bar height | 8 px | Segmented-bar and temperature-bar height (4–16). |
| Segment count | 20 | Segments in the CPU, RAM, GPU and VRAM bars (8–40). |
| Segment gap | 3 px | Gap between segments (0–6). |
| Divider thickness | 1 px | Header, GPU-details and disk dividers (0.5–4). |

### Charts

CPU and GPU usage are area charts like the network charts and auto-scale to
their largest visible sample, with a configurable minimum top of the scale. RAM,
VRAM and disks keep segmented bars. All charts and percentage values use the
accent colour; disk warnings use the critical colour.

| Setting | Default | What it does |
| --- | --- | --- |
| CPU chart height | 20 px | CPU usage chart height (12–48). |
| CPU chart scale | 10% | Minimum top of the CPU usage scale; a larger sample raises it automatically. Set 100 for an absolute 0–100% scale. |
| GPU chart height | 20 px | GPU usage chart height (12–48). |
| GPU chart scale | 10% | Minimum top of the GPU usage scale; a larger sample raises it automatically. Set 100 for an absolute 0–100% scale. |
| Network chart height | 32 px | Download chart height (16–80); the upload chart is 65% of it. |
| Network chart scale | 10 KB/s | Minimum top of the network scale; a larger sample raises it automatically (1–1024 KB/s). |
| Chart line width | 1.5 | Network and CPU/GPU usage chart line thickness (0.5–4). |
| Chart fill opacity | 0.15 | Area fill under every chart line (0–1). |
| Chart history | 30 | Samples kept for the network and CPU/GPU usage charts (10–120). |

### Colours

Every colour accepts a palette role token (`primary`, `secondary`, `tertiary`,
`on_surface`, `on_surface_variant`, `outline`, `error`, …) or a hex
value (`#rrggbb` / `#rrggbbaa`). Role tokens follow the live Noctalia palette;
hex values stay fixed. The manifest does not accept a role with an alpha suffix
in a setting, so translucency has separate opacity controls.

| Setting | Default | What it styles |
| --- | --- | --- |
| Accent colour | `primary` | Section headings, bar fills, charts and normal temperature. |
| Primary text colour | `on_surface` | Values and titles. |
| Secondary text colour | `on_surface_variant` | Labels, units and unknown values. |
| Card fill colour | `surface_variant` | Inner-card fill. |
| Card fill opacity | 0.35 | Inner-card fill opacity (0–1). |
| Card border colour | `outline` | Inner-card border. |
| Card border width | 1 px | Inner-card border (0–4). |
| Bar track colour | `on_surface` | Unfilled segmented bar and temperature track. |
| Bar track opacity | 0.14 | Track opacity (0–1). |
| Warm temperature colour | `tertiary` | Temperature between the warm and critical thresholds. |
| Critical colour | `error` | Hot temperature, disk warning, alert glyphs. |
| Divider colour | `outline` | All dividers. |

### Temperature and disk safety

| Setting | Default | What it does |
| --- | --- | --- |
| Warm temperature | 70 °C | At or above this the bar/value use the warm colour. |
| Critical temperature | 85 °C | At or above this the bar/value use the critical colour and show a warning glyph. Critical wins over warm. |
| Disk warning | 90% | At or above this the disk bar/percentage use the critical colour and show a warning glyph. |

### Surface

The card deliberately draws **no outer surface**. Noctalia's desktop-widget
host owns the panel behind it, so the panel toggle and opacity slider always
affect the surface the user sees. These keys are handled by the host, not this
script:

| Setting | Default | What it does |
| --- | --- | --- |
| Host panel background | on | Let Noctalia draw its surface behind the card. Turn off to place content directly on the wallpaper. |
| Panel colour | `surface` | Host panel fill. |
| Panel opacity | 0.8 | Applied live by the host without recreating the widget. |
| Panel corner radius | 12 px | Host panel radius. |
| Panel padding | 10 px | Space between the panel edge and the card content. |

These five controls appear first in the editor's **Widget** section so the
transparency is easy to reach. Noctalia also renders its own **Background**
section at the bottom of the inspector; both edit the same host-panel keys.

With the panel on, size the editor tile to **Content width + 2 × Panel padding**
(340 px wide with the defaults) for a tight fit. With the panel off the card
adds a 6 px content inset.

For the original glass look, use **Panel opacity 0.22**, **Accent colour
`#00f0ff`** and **Primary text colour `#ffffff`**.

## Theming behaviour

- Defaults are palette roles, so they track theme and palette changes live.
  `on_surface/0.14` for the bar track is a translucent role, not a fixed grey.
- Fixed hex values in user settings do not change with the theme; that is
  intentional, so brand or custom colours stay put.
- Unknown or stale data is dimmed and rendered as `—`, never as a misleading
  `0%`. A stale card also shows a **Waiting for system data** line.
- The card never draws a second outer surface on top of the host panel, so the
  host opacity control cannot be hidden by an opaque plugin fill.
- Temperature and disk warnings are paired with a glyph, so colour is not the
  only signal.

## Troubleshooting

**The widget does not appear in the editor.** Check the install path. The plugin
must live in the running shell's app dir:

- upstream: `~/.local/share/noctalia/plugins/modern-sysmonitor-plus`
- KWE: `~/.local/share/noctalia-kwe/plugins/modern-sysmonitor-plus`

Then run `noctalia msg config-reload` (or `noctalia-kwe msg config-reload`) and
enable it in **Settings → Plugins**. A plugin must be discovered before it can
be enabled, and enabled before its widget type appears.

**CPU shows `—` for the first interval.** The first `/proc/stat` sample only
primes the delta. The first percentage appears on the next sample.

**Network shows `—` for the first interval.** The first `/proc/net/dev` sample
primes the byte counters. The first rate appears on the next sample.

**CPU temperature shows `—`.** The kernel exposes no matching sensor. Check
`sensors`; the service looks for `coretemp`, `k10temp`, `zenpower`,
`cpu_thermal`, `soc_thermal`, then CPU thermal zones.

**CPU fan is missing.** Leave **CPU fan number** on Automatic and check whether
`sensors` gives the fan a label containing “cpu”. Otherwise set the number that
matches `fan1`, `fan2`, … in `sensors`. The motherboard driver (for example
`nct6775` or `it87`) must be loaded.

**The GPU card says “No GPU detected”.** AMD cards are read from
`/sys/class/drm/card*/device`. Nvidia needs `nvidia-smi` on `PATH`. Other vendors
need Noctalia's system monitor (`[system.monitor].enabled`, on by default) so the
host GPU probe can run. A VM or a machine with no probe shows the explicit
message.

**A disk temperature is missing.** NVMe drives expose it out of the box. SATA
drives need the `drivetemp` module; without it the disk still shows model,
sizes and usage.

**A disk is missing.** The service only lists physical `/dev/*` filesystems from
`df -kPT`; pseudo filesystems, loop devices, zram and read-only images are
excluded. LVM/LUKS/RAID devices are grouped under their first physical slave.

**The card is clipped or has empty space.** Set **Content width** to match the
tile width minus twice the panel padding, or turn the host panel off. The port
does not scroll inside a fixed-height tile like the KDE widget did; resize the
tile height instead.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE). Based on Modern SysMonitor Plus by
UnsaidSpeech and the original Modern SysMonitor by Joao Gabriel Medeiros.
