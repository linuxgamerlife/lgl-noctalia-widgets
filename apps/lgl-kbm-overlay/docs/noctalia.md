# Noctalia plugin notes — LGL KBM Overlay

This is the Noctalia-specific companion to the app README. It covers the API
surface, entries, state flow, permissions and development commands.

## Plugin API and entries

`plugin.toml` declares `plugin_api = 30` for Noctalia KWE 5.3.0.

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `reader` | `[[service]]` | `service.luau` | Starts/stops the evdev helper, publishes state |
| `card` | `[[desktop_widget]]` | `card.luau` | Movable keyboard/mouse drawing |
| `bar` | `[[widget]]` | `bar.luau` | Opens the device picker |
| `devices` | `[[panel]]` | `devices.luau` | Device picker and permission help |

API levels used:

| Level | Capability | Why it is needed |
| --- | --- | --- |
| 9 | UI closures | Device buttons |
| 17 | Services start on enable | Reader starts when the plugin is enabled |
| 30 | Panel/tooling baseline | Matches the KWE 5.3.0 fork |

There is **no `[[layer]]` entry and no overlay panel**. The visual is a normal
desktop widget, so the user can place and move it in desktop edit mode. A
layer-shell overlay above every window would be a separate future feature.

## Desktop widget

`card.luau` reads its settings from the desktop-widget settings table. It builds
an SVG with `lib/svg.luau`, writes it to the plugin data directory under a
small frame ring, and renders it with `ui.image`. This keeps the black/cyan
reference look with outlined, slightly skewed keycaps and a real mouse
silhouette.

All visual settings are declared under `[[desktop_widget.setting]]`. The four
main toggles are `show_layout_section`, `show_mouse_section`,
`show_appearance_section` and `show_scaling_section`; their sub-toggles and
leaves use the corresponding `visible_when` gate. Sub-toggle labels are indented
with em spaces so the flat settings editor still shows the hierarchy. There are
no plugin-level visual settings.

## Device classification

A device is a keyboard when it reports `KEY_A`, `KEY_Z`, `KEY_SPACE` or
`KEY_ENTER`. A mouse must report `REL_X`/`REL_Y` and `BTN_LEFT`/`BTN_RIGHT`, and
must **not** be classified as a keyboard. This prevents a keyboard with a few
BTN_* codes from appearing in the mouse list.

Unreadable devices are still classified from
`/sys/class/input/event*/device/capabilities/key` and `rel`, so the picker can
show them before the udev rule is installed.

## IPC

The reader service handles three display events:

```bash
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all toggle
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all hide
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all show
```

`hide` sets `kbm_hidden`; the desktop widget renders a blank zero-size tree
instead of an image. It does not remove or unplace the tile. The state is
process-lifetime, so a Noctalia restart makes the widget visible again.

To hide every desktop widget, use `noctalia-kwe msg desktop-widgets-toggle`
(or `desktop-widgets-hide` / `desktop-widgets-show`). To disable the plugin
entirely, use `noctalia-kwe msg plugins disable linuxgamerlife/kbm-overlay`.

## Files

| File | Purpose |
| --- | --- |
| `<pluginDataDir>/devices.json` | Selected keyboard/mouse (authoritative) |
| `<pluginDataDir>/runtime.json` | Effective selection passed to the helper |
| `<pluginDataDir>/reader.pid` | Stale-process cleanup |
| `<pluginDataDir>/frame-N.svg` | Small ring of rendered SVG frames |

Install locations:

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/kbm-overlay` | `~/.local/state/noctalia` | `noctalia` |
| Noctalia KWE | `~/.local/share/noctalia-kwe/plugins/kbm-overlay` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME`, `XDG_DATA_HOME`, `NOCTALIA_STATE_HOME` and
`XDG_STATE_HOME`.

## Permissions and udev

Installing the plugin does not install a udev rule. The device picker writes the
selected name, path and vendor/product IDs to `devices.json`; the user then runs
`code/setup-input-permissions.sh`.

The helper:

- requires exactly four hex digits for each vendor/product ID;
- has no device-name fallback, so a name cannot inject rule text;
- generates `SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="…",
  ATTRS{id/product}=="…", TAG+="uaccess"`;
- supports `--print` to review without root and `--remove` to delete the rule;
- installs `/etc/udev/rules.d/70-lgl-kbm-overlay.rules` as root-owned `0644`,
  reloads udev rules and triggers the input subsystem.

`TAG+="uaccess"` grants the active seat user read access to matching devices.
Any process running as that user can read them. The reader itself is read-only:
no `EVIOCGRAB`, no `uinput`, no event injection, no network, no key logging to
disk. It does observe every key on the selected keyboard because custom layouts
need arbitrary key names.

The rule is left in place on uninstall. Remove it with `--remove`.


## Reloading during development

- `.luau` changes hot-reload the owning entry.
- `plugin.toml` changes need `noctalia-kwe msg config-reload`; disable/enable
  once if a new setting is not recognised.
- Restart the reader after Python changes:

  ```bash
  noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all restart
  ```

- Inspect devices without the plugin:

  ```bash
  python3 kbm-overlay/code/kbm_daemon.py --list
  ```

- Check logs:

  ```bash
  journalctl --user -n 200 --no-pager | grep -iE 'kbm-overlay|script-runtime'
  ```

## Future

A true click-through overlay above fullscreen games is a separate future
feature. It needs plugin API 36 (`[[layer]]` with `click_through = true`) and is
not part of this desktop-widget version. The daemon reads `REL_X`/`REL_Y` for
arrow direction and length and polls `kdotool getmouselocation` on KWin for the
absolute cursor position. Arrow direction is the vector from the containing
output's centre to the cursor; length is the normalised distance from that
centre. In pointer-locked games, use the `Movement direction` option or Auto.
Trails and the idle-center reset are future work.

## Tests

`tests/run.sh` parses every `.luau` file with LuaJIT, runs the mocked entry
tests, runs the Python evdev unit tests, and validates the manifest, catalog,
translations, entries, required files and thumbnail. No live shell or input
device is required.
