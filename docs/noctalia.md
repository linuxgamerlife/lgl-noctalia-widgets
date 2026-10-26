# Noctalia plugin notes

This is the Noctalia-specific companion to the main [README](../README.md). It
covers the plugin API surface, install locations, live-reload behaviour,
settings, state flow and debugging commands.

## Plugin API and entries

`plugin.toml` declares `plugin_api = 24` and four entries:

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `poller` | `[[service]]` | `service.luau` | Owns accounts, timer, checks and published state |
| `card` | `[[desktop_widget]]` | `card.luau` | Full cards on the desktop |
| `usage` | `[[widget]]` | `bar.luau` | Compact bar capsule |
| `panel` | `[[panel]]` | `panel.luau` | Cards, account management, Refresh now |

The service and the UI entries are separate Luau VMs. They exchange only plain
values through `noctalia.state` under the key `ai_usage`.

## Install locations

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/ai-usage` | `~/.local/state/noctalia` | `noctalia` |
| KineticWE `noctalia-kwe` | `~/.local/share/noctalia-kwe/plugins/ai-usage` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`. The install scripts create
a symlink to the repo's `ai-usage/` directory, so repository edits are visible to
the shell immediately.

## Reloading during development

- **`.luau` changes** hot-reload the owning entry. The shell log shows messages
  such as `hot reload: reloaded 'card.luau'`.
- **`plugin.toml` changes** need a config reload:

  ```bash
  noctalia-kwe msg config-reload
  ```

  If a new root setting is not recognised, disable and re-enable the plugin once
  so the service gets a fresh settings snapshot:

  ```bash
  noctalia-kwe msg plugins disable lukk17/ai-usage
  noctalia-kwe msg plugins enable lukk17/ai-usage
  ```

- **Desktop-widget settings controls** are built from the manifest when the
  widget editor opens. After changing a `[[desktop_widget.setting]]`, close and
  reopen the editor.
- **Do not edit `settings.toml` by hand to add a widget instance** unless you
  validate the TOML first. A missing comma in a `widget_order` array makes the
  shell reject the whole file and fall back to defaults. Use the desktop-widget
  editor, or the uninstall helper's line-based cleanup with a backup.

## Settings

Plugin-level, shared by the service and entries:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `refresh_seconds` | select | `30` | `0` = manual only; otherwise 30 s, 1, 5, 15, 30 or 60 minutes |
| `show_model_stats` | bool | `true` | Read local OpenCode Go model usage with `opencode stats` |

Desktop card:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `show_header` | bool | `true` | Title and refresh/settings buttons |
| `show_details` | bool | `true` | Extra rows and local model stats |
| `card_width` | int | `360` | Content width; bars and rows grow with it |
| `background` | bool | `true` | Show Noctalia's outer desktop-widget panel |
| `background_opacity` | double | `0.85` | Outer panel opacity, step `0.01` |
| `card_opacity` | double | `0.42` | Account card opacity, step `0.01` |
| `dense` | bool | `false` | Smaller text, gaps and bars |

Bar widget:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `show_percent` | bool | `true` | Show the value beside the glyph |
| `glyph` | glyph | `chart-bar` | Bar icon |
| `mode` | select | `worst` | `worst`, `errors` or `count` |

### Background and opacity

The outer panel is **Noctalia's own desktop-widget background**, not a surface
drawn by the plugin. That is why its opacity slider updates live: the host
handles `background_opacity` directly. The plugin deliberately does not draw a
second outer surface on top of it.

- `background = false` removes the outer panel; the plugin also removes its own
  content padding, leaving only the cards and text on the wallpaper.
- `background_opacity = 0` makes the outer panel transparent while leaving the
  show/hide toggle on.
- `card_opacity = 0` removes the account-card fill and border.

For a completely transparent widget: `background = false`, `card_opacity = 0`.

The white selection rectangle and handles in the desktop-widget editor are host
editor chrome, not part of the widget.

### Width

`card_width` sets the content width. Noctalia's plugin desktop-widget API does
not expose the tile width to the script in v5.3.0, so the content is centred
inside the editor-sized tile. Set the tile width in the editor and `card_width`
to roughly the same value for a tight fit.

