<div align="center">

# LGL DualSense Battery

**DualSense battery, lightbar, player LEDs, and profiles in a Noctalia desktop widget.**

[![Version](https://img.shields.io/badge/version-1.1.0-purple)](dualsense/plugin.toml)
[![Plugin API](https://img.shields.io/badge/Noctalia_API-17-blue)](dualsense/plugin.toml)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)

</div>

---

## Overview

LGL DualSense Battery is a Noctalia v5 desktop widget and headless service for
the PlayStation 5 DualSense (`054c:0ce6`) and DualSense Edge (`054c:0df2`). It
combines the desktop-card approach inspired by Jahrek's
[Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget)
with DualSense HID handling, artwork, lightbar and player-LED state, and profile
management informed by [ds4u](https://git.yokai.digital/deadYokai/ds4u).

| Field | Value |
| --- | --- |
| Plugin ID | `linuxgamerlife/dualsense` |
| Version | `1.1.0` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |
| License | MIT |

Tested live on KineticWE's `noctalia-kwe` v5.3.0. Upstream Noctalia uses the
same v5 plugin API and is supported by the install scripts.

## Features

- **Battery level & charging state**: reads DualSense USB (`0x01`) and
  Bluetooth (`0x31`) HID input reports using `ds4u`'s battery formula, with
  automatic coexistence via `$XDG_RUNTIME_DIR/ds4u.socket` when the `ds4u`
  daemon is active, plus Linux `hid-playstation` (`power_supply`) and BlueZ
  `Battery1` fallbacks.
- **DualSense & DualSense Edge detection**: identifies both `054c:0ce6`
  (DualSense) and `054c:0df2` (DualSense Edge), displaying an optional
  `DualSense Edge` badge.
- **`ds4u` integration**:
  - Syncs the controller's touchpad lightbar accents and battery fill with the
    active `ds4u` profile's lightbar RGB colour (`~/.config/ds4u/profiles/`) by
    default. The accents can instead use a custom colour or any Noctalia palette
    role, with an adjustable thickness.
  - Displays the 5-segment DualSense player indicator LED bar matching `ds4u`'s
    8 player LED patterns.
  - Shows an explicit profile dropdown on the card. Select any saved `ds4u`
    profile to apply it via daemon IPC or direct HID output reports. The adjacent
    settings button opens `ds4u` to create and edit controller profiles.
  - **Click the controller illustration** (or send the `buzz` IPC event) to
    rumble the DualSense controller.
- **Live input visualisation**: overlays button presses, both sticks, trigger
  pulls and touchpad points on the controller art at about 30 Hz. It uses the
  ds4u IPC input stream when its daemon is running and reads the same fields
  from HID reports otherwise.

`ds4u` is optional: battery, charging and connection monitoring work through
the bundled Python HID reader without it. Install ds4u for its graphical profile
editor, remapping/trigger/gyro/haptic controls, animated effects and shared
controller daemon. See [Why ds4u is optional](dualsense/README.md#why-ds4u-is-optional).

## Configuration

The desktop widget exposes:

- controller line colour, body colour, body opacity and outline thickness
- independent background opacity for the ds4u profile-settings button; the cog stays opaque
- battery fill mode: `ds4u` lightbar colour, connection colours (blue on
  Bluetooth, green on USB-C), or a custom colour
- battery fill opacity (`0–1`) and a separate low-battery colour
- optional battery bar; hiding it centres the controller card
- independent toggles for the percentage readout and status line
- live input visualisation toggle and highlight colour (palette role or custom
  hex)
- lightbar accent colour (ds4u profile, custom colour, or Noctalia palette role)
  and thickness
- primary and secondary text colours
- toggles for the `ds4u` profile pill, 5-segment player LED bar, and DualSense
  Edge model badge
- low-battery threshold and notification toggle

Colour settings accept hex values or palette role tokens. Role tokens follow the
live Noctalia theme; the controller art regenerates when the resolved palette
colour or `ds4u` lightbar colour changes. See the
[full settings table](dualsense/README.md#settings).

## Project layout

| Path | What it is |
| --- | --- |
| `dualsense/` | Plugin payload: manifest, entries, translations, thumbnail |
| `dev/dualsense/` | These developer notes and tests |
| `tools/` | Catalog, validation and migration helpers |
| `catalog.toml` | Root source catalog |

## Install

Add this repository as a Noctalia source, then enable the plugin:

```sh
noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia msg plugins enable linuxgamerlife/dualsense
```

For KineticWE's `noctalia-kwe` fork, use the same commands with
`noctalia-kwe`.

If upgrading from the old `apps/` layout, run `./tools/migrate.py` first. See
the repository `MIGRATION.md` for the upgrade notes.

## Uninstall

Disable or remove the plugin in **Settings → Plugins**, or disable it from
the command line:

```sh
noctalia msg plugins disable linuxgamerlife/dualsense
```

Plugin data is kept unless you remove it manually. See the repository
`MIGRATION.md` for data locations.

## Requirements

- Noctalia Shell with plugin API 17 or newer (upstream or `noctalia-kwe`)
- Python 3 (standard library only)
- Permission for the widget or `ds4u --daemon` to access the DualSense
  `/dev/hidraw*` nodes. See the beginner-friendly
  [udev setup and removal guide](dualsense/README.md#give-your-user-controller-access-udev).

## Credits and License

Thanks to Jahrek for the original Steam Controller Plasma widget that inspired
the card approach, and to deadYokai for the DualSense protocol and profile work
in [ds4u](https://git.yokai.digital/deadYokai/ds4u). LGL adapted and integrated
these ideas for Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE).
