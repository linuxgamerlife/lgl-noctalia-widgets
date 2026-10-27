# DualSense Battery — Noctalia plugin

A Noctalia desktop widget for Sony DualSense (`054c:0ce6`) and DualSense Edge
(`054c:0df2`) controllers that shows the battery level, charging state,
connection type, player indicator LEDs and active `ds4u` profile.

By default the card mirrors the controller's effective **`ds4u` lightbar colour** on both
the touchpad lightbar accents and the battery fill, or can switch to
**connection colours** (PlayStation blue over Bluetooth, green on USB-C), or a
custom colour with adjustable opacity. The effective colour includes the
profile's `lightbar_brightness`. Charging pulses; low battery turns red.

| Field | Value |
| --- | --- |
| ID | `deadYokai/dualsense` |
| Version | `1.0.8` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

## Requirements

- Noctalia Shell with plugin API 17 or newer, including KineticWE's
  `noctalia-kwe` build of Noctalia v5
- Python 3 (standard library only — no pip packages)
- Optional: [`ds4u`](https://git.yokai.digital/deadYokai/ds4u) for profile
  management and background daemon effects
- Permission to access the DualSense `/dev/hidraw*` nodes (setup below)

### hidraw permissions

Install one udev rule covering the standard and Edge controller:

```bash
sudo tee /etc/udev/rules.d/70-dualsense.rules >/dev/null <<'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0664", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0664", GROUP="input", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

Then unplug/replug a USB controller or disconnect/reconnect Bluetooth. On a
normal local graphical login, `TAG+="uaccess"` grants the active user access.
If your session does not apply ACLs, add your user to `input`, then log out and
back in completely:

```bash
sudo usermod -aG input "$USER"
```

Find and verify the matching node (the Sony vendor ID is `054c`):

```bash
for node in /dev/hidraw*; do
  udevadm info --query=property --name="$node" 2>/dev/null |
    grep -qiE 'HID_ID=.*054C.*(0CE6|0DF2)' && ls -l "$node"
done
getfacl /dev/hidrawN       # replace N with the node printed above
test -r /dev/hidrawN && test -w /dev/hidrawN && echo "hidraw access OK"
```

If no node is printed, confirm the controller is connected with `lsusb` (USB)
or `bluetoothctl devices Connected` (Bluetooth). Do not use `MODE="0666"` as a
workaround; fix the active-seat ACL or `input` group membership instead.

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Enable the plugin and verify the service is running. For KWE:

```bash
noctalia-kwe msg plugins enable deadYokai/dualsense
noctalia-kwe msg plugins list | grep deadYokai/dualsense
```

The result must include `enabled`. Next open **Settings → Desktop → Toggle
Editor**, add **DualSense Battery**, position it, and leave the editor. Configure
the card from its widget settings. Restart Noctalia once if the plugin was
installed while the shell was already running and the entry does not appear.

### Declarative config

The UI is the recommended configuration method. For a declarative setup, exit
Noctalia first so it does not overwrite the file, then back up and edit:

- KWE: `~/.local/state/noctalia-kwe/settings.toml`
- upstream: `~/.local/state/noctalia/settings.toml`

Use an actual connector from `wlr-randr` (for example `DP-1`) as `output`, and
use a widget key such as `dualsense` only once. Merge these tables into the
existing file; do not replace unrelated settings.

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
controller_body_opacity = 1.0            # 0 = line art only, 1 = solid body
controller_stroke_width = 2.8
profile_settings_opacity = 0.65           # cog background only; icon stays solid
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
| `controller_body_opacity` | desktop widget | `1.0` | Controller body fill opacity (`0` = transparent line art, `1` = solid). |
| `controller_stroke_width` | desktop widget | `2.8` | Controller outline and touchpad/button edge thickness (`0.5`–`8`). |
| `profile_settings_opacity` | desktop widget | `0.65` | Opacity of the ds4u settings button background (`0`–`1`); the cog remains fully opaque. |
| `battery_color_mode` | desktop widget | `lightbar` | `lightbar` uses the active `ds4u` profile lightbar colour; `connection` uses link colours; `custom` uses `battery_fill_color`. |
| `battery_fill_color` | desktop widget | `#0080ff` | Custom battery fill colour, used when `battery_color_mode = "custom"`. |
| `battery_fill_opacity` | desktop widget | `1.0` | Battery fill opacity (`0` = transparent, `1` = solid). |
| `battery_low_color` | desktop widget | `#ed4c4c` | Low-battery fill, percentage and marker colour. Always wins when low. |
| `text_color` | desktop widget | `on_surface` | Percentage, status text, marker and active player LEDs. |
| `muted_text_color` | desktop widget | `on_surface_variant` | Percentage sign, profile label, model badge and inactive player LEDs. |
| `show_profile` | desktop widget | `true` | Show the active `ds4u` profile dropdown for direct profile selection. |
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
   - Selecting a profile from the card dropdown switches directly among profiles
     in `~/.config/ds4u/profiles/` (via `SwitchProfile` IPC when `ds4u --daemon`
     is running, or by updating `~/.config/ds4u/settings.json` and sending a
     DualSense HID output report with the profile's lightbar RGB and player LED
     pattern). The settings button beside the dropdown opens `ds4u`, where you
     can create and edit profiles; saved profiles then appear in the dropdown.
   - Clicking the controller illustration rumbles the controller (`SetRumble`
     IPC or direct HID output report `0x02` / `0x31` with CRC-32).

### ds4u lightbar matching

The widget reads the active profile under `~/.config/ds4u/profiles/` and applies
the same `lightbar_brightness / 255` channel scaling as `ds4u`. For example,
full blue with brightness `128` is displayed as `#000080`, not `#0000ff`.
Restart the widget service after editing profile JSON manually, or switch
profiles normally so the state refreshes. The DualSense input report does not
report the current lightbar RGB, so continuously animated effects that are not
exposed by `ds4u` IPC cannot be sampled exactly; the card shows the profile's
effective static colour.

## IPC

The service entry is `deadYokai/dualsense:battery` and, because services are
not tied to a monitor, its target must be `all`. The CLI returning
`ok: dispatched 1` confirms delivery to `onIpc`.

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

For upstream Noctalia, replace `noctalia-kwe` with `noctalia`.

If a command does not act on the controller:

```bash
# Must show the plugin as enabled.
noctalia-kwe msg plugins list | grep deadYokai/dualsense

# Must print: ok: dispatched 1
noctalia-kwe msg plugin deadYokai/dualsense:battery all buzz

# Test the action independently of Noctalia (from this repository).
python3 dualsense/code/ds_battery_daemon.py --buzz
echo $?
```

An IPC response such as `no plugin entry matched` means the plugin is disabled,
the shell needs restarting, or the entry/target was typed incorrectly. A
successful dispatch followed by no rumble means IPC is working; check that the
controller is connected, `ds4u --daemon` has created
`$XDG_RUNTIME_DIR/ds4u.socket`, or the hidraw access test above succeeds. The
direct Python command exits `0` on success and `1` when neither path can control
the device.

## License

MIT — see [LICENSE](LICENSE).