## Manual refresh and manual-only mode

The service normally ticks every 5 seconds and checks accounts whose next
attempt is due. A **manual refresh** is different: it sets every non-loading
account due immediately, ignoring the 30-second manual floor and existing
backoff. The provider's own rate-limit response still applies.

Triggers:

- desktop card **Refresh**
- panel **Refresh now** / header **Refresh**
- right-click the bar widget
- IPC:

  ```bash
  noctalia msg plugin lukk17/ai-usage:poller all refresh
  ```

`refresh_seconds = 0` means **manual only**:

- one check runs at service startup,
- the periodic tick and automatic local model-stat reads stop,
- a manual refresh checks every account and re-reads local model stats,
- the 30-second heartbeat still publishes state so the widget does not look
  disconnected while idle.

## State flow

The service owns the account list and the checks. It publishes `ai_usage`:

```text
{
  ts, refresh_seconds,
  accounts: {
    key, providerId, title,
    account: { id, service, name },   -- name is masked if it looks like an email
    usage, error, local_models, local_models_error,
    isLoading, lastAttemptAt, lastSuccessAt, nextAttemptAt, ...
  },
  has_accounts, wallet_locked, tools_missing, running
}
```

The card, bar and panel only format and render that value. Use
`noctalia.state.watch("ai_usage", fn)` in UI entries; the service uses
`noctalia.state.set("ai_usage", value)`.

Internal editor-only state keys:

| Key | Direction | Meaning |
| --- | --- | --- |
| `ai_usage_accounts_rev` | panel → service | Account list changed; reload `accounts.json` |
| `ai_usage_refresh_seq` | card/bar/panel → service | Force a manual refresh |
| `ai_usage_open_add` | card/bar → panel | Open the panel directly in Add account |

## Accounts and permissions

Accounts live in `noctalia.pluginDataDir()/accounts.json`, not in
`settings.toml`. The service writes the file atomically (temporary file then
rename) and asks `chmod` to set the directory to `700` and the file to `600`.
The file contains no keys:

```json
{"version":1,"updated_ms":1793030414000,
 "accounts":[{"id":"a2b0...","service":"opencodeGo","name":"alice@example.com"}]}
```

The stored `name` is the raw label (which may be an email); the service masks
email-style labels before publishing them to widget VMs.

## Secrets

Keys are only in the Secret Service. See the main README's
[How it gets data, and is it secure?](../README.md#how-it-gets-data-and-is-it-secure)
section for the full threat model, the curl pipeline and the one caveat about
saving a key.

## Local OpenCode model stats

When an OpenCode Go account exists and `show_model_stats` is on, the service
runs:

```bash
opencode stats --json --models --limit 10
```

It filters `model.providerID == "opencode-go"`, sorts by cost, and publishes the
top five with model, variant, steps, cost and input/output tokens. This is local
machine data, not the official Go quota, and it cannot attribute usage to a
particular API key or other machines.

The command is looked up on `PATH`, then at `~/.opencode/bin/opencode` and
`~/.local/bin/opencode`. Missing CLI is reported on the card; quota checks still
work.

## Debugging

Read-only checks:

```bash
noctalia-kwe plugins lint ai-usage
journalctl --user -n 100 --no-pager | grep -iE 'ai-usage|plugin'
```

Manual actions:

```bash
# force a check without touching settings
noctalia-kwe msg plugin lukk17/ai-usage:poller all refresh

# open the panel
noctalia-kwe msg panel-toggle lukk17/ai-usage:panel
```

If a new manifest setting warns `read undeclared setting`, the running manifest
is stale: `config-reload`, then disable/enable the plugin if needed.

## Tests

`tests/run.sh` runs LuaJIT tests with mocked `noctalia.*`, `ui.*`,
`desktopWidget.*`, `barWidget.*` and `panel.*`. They do not need a live shell.
The manifest is also checked with `noctalia-kwe plugins lint ai-usage`.

## Related

- [README](../README.md) — install, use, providers, security, limitations
- [catalog.toml](../catalog.toml) — source catalog metadata
- [install-kwe.sh](../install-kwe.sh) / [install.sh](../install.sh) — installers
