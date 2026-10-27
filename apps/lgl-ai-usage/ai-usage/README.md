# LGL AI Usage — Technical Reference

Noctalia v5 plugin with a headless `poller` service, a desktop card, a compact
bar widget and a panel. The service checks every account on a timer and publishes
plain state; the UI entries only watch it and render `ui.*` trees. There is no
QML and no background daemon.

## How the data is collected

Every remote check is one shell pipeline: `secret-tool lookup` reads the key from
the Secret Service into a shell variable, a constant `printf` sends the auth
header to `curl -H @-` on stdin, and the answer is framed and parsed in Luau. The
key is never a process argument, never in a URL, and never written to disk.
`curl` runs with no redirects, a 20 s timeout and a 1 MiB response cap.

Local providers read files with fixed, read-only shell commands and a byte cap.
They skip symlinks and publish only calculated values, not file contents.

| Service | Source | Key |
| --- | --- | --- |
| Claude | Claude desktop app `plan-usage-history.json`, read only | None |
| ChatGPT | Newest Codex `rollout-*.jsonl` rate-limit line, read only | None |
| OpenAI API | `GET /v1/organization/costs` and `/usage/completions`, daily buckets since month start (UTC) | Admin API key |
| Anthropic API | `GET /v1/organizations/cost_report` and `/usage_report/messages`, team organizations | Admin API key |
| xAI API | `management-api.x.ai` prepaid balance and postpaid invoice preview | Management key + team ID |
| OpenCode Go | `opencode.ai/zen/go/v1/usage` rolling, weekly and monthly limits | Go API key |
| OpenCode Zen | `opencode.ai/console/api/v1/budgets/members` member spend and monthly budgets | Service account key with All permissions |
| MiniMax | `api.minimax.io/v1/token_plan/remains` | Token Plan key |
| Requesty | `api-v2.requesty.ai/v1/manage/apikey/self` and `/org` | Any key; balance needs manage permission |
| Hugging Face | `whoami-v2` and billing usage by inference session | Fine-grained token with `user.billing.read` |
| JetBrains AI | Newest `QuotaManager2Impl … Available(` line in the IDE log | None |

The service publishes one `ai_usage` table per change and a 30 s heartbeat:

```lua
{
  ts, refresh_seconds,
  accounts = {
    {
      key, providerId, title,
      account = { id, service, name },  -- name is masked if it looks like an email
      usage, error,
      local_models, local_models_error,
      isLoading, lastAttemptAt, lastSuccessAt, nextAttemptAt, ...
    },
  },
  has_accounts, wallet_locked, tools_missing, running,
}
```

## Settings

### Plugin settings

Edited under **Settings → Plugins** (the gear on the plugin row). They are shared
by the service, the card and the panel.

| Setting | Default | What it does |
| --- | --- | --- |
| Refresh every | 30 s | `Manual only` (`0`), 30 s, 1, 5, 15, 30 or 60 minutes. Spend services are checked at most every 5 minutes. |
| Show local model stats | on | Read `opencode stats --json --models` for OpenCode Go and show the top local models. |
| Local models shown | 5 | How many OpenCode Go models to show (1–20). |

### Manual refresh

A manual refresh bypasses the 30 s floor and existing backoff, checks every
account immediately, and re-reads local model stats. Provider rate limits still
apply. Use the card refresh glyph, the panel **Refresh now**, right-click on the
bar capsule, or:

```bash
noctalia msg plugin lukk17/ai-usage:poller all refresh
```

**Manual only** (`0`) stops the timer. The service still checks once at startup,
then waits for an explicit refresh. Automatic local model-stat reads also stop.

### Card display

The inspector keeps four optional groups of controls; all default off except
layout. Hidden values stay active, so collapsing a group only changes the
editor.

| Setting | Default | What it does |
| --- | --- | --- |
| Show layout settings | on | Reveal content width and the optional account-section fill, radius and border. |
| Show colour settings | off | Reveal header, limit, track, text and divider colours. |
| Show scaling settings | off | Reveal text size, progress bar height and divider thickness. |
| Show section toggles | off | Reveal the Show header, details, reset times and service icons toggles. |
| Card title | AI Usage | Header heading. |
| Show header | on | Header badge, title, refresh and settings buttons. |
| Show details | on | Extra rows (tokens, plan, billing mode, top-up, member budgets) and local model stats. |
| Show reset times | on | Reset line under each limit bar. |
| Show service icons | on | Provider glyph in each account section header. |

