# Steam Controller Battery — Noctalia plugin

A Noctalia desktop widget for the Steam Controller 2 ("Triton") that shows the
battery level, charging state, connection type and wireless link quality. It is
a port of the
[KDE Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget),
using the same reverse-engineered HID protocol.

The card mirrors the controller's LED: **colour = how it is connected** (white =
puck, blue = Bluetooth, green = USB-C), **pulsing = charging**, orange = switched
off on the puck's dock, red = low battery.

| Field | Value |
| --- | --- |
| ID | `jahrek/steam-controller` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

Tested live on KineticWE's `noctalia-kwe` v5.3.0. Upstream Noctalia uses the
same v5 plugin API; adjust the data path as described under **Install**.

## Requirements

- Noctalia Shell with plugin API 17 or newer, including KineticWE's
  `noctalia-kwe` build of Noctalia v5
- Python 3 (standard library only — no pip packages)
- Permission to read the controller's `/dev/hidraw*` nodes. On most distros the
  udev rules shipped for Steam already grant this. If not, add a rule such as:

  ```udev
  SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", TAG+="uaccess"
  ```

  then reload udev and replug the controller.

The controller is not supported by the kernel's `hid-steam` driver yet, so it
does not appear in `/sys/class/power_supply/` or in UPower. This plugin reads
the vendor HID reports directly.

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

`install-kwe.sh` links into `~/.local/share/noctalia-kwe/plugins`.
`install.sh` links into `~/.local/share/noctalia/plugins`. Both scripts honor
`NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`.

Manual install for upstream Noctalia:

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins"
ln -sfn "$PWD/steam-controller" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/steam-controller"
noctalia msg config-reload
noctalia msg plugins enable jahrek/steam-controller
```

Manual install for `noctalia-kwe`:

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia-kwe/plugins"
ln -sfn "$PWD/steam-controller" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia-kwe/plugins/steam-controller"
noctalia-kwe msg config-reload
noctalia-kwe msg plugins enable jahrek/steam-controller
```

You can also add the `noctalia/` directory as a local source (it contains
`catalog.toml`):

```bash
noctalia-kwe msg plugins source add steam-controller path /path/to/repo/noctalia
```

Then:

1. Open **Settings → Plugins**, refresh the plugin list, and enable
   **Steam Controller Battery** if it is not already enabled.
2. Turn on the desktop widget editor (**Settings → Desktop → Toggle Editor**)
   and add **Steam Controller Battery**.
3. Place and size the card. The card scales with its box.

The service starts automatically when the plugin is enabled. No autostart entry
or separate systemd unit is needed.

The editor writes widget instances to `settings.toml`; upstream Noctalia uses
`~/.local/state/noctalia/settings.toml`, and `noctalia-kwe` uses
`~/.local/state/noctalia-kwe/settings.toml`.

### Declarative config

The editor writes to `settings.toml`, but you can also declare the widget in
`~/.config/noctalia/*.toml`:

```toml
[desktop_widgets]
enabled = true

[desktop_widgets.widget.steam_controller]
type       = "jahrek/steam-controller:card"
output     = "DP-1"          # your connector name
cx         = 1400.0
cy         = 200.0
box_width  = 0.0             # 0 = auto-fit the card
box_height = 0.0

[desktop_widgets.widget.steam_controller.settings]
illustration_color      = "#e8ebef"
controller_body_color   = "#2c3035"
controller_stroke_width = 3.4
battery_color_mode      = "connection"   # connection | custom
battery_fill_color    = "#fcfcfc"      # used when mode = custom
battery_low_color       = "#ed4c4c"
text_color              = "on_surface"
muted_text_color        = "on_surface_variant"
show_signal             = true
signal_style            = "bars"         # bars | bars_dbm | dbm

[plugin_settings."jahrek/steam-controller"]
low_threshold = 20
notify_low    = true
```

The plugin-level keys are shared by the service and the card; the other
entries are per-widget presentation settings.

## Settings

| Setting | Scope | Default | Description |
| --- | --- | --- | --- |
| `low_threshold` | plugin | `20` | Percentage at or below which the card shows the low state and the service may notify. |
| `notify_low` | plugin | `true` | Send one desktop notification when the battery first drops to the threshold. |
| `illustration_color` | desktop widget | `#e8ebef` | Controller line-art colour. |
| `controller_body_color` | desktop widget | `#2c3035` | Controller body fill colour. |
| `controller_stroke_width` | desktop widget | `3.4` | Controller outline and trackpad edge thickness (`0.5`–`8`). |
| `battery_color_mode` | desktop widget | `connection` | `connection` uses the LED colours; `custom` uses `battery_fill_color`. |
| `battery_fill_color` | desktop widget | `#fcfcfc` | Custom battery fill colour, used when `battery_color_mode = "custom"`. |
| `battery_low_color` | desktop widget | `#ed4c4c` | Low-battery fill, percentage, weak-signal meter and marker colour. Always wins when low. |
| `text_color` | desktop widget | `on_surface` | Percentage, status text, marker and active signal bars. |
| `muted_text_color` | desktop widget | `on_surface_variant` | Percentage sign, `via` line, dBm label and inactive signal bars. |
| `show_signal` | desktop widget | `true` | Show the wireless link meter for a controller connected through the puck. |
| `signal_style` | desktop widget | `bars` | `bars`, `bars_dbm`, or `dbm`. |

The desktop widget also gets Noctalia's standard background settings
(`background`, `background_color`, `background_opacity`, `background_radius`,
`background_padding`). To match the Plasma card, try `background_color =
"surface"`, `background_opacity = 0.92`, `background_radius = 16`, and
`background_padding = 14`.

### Colours

