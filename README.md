# DualSense Battery — Noctalia plugin

A Noctalia v5 desktop widget and headless service for the PlayStation 5
DualSense (`054c:0ce6`) and DualSense Edge (`054c:0df2`) controllers, combining
the desktop card architecture of
[`lgl-steam-controller-noctalia-widget`](https://github.com/jahrekza/steam-controller-plasma-widget)
with the DualSense HID protocol, artwork, lightbar/player-LED state and profile
management of [`ds4u` (DualSense 4 You)](https://git.yokai.digital/deadYokai/ds4u).

| Field | Value |
| --- | --- |
| Plugin ID | `deadYokai/dualsense` |
| Version | `1.0.5` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

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
    active `ds4u` profile's lightbar RGB colour (`~/.config/ds4u/profiles/`).
  - Displays the 5-segment DualSense player indicator LED bar matching `ds4u`'s
    8 player LED patterns.
  - Shows an explicit profile dropdown on the card. Select any saved `ds4u`
    profile to apply it via daemon IPC or direct HID output reports. The adjacent
    settings button opens `ds4u` to create and edit controller profiles.
  - **Click the controller illustration** (or send the `buzz` IPC event) to
    rumble the DualSense controller.

## Configuration

The desktop widget exposes:

- controller line colour, body colour, body opacity and outline thickness
- battery fill mode: `ds4u` lightbar colour, connection colours (blue on
  Bluetooth, green on USB-C), or a custom colour
- battery fill opacity (`0–1`) and a separate low-battery colour
- primary and secondary text colours
- toggles for the `ds4u` profile pill, 5-segment player LED bar, and DualSense
  Edge model badge
- low-battery threshold and notification toggle

Colour settings accept hex values or palette role tokens. Role tokens follow the
live Noctalia theme; the controller art regenerates when the resolved palette
colour or `ds4u` lightbar colour changes. See the
[full settings table](dualsense/README.md#settings).

## Layout

| Path | What it is |
| --- | --- |
| `dualsense/` | The plugin: `plugin.toml`, `card.luau`, `battery.luau`, HID/ds4u daemon, assets, translations |
| `install-kwe.sh` | Install for KineticWE's `noctalia-kwe` fork |
| `install.sh` | Install for upstream Noctalia |
| `uninstall-kwe.sh` | Remove from `noctalia-kwe` |
| `uninstall.sh` | Remove from upstream Noctalia |
| `remove-plugin-widgets.py` | Safely removes this plugin's desktop-widget instances from `settings.toml` |
| `catalog.toml` | Noctalia source catalog (the repo can be added as a plugin source) |
| `tests/` | LuaJIT tests with a mocked Noctalia API |

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then enable **DualSense Battery** in **Settings → Plugins** if the installer
did not, and add it from **Settings → Desktop → Toggle Editor**.

For KWE, you can also enable the plugin from a terminal:

```bash
noctalia-kwe msg plugins enable deadYokai/dualsense
noctalia-kwe msg plugins list | grep deadYokai/dualsense
```

The service must say `enabled` before widget actions or plugin IPC can work.
Grant HID access before testing direct controller reads:

```bash
sudo tee /etc/udev/rules.d/70-dualsense.rules >/dev/null <<'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0664", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0664", GROUP="input", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

Unplug/replug USB controllers or reconnect Bluetooth after loading the rule.
See the [complete setup and verification guide](dualsense/README.md#hidraw-permissions)
for group membership, declarative configuration, `ds4u`, and IPC diagnostics.

`install-kwe.sh` links the plugin into
`~/.local/share/noctalia-kwe/plugins`; `install.sh` uses
`~/.local/share/noctalia/plugins`. Both honor `NOCTALIA_DATA_HOME` and
`XDG_DATA_HOME`.

Full requirements, settings, protocol notes, IPC and troubleshooting are in
[`dualsense/README.md`](dualsense/README.md).

## Remove

```bash
./uninstall-kwe.sh   # KWE
./uninstall.sh       # upstream
```

The uninstall scripts disable the plugin, stop its service/daemon, remove its
desktop-widget instances (with a timestamped settings backup), and clean its
runtime and plugin data. Use `--yes` for non-interactive removal.

## Tests

```bash
./tests/run.sh
```

Requires LuaJIT. The tests mock `noctalia.*` and `desktopWidget.*`, so no live
Noctalia session is needed.

## Requirements

- Noctalia Shell with plugin API 17 or newer (upstream or `noctalia-kwe`)
- Python 3 (standard library only)
- Permission to read the DualSense `/dev/hidraw*` nodes (or `ds4u --daemon` /
  kernel `hid-playstation` power_supply)

## License

MIT — see [LICENSE](LICENSE).
