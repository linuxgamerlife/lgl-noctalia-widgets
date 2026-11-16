# Noctalia plugin notes — LGL SteamDB Stats

This is the Noctalia-specific companion to the app README. It covers the API
surface, entries, state flow, data sources, overlay limits and development
commands.

## Plugin API and entries

`plugin.toml` declares `plugin_api = 24` and two entries:

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `poller` | `[[service]]` | `service.luau` | Detect the Steam game, fetch stats, publish `steam_stats` |
| `card` | `[[desktop_widget]]` | `card.luau` | Render the summary and 24-hour graph |

API levels used:

| Level | Capability | Why it is needed |
| --- | --- | --- |
| 15 | `noctalia.openSettings()` | Header settings button |
| 17 | Services start on enable | The poller is a service |
| 24 | Relative module `require`, `noctalia.http` | `lib/` modules and HTTP |

The service and card are separate Luau VMs. They exchange only plain values
through `noctalia.state` under the key `steam_stats`; no functions, userdata or
file handles cross the boundary.

## Modules

| File | Responsibility |
| --- | --- |
| `service.luau` | Composition entry: settings, timers, detection, HTTP, cache, publishing |
| `card.luau` | Declarative card, stat cells, graph, idle state |
| `lib/steam.luau` | Steam root, log replay, `/proc` liveness, manifests |
| `lib/steamcharts.luau` | SteamCharts page/chart parser and HTTP transports |
| `lib/cache.luau` | Atomic JSON cache |
| `lib/format.luau` | Number grouping and relative time |

Only `service.luau` composes the filesystem and network modules. `card.luau`
imports only `lib/format.luau`.

## Install locations

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/steamdb-stats` | `~/.local/state/noctalia` | `noctalia` |
| KineticWE `noctalia-kwe` | `~/.local/share/noctalia-kwe/plugins/steamdb-stats` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`. The install scripts create
a symlink to the repo's `steamdb-stats/` directory, so repository edits are
visible to the shell immediately.

The plugin writes `<pluginDataDir>/cache.json` and one
`<pluginDataDir>/header_v2_<appid>.jpg` per detected game. It removes those
files on uninstall with the rest of the plugin data directory. Headers come
from Valve's store `appdetails` API, with SteamCharts as the fallback.

## Detection flow

```text
logs/gameprocess_log.txt
  -> AppID N adding PID P
  -> AppID N no longer tracking PID P
  -> Remove N from running list
  -> /proc/P/stat (reject Z/X)
  -> appmanifest_<appid>.acf name
  -> steam_stats.game
```

Every `detect_interval` seconds the service runs:

```sh
tail -c 524288 -- <log> \
  | grep -aE 'AppID [0-9]+ adding PID [0-9]+|Remove [0-9]+ from running list' \
  | tail -n 200
```

The shell does the large scan; only the last 200 relevant events cross into
Luau. That is enough for a live game (a launch produces dozens of tracked PIDs)
and keeps the async callback under Noctalia's CPU budget.

Known non-game AppIDs are filtered:

- Steam Linux Runtime (1.0, 2.0, 3.0)
- Steamworks Common Redistributables
- Proton Experimental, Proton Hotfix and numbered Proton builds

## Data flow and caching

```text
SteamCharts /app/<id>              -> current, 24h peak, all-time peak, name
SteamCharts /app/<id>/chart-data   -> hourly series, current, 24h peak, peak date
Valve GetNumberOfCurrentPlayers    -> live count
```

- Detection: every `detect_interval` seconds (default 3).
- Live count: every `current_refresh` seconds (default 60).
- Page/chart: every `stats_refresh` seconds (default 600).
- In-flight timeout: 45 seconds; late callbacks are ignored by a run counter.
- Cache writes: at most once every two minutes, plus immediately on a game
  change or a successful chart refresh.

The chart series provides both the 24-hour peak and the graph, so the displayed
number and the graph's high point agree. The all-time peak comes from the page.

