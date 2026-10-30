# LGL KBM Overlay

A movable Noctalia desktop widget showing gaming keyboard keys and mouse buttons
in the black / white / cyan input-overlay style.

- FPS or WASD key cluster, or a custom key list.
- Mouse silhouette with left/right buttons, wheel/middle button and exactly
  two side buttons.
- Cyan press fill, white outlines, optional glow/ripple.
- All visual settings live in the desktop widget's own settings.
- Device picker that reads only the selected keyboard and mouse.
- Bar shortcut to open the device picker.

## Requirements

- Noctalia / Noctalia KWE with plugin API 30 (KWE 5.3.0).
- `python3`.
- Read access to the selected input devices, via the bundled udev helper.
  The helper validates vendor/product IDs and supports `--print` for review.

## First run

1. Add **LGL KBM Overlay** in **Settings → Desktop → Desktop widgets** and move
   it where you want it.
2. Open the Device picker from the KBM bar widget or run:

   ```bash
   noctalia-kwe msg panel-toggle linuxgamerlife/kbm-overlay:devices
   ```

3. Select a keyboard and mouse.
4. Run:

   ```bash
   bash code/setup-input-permissions.sh
   ```

This is a desktop widget, not a layer-shell overlay. It does not sit above every
window and can be moved in desktop edit mode. Mouse-movement/trail support is
planned separately.

Toggle it from IPC:

```bash
noctalia-kwe msg plugin linuxgamerlife/kbm-overlay:reader all toggle
```

See the repository app README for the full settings reference and privacy
notes.

## Licence

MIT — see [LICENSE](LICENSE). Inspired by
[univrsal/input-overlay](https://github.com/univrsal/input-overlay); this is an
independent implementation with its own procedurally drawn artwork.
