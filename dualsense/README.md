# DualSense Battery

A Noctalia desktop widget for Sony DualSense and DualSense Edge controllers that
shows battery level, charging state, connection type, player LEDs, live input
and optional ds4u profile controls.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/dualsense` |
| Desktop widget | `card` |
| Service | `battery` |

## Requirements

- Noctalia Shell with plugin API 17 or newer.
- `python3` (standard library only; no pip packages).
- Read/write access to the controller's `/dev/hidraw*` node. The udev rule below
  grants access to the active desktop user.
- Optional: [ds4u](https://git.yokai.digital/deadYokai/ds4u) for profile editing,
  profile switching, lightbar brightness, player LEDs and advanced controller
  settings.

The widget works without ds4u: the bundled daemon reads the controller directly
and can send basic rumble and lightbar commands. Install ds4u if you want its
profile management and graphical editor.

### Controller access

Install this udev rule once, then reconnect the controller:

```bash
sudo tee /etc/udev/rules.d/70-dualsense.rules >/dev/null <<'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0664", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0664", GROUP="input", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

`054c:0ce6` is the DualSense and `054c:0df2` is the DualSense Edge.

## Usage

Enable **DualSense Battery** in **Settings → Plugins**, then add the **DualSense
Battery** card from the desktop-widget editor. The service starts automatically
when the plugin is enabled; no autostart entry or systemd unit is needed.

The card shows the controller illustration, battery percentage, connection and
charging state, player LEDs and, when ds4u is running, the active profile. Click
the controller to rumble it. Use the profile dropdown to switch profiles and the
cog to open the ds4u editor.

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
| `controller_body_opacity` | `1.0` | Body fill opacity (0–1). |
| `controller_stroke_width` | `2.8` | Outline and touchpad/button edge thickness (0.5–8). |
| `lightbar_color_mode` | `ds4u` | `ds4u` follows the active profile's lightbar colour; `custom` uses `lightbar_color`. |
| `lightbar_color` | `#0080ff` | Lightbar accent when `lightbar_color_mode` is `custom`. |
| `lightbar_width` | `3.0` | Lightbar strip thickness beside the touchpad (0.5–8). |
| `profile_settings_opacity` | `0.65` | Opacity of the ds4u settings button background (0–1). |
| `battery_color_mode` | `lightbar` | `lightbar` follows the ds4u profile, `connection` uses link colours, `custom` uses `battery_fill_color`. |
| `battery_fill_color` | `#0080ff` | Custom battery fill colour. |
| `battery_fill_opacity` | `1.0` | Battery fill opacity (0–1). |
| `battery_low_color` | `#ed4c4c` | Low-battery fill, percentage and marker colour; always wins when low. |
| `text_color` | `on_surface` | Percentage, status, marker and active player LEDs. |
| `muted_text_color` | `on_surface_variant` | Percentage sign, profile label, model badge and inactive LEDs. |
| `show_battery_bar` | on | Show the vertical battery bar. |
| `show_percentage` | on | Show the battery percentage. |
| `show_status` | on | Show connection, charging and low-battery status. |
| `show_live_inputs` | on | Overlay live button presses, sticks, triggers and touchpad points. |
| `input_highlight_color` | `primary` | Highlight colour for the live input overlay. |
| `show_profile` | on | Show the active ds4u profile dropdown. |
| `show_player_leds` | on | Show the five-segment player indicator. |
| `show_model_badge` | on | Show a `DualSense Edge` label when an Edge is connected. |

Every colour accepts a palette role token or a hex value. With
`show_battery_bar = false`, the battery graphic is hidden and the controller,
percentage and status are centred.

## IPC

The service entry is `linuxgamerlife/dualsense:battery`; services use the
`all` target.

```sh
noctalia msg plugin linuxgamerlife/dualsense:battery all buzz
noctalia msg plugin linuxgamerlife/dualsense:battery all cycle-profile
noctalia msg plugin linuxgamerlife/dualsense:battery all switch-profile Default
noctalia msg plugin linuxgamerlife/dualsense:battery all restart
```

`switch-profile` accepts any profile name from ds4u. A reply of
`ok: dispatched 1` confirms delivery to the service.

## Notes

- When ds4u's daemon is running, the service talks to its Unix socket at
  `$XDG_RUNTIME_DIR/ds4u.socket`; otherwise it reads the DualSense HID reports
  directly, with `hid-playstation` and BlueZ battery fallbacks.
- The plugin reads controller reports and sends rumble/lightbar/profile
  commands. It makes no network requests.
- The card uses the controller illustration and schematic assets from ds4u; see
  [NOTICE](NOTICE) and [LICENSE](LICENSE).
- A locked or unavailable controller node shows a waiting state instead of a
  fake percentage. Reinstall the udev rule and reconnect the controller if
  access is denied.
- Desktop widgets cannot show tooltips; the battery, connection and profile
  state are visible on the card.

## Credits and License

DualSense protocol and profile work is based on deadYokai's
[ds4u](https://git.yokai.digital/deadYokai/ds4u). The card approach was inspired
by Jahrek's Steam Controller Plasma widget. LGL adapted and integrated it for
Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