### Layout

| Setting | Default | What it does |
| --- | --- | --- |
| Content width | 432 px | Width of the card content (240–900). Match the editor tile width. |
| Account section opacity | 0 | Fill behind each account section. `0` keeps the HUD-style divider-only layout. |
| Account section radius | 12 px | Radius of the optional section surface. |
| Account section border opacity | 0 | Border opacity of the optional section surface. |
| Account section border width | 1 px | Border thickness of the optional section surface. |

### Scaling

Text size is independent of every other dimension, so larger labels do not make
the bars or dividers thicker.

| Setting | Default | What it does |
| --- | --- | --- |
| Text size | 1.0× | Multiplies every title, label, value, reset and detail font size (0.5–2.0), including the header badge and inline glyphs. Bars, dividers and section surfaces keep their own dimensions. |
| Progress bar height | 5 px | Thickness of each limit bar (2–14). |
| Divider thickness | 1 px | Header, account and section dividers (0.5–4). |

### Colours

Every colour accepts a palette role token (`primary`, `secondary`,
`on_surface`, `on_surface_variant`, `outline`, `error`, …) or a hex value
(`#rrggbb` / `#rrggbbaa`). Role tokens follow the live Noctalia palette; hex
values stay fixed. The manifest validator does not accept a role with an alpha
suffix in a setting, so translucent surfaces have separate opacity settings.

| Setting | Default | What it styles |
| --- | --- | --- |
| Header icon colour | `primary` | Header badge outline and icon. |
| Header icon | `chart-bar` | Glyph in the header badge. |
| Normal limit colour | `primary` | Bars and values below 75%. |
| Warning limit colour | `tertiary` | Bars and values from 75%. |
| Critical limit colour | `error` | Bars and values from 90%, rejected keys and expired windows. |
| Unknown / expired colour | `on_surface_variant` | Expired, disabled or unavailable values. |
| Bar track colour | `on_surface` | Unfilled part of each limit bar. |
| Bar track opacity | 0.14 | Unfilled part, combined with the track colour. |
| Primary text colour | `on_surface` | Titles, values and labels. |
| Secondary text colour | `on_surface_variant` | Account labels, reset times, units and inactive values. |
| Divider colour | `outline` | Header, account and section dividers. |
| Divider opacity | 0.5 | Divider opacity (0–1). |
| Account section colour | `surface_variant` | Fill used only when Account section opacity is above 0. |
| Account section border colour | `outline` | Border of the optional section surface. |

The critical colour wins over presentation choices and is paired with a text
state, so colour is never the only signal.

### Surface

The card deliberately draws **no outer surface**. Noctalia's desktop-widget host
owns the panel behind it, so the panel toggle and opacity slider always affect
the surface the user sees. These keys are handled by the host, not this script:

| Setting | Default | What it does |
| --- | --- | --- |
| Show host panel | on | Let Noctalia draw its surface behind the card. Turn off to place content directly on the wallpaper. |
| Panel colour | `surface` | Host panel fill. |
| Panel opacity | 0.8 | Applied live by the host without recreating the widget. |
| Panel corner radius | 12 px | Host panel radius. |
| Panel padding | 10 px | Space between panel edge and card content. |

If the panel is on, size the editor tile to **Content width + 2 × panel
padding** (452 px wide with the defaults) for a tight fit. With the panel off,
the card adds a 6 px content inset instead of sitting flush on the wallpaper.

### Bar widget

| Setting | Default | What it does |
| --- | --- | --- |
| Show percentage | on | Show the value beside the glyph. |
| Icon | `chart-bar` | Bar icon. |
| Bar value | Worst limit | `Worst limit`, `Error count` or `Account count`. |

The bar inherits the bar's typography and foreground/icon colours when no colour
is set.

## Local OpenCode model stats

When an OpenCode Go account exists and **Show local model stats** is on, the
service runs:

