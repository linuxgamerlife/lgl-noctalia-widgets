# LGL KBM Overlay

A **movable Noctalia desktop widget** that shows the gaming keys and mouse
buttons you are pressing. It uses the black / white / cyan look of the
[univrsal/input-overlay](https://github.com/univrsal/input-overlay) presets:
outlined slanted keycaps, bright cyan pressed keys, a large mouse silhouette,
and a thin cyan frame.

It is a normal desktop widget, not a layer-shell panel. Place, move and resize
it in Noctalia's desktop-widget editor. It does not sit above every window.

| | |
|---|---|
| Plugin ID | `linuxgamerlife/kbm-overlay` |
| Plugin API | 30 |
| License | MIT — see [LICENSE](LICENSE) |

---

## Requirements

- Noctalia / Noctalia KWE with plugin API **30** (KWE 5.3.0).
- `python3` for the bundled evdev reader.
- `kdotool` for absolute cursor position on KWin (used for the screen-relative
  arrow direction). Without it, the arrow falls back to the movement direction.
- Read access to the selected keyboard and mouse. The app creates a narrow
  udev rule; see [Permissions and udev rules](#permissions-and-udev-rules).

Noctalia v4 / Quickshell plugin APIs are not used.

---

## Install

From the repository root:

```bash
# KineticWE's noctalia-kwe fork
./apps/lgl-kbm-overlay/install-kwe.sh

# Upstream Noctalia
./apps/lgl-kbm-overlay/install.sh
```

Both installers symlink the `kbm-overlay/` plugin into the shell's plugin
directory and try to enable it. They honour `NOCTALIA_DATA_HOME` and
`XDG_DATA_HOME`.

### Add the widget

1. Open **Settings → Desktop → Desktop widgets** (or the desktop-widget edit
   mode).
2. Add **LGL KBM Overlay**.
3. Move and size it like any other desktop widget.
4. Open the device picker from the **KBM** bar widget, or run:

   ```bash
   noctalia-kwe msg panel-toggle linuxgamerlife/kbm-overlay:devices
   ```

5. Select the keyboard and mouse you want to follow.
6. Apply the narrow udev rule:

   ```bash
   bash apps/lgl-kbm-overlay/kbm-overlay/code/setup-input-permissions.sh
   ```

   The script shows the rule before installing it. Use `--print` to review it
   without root. Replug the devices (or log out and back in) if access is still
   denied.


### Toggle via IPC

Show or hide the KBM widget without removing it from the desktop layout:

```bash
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all toggle
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all hide
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all show
```

`hide` blanks the widget; it does not delete or unplace it. The state is
process-lifetime, so it returns to visible after a Noctalia restart. The
`all` target applies to every KBM widget instance.

These commands hide **all desktop widgets**, not just KBM:

```bash
noctalia-kwe msg desktop-widgets-toggle
noctalia-kwe msg desktop-widgets-hide
noctalia-kwe msg desktop-widgets-show
```

To disable the plugin entirely:

```bash
noctalia-kwe msg plugins disable linuxgamerlife/kbm-overlay
```

---

## How it works

```text
/dev/input/event* → python3 evdev reader → JSON lines
                                      │
                                service.luau
                                      │
                              noctalia.state
                                      │
              card.luau (desktop widget SVG) · devices.luau (picker)
```

- `code/kbm_daemon.py` reads only the selected devices, maps key/button codes
  to names, and emits compact state at up to 60 Hz.
- `service.luau` starts the reader, writes the effective device selection,
  watches its heartbeat, and republishes state.
- `card.luau` draws the keyboard and mouse as an SVG and shows it through
  `ui.image` inside the desktop widget.
- `bar.luau` is only a shortcut to the device picker.
- `devices.luau` is the device picker and permission status panel.

### Why a helper process?

Noctalia does not expose global keyboard or mouse state to plugins. A plugin
panel only receives keys while it has focus, which is useless for a gaming HUD.
The reader is a small, unprivileged Python process using Linux evdev. It never
grabs the device, never injects events and never logs input.

---

## Permissions and udev rules

Installing the plugin **does not install a udev rule**. The rule is a deliberate
one-time step because it grants read access to an input device.

### What the helper does

1. Open the Device picker and select a keyboard and mouse.
2. The picker stores the device name, event path and USB vendor/product IDs in
   `devices.json` under the plugin data directory.
3. Review the generated rule without root:

   ```bash
   bash apps/lgl-kbm-overlay/kbm-overlay/code/setup-input-permissions.sh --print
   ```

4. Install it when it looks right:

   ```bash
   bash apps/lgl-kbm-overlay/kbm-overlay/code/setup-input-permissions.sh
   ```

5. The script validates the vendor/product IDs, writes
   `/etc/udev/rules.d/70-lgl-kbm-overlay.rules` as root-owned `0644`, then runs:

   ```bash
   udevadm control --reload-rules
   udevadm trigger --subsystem-match=input
   ```

6. Replug the selected devices, or log out and back in, if access is still
   denied.

Generated rule shape:

```udev
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="1234", ATTRS{id/product}=="abcd", TAG+="uaccess"
```

### Scope

- `TAG+="uaccess"` grants read access to the **active seat user** for devices
  matching the selected vendor/product IDs.
- It does **not** add you to the `input` group and does **not** run a root
  daemon.
- Any process running as your user can read the selected device. This is the
  main trade-off of the uaccess approach.
- The reader sees every key on the selected keyboard, not only the keys drawn by
  the widget. It keeps the pressed-key state in memory, does not log it, does not
  write it to disk, and does not send it over the network. Use a dedicated
  gaming keyboard if you do not want a shared keyboard exposed.
- Matching is by vendor/product, so two identical models receive the same rule.
  If you replace the device, open the picker and run the helper again.
- Uninstalling leaves the rule in place. Remove it with:

  ```bash
  bash apps/lgl-kbm-overlay/kbm-overlay/code/setup-input-permissions.sh --remove
  ```

Invalid, missing or malformed USB IDs are rejected instead of being written into
a root-owned udev rule.

---

## Security notes

The app has no network access and no root daemon. The reader is read-only: it
does not grab, inject or remap input, and it does not log key values.

Security review summary:

- **Fixed: udev rule injection.** The setup helper used to interpolate
  `devices.json` values and a device-name fallback into a rule that is installed
  with `sudo`. A crafted value could inject extra udev directives. Vendor/product
  IDs are now required to be exactly four hex digits, the name fallback is
  removed, and the rule is limited to `KERNEL=="event*"`. `--print` lets you
  review the rule before installing.
- **Inherent: uaccess scope.** The active user's processes can read the selected
  device. Prefer a dedicated gaming keyboard/mouse if that matters.
- **Inherent: all keys are observed.** The daemon tracks every key on the selected
  keyboard so custom layouts work. State stays in memory and is published only to
  this plugin's entries.
- **Low: `/tmp` fallback.** If Noctalia's `pluginDataDir()` is unavailable and
  `XDG_RUNTIME_DIR` is unset, the app falls back to a `/tmp` path. Normal
  Noctalia installations use the owner-only plugin data directory.
- **Low: uninstall/install environment paths.** The uninstall scripts remove
  paths derived from `XDG_*`/`NOCTALIA_*` variables. Run them from a trusted
  environment.
- **Low: PID cleanup.** `kill_stale()` trusts a PID file plus a command-line
  substring. A same-user process could be killed; there is no privilege
  escalation.

No command injection was found in the service path: dynamic paths are
single-quote escaped, the PID is numeric, and JSON is parsed as data only.

---

## Layouts and style

| Preset | Keys |
| --- | --- |
| **FPS** | `~ 1 2 3 4 5`, `TAB Q W E R T`, `A S D F G`, `SHIFT Z X C V B`, `CTRL ALT SPACE` |
| **WASD compact** | `1 2 3 4`, `Q W E R`, `A S D F`, `SHIFT SPACE CTRL` |
| **Custom** | Any comma/space-separated key list: `W A S D SPACE SHIFT CTRL TAB ESC` |

The mouse is drawn as a mouse, with:

- left and right top buttons
- scroll wheel / middle button with up/down indicators
- exactly two side buttons, forward on top and back below
- optional body/button fill with a separate opacity
- cyan active fill and a white outline, with an optional glow/ripple on press
- a motion arrow whose direction is relative to the centre of the screen
  containing the cursor: above the horizontal midline points up, right of the
  vertical midline points right, and so on. Its length follows the distance from
  that centre: near the centre it is short, near the screen edge it uses the
  whole mouse body. It fades after the configured idle time.
- a permanently visible centre anchor dot

Cursor position, trails and the “lift off the mat” reset are not in this
version.

---

## Desktop widget settings

The settings are grouped into four main section toggles. Turning a main toggle
off hides that whole section. The indented sub-toggles enable individual
features inside the section:

- **Layout** — show keyboard, key labels, widget width, layout preset, custom
  keys.
- **Mouse** — show mouse, mouse labels, scroll wheel, side buttons.
- **Appearance** — panel background, glow, ripple, panel/key/mouse colours,
  mouse body/button opacity, radius and border, plus arrow direction, motion-arrow
  size, length scale, colour and idle time, and anchor-dot size, scale and colour.
- **Scaling** — key size, key gap, key radius, mouse height, label scale.

The usual Noctalia desktop-widget background controls stay above the sections.
Three mouse buttons are drawn on top (left, right, wheel/middle) and exactly two
on the side.

## Notes and limitations

- This is deliberately a **desktop widget**. It can be moved in desktop edit
  mode and does not float above every window. If you later want a click-through
  overlay over a fullscreen game, that is a separate future feature and needs
  Noctalia plugin API 36 (`[[layer]]` entries).
- Arrow direction and length use `kdotool getmouselocation` on KWin. If
  `kdotool` is unavailable, the arrow falls back to movement direction and
  speed-based length. In pointer-locked games, set **Arrow direction** to
  **Movement direction** or **Auto**.
- Device names can change after replug; if the selection stops matching, open
  the picker and select the device again.
- The reader needs a one-time udev rule per selected device.
- The lower mouse body is outline-only; `Mouse fill` and `Mouse body opacity`
  control the body and button fills. Set opacity to `0` for a fully outline-only
  mouse.

---

## Credits

Inspired by [univrsal/input-overlay](https://github.com/univrsal/input-overlay),
especially its black/white/cyan keyboard and mouse presets. This is an
independent Noctalia implementation, not a port of the OBS plugin.

Part of the [LGL Noctalia Widgets](../../README.md) collection. Licensed under
MIT — see [LICENSE](LICENSE).
