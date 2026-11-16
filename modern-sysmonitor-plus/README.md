# Modern SysMonitor Plus

A Noctalia desktop widget that monitors CPU, GPU, RAM, VRAM, physical disks and
network activity with solid bars, live usage charts and theme-aware colours.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/modern-sysmonitor-plus` |
| Desktop widget | `card` |
| Service | `poller` |

## Requirements

- Noctalia Shell with plugin API 22 or newer, including Noctalia KWE v5.
- Linux `/proc`, `/sys/class/hwmon` and `df` from coreutils.
- `pciutils` for the `lspci` AMD GPU name fallback.
- `vulkan-tools` for the exact AMD GPU name through `vulkaninfo`.
- Optional: `nvidia-smi` from the NVIDIA driver for NVIDIA telemetry.

The service reads local kernel interfaces. It makes no network requests and
writes no persistent data.

## Usage

Enable **Modern SysMonitor Plus** in **Settings → Plugins**, then add it from
**Settings → Desktop → Toggle Editor** (or the desktop-widget editor in your
Noctalia version). The card is content-sized; set the tile to roughly
**Content width + 2 × Panel padding** for a tight fit.

The header cog opens this plugin's settings. Hover is not used; every value is
visible on the card. When no sample has arrived yet, the card dims and shows
**Waiting for system data**; a machine without a GPU probe shows **No GPU
detected** instead of misleading zeros.

The editor groups the long settings list behind four toggles:

- **Show card settings** — title, content width, card gap, padding, radius, fill
  and border.
- **Show styling controls** — text, accent, track, temperature and warning
  colours.
- **Show scaling controls** — text size, bar/divider dimensions and chart
  scales.
- **Show section toggles** — the CPU, GPU, VRAM, RAM, disks, network, header and
  fan visibility controls.

Stored values keep working while a group is collapsed.

## Settings

### Sampling

| Setting | Default | Description |
| --- | --- | --- |
| `update_interval` | `2` s | Seconds between samples (1–60). The card treats a sample older than three intervals as stale. |
| `cpu_fan_number` | `0` | `0` selects a hwmon fan whose label contains “cpu”; `1`–`16` selects `fan<N>` on the motherboard sensor chip. |

### Sections

| Setting | Default | Description |
| --- | --- | --- |
| `show_header` | on | Title, settings button and header divider. |
| `show_network` | on | Download/upload values and their history charts. |
| `show_cpu` | on | CPU usage chart, temperature bar and optional fan row. |
| `show_ram` | on | RAM summary and solid usage bar. |
| `show_gpu` | on | GPU usage chart, temperature bar and **More** details. |
| `show_vram` | on | VRAM summary and solid usage bar. |
| `show_disks` | on | One block per physical disk with sizes, usage and temperature. |
| `show_cpu_fan` | on | Show the CPU fan row when the service found one. |
| `allow_gpu_details` | on | Show the GPU **More/Less** button. |

### Layout and scaling

| Setting | Default | Description |
| --- | --- | --- |
| `title` | `System Monitor` | Header heading. |
| `content_width` | `320` px | Card content width (240–900). |
| `card_gap` | `10` px | Gap between the header and cards, and between cards. |
| `card_padding` | `10` px | Inner padding of each card. |
| `card_radius` | `8` px | Inner-card corner radius. |
| `text_scale` | `1.0` | Multiplies every title, label, value and inline glyph (0.5–2.0) without changing bars or charts. |
| `bar_height` | `8` px | Solid usage, memory and temperature bar height (4–16). |
| `divider_width` | `1` px | Header, GPU-detail and disk divider thickness (0.5–4). |

### Charts

| Setting | Default | Description |
| --- | --- | --- |
| `chart_scale_mode` | `auto` | `auto` fits the largest visible sample; `fixed` uses the scale setting as the top and clips larger samples. |
| `cpu_chart_height` | `20` px | CPU usage chart height (12–48). |
| `cpu_chart_scale` | `10`% | Minimum CPU usage top; larger samples raise it. Set `100` for a fixed 0–100% scale. |
| `gpu_chart_height` | `20` px | GPU usage chart height (12–48). |
| `gpu_chart_scale` | `10`% | Minimum GPU usage top; larger samples raise it. |
| `network_chart_height` | `32` px | Download chart height (16–80); the upload chart uses 65%. |
| `network_scale_kbps` | `10` KB/s | Minimum network chart top (1–1024 KB/s). |
| `network_line_width` | `1.5` | Chart line thickness (0.5–4). |
| `network_fill_opacity` | `0.15` | Area fill under every chart line (0–1). |
| `history_points` | `30` | Samples kept for network and CPU/GPU charts (10–120). |

### Colours and surfaces

| Setting | Default | Description |
| --- | --- | --- |
| `accent_color` | `primary` | Headings, bar fills, chart lines and normal temperature. |
| `text_color` | `on_surface` | Values and titles. |
| `muted_text_color` | `on_surface_variant` | Labels, units, placeholders and inactive values. |
| `track_color` | `on_surface` | Unfilled bar and temperature track. |
| `track_opacity` | `0.14` | Track opacity (0–1). |
| `card_fill_color` | `surface_variant` | Inner-card fill. |
| `card_fill_opacity` | `0.35` | Inner-card fill opacity (0–1). |
| `card_border_color` | `outline` | Inner-card border. |
| `card_border_width` | `1` px | Inner-card border width (0–4). |
| `divider_color` | `outline` | Header, GPU-detail and disk dividers. |
| `temp_warm_color` | `tertiary` | Temperature between the warm and critical thresholds. |
| `critical_color` | `error` | Hot temperature, disk warning and alert glyphs. |

Every colour accepts a palette role or a hex value. Role tokens follow the live
Noctalia palette; hex values stay fixed.

### Temperature and disk safety

| Setting | Default | Description |
| --- | --- | --- |
| `temp_warm` | `70` °C | At or above this the temperature bar/value use the warm colour. |
| `temp_hot` | `85` °C | At or above this the bar/value use the critical colour and show an alert glyph. Critical wins over warm. |
| `disk_warning` | `90`% | At or above this the disk bar/percentage use the critical colour and show an alert glyph. |

### Host surface

| Setting | Default | Description |
| --- | --- | --- |
| `background` | on | Let Noctalia draw its panel behind the card. |
| `background_color` | `surface` | Host panel fill. |
| `background_opacity` | `0.8` | Host panel opacity (0–1). |
| `background_radius` | `12` px | Host panel corner radius. |
| `background_padding` | `10` px | Space between the panel edge and the card content. |

The card draws no outer surface of its own. With the host panel off it adds a
6 px content inset and renders directly on the wallpaper.

## Notes

- CPU, RAM, network and temperatures are read from `/proc` and `/sys` every
  update interval.
- Disks come from `df -kPT` and are refreshed every 10 seconds. Physical
  filesystems are grouped by disk; LVM/LUKS/RAID devices follow their first
  slave.
- The AMD GPU is read from `/sys/class/drm`; Nvidia uses `nvidia-smi` when it is
  available; other GPUs fall back to the host system-monitor probe.
- Optional commands: `lspci` (`pciutils`), `vulkaninfo` (`vulkan-tools`) and
  `nvidia-smi` (NVIDIA driver). They are not required for CPU, memory, network
  or disk monitoring.
- One GPU is shown. Disk temperature requires NVMe or the `drivetemp` module
  for SATA.
- Desktop widgets cannot read their tile width, so use **Content width** to
  match the editor tile. The port does not scroll inside a fixed-height tile.

## Credits and License

Based on Modern SysMonitor Plus by UnsaidSpeech, itself based on Modern
SysMonitor by Joao Gabriel Medeiros. LGL adapted and extended it for Noctalia
and Noctalia KWE.

GPL-3.0-or-later — see [LICENSE](LICENSE).