```bash
opencode stats --json --models --limit 10
```

It filters `model.providerID == "opencode-go"`, sorts by cost, and publishes the
top `Local models shown` models with model id, variant, steps, cost and
input/output tokens. This is **local machine data**, not official Go quota: it
only sees this machine, cannot attribute usage to a key or account, and is
all-time rather than the rolling windows. The card labels it “Models on this
machine”.

The CLI is looked up on `PATH`, then at `~/.opencode/bin/opencode` and
`~/.local/bin/opencode`. A missing CLI is reported on the card; quota checks
still work.

## Theming behaviour

- Default palette roles track theme switches, including `on_surface/0.14` for the
  bar track.
- Fixed hex values in user settings do not change with the theme.
- Stale data is dimmed and labelled; it is never shown as a misleading zero.
- Text size scales titles, labels, values and inline glyphs without changing the
  bar, divider or section-surface dimensions.
- The card never draws a second outer surface on top of the host panel, so the
  host opacity control cannot be hidden by an opaque plugin fill.
- Account-section fills are optional and default to `0`, matching the HUD-style
  divider layout.

## Security and secrets

By default, keys live only in the Secret Service under `server=ai-usage`,
`user=<service>.<account-id>`, `type=plaintext`. `accounts.json` contains only
the account id, service, label and provider fields (no keys) and is written
atomically with mode `600`; its directory is mode `700`. Email-style labels are
masked before they are published or rendered.

For systems without a Secret Service, **API key storage** can explicitly be set
to **Local files (unencrypted)** in the plugin settings. Each key is then stored
under `pluginDataDir()/keys/` in its own mode-`600` file; the directory is mode
`700`, and key-file symlinks are not followed. This protects keys from other
non-root users, but not from root, programs running as your user, disk access or
unencrypted backups. **Only use read-only, narrowly scoped and rotatable API
keys with this mode.** Never use an administrative, billing-capable or general
purpose credential. Secret Service remains the recommended mode.

Remote checks read the key from the configured store, pipe the auth header into
`curl -H @-` on stdin, and use TLS 1.2+, no redirects and a 1 MiB cap. Saving a
key is the one difference from KDE: Noctalia has no wallet D-Bus API, so the
panel pipes a base64 key into `secret-tool store`; the base64 is briefly visible
in the short shell command line but is never written to disk. Use dedicated,
rotatable keys. Any program running as you can ask the Secret Service for keys.

## Troubleshooting

**The widget does not appear in the editor.** Check the install path. The plugin
must live in the running shell's app dir:

- upstream: `~/.local/share/noctalia/plugins/ai-usage`
- KWE: `~/.local/share/noctalia-kwe/plugins/ai-usage`

Then run `noctalia msg config-reload` (or `noctalia-kwe msg config-reload`) and
enable it in **Settings → Plugins**.

If a manifest setting was just added and is missing from the widget editor, the
running entry still has the old settings snapshot. **`config-reload` alone does
not reseed an already-enabled entry.** Disable and re-enable the plugin once,
then reopen the desktop-widget editor:

```bash
noctalia-kwe msg config-reload
noctalia-kwe msg plugins disable lukk17/ai-usage
noctalia-kwe msg plugins enable lukk17/ai-usage
```

Existing widget instances are kept. The old `card_width` and `dense` keys are
ignored by the new card; set **Content width** to the tile width. A card wider
than its tile is clipped.

**The card is clipped or has empty space.** Set **Content width** to match the
tile width minus twice the panel padding.

**An account says “the answer format changed”.** The provider changed its
response. Check the account's HTTP status in the journal; the per-account error
keeps the other accounts working.

**The keyring is locked.** Unlock it with your keyring app, then use **Refresh**.
Noctalia has no wallet unlock API.

**Local model stats are unavailable.** Install the `opencode` CLI and make sure
it can read this machine's OpenCode database; quota checks still work.

## Credits and License

Based on the GPL-3.0 AI Usage Plasma widget by Łukasz Sarna and adapted by LGL
for Noctalia and Noctalia KWE.

GPL-3.0-or-later — see [LICENSE](LICENSE).