## State schema

```text
steam_stats = {
  ts, seq, status, source,
  game = { appid, name, header, started_at } | nil,
  stats = {
    current, peak_24h, peak_all_time, peak_at,
    history = { 0..1, ... },
    chart_at, page_at, updated_at
  }
}
```

`status`: `idle`, `no_steam`, `loading`, `ok`, `partial`, `error`.

## Settings

### Plugin-level

| Key | Type | Default | Meaning |
| --- | --- | ---: | --- |
| `detect_interval` | int | 3 | Seconds between Steam log checks (2–15) |
| `current_refresh` | int | 60 | Seconds between live-count refreshes (30–300) |
| `stats_refresh` | int | 600 | Seconds between page/chart refreshes (300–3600) |

Changing the interval calls `noctalia.setUpdateInterval()` in place through
`onConfigChanged()`. A config change also forces one live and chart refresh.

### Desktop card

- sections: `hide_when_idle`, `show_title`, `show_settings_button`,
  `show_cover`, `show_current`, `show_peak_24h`, `show_peak_all_time`,
  `show_graph`, `show_attribution`
- layout: `title`, `content_width`, `card_gap`, `card_padding`, `card_radius`,
  `card_fill_color`, `card_fill_opacity`, `card_border_color`,
  `card_border_width`
- styling: `accent_color`, `text_color`, `muted_text_color`, `graph_color`
- scaling: `graph_height`, `graph_line_width`, `graph_fill_opacity`,
  `text_scale`
- host surface: `background`, `background_color`, `background_opacity`,
  `background_radius`, `background_padding`

Noctalia renders the desktop-widget inspector as a single column. The
`show_card_settings`, `show_styling`, `show_scaling` and `show_sections`
toggles keep the long lists collapsed until needed; stored values stay active.
The host background controls are declared first and duplicated in the host's
own Background section.

## Alignment with Modern SysMonitor Plus

Default card metrics match the SysMonitor card:

| Metric | Value |
| --- | ---: |
| `content_width` | 320 |
| `card_padding` | 10 |
| `card_radius` | 8 |
| `card_fill_color` | `surface_variant` |
| `card_fill_opacity` | 0.35 |
| `card_border_color` | `outline` |
| `graph_height` | 32 |
| `graph_line_width` | 1.5 |
| `graph_fill_opacity` | 0.15 |

Noctalia has no shared multi-widget layout container. Place the two desktop
widgets in the same column in the editor; matching the width and padding makes
their graph rows line up.

## Overlay limits

There is no `[[layer]]` entry and no click-through overlay. The visual is a
normal desktop widget. A true overlay above a fullscreen game needs plugin API
36 (`[[layer]]` with `click_through = true`), which the current KWE 5.3.0
baseline does not provide. The KBM Overlay port documents the same constraint.

## Reloading during development

- `.luau` changes hot-reload the owning entry. A change in `lib/` reloads every
  entry that successfully required the module.
- `plugin.toml` changes need `noctalia-kwe msg config-reload`; disable/enable
  once if a new setting is not recognised.
- Desktop-widget settings controls are rebuilt when the widget editor opens.
- Check logs:
  `journalctl --user -n 200 --no-pager | grep -iE 'steamdb-stats|plugin'`.

## Manual checks

```bash
# Manifest and entry lint
noctalia-kwe plugins lint /path/to/lgl-noctalia-widgets/steamdb-stats

# Steam's own launch log
tail -n 20 ~/.local/share/Steam/logs/gameprocess_log.txt

# Confirm a tracked PID is still alive
ps -p <pid> -o pid,stat,cmd

# Player endpoints used by the service
curl -s 'https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=2943650'
curl -s 'https://steamcharts.com/app/2943650/chart-data.json' | head -c 200
```

## Related

- [App README](../README.md) — install, features, settings, troubleshooting
- [technical reference](technical.md) — technical reference
- [catalog.toml](../../../catalog.toml) — source catalog metadata
