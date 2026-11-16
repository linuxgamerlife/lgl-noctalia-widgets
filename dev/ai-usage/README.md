<div align="center">

# LGL AI Usage

**AI limits, spend, and balances in a Noctalia desktop widget, bar widget, and panel.**

[![Version](https://img.shields.io/badge/version-1.0.0-purple)](ai-usage/plugin.toml)
[![Plugin API](https://img.shields.io/badge/Noctalia_API-24-blue)](ai-usage/plugin.toml)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-yellow)](../../ai-usage/LICENSE)

</div>

---

## Overview

LGL AI Usage is a Noctalia v5 port and adaptation of the
[AI Usage KDE Plasma widget](https://github.com/linuxgamerlife/ai-usage-widget) by
Łukasz Sarna. It shows AI limits, spend, and balances for several services and
accounts in one place, with additional Noctalia-native desktop, bar, and panel
views.

| Field | Value |
| --- | --- |
| Plugin ID | `linuxgamerlife/ai-usage` |
| Version | `1.0.0` |
| Entries | Service `poller`, desktop widget `card`, bar widget `usage`, panel `panel` |
| Plugin API | 24 |
| License | GPL-3.0-or-later |

Targets KineticWE's `noctalia-kwe` v5.3.0 and upstream Noctalia v5. Both install
scripts use the same v5 plugin API and the `noctalia` / `noctalia-kwe` app
directories.

## Feature mapping

| KDE widget | Noctalia port |
| --- | --- |
| Panel icon + popup with cards | Bar widget `usage` + panel `panel` with the same cards |
| Desktop placement with the same cards | `[[desktop_widget]]` card with host-panel surface |
| Header: title, refresh, settings | HUD-style header badge, title, refresh glyph and settings glyph |
| One card per account: title, account, error, main rows, bars, extra rows | Account sections in `lib/view.luau`; dividers by default, optional section surface |
| Bar severity colours: normal / warning / critical / unknown | Palette roles `primary` / `tertiary` / `error` / `on_surface_variant`, every colour overridable |
| Add, edit, delete, reorder accounts | Panel account list and add/edit forms; up/down buttons instead of drag |
| Refresh every 30 s … 1 h | `refresh_seconds` plugin setting, including `Manual only` (`0`), plus a manual refresh on every entry |
| Accounts in `~/.config/ai-usage-widgetrc` | `pluginDataDir()/accounts.json` (atomic write, no secrets) |
| Keys in KWallet via D-Bus | Secret Service via `secret-tool` |
| Claude organization discovery | Panel discovery rows from the same history file |
| “Unlock KWallet” button and waiting/cancel flow | No Noctalia wallet API: a locked/unavailable keyring is reported, with a hint to unlock it in the keyring app |
| Glass panel | Host desktop-widget panel (`background`, colour, opacity, radius, padding) |
| KDE theme colours | Palette role tokens by default; configurable colours follow or override the live theme |
| — | Local OpenCode Go per-model stats (`opencode stats`) |
| — | Optional account-section surface, dividers, bar height, text scaling and width controls |

## Project layout

| Path | What it is |
| --- | --- |
| `ai-usage/` | Plugin payload: manifest, entries, translations, thumbnail |
| `dev/ai-usage/` | These developer notes and tests |
| `tools/` | Catalog, validation and migration helpers |
| `catalog.toml` | Root source catalog |

## Install

Add this repository as a Noctalia source, then enable the plugin:

```sh
noctalia msg plugins source add lgl git https://github.com/linuxgamerlife/lgl-noctalia-widgets
noctalia msg plugins enable linuxgamerlife/ai-usage
```

For KineticWE's `noctalia-kwe` fork, use the same commands with
`noctalia-kwe`.

If upgrading from the old `apps/` layout, run `./tools/migrate.py` first. See
the repository `MIGRATION.md` for the upgrade notes.

## Uninstall

Disable or remove the plugin in **Settings → Plugins**, or disable it from
the command line:

```sh
noctalia msg plugins disable linuxgamerlife/ai-usage
```

Plugin data is kept unless you remove it manually. See the repository
`MIGRATION.md` for data locations.

## Tests

```bash
./tests/run.sh
```

Requires LuaJIT. The tests mock `noctalia.*`, `ui.*`, `desktopWidget.*`,
`barWidget.*` and `panel.*`, so no live Noctalia session is needed.

## Requirements

- Noctalia Shell with plugin API 24 or newer (upstream or `noctalia-kwe`)
- `curl`, `timeout` and GNU `find` for remote checks
- Recommended: `secret-tool` (libsecret) and a Secret Service for keys
- `gdbus` (glib2) for the locked-keyring probe when using Secret Service
- Alternatively, unencrypted mode-`600` local key files (use read-only,
  narrowly scoped and rotatable keys only)
- Optional: the `opencode` CLI for local per-model OpenCode Go stats

## Limitations

- No KWallet unlock button: Noctalia has no wallet API, so a locked keyring is
  reported with a hint instead.
- No drag-to-reorder in the account list; use the up/down buttons.
- Desktop widgets cannot show tooltips; every value is visible on the card.
- A desktop widget cannot read its tile width in v5.3.0, so the card exposes a
  **Content width** setting. Match it to the editor tile width.
- Local OpenCode model stats come from this machine only and are not official Go
  quota.
- Some provider endpoints and local formats are undocumented; they can change
  without notice and produce a per-account error.

## Credits and License

Based on the [AI Usage KDE Plasma widget](https://github.com/linuxgamerlife/ai-usage-widget)
by Łukasz Sarna. LGL adapted and extended it for Noctalia and Noctalia KWE.

GPL-3.0-or-later — see [LICENSE](../../ai-usage/LICENSE).