- `illustration_color`, `controller_body_color` and
  `controller_stroke_width` are drawn into a generated SVG in the plugin data
  directory. The colours accept a hex value or a palette role token;
  `controller_stroke_width` scales the body outline and trackpad edges.
- `battery_color_mode = "connection"` (the default) uses the controller's LED
  colours: white on the puck, blue over Bluetooth, green on USB-C, orange while
  charging off-dock.
- `battery_color_mode = "custom"` uses `battery_fill_color` for the battery fill.
- `battery_low_color` always takes precedence when the battery is low. It also
  colours the percentage, the weak-signal meter and the low-battery marker.
- `text_color` and `muted_text_color` control the percentage/status/marker and
  the secondary text (`%`, `via` line, dBm, inactive bars). They are passed
  straight to the UI, so a role token follows a live theme change.

The battery and text colour settings accept hex values or palette role tokens.

For the controller colours, palette roles are resolved with
`noctalia.getColor()` and re-resolved on every update (about once a second), so
a role like `primary`, `on_surface` or `surface_variant` follows a live theme
change. Hex values stay fixed. On a Noctalia version without `getColor()`, the
controller falls back to the default light line and dark body.

The connection-mode battery fill uses fixed LED colours by design. Select
**Custom colour** and set a role token if you want the battery fill itself to
follow the theme; `battery_low_color` also accepts a role token such as
`error`.

## How it works

- `code/sc_battery_daemon.py` scans `/dev/hidraw*` for Valve's `28de:1304`
  (puck), `28de:1305` (Steam Machine's built-in receiver), `28de:1302` (USB-C)
  and `28de:1303` (Bluetooth LE).
- Report `0x43` carries the live battery percentage in byte `[2]` and the
  charging flag in byte `[1]`.
- Report `0x7b` byte `[9]` carries the signed dBm value of the pad ↔ puck link.
- Over Bluetooth the pad exposes a standard Battery Service, so the daemon reads
  the live percentage through BlueZ (`busctl`).
- The puck is asked (feature report `0xB4`) whether the pad is on its charging
  dock, which distinguishes "docked and switched off" from "off".
- The service runs the daemon with `noctalia.runStream()` and publishes each
  JSON line to the `controller` key in `noctalia.state`. The desktop widget
  watches that key and re-renders.
- A lock file (`$XDG_RUNTIME_DIR/noctalia-sc-battery.lock`) keeps a single
  daemon. The service also kills a daemon left over from a previous Noctalia
  process before starting a new one.
- A debug copy of the current state is written to
  `$XDG_RUNTIME_DIR/noctalia-sc-battery.json`.

## IPC

Rumble the controller (the Plasma widget's easter egg, without the sound):

```bash
noctalia-kwe msg plugin jahrek/steam-controller:battery all buzz
```

Restart the daemon:

```bash
noctalia-kwe msg plugin jahrek/steam-controller:battery all restart
```

Use `noctalia msg ...` instead of `noctalia-kwe msg ...` on upstream Noctalia.

## Troubleshooting

- **Plugin never appears in Settings → Plugins / the desktop editor:** check the
  data path. `noctalia-kwe` reads
  `~/.local/share/noctalia-kwe/plugins`, not
  `~/.local/share/noctalia/plugins`. Run `./install-kwe.sh` for KWE
  (or `./install.sh` for upstream), then
  `noctalia-kwe msg config-reload`.
- **Plugin appears but the widget does not:** the `illustration_color` setting
  must be a valid hex or palette role. This port defaults to `#e8ebef`; do not
  set it to an empty string in `settings.toml`.
- **"Waiting for controller" forever:** check the plugin log and `python3
  --version`. Also verify the daemon can open the hidraw node:
  `python3 steam-controller/code/sc_battery_daemon.py --stream`.
- **Battery stays at the last value:** the pad is on the puck's dock but
  switched off. The card shows the last known value dimmed with a clock.
- **No signal meter:** signal strength is only sent over the puck link, not over
  Bluetooth or USB-C.
- **Card has no background:** enable `background` in the widget's settings; the
  host draws the card surface.

## Development

The service and card scripts have small LuaJIT tests that mock the Noctalia API
(no live Noctalia session needed):

```bash
./tests/run.sh
```

They cover state publishing, low-battery notifications, the card tree, signal
bars, the charging pulse, the stale state and the service→card integration.

## Uninstall

Use the script that matches your shell:

```bash
# KineticWE's noctalia-kwe fork
./uninstall-kwe.sh

# Upstream Noctalia
./uninstall.sh
```

Each script:

- disables the plugin through the running shell, so its service and daemon stop
- removes only this plugin's desktop-widget instances from `settings.toml`
  (a timestamped backup is written first)
- stops a leftover daemon if the shell was not running
- removes the runtime state/lock files
- removes the installed plugin link and the plugin's per-plugin data directory

Pass `--yes` for a non-interactive removal. The scripts honor
`NOCTALIA_DATA_HOME`, `NOCTALIA_STATE_HOME`, `XDG_DATA_HOME`,
`XDG_STATE_HOME` and `XDG_RUNTIME_DIR`.

If you prefer to remove things by hand:

```bash
APP_DIR=noctalia-kwe   # or: APP_DIR=noctalia
noctalia-kwe msg plugins disable jahrek/steam-controller 2>/dev/null || true
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/$APP_DIR/plugins/steam-controller"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/$APP_DIR/plugins/data/jahrek/steam-controller"
rm -f "${XDG_RUNTIME_DIR:-/tmp}/noctalia-sc-battery.json" \
      "${XDG_RUNTIME_DIR:-/tmp}/noctalia-sc-battery.lock"
```

Disabling the plugin in Noctalia is enough to stop the service; the scripts
also clean the widget instances and leftover files.

## License

MIT — same as the Plasma widget. The controller illustration is drawn from
scratch, not Valve artwork.
