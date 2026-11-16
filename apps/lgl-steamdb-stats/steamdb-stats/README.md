# SteamDB Stats — plugin reference

This is the technical reference for the Noctalia plugin payload. Start with the
[app README](../README.md) for installation and user-facing settings.

## Entries

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `poller` | `[[service]]` | `service.luau` | Detect the Steam game, fetch stats, write the cache, publish `steam_stats` |
| `card` | `[[desktop_widget]]` | `card.luau` | Render the SteamDB-style summary and 24-hour graph |

`plugin_api = 24` is the first level used by this port. It provides relative
module `require` and `noctalia.http` (already used by the Weather & Time port).
Services start on enable at API 17.

The service and the card are separate Luau VMs. They exchange only the plain
`steam_stats` table through `noctalia.state`; no functions, userdata or file
handles cross the boundary.

## Modules

| File | Responsibility |
| --- | --- |
| `service.luau` | Settings, detection loop, HTTP scheduling, retries, cache, publishing |
| `card.luau` | Declarative card, stat cells, graph normalisation, idle state |
| `lib/steam.luau` | Steam root discovery, log replay, `/proc` liveness, manifests, cover path |
| `lib/steamcharts.luau` | SteamCharts page/chart parsing, Valve current-count parser, HTTP helpers |
| `lib/cache.luau` | Atomic JSON cache in `pluginDataDir()`, capped at 16 games |
| `lib/format.luau` | Clamp, rounding, thousands grouping and relative time |

Only the service touches Steam files and the network. The card imports only
`lib/format.luau` and never reads `/proc` or Steam's directories.

## Detection

Steam appends to `logs/gameprocess_log.txt`:

```text
[2026-11-05 19:23:00] AppID 2943650 adding PID 358960 as a tracked process
[2026-11-05 20:11:29] Remove 2943650 from running list
```

Every three seconds the service scans the last 512 KiB of the log with
`tail | grep` and hands only the last 200 launch/remove events to Luau. That
keeps the async callback under Noctalia's CPU budget. The detector:

1. Collects `AppID N adding PID P` events and their byte positions.
2. Collects `Remove N from running list` events.
3. Drops an AppID whose remove event is newer than its last launch event.
4. Checks `/proc/P/stat` and rejects zombies.
5. Filters known runtimes (Steam Linux Runtime, Steamworks Common
   Redistributables, Proton).
6. Returns the most recently started AppID that still has a live process.

The 200-event window is enough for a live game: a launch produces dozens of
tracked PIDs, and no newer game can start without adding more events. The
512 KiB scan keeps the shell-side work cheap while still covering weeks of log
history.

## Data flow

```text
SteamCharts app page   -> current, 24h peak, all-time peak, name
SteamCharts chart JSON -> hourly points, current, 24h peak, first-point date
Valve current endpoint -> more frequent live current count
```

Refreshes:

- detection: every `detect_interval` seconds
- live count: every `current_refresh` seconds
- page and chart: every `stats_refresh` seconds

Each HTTP request has a 45-second in-flight timeout. Late callbacks are ignored
through a per-request run counter. A successful refresh writes the cache at most
once every two minutes; a game change writes immediately.

## State schema

```text
steam_stats = {
  ts, seq, status, source,
  game = {
    appid, name, header, started_at
  } | nil,
  stats = {
    current, peak_24h, peak_all_time, peak_at,
    history = { 0..1, ... },
    chart_at, page_at, updated_at
  }
}
```

`status` is one of `idle`, `no_steam`, `loading`, `ok`, `partial` or `error`.

`history` is already normalised against the 24-hour peak, so the card passes it
straight to `ui.graph`. The graph and the `peak_24h` value come from the same
SteamCharts series.

## Files

| Path | Purpose |
| --- | --- |
| `<pluginDataDir>/cache.json` | Last good values for up to 16 AppIDs |
| `<pluginDataDir>/header_v2_<appid>.jpg` | Cached store header per AppID |

Install locations:

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/steamdb-stats` | `~/.local/state/noctalia` | `noctalia` |
| Noctalia KWE | `~/.local/share/noctalia-kwe/plugins/steamdb-stats` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME`, `XDG_DATA_HOME`, `NOCTALIA_STATE_HOME` and
`XDG_STATE_HOME`.

## Why not SteamDB directly

SteamDB blocks automated clients:

- `/api/GetGraph/...` → HTTP 410
- `/app/...` → HTTP 403 (Cloudflare)

SteamCharts exposes the same three values on its app page and a chart-data JSON
series with recent hourly points. The port attributes the source in the card's
footer and caches aggressively instead of retrying against SteamDB.

## Card alignment

`card.luau` defaults to the Modern SysMonitor Plus metrics:

- width 320, padding 10, radius 8
- inner fill `surface_variant` at 0.35
- border `outline` at 1
- graph height 32, line width 1.5, fill opacity 0.15

Changing `graph_height` to 20 matches the SysMonitor GPU usage row; 32 matches
the network chart.

## Overlay limits

This is a normal `[[desktop_widget]]`, not a `[[layer]]` entry. It cannot draw
above a fullscreen game. A click-through overlay needs plugin API 36
(`[[layer]]` with `click_through = true`), which Noctalia KWE 5.3.0 does not
provide. The KBM Overlay port documents the same limitation.

## Development

- `.luau` changes hot-reload the owning entry and any module it required.
- `plugin.toml` changes need `noctalia-kwe msg config-reload`; disable/enable
  once if a new setting is not recognised.
- `noctalia-kwe msg desktop-widgets-edit` opens the widget editor.
- Logs: `journalctl --user -n 200 --no-pager | grep -iE 'steamdb-stats|plugin'`.

Manual detection check:

```bash
tail -n 20 ~/.local/share/Steam/logs/gameprocess_log.txt
grep -E 'AppID .* adding PID|Remove .* from running list' \
  ~/.local/share/Steam/logs/gameprocess_log.txt | tail
```

If the card is stuck on an old game, check that the tracked PID still exists:

```bash
ps -p <pid> -o pid,stat,cmd
```
