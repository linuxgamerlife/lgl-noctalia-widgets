# Privacy and input access

LGL KBM Overlay reads keyboard and mouse **button** events locally so it can
draw which keys and buttons are pressed. It does not record, save, transmit or
replay input.

## What is read

- Only the keyboard and mouse selected in the plugin's Device picker.
- Key press/release events and mouse button press/release events.
- Mouse wheel direction and count.
- Mouse movement is ignored in this version.
- Device names, paths, vendor IDs and product IDs, used for the picker and the
  udev rule.

The reader maps key codes to display names such as `KEY_W` and `BTN_LEFT`. It
does not collect typed text, clipboard contents, window titles, or application
data. Nothing is written to disk except the selected device paths and the
`runtime.json` handoff file in the plugin data directory.

## What is not done

- No network requests.
- No keylogging to a file.
- No input injection, grabbing or remapping.
- No root daemon.
- No analytics or telemetry.

## Permissions

Linux exposes `/dev/input/event*` to privileged processes. The recommended
setup is the bundled script:

```bash
bash kbm-overlay/code/setup-input-permissions.sh
```

It creates a narrow udev rule matching the selected keyboard and mouse
vendor/product IDs and adds `TAG+="uaccess"`. That grants read access to the
active seat user for those devices only. It does **not** add the user to the
broad `input` group, which would expose every input device to every process
running as that user.

If the udev rule is not possible on a system, adding the user to `input` also
works, but it is a wider permission and is not the default.

## Data retention

- `devices.json` stores the selected device names, event paths and USB IDs.
- `runtime.json` is rewritten whenever the reader starts.
- `reader.pid` is removed when the reader exits.
- `frame-N.svg` files contain only the current keys/buttons drawn by the widget; they are overwritten continuously and contain no typed text.

Uninstalling removes the plugin data directory. The udev rule is intentionally
left in place; remove it with:

```bash
bash kbm-overlay/code/setup-input-permissions.sh --remove
```
