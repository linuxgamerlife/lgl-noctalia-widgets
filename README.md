# AI Usage — Noctalia plugin

A Noctalia v5 plugin that shows AI limits, spend and balance for several services
and accounts in one place. It is a port of the
[AI Usage KDE Plasma widget](https://github.com/lukk17/ai-usage-widget): a
headless service checks every account on a timer, a desktop card renders the
full cards, a compact bar widget shows the worst current limit, and a panel
handles account management.

Targets Noctalia v5 / KineticWE's `noctalia-kwe` v5.3.0. The plugin API 24
manifest, the service start and the LuaJIT suite were verified on that shell;
the rendered widget was not screenshot-verified because the live settings edit
had to be reverted. Upstream Noctalia uses the same v5 plugin API and is
supported by the install scripts, but has not been tested on the author's
machine.

## Layout

| Path | What it is |
| --- | --- |
| `ai-usage/` | The plugin: `plugin.toml`, service, card, bar, panel, `lib/`, `providers/`, translations |
| `install-kwe.sh` | Install for KineticWE's `noctalia-kwe` fork |
| `install.sh` | Install for upstream Noctalia |
| `uninstall-kwe.sh` | Remove from `noctalia-kwe` |
| `uninstall.sh` | Remove from upstream Noctalia |
| `remove-plugin-widgets.py` | Safely removes this plugin's desktop and bar widget instances from `settings.toml` |
| `catalog.toml` | Noctalia source catalog (the repo can be added as a plugin source) |
| `tests/` | LuaJIT tests with a mocked Noctalia API |

## Install

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then enable **AI Usage** in **Settings → Plugins** if the installer did not,
and add it from **Settings → Desktop → Toggle Editor** for the card, or from
**Settings → Bar → Widgets** for the compact bar widget.

`install-kwe.sh` links the plugin into `~/.local/share/noctalia-kwe/plugins`;
`install.sh` uses `~/.local/share/noctalia/plugins`. Both honour
`NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`.

Open the panel directly at any time:

```bash
noctalia-kwe msg panel-toggle lukk17/ai-usage:panel   # or: noctalia msg ...
```

## Use

1. Click the desktop card, the bar widget, or open the panel. With no account
   the panel shows **Add account**.
2. Pick a service, type a name or email, paste the key (Claude, ChatGPT and
   JetBrains AI need no key). For Claude the panel lists the organizations in
   the Claude desktop app file; type a name for each one you want.
3. **Manage accounts** edits labels and fields, moves accounts up and down, and
   deletes an account together with its stored key. An account label that looks
   like an email address is shown as `j***` on the card, in the account list and
   in status messages. The raw label stays only in the local accounts file; the
   edit form never pre-fills it, so leaving the label field empty keeps it.
4. **Open plugin settings** edits the refresh interval. The panel is deliberately
   not a second settings editor: Noctalia owns plugin settings, and a plugin
   cannot write them.

The desktop card has a refresh button, a settings button that opens the panel,
and an **Add account** button when empty. The bar widget shows the worst current
limit by default; click opens the panel, right-click asks the service to refresh.

## Feature mapping

| KDE widget | Noctalia port |
| --- | --- |
| Panel icon + popup with cards | Bar widget + `[[panel]]` with the same cards |
| Desktop placement with the same cards | `[[desktop_widget]]` card |
| Header: title, refresh, settings | Card and panel headers with refresh / panel-settings buttons |
| One card per account: title, account, error, main rows, bars, extra rows | Same layout in `lib/view.luau` |
| Bar severity colours: normal / warning / critical / unknown | Theme roles `primary` / `tertiary` / `error` / `on_surface_variant` |
| Add, edit, delete, reorder accounts inside the popup | Panel account list and add/edit forms; up/down buttons instead of drag |
| Refresh every 30 s … 1 h | Root `refresh_seconds` setting, read by the service |
| Accounts in `~/.config/ai-usage-widgetrc` | `pluginDataDir()/accounts.json` (atomic write, no secrets) |
| Keys in KWallet via D-Bus | Secret Service via `secret-tool` (see below) |
| Claude organization discovery | Panel discovery rows from the same history file |
| “Unlock KWallet” button and waiting/cancel flow | No Noctalia wallet API: a locked/unavailable keyring is reported, with a hint to unlock it in the keyring app |
| Loading spinner | Small `loader` glyph while a check runs |
| Accessibility names | Not exposed by the `ui.*` vocabulary; native controls keep their own semantics |
| Glass panel | Theme `surface` role with a configurable opacity |

Unchanged from the KDE widget: the 11 providers and their endpoints, the
per-provider minimum intervals (5 minutes for spend services), exponential
backoff up to one hour, `Retry-After`, the “connection lost retries without
doubling” rule, the clock-moved-back rule, multiple accounts per service,
per-account error states, the 1 MiB answer cap and the read-only local sources.

### Background and width

The desktop widget has two independent opacity sliders:

- **Outer background opacity** is the panel behind the header and cards. At `0`
  the outer fill and border are removed.
- **Account card opacity** is the surface of each account card. At `0` the cards
  have no fill or border, so only text and bars remain over the wallpaper.

Set both to `0` for a completely transparent widget. The selection handles and
the white rectangle in the widget editor are the editor’s own chrome, not part
of the widget, and disappear when you leave the editor.

**Widget width** sets the content width in logical pixels. Rows, progress bars
and separators stretch to that width. The desktop tile itself is sized by the
widget editor; Noctalia’s plugin desktop-widget API does not expose the tile
width to the script in v5.3.0, so the content is centered inside the tile. To
get a tight fit, set the tile width in the editor and `card_width` here to the
same value.

### OpenCode Go fields

`GET /zen/go/v1/usage` exposes only three windows (`rolling`, `weekly`,
`monthly`), and each window has only:

- `percent` — used percentage, floored by the API
- `resetsAt` — ISO reset timestamp
- `status` — `ok` or `rate-limited`

There is no plan name, dollar amount, credit balance, token count, model
breakdown or history in this endpoint. The plugin shows percent and reset for
each window, and shows **Rate limited** (and treats the window as 100%) when the
status is `rate-limited`. Dollar figures would require the OpenCode console
session, not an API key, so they are intentionally not used.

## How it gets data, and is it secure?

### Remote providers

Every check is **one shell pipeline**, built in
[`ai-usage/lib/curlcommand.luau`](ai-usage/lib/curlcommand.luau), exactly as in
the KDE widget:

1. `secret-tool lookup server ai-usage user <service>.<account-id> type plaintext`
   reads the key from the Secret Service into a shell variable.
2. A constant `printf` sends `Authorization: …` (or `x-api-key: …`) to
   `curl -H @-` on **standard input**. The key is never a process argument.
3. `curl` runs with `--disable --silent --show-error --globoff --tlsv1.2
   --proto '=https' --max-redirs 0 --max-time 20 --max-filesize 1048576` inside
   `timeout 25`. Redirects are not followed (a `3xx` becomes “unexpected
   answer”), the answer is capped at 1 MiB, and the command starts with
   `ulimit -c 0; set +a +x +v; unset SSLKEYLOGFILE`.
4. The body and status are framed with a random boundary and parsed in Luau.

The key never enters `accounts.json`, never enters the published state, and is
never in a process argument list. It is in the memory of `secret-tool`, the
short shell and `curl` for the duration of one check. Only constant URLs,
headers, provider ids and validated account ids reach the command; the account
name is never used in a URL or a command.

### Account labels and email privacy

An account label is only a display label; providers never receive it. Before an
entry is published to the widget state, the service replaces an email-style
label with a masked form such as `j***`. The card, panel list and success/delete
messages use that masked value, and the formatter masks again as a second line
of defence. The raw label is kept only in
`pluginDataDir()/accounts.json`, because it is what the edit form works with.
That directory is set to mode `700` and the file to `600`. The edit form starts
empty and shows `Current label: j***`, so leaving the field empty keeps the
existing label without displaying the address.

### Where keys live

Keys live **only in the Secret Service** (KWallet, gnome-keyring, KeePassXC,
etc.) under `server=ai-usage`, `user=<service>.<account-id>`,
`type=plaintext`. The accounts file contains only service id, generated account
id, display label and the provider fields (`org` for Claude, `teamId` for xAI);
an email-style display label is stored there but masked before it is published
or rendered.

Noctalia does not expose a Secret Service API to plugins, so saving a key is the
one place this port differs from KDE: the panel runs
`printf '<base64>' | base64 -d | secret-tool store …`. The key is passed on
standard input to `secret-tool`, but the base64 form is visible in the short
shell command line while the save runs. It is never written to disk. Use a
dedicated key per service and rotate it, because any program running as you can
ask the Secret Service for keys anyway.

### Local providers

Claude, ChatGPT and JetBrains AI need no key. The service runs a fixed,
read-only shell command with a timeout and a byte cap; the commands contain no
user input. They read:

- `${XDG_CONFIG_HOME:-~/.config}/Claude/plan-usage-history.json`
- the newest 20 `rollout-*.jsonl` files under `$CODEX_HOME/sessions` or
  `~/.codex/sessions`
- the last 4 MiB of `~/.cache/JetBrains/*/log/idea.log`

Symlinks are skipped. JetBrains lines are parsed in the service and only the
percentages are published, so licence and quota ids never reach the widget VMs.

### Limits of the guarantee

- curl still honours the session's proxy and certificate variables
  (`HTTPS_PROXY`, `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `SSL_CERT_DIR`). Whoever
  can set them can route the requests through their own proxy or trust their
  own certificate.
- The Secret Service protects keys at rest and from other users, not from
  programs that run as you.
- Some endpoints and local formats are undocumented (see the provider table);
  they can change without notice and produce a per-account error.

## Providers

| Service | Source | Key |
| --- | --- | --- |
| Claude | Claude desktop app `plan-usage-history.json`, read only | None |
| ChatGPT | Newest Codex `rollout-*.jsonl` rate-limit line, read only | None |
| OpenAI API | `GET /v1/organization/costs` and `/usage/completions`, daily buckets since the month start (UTC) | Admin API key |
| Anthropic API | `GET /v1/organizations/cost_report` and `/usage_report/messages`, team organizations | Admin API key |
| xAI API | `management-api.x.ai` prepaid balance and postpaid invoice preview | Management key + team ID |
| OpenCode Go | `opencode.ai/zen/go/v1/usage` 5hr, weekly and monthly limits | Go API key |
| OpenCode Zen | `opencode.ai/console/api/v1/budgets/members` member spend and monthly budgets | Service account key with All permissions |
| MiniMax | `api.minimax.io/v1/token_plan/remains` | Token Plan key (`sk-cp-…`) |
| Requesty | `api-v2.requesty.ai/v1/manage/apikey/self` and `/org` | Any key; balance needs manage permission |
| Hugging Face | `whoami-v2` and billing usage by inference session | Fine-grained token with `user.billing.read` |
| JetBrains AI | Newest `QuotaManager2Impl … Available(` line in the IDE log | None |

The KDE project's terms-of-service notes and per-service key advice still
apply. In particular: OpenCode Go allows one account per person; use a separate
admin key for OpenAI/Anthropic; xAI management keys can manage the team; and
OpenCode Zen “All permissions” also lets the key change member budgets.

## Settings

Plugin-level (Settings → Plugins):

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `refresh_seconds` | select | `30` | 30 s, 1, 5, 15, 30 or 60 minutes |

Desktop card:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `show_header` | bool | `true` | Title, refresh and settings buttons |
| `show_details` | bool | `true` | Tokens, plan, billing mode, top-up, member budgets |
| `card_width` | int | `360` | Content width in logical px; cards, rows and bars grow with it |
| `background_opacity` | double | `0.85` | Outer panel opacity; `0` removes the outer fill and border |
| `card_opacity` | double | `0.42` | Account card opacity; `0` blends the cards into the wallpaper |
| `dense` | bool | `false` | Smaller text, gaps and bars |

Bar widget:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `show_percent` | bool | `true` | Show the value next to the glyph |
| `glyph` | glyph | `chart-bar` | Bar icon |
| `mode` | select | `worst` | Worst limit, error count or account count |

## Requirements

- Noctalia Shell with plugin API 24 or newer (upstream or `noctalia-kwe`)
- `curl`, `timeout` and GNU `find` for remote checks
- `secret-tool` (libsecret) and a Secret Service for keys
- `gdbus` (glib2) for the locked-keyring probe

## Tests

```bash
./tests/run.sh
```

Requires LuaJIT. The tests mock `noctalia.*`, `ui.*`, `desktopWidget.*`,
`barWidget.*` and `panel.*`, and cover provider parsing, the curl command and
parser, scheduling/backoff, formatting, service publishing and reload, the card,
the bar widget, the panel add/edit/reorder/delete flow, and service → card
integration.

`noctalia-kwe plugins lint ai-usage` is clean.

## Remove

```bash
./uninstall-kwe.sh   # KWE
./uninstall.sh       # upstream
```

The uninstall scripts disable the plugin, stop its service, remove its desktop
and bar widget instances (with a timestamped settings backup), and delete its
plugin data. Keys in the Secret Service are left alone; remove them with:

```bash
secret-tool clear server ai-usage user minimax.a3f09c1d2b4e type plaintext
```

Use `--yes` for non-interactive removal.

## Relation to the existing community plugin

The Noctalia community catalogue also has `felipeartur/ai-usagebar`, which is a
different project: it wraps the `ai-usagebar` Rust CLI and its provider list,
rather than porting this KDE widget's own curl/local-file checks. This repo is
the port of the KDE widget described above.

## Limitations

- No KWallet unlock button: Noctalia has no wallet API, so a locked keyring is
  reported with a hint instead.
- No drag-to-reorder in the account list; use the up/down buttons.
- The bar widget and panel cannot show tooltips on every control; the desktop
  widget shows none by design.
- Accounts are stored per plugin data directory, not in Noctalia settings, so
  they survive panel/layout resets but are not editable from the settings GUI.
- The `ui.*` vocabulary has no `Accessible.*` properties, so the explicit
  accessibility names from the KDE widget are not reproduced.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
