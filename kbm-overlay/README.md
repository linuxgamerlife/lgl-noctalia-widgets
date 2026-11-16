# LGL KBM Overlay

A movable Noctalia desktop widget that draws a gaming keyboard and mouse input
overlay in a black and cyan style, with live key, button, wheel and movement
feedback.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/kbm-overlay` |
| Bar widget | `bar` |
| Desktop widget | `card` |
| Panel | `devices` |
| Service | `reader` |

## Requirements

- Noctalia Shell with plugin API 30 or newer (Noctalia KWE 5.3.0 or newer).
- `python3`.
- Read access to the selected keyboard and mouse input devices. Use the bundled
  udev helper to grant access to the active desktop user.
- Optional: `kdotool` for screen-relative mouse-arrow direction on KWin. Without
  it the arrow follows raw movement direction.

## Usage

Enable **LGL KBM Overlay** in **Settings → Plugins**, then add the **LGL KBM
Overlay** desktop widget. A bar capsule is also available; clicking it opens the
device picker.

Open the picker directly with:

```sh
noctalia msg panel-toggle linuxgamerlife/kbm-overlay:devices
```

Select one keyboard and one mouse. Then install the narrow udev rule from the
device picker's **Install permissions** button, or run the bundled helper from a
checkout:

```sh
bash kbm-overlay/code/setup-input-permissions.sh
```

The script prints the rule before installing it. Use `--print` to review it
without root. Reconnect the devices, or log out and back in, if access is still
denied.

Toggle the overlay without removing it from the desktop layout:

```sh
noctalia msg plugin linuxgamerlife/kbm-overlay:reader all toggle
```

The widget is a normal desktop widget, not a layer-shell overlay. It can be
moved and resized in desktop edit mode and does not sit above every window.

## Settings

The desktop card starts with the host background controls and four section
toggles:

- **Show layout section** — content width, keyboard layout, custom keys and
  keyboard/label visibility.
- **Show mouse section** — mouse visibility, labels, wheel and side buttons.
- **Show appearance section** — overlay background, key/mouse colours, glow,
  ripple, border and motion-arrow appearance.
- **Show scaling section** — key size/gap/radius, mouse size and label scale.

Key settings:

| Setting | Default | Description |
| --- | --- | --- |
| `content_width` | `620` px | Card content width (420–1000). |
| `keyboard_layout` | `fps` | `fps`, `wasd` or `custom`. |
| `custom_keys` | FPS key list | Key names used when `keyboard_layout` is `custom`. |
| `show_keyboard` | on | Draw the keyboard. |
| `show_key_labels` | on | Draw key legends. |
| `show_mouse` | on | Draw the mouse. |
| `show_mouse_labels` | off | Draw mouse button labels. |
| `mouse_show_wheel` | on | Draw the wheel/middle button. |
| `mouse_show_extra` | on | Draw the two side buttons. |
| `overlay_background` | on | Draw the overlay's own rounded background. |
| `overlay_background_color` | `#05070a` | Overlay background colour. |
| `overlay_background_opacity` | `0.94` | Overlay background opacity (0–1). |
| `overlay_radius` | `14` px | Overlay corner radius (0–40). |
| `overlay_border_color` | `#22e6ff` | Overlay border colour. |
| `overlay_border_width` | `2.0` px | Overlay border width (0–6). |
| `key_idle_color` | `#05070a` | Unpressed key fill. |
| `key_idle_opacity` | `1.0` | Unpressed key fill opacity (0–1). |
| `key_border_color` | `#f4f8fb` | Key outline colour. |
| `key_border_width` | `2.0` px | Key outline width (0.5–5). |
| `key_text_color` | `#f4f8fb` | Key legend colour. |
| `accent_color` | `#22e6ff` | Pressed-key fill and highlight. |
| `accent_text_color` | `#031014` | Pressed-key legend colour. |
| `glow_color` | `#22e6ff` | Glow and ripple colour. |
| `glow_opacity` | `0.35` | Glow/ripple opacity (0–1). |
| `effects_glow` | on | Draw the pressed-key glow. |
| `effects_ripple` | on | Draw the press ripple. |
| `mouse_body_color` | `#05070a` | Mouse body fill. |
| `mouse_body_opacity` | `1.0` | Mouse body opacity (0–1). |
| `mouse_border_color` | `#f4f8fb` | Mouse outline colour. |
| `mouse_border_width` | `2.5` px | Mouse outline width (0.5–6). |
| `motion_direction` | `auto` | `auto` uses screen-relative direction when `kdotool` is available, otherwise movement; `screen` and `movement` force a mode. |
| `key_size` | `46` px | Key width/height (26–64). |
| `key_gap` | `6` px | Gap between keys (2–16). |
| `key_radius` | `6` px | Key corner radius (0–20). |
| `mouse_size` | `300` px | Mouse width (160–420). |
| `label_scale` | `1.0` | Key/mouse label size multiplier (0.6–1.8). |

The bar widget has its own `show_label`, `label` and `glyph` settings for the
compact capsule.

Every colour accepts a palette role token or a hex value.

## Notes

- The service reads button and movement events from the selected
  `/dev/input/event*` devices. It does not record typed text, clipboard
  contents, window titles or application data.
- The plugin makes no network requests and has no analytics or telemetry.
- It writes only the selected device paths and a small `runtime.json` handoff
  file in the plugin data directory.
- The udev helper matches only the selected vendor/product IDs and adds
  `TAG+="uaccess"`; it does not run a root daemon.
- Keyboard and mouse input is read locally for drawing only. It is not injected,
  grabbed or remapped.
- See [PRIVACY.md](PRIVACY.md) for the full privacy and permission notes.

## Credits and License

Inspired by [univrsal/input-overlay](https://github.com/univrsal/input-overlay).
This is an independent Noctalia implementation with procedurally drawn artwork.

MIT — see [LICENSE](LICENSE).
