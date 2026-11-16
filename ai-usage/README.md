# AI Usage

A Noctalia plugin that tracks AI subscription limits, spend and balances in a
desktop card, a bar capsule and a management panel.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/ai-usage` |
| Bar widget | `usage` |
| Desktop widget | `card` |
| Panel | `panel` |
| Service | `poller` |

## Requirements

- Noctalia Shell with plugin API 24 or newer.
- `curl` for remote provider checks.
- `libsecret` (Secret Service) for the recommended key store.
- `glib2` for the `gdbus` keyring probe.

The plugin supports Claude, ChatGPT/Codex, OpenAI, Anthropic, xAI, OpenCode Go,
OpenCode Zen, MiniMax, Requesty, Hugging Face and JetBrains AI. Some providers
read local files and need no key; the others need a read-only API key with the
permissions described in the add-account form.

## Usage

Enable **AI Usage** in **Settings → Plugins**, then:

- add the **AI Usage** desktop card from the desktop-widget editor;
- add the compact **AI Usage** capsule from the bar-widget editor;
- open the account and settings panel with:

```sh
noctalia msg panel-toggle linuxgamerlife/ai-usage:panel
```

Use **Add account** in the panel, pick a provider and paste the key when the
provider needs one. Account rows can be edited, deleted and reordered. The panel
also shows the refresh schedule, key storage mode and local model statistics.

Manual refresh is available from the card refresh button, **Refresh now** in the
panel, right-click on the bar capsule, or:

```sh
noctalia msg plugin linuxgamerlife/ai-usage:poller all refresh
```

## Settings

### Plugin settings

| Setting | Default | Description |
| --- | --- | --- |
| `refresh_seconds` | `30` s | Refresh interval: manual only, 30 s, 1/5/15/30 minutes or 1 hour. Spend services are checked at most every 5 minutes. |
| `key_storage` | Secret Service | Secret Service is recommended. Local files are unencrypted and mode 600; use only read-only, narrowly scoped, rotatable keys. |
| `show_model_stats` | on | Read local OpenCode statistics with `opencode stats --json --models` for OpenCode Go. This is local data, not official quota. |
| `model_stats_limit` | `5` | Number of local models to show (1–20). |

### Bar widget

| Setting | Default | Description |
| --- | --- | --- |
| `show_percent` | on | Show the selected value beside the glyph. |
| `glyph` | `chart-bar` | Bar icon. |
| `mode` | Worst limit | Show the worst limit, the error count or the account count. |

### Desktop card

The card starts with the host background controls and six groups:

- **Show header** — title, refresh and settings buttons.
- **Show details** — token, plan, billing, top-up, member-budget and local-model
  rows.
- **Show layout settings** — content width and the optional account-section
  surface.
- **Show colour settings** — header, limit, track, text and divider colours.
- **Show scaling settings** — text size, bar height and divider thickness.
- **Show section toggles** — header, details, reset times and service icons.

Key settings:

| Setting | Default | Description |
| --- | --- | --- |
| `title` | `AI Usage` | Header heading. |
| `content_width` | `432` px | Card width (240–900). Match the editor tile. |
| `text_scale` | `1.0` | Multiplies card typography (0.5–2.0) without changing bars or dividers. |
| `bar_height` | `5` px | Limit-bar thickness (2–14). |
| `divider_width` | `1` px | Divider thickness (0.5–4). |
| `show_reset_times` | on | Reset line under each limit bar. |
| `show_service_icon` | on | Provider glyph in each account header. |
| `header_color` | `primary` | Header badge outline and icon. |
| `normal_color` | `primary` | Bars and values below 75%. |
| `warning_color` | `tertiary` | Bars and values from 75%. |
| `critical_color` | `error` | Bars and values from 90%, rejected keys and expired windows. |
| `unknown_color` | `on_surface_variant` | Expired, disabled or unavailable values. |
| `track_color` | `on_surface` | Unfilled part of each limit bar. |
| `track_opacity` | `0.14` | Track opacity (0–1). |
| `text_color` | `on_surface` | Titles, values and labels. |
| `muted_text_color` | `on_surface_variant` | Account labels, reset times and inactive values. |
| `card_color` | `surface_variant` | Optional account-section fill, used only when `card_opacity` is above 0. |
| `card_opacity` | `0` | Account-section fill opacity (0–1). `0` keeps the HUD-style divider layout. |
| `card_radius` | `12` px | Optional account-section corner radius. |
| `card_border_color` | `outline` | Optional account-section border. |
| `card_border_opacity` | `0` | Account-section border opacity (0–1). |
| `card_border_width` | `1` px | Account-section border width (0.5–4). |

Every colour accepts a palette role token or a hex value.

## Notes

- Remote checks use `curl` with TLS 1.2+, no redirects, a 20 s timeout and a
  1 MiB response cap. Keys are never passed as process arguments or URLs.
- Keys live in the Secret Service by default. The optional local-file mode is
  unencrypted and should only be used with narrow, rotatable keys.
- `accounts.json` contains account labels and provider fields, never keys.
- The plugin has no analytics or telemetry. Local OpenCode model statistics are
  read from this machine only and are not official Go quota.
- A locked or unavailable keyring is reported on the card and in the panel;
  Noctalia has no keyring-unlock API.
- When the service has not published data yet, the card shows **Waiting for the
  AI Usage service** and keeps the last known values only while they are fresh.

## Credits and License

Based on the AI Usage KDE Plasma widget by Łukasz Sarna. LGL adapted and extended
it for Noctalia and Noctalia KWE.

GPL-3.0-or-later — see [LICENSE](LICENSE).
