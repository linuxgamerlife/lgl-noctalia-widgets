# DualSense Battery — Noctalia plugin

A Noctalia desktop widget for Sony DualSense (`054c:0ce6`) and DualSense Edge
(`054c:0df2`) controllers that shows the battery level, charging state,
connection type, player indicator LEDs and active `ds4u` profile.

By default the card mirrors the controller's **`ds4u` lightbar colour** on both
the touchpad lightbar accents and the battery fill, or can switch to
**connection colours** (PlayStation blue over Bluetooth, green on USB-C), or a
custom colour with adjustable opacity. Charging pulses; low battery turns red.

| Field | Value |
| --- | --- |
| ID | `deadYokai/dualsense` |
| Version | `1.0.0` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

## Requirements

- Noctalia Shell with plugin API 17 or newer, including KineticWE's
  `noctalia-kwe` build of Noctalia v5
- Python 3 (standard library only — no pip packages)
- Optional: [`ds4u`](https://git.yokai.digital/deadYokai/ds4u) for profile
  management and background daemon effects
- Permission to access the DualSense `/dev/hidraw*` nodes:

  ```udev
  SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0664", GROUP="input", TAG+="uaccess"
  SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0664", GROUP="input", TAG+="uaccess"
  ```

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

### Declarative config

```toml
[desktop_widgets]
enabled = true

[desktop_widgets.widget.dualsense]
type       = "deadYokai/dualsense:card"
output     = "DP-1"
cx         = 1400.0
cy         = 200.0
box_width  = 0.0
box_height = 0.0

[desktop_widgets.widget.dualsense.settings]
illustration_color      = "#e8ebef"
controller_body_color   = "#2c3035"
controller_stroke_width = 2.8
battery_color_mode      = "lightbar"     # lightbar | connection | custom
battery_fill_color      = "#0080ff"      # used when mode = custom
battery_fill_opacity    = 1.0            # 0 = transparent, 1 = solid
battery_low_color       = "#ed4c4c"
text_color              = "on_surface"
muted_text_color        = "on_surface_variant"
show_profile            = true
show_player_leds        = true
show_model_badge        = true

[plugin_settings."deadYokai/dualsense"]
low_threshold = 20
notify_low    = true
```

## Settings

| Setting | Scope | Default | Description |
| --- | --- | --- | --- |
| `low_threshold` | plugin | `20` | Percentage at or below which the card shows the low state and the service may notify. |
| `notify_low` | plugin | `true` | Send one desktop notification when the battery first drops to the threshold. |
| `illustration_color` | desktop widget | `#e8ebef` | Controller line-art colour. |
| `controller_body_color` | desktop widget | `#2c3035` | Controller body fill colour. |
| `controller_stroke_width` | desktop widget | `2.8` | Controller outline and touchpad/button edge thickness (`0.5`–`8`). |
| `battery_color_mode` | desktop widget | `lightbar` | `lightbar` uses the active `ds4u` profile lightbar colour; `connection` uses link colours; `custom` uses `battery_fill_color`. |
| `battery_fill_color` | desktop widget | `#0080ff` | Custom battery fill colour, used when `battery_color_mode = "custom"`. |
| `battery_fill_opacity` | desktop widget | `1.0` | Battery fill opacity (`0` = transparent, `1` = solid). |
| `battery_low_color` | desktop widget | `#ed4c4c` | Low-battery fill, percentage and marker colour. Always wins when low. |
| `text_color` | desktop widget | `on_surface` | Percentage, status text, marker and active player LEDs. |
| `muted_text_color` | desktop widget | `on_surface_variant` | Percentage sign, profile label, model badge and inactive player LEDs. |
| `show_profile` | desktop widget | `true` | Show the active `ds4u` profile pill (click to cycle saved profiles). |
| `show_player_leds` | desktop widget | `true` | Show the 5-segment DualSense player indicator LEDs. |
| `show_model_badge` | desktop widget | `true` | Show a `DualSense Edge` label when a DualSense Edge controller is connected. |

## How it works

1. **`ds4u` Daemon IPC (`$XDG_RUNTIME_DIR/ds4u.socket`)**: When `ds4u --daemon`
   is running, `code/ds_battery_daemon.py` queries it over its Unix socket
   (`GetControllerInfo`, `GetBattery`, `GetActiveProfile`, `ListProfiles`) so
   both tools coexist without competing for `/dev/hidraw*` reads.
2. **Direct HID & Kernel Fallbacks**: When `ds4u --daemon` is not running, the
   daemon reads DualSense USB (`0x01`, byte `53`) and Bluetooth (`0x31`, byte
   `54`) input reports directly, with fallbacks to Linux's `hid-playstation`
   `/sys/class/power_supply/ps-controller-battery*` and BlueZ `org.bluez.Battery1`.
3. **Profile & Rumble Actions**:
   - Clicking the profile row on the card cycles through saved profiles in
     `~/.config/ds4u/profiles/` (via `SwitchProfile` IPC when `ds4u --daemon`
     is running, or by updating `~/.config/ds4u/settings.json` and sending a
     DualSense HID output report with the profile's lightbar RGB and player LED
     pattern).
   - Clicking the controller illustration rumbles the controller (`SetRumble`
     IPC or direct HID output report `0x02` / `0x31` with CRC-32).

## IPC

Rumble the controller:

```bash
noctalia-kwe msg plugin deadYokai/dualsense:battery all buzz
```

Cycle to the next `ds4u` profile:

```bash
noctalia-kwe msg plugin deadYokai/dualsense:battery all cycle-profile
```

Switch to a specific `ds4u` profile:

```bash
noctalia-kwe msg plugin deadYokai/dualsense:battery all switch-profile Default
```

Restart the daemon:

```bash
noctalia-kwe msg plugin deadYokai/dualsense:battery all restart
```

## License

MIT — see [LICENSE](LICENSE).
