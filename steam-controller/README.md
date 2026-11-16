# Steam Controller Battery

A Noctalia desktop widget for the Steam Controller 2 ("Triton") that shows
battery level, charging state, connection type and wireless link quality, with
live input visualisation on the controller illustration.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/steam-controller` |
| Desktop widget | `card` |
| Service | `battery` |

## Requirements

- Noctalia Shell with plugin API 17 or newer.
- `python3` (standard library only; no pip packages).
- Read access to the controller's `/dev/hidraw*` node. On most distributions the
  Steam udev rules already grant this. If not, add a rule such as:

```udev
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", TAG+="uaccess"
```

Then reload udev and reconnect the controller.

- Bluetooth connection state uses BlueZ through `busctl`, which is part of
  systemd on most distributions.

The controller is not supported by the kernel `hid-steam` driver yet, so it does
not appear in `/sys/class/power_supply/` or UPower. The plugin reads the vendor
HID reports directly.

## Usage

Enable **Steam Controller Battery** in **Settings → Plugins**, then add the
**Steam Controller Battery** card from the desktop-widget editor. The service
starts automatically and publishes the controller state; no autostart entry or
systemd unit is needed.

The card shows the controller, battery percentage, connection type, charging
state and, on the wireless puck, the link signal. The battery fill follows the
controller LED colours by default; choose a custom colour in the card settings
if you prefer a fixed fill.

## Settings

### Plugin settings

| Setting | Default | Description |
| --- | --- | --- |
| `low_threshold` | `20`% | Percentage at or below which the card shows the low state and the service may notify. |
| `notify_low` | on | Send one desktop notification when the battery first reaches the threshold. |

### Desktop card

| Setting | Default | Description |
| --- | --- | --- |
| `illustration_color` | `#e8ebef` | Controller line-art colour. |
| `controller_body_color` | `#2c3035` | Controller body fill colour. |
| `controller_stroke_width` | `3.4` | Controller outline and trackpad edge thickness (0.5–8). |
| `battery_color_mode` | `connection` | `connection` uses the LED colours; `custom` uses `battery_fill_color`. |
| `battery_fill_color` | `#fcfcfc` | Custom battery fill colour. |
| `battery_fill_opacity` | `1.0` | Battery fill opacity (0–1), in both colour modes. |
| `battery_low_color` | `#ed4c4c` | Low-battery fill, percentage, weak-signal meter and marker; always wins when low. |
| `text_color` | `on_surface` | Percentage, status, marker and active signal bars. |
| `muted_text_color` | `on_surface_variant` | Percentage sign, `via` line, dBm label and inactive signal bars. |
| `show_battery_bar` | on | Show the vertical battery bar. |
| `show_percentage` | on | Show the battery percentage. |
| `show_status` | on | Show connection, charging and low-battery status. |
| `show_live_inputs` | on | Overlay button presses, sticks, triggers and touchpad points. |
| `input_highlight_color` | `primary` | Highlight colour for the live input overlay. |
| `show_signal` | on | Show the wireless link meter on the puck. |
| `signal_style` | `bars` | `bars`, `bars_dbm` or `dbm`. |

Every colour accepts a palette role token or a hex value. With
`show_battery_bar = false`, the battery graphic is hidden and the controller,
percentage and status are centred.

The widget also gets Noctalia's standard host-panel settings (`background`,
`background_color`, `background_opacity`, `background_radius`,
`background_padding`).

## IPC

The service entry is `linuxgamerlife/steam-controller:battery`; services use the
`all` target.

```sh
noctalia msg plugin linuxgamerlife/steam-controller:battery all buzz
noctalia msg plugin linuxgamerlife/steam-controller:battery all restart
```

`buzz` rumbles the controller. `restart` restarts the bundled daemon after a
controller reconnect or a driver change.

## Notes

- The daemon scans `/dev/hidraw*` for Valve's `28de:1304` puck, `28de:1305`
  Steam Machine built-in receiver, `28de:1302` USB-C and `28de:1303` Bluetooth
  LE devices.
- Reports `0x43` and `0x7b` carry battery/charging and link strength. Reports
  `0x42`, `0x45` and `0x47` carry live input, which the card redraws at up to
  30 Hz only when input changes.
- Over Bluetooth the pad exposes a standard Battery Service; the daemon reads it
  through BlueZ (`busctl`).
- The daemon writes a lock file and a debug JSON snapshot under
  `$XDG_RUNTIME_DIR`. It makes no network requests.
- One controller is shown. Live input requires the Steam Controller 2
  ("Triton"); the original Steam Controller uses a different protocol.
- Desktop widgets cannot show tooltips; battery, connection and signal state are
  visible on the card.

## Credits and License

Based on the [Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget)
by Jahrek, using the same reverse-engineered HID protocol. LGL adapted and
extended it for Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE).
