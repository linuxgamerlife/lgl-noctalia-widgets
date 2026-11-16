# LGL DualSense Battery — Technical Reference

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
| Version | `1.1.0` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

## Requirements

- Noctalia Shell with plugin API 17 or newer, including KineticWE's
  `noctalia-kwe` build of Noctalia v5
- Python 3 (standard library only — no pip packages)
- Optional: [`ds4u`](https://git.yokai.digital/deadYokai/ds4u); see
  [Why ds4u is optional](#why-ds4u-is-optional)
- Permission to access the DualSense `/dev/hidraw*` nodes (setup below)

### Why ds4u is optional

The widget does **not** require ds4u just to show battery, charging and
connection state. Without ds4u, the bundled Python monitor can read the
controller directly and can send basic rumble/lightbar commands.

Install ds4u if you want its controller-management features:

- a graphical editor for creating profiles
- profile switching from the widget dropdown
- lightbar brightness, player LEDs, trigger, gyro, remapping and haptic settings
- animated lightbar effects
- one long-running controller daemon shared by ds4u and this widget

When `ds4u --daemon` is running, the widget talks to its Unix socket instead of
competing with it for controller reports. Without ds4u, the profile dropdown
normally contains only `Default`, and the cog cannot open the ds4u profile
editor. In both modes, the user running ds4u/Noctalia needs permission to access
the controller's hidraw device.

### Give your user controller access (udev)

#### What this is for

Linux exposes the controller's low-level USB/Bluetooth reports as a file named
`/dev/hidrawN` (for example `/dev/hidraw0`). That file is protected so ordinary
applications cannot automatically read every USB device. The udev rule below
identifies only Sony DualSense and DualSense Edge controllers and grants the
active desktop user read/write access.

You normally do this **once**. It is needed whether the controller is read
directly by the widget or by ds4u.

#### 1. Install the rule

Copy and paste this complete block into a terminal:

```bash
sudo tee /etc/udev/rules.d/70-dualsense.rules >/dev/null <<'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0664", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0664", GROUP="input", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

The two product IDs are:

- `054c:0ce6` — DualSense
- `054c:0df2` — DualSense Edge

`TAG+="uaccess"` asks systemd/udev to grant access to the user currently logged
in at the local graphical seat. `GROUP="input"` provides a fallback for systems
that do not apply those per-user ACLs.

#### 2. Reconnect the controller

Rules are applied when a device appears. After installing the rule:

- USB: unplug the cable, then reconnect it.
- Bluetooth: disconnect the controller, then reconnect it.

Merely reloading the rule does not always change permissions on an already-open
device.

#### 3. Verify access

Keep the controller connected and run this complete block. It searches sysfs
for Sony's vendor/product IDs, prints the matching `/dev/hidrawN` path, then
checks whether your current user can read and write it:

```bash
controller_node=""
for sysfs in /sys/class/hidraw/hidraw*; do
  if grep -qiE '^HID_ID=.*054C.*(0CE6|0DF2)' "$sysfs/device/uevent" 2>/dev/null; then
    controller_node="/dev/${sysfs##*/}"
    echo "DualSense node: $controller_node"
    ls -l "$controller_node"
  fi
done

if [ -z "$controller_node" ]; then
  echo "No DualSense hidraw node found"
elif [ -r "$controller_node" ] && [ -w "$controller_node" ]; then
  echo "hidraw access OK"
else
  echo "Controller found, but your user does not have read/write access"
fi
```

Success looks like:

```text
DualSense node: /dev/hidraw0
hidraw access OK
```

The number may be different and can change after reconnecting. That is normal.

If the controller is found but access fails, first log out of the desktop and
back in so the seat ACL is recreated. If it still fails, use the `input` group
fallback, then log out and back in again:

```bash
sudo usermod -aG input "$USER"
```

You can inspect the exact ACL with `getfacl /dev/hidrawN`, replacing `N` with
the number printed by the verification block. The `getfacl` command is optional
and may require your distribution's `acl` package.

If no DualSense node is found, first check whether Linux sees the controller:

```bash
# USB (either command may print the controller)
lsusb -d 054c:0ce6
lsusb -d 054c:0df2

# Bluetooth
bluetoothctl devices Connected
```

Do not change the rule to `MODE="0666"`. That would let every local user and
process control the device. Fix the active-seat ACL or group membership instead.

#### Remove the udev rule

To undo the rule:

```bash
sudo rm /etc/udev/rules.d/70-dualsense.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

Reconnect the controller afterward so the old permissions are discarded. If
you also added yourself to `input` solely for this plugin, you may remove that
membership, then log out and back in:

```bash
sudo gpasswd -d "$USER" input
```

## Install

From the app directory (`apps/lgl-dualsense`):

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

### Configure the widget

You do **not** need to edit a TOML file.

1. Open **Noctalia Settings → Desktop → Toggle Editor**.
2. Add **DualSense Battery** if it is not already on the desktop.
3. Select the widget in the editor and use its settings panel to change colours,
   opacity, profile controls and visibility options.
4. Leave the editor when positioning is complete.
5. Open **Noctalia Settings → Plugins → DualSense Battery** for shared settings
   such as the low-battery threshold and notification toggle.

Noctalia saves these choices automatically. Its generated settings file is at
`~/.local/state/noctalia-kwe/settings.toml` for KWE or
`~/.local/state/noctalia/settings.toml` upstream. Those paths are useful for
backups and troubleshooting; manual editing is not required and is discouraged
while Noctalia is running because the shell may overwrite the file.

## Settings

| Setting | Scope | Default | Description |
| --- | --- | --- | --- |
| `low_threshold` | plugin | `20` | Percentage at or below which the card shows the low state and the service may notify. |
| `notify_low` | plugin | `true` | Send one desktop notification when the battery first drops to the threshold. |
| `illustration_color` | desktop widget | `#e8ebef` | Controller line-art colour. |
| `controller_body_color` | desktop widget | `#2c3035` | Controller body fill colour. |
| `controller_body_opacity` | desktop widget | `1.0` | Controller body fill opacity (`0` = transparent line art, `1` = solid). |
| `controller_stroke_width` | desktop widget | `2.8` | Controller outline and touchpad/button edge thickness (`0.5`–`8`). |
| `lightbar_color_mode` | desktop widget | `ds4u` | `ds4u` follows the active profile's lightbar colour; `custom` uses `lightbar_color`. |
| `lightbar_color` | desktop widget | `#0080ff` | Lightbar accent colour when `lightbar_color_mode = "custom"`. Accepts a hex value or any Noctalia palette role. |
| `lightbar_width` | desktop widget | `3.0` | Lightbar strip thickness beside the touchpad (`0.5`–`8`). |
| `profile_settings_opacity` | desktop widget | `0.65` | Opacity of the ds4u settings button background (`0`–`1`); the cog remains fully opaque. |
| `battery_color_mode` | desktop widget | `lightbar` | `lightbar` uses the active `ds4u` profile lightbar colour; `connection` uses link colours; `custom` uses `battery_fill_color`. |
| `battery_fill_color` | desktop widget | `#0080ff` | Custom battery fill colour, used when `battery_color_mode = "custom"`. |
| `battery_fill_opacity` | desktop widget | `1.0` | Battery fill opacity (`0` = transparent, `1` = solid). |
| `battery_low_color` | desktop widget | `#ed4c4c` | Low-battery fill, percentage and marker colour. Always wins when low. |
| `text_color` | desktop widget | `on_surface` | Percentage, status text, marker and active player LEDs. |
| `muted_text_color` | desktop widget | `on_surface_variant` | Percentage sign, profile label, model badge and inactive player LEDs. |
| `show_battery_bar` | desktop widget | `true` | Show the vertical battery bar. When off, the bar is hidden and the controller content is centred. |
| `show_percentage` | desktop widget | `true` | Show the battery percentage below the controller. |
| `show_status` | desktop widget | `true` | Show the connection, charging and low-battery status line below the controller. |
| `show_live_inputs` | desktop widget | `true` | Overlay live button presses, stick movement, trigger pulls and touchpad points on the controller. |
| `input_highlight_color` | desktop widget | `primary` | Highlight colour for the live input overlay. Accepts a hex value or any Noctalia palette role. |
| `show_profile` | desktop widget | `true` | Show the active `ds4u` profile dropdown for direct profile selection. |
| `show_player_leds` | desktop widget | `true` | Show the 5-segment DualSense player indicator LEDs. |
| `show_model_badge` | desktop widget | `true` | Show a `DualSense Edge` label when a DualSense Edge controller is connected. |

With `show_battery_bar = false`, the battery graphic is omitted and the
controller, percentage and status column is centred in the card. The percentage
and status line can be hidden independently with `show_percentage` and
`show_status`.

## How it works

1. **`ds4u` Daemon IPC (`$XDG_RUNTIME_DIR/ds4u.socket`)**: When `ds4u --daemon`
   is running, `code/ds_battery_daemon.py` queries it over its Unix socket
   (`GetControllerInfo`, `GetBattery`, `GetInputState`, `GetActiveProfile`,
   `ListProfiles`) so both tools coexist without competing for `/dev/hidraw*`
   reads.
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

The touchpad accent strips follow that profile colour by default. Set
`lightbar_color_mode = "custom"` to use `lightbar_color` instead: the colour
picker lists every Noctalia palette role and also accepts a custom hex value.
`lightbar_width` controls the strip thickness independently of the controller
outline. The battery fill's `lightbar` colour mode and the profile swatch keep
mirroring the controller's actual `ds4u` colour; the override only changes the
illustration.

### Live input visualisation

The controller drawing can show live input: face buttons, D-pad, shoulders,
PS/touchpad/mute, both sticks, L2/R2 trigger bars and active touchpad points.
When `ds4u --daemon` is running the widget polls `GetInputState` over its Unix
socket; otherwise it reads the same fields directly from the HID input reports.
The overlay refreshes at about 30 Hz and only redraws when the input changes.

`show_live_inputs = false` keeps the static illustration and disables the
overlay. `input_highlight_color` sets the highlight colour and accepts any
Noctalia palette role or a hex value. The overlay only renders while the
controller is connected and its state is fresh.

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

## Credits and License

Thanks to Jahrek for the Steam Controller Plasma widget that inspired the card
approach, and to deadYokai for the DualSense work in `ds4u`. LGL adapted and
integrated these ideas for Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE).
