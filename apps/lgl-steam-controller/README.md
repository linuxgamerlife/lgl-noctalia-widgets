# Steam Controller Battery — Noctalia plugin

A Noctalia v5 desktop widget and headless service that shows the battery level,
charging state, connection type and wireless link quality of the Steam
Controller 2 ("Triton").

This is the standalone Noctalia repository, split out of the
[Steam Controller Plasma widget](https://github.com/jahrekza/steam-controller-plasma-widget).
The Plasma widget lives in that repository; this one contains the Noctalia port.

| Field | Value |
| --- | --- |
| Plugin ID | `jahrek/steam-controller` |
| Version | `2.3.0` |
| Entries | Service `battery`, desktop widget `card` |
| Plugin API | 17 |

Tested live on KineticWE's `noctalia-kwe` v5.3.0. Upstream Noctalia uses the
same v5 plugin API and is supported by the install scripts, but has not been
tested on the author's machine.

## Configuration

The desktop widget exposes:

- controller line colour, body colour and outline thickness
- battery fill mode: connection LED colours or a custom colour
- battery fill opacity (`0–1`) and a separate low-battery colour
- primary and secondary text colours
- signal display mode, low-battery threshold and notification toggle

Colour settings accept hex values or palette role tokens. Role tokens follow the
live Noctalia theme; the controller art regenerates when the resolved palette
colour changes. See the
[full settings table](steam-controller/README.md#settings).

## Layout

| Path | What it is |
| --- | --- |
| `steam-controller/` | The plugin: `plugin.toml`, `card.luau`, `battery.luau`, HID daemon, assets, translations |
| `install-kwe.sh` | Install for KineticWE's `noctalia-kwe` fork |
| `install.sh` | Install for upstream Noctalia |
| `uninstall-kwe.sh` | Remove from `noctalia-kwe` |
| `uninstall.sh` | Remove from upstream Noctalia |
| `remove-plugin-widgets.py` | Safely removes this plugin's desktop-widget instances from `settings.toml` |
| `catalog.toml` | Noctalia source catalog (the repo can be added as a plugin source) |
| `tests/` | LuaJIT tests with a mocked Noctalia API |

## Install

From the app directory (`apps/lgl-steam-controller`):

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then enable **Steam Controller Battery** in **Settings → Plugins** if the
installer did not, and add it from **Settings → Desktop → Toggle Editor**.

`install-kwe.sh` links the plugin into
`~/.local/share/noctalia-kwe/plugins`; `install.sh` uses
`~/.local/share/noctalia/plugins`. Both honor `NOCTALIA_DATA_HOME` and
`XDG_DATA_HOME`.

Full requirements, settings, protocol notes, IPC and troubleshooting are in
[`steam-controller/README.md`](steam-controller/README.md).

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
- Permission to read the controller's `/dev/hidraw*` nodes

## License

MIT — see [LICENSE](LICENSE). The controller illustration is drawn from scratch,
not Valve artwork.
