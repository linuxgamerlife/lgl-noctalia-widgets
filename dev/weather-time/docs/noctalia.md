# Noctalia plugin notes — Weather & Time

This is the Noctalia-specific companion to the app README. It covers the plugin
API surface, entries, state flow, reloads and debugging commands.

## Plugin API and entries

`plugin.toml` declares `plugin_api = 24` and four entries:

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `fetcher` | `[[service]]` | `service.luau` | Location, HTTP, cache, scene assets, state |
| `card` | `[[desktop_widget]]` | `card.luau` | Full clock + weather card |
| `bar` | `[[widget]]` | `bar.luau` | Compact bar capsule |
| `setup` | `[[panel]]` | `panel.luau` | Location search and status |

API levels used:

| Level | Capability | Why it is needed |
| --- | --- | --- |
| 17 | services start on enable | `fetcher` |
| 19 | timezone-aware `formatTime`, `timeFormat`, `dateFormat`, `isValidTimezone` | Location clock |
| 22 | relative module `require` | `lib/` and `providers/` |
| 24 | direct-argv `runAsync` | `chmod 600` on cache files |

`noctalia.http` is part of the base scripting API. `noctalia.getSetting` is
optional and feature-detected: when it exists, the panel can import Noctalia's
**manual** location or address; when it does not, the plugin still works from
its own location file.

The service, card, bar and panel are separate Luau VMs. They exchange only plain
values through `noctalia.state` under `weather_time`. No functions, userdata or
file handles cross the boundary.

## State flow

```text
location.json ──┐
                ├─ service fetcher ── state.weather_time ── card
weather.json ───┘        │                     │
Open-Meteo HTTPS ────────┘                     ├─ bar
                                              └─ panel
```

- `service.luau` calls `lib/service.start()`.
- The service publishes immediately on start (cached state or clock-only),
  then on fetch success/failure and a 60-second heartbeat.
- The card watches `weather_time` and re-renders; it also uses a 200 ms update
  interval while an animated scene is active, otherwise 1 s.
- The bar watches the same key and updates every 15 s (1 s with seconds).
- The panel watches the same key and updates every 30 s.

### Refresh and location revisions

The panel writes `location.json`, then increments:

- `weather_time_location_rev` — the service reloads the location, clears the old
  weather cache and fetches immediately.
- `weather_time_refresh_seq` — the service forces a fetch.

The service watches both keys. This is the same in-memory revision pattern used
by AI Usage; no IPC is required.

## Install locations

| Shell | Plugin directory | State directory | CLI |
| --- | --- | --- | --- |
| Upstream Noctalia | `~/.local/share/noctalia/plugins/weather-time` | `~/.local/state/noctalia` | `noctalia` |
| KineticWE `noctalia-kwe` | `~/.local/share/noctalia-kwe/plugins/weather-time` | `~/.local/state/noctalia-kwe` | `noctalia-kwe` |

Both honour `NOCTALIA_DATA_HOME` and `XDG_DATA_HOME`. The install scripts create
a symlink to the repository's `weather-time/` directory, so edits are visible
immediately. Per-plugin data lives under
`<state>/<app>/plugins/data/linuxgamerlife/weather-time`.

## Reloading during development

- **`.luau` changes** hot-reload the owning entry. A change in `lib/` or
  `providers/` reloads every entry that successfully required it.
- **`plugin.toml` changes** need a config reload:

  ```bash
  noctalia-kwe msg config-reload
  ```

  If a new setting is not recognised, disable and re-enable the plugin once:

  ```bash
  noctalia-kwe msg plugins disable linuxgamerlife/weather-time
  noctalia-kwe msg plugins enable linuxgamerlife/weather-time
  ```

- **Desktop-widget settings controls** are built from the manifest when the
  editor opens. Close and reopen the editor after changing a
  `[[desktop_widget.setting]]`.
- **Plugin-level settings** live in `[plugin_settings."linuxgamerlife/weather-time"]`
  in the state `settings.toml`. Prefer the Settings UI.

## Manual checks

```bash
# Discover / lint the installed plugin
noctalia-kwe plugins lint weather-time

# Check the live plugin list
noctalia-kwe msg plugins list

# Force a config reload after editing plugin.toml
noctalia-kwe msg config-reload

# Open the desktop-widget editor
noctalia-kwe msg desktop-widgets-edit
noctalia-kwe msg desktop-widgets-exit

# Inspect logs
journalctl --user -n 200 --no-pager | grep -iE 'weather-time|script-runtime|plugin'
```

Check the cache does not contain coordinates:

```bash
grep -iE 'latitude|longitude' \
  ~/.local/state/noctalia-kwe/plugins/data/linuxgamerlife/weather-time/weather.json
```

Check the scene assets were generated:

```bash
find ~/.local/state/noctalia-kwe/plugins/data/linuxgamerlife/weather-time/scenes \
  -maxdepth 2 -type f | sort
```

## Full-bleed card note

Noctalia's `ui.*` vocabulary has no z-index. The card uses a two-child flex
column with `gap = -card_height`: the generated scene image first, then the real
content column of the same height. The second child is drawn after the image, so
the clock and weather text sit on top. This was verified on a live `noctalia-kwe`
session. If a future host adds a background-image prop, the negative gap can be
replaced with that prop without changing the scene generator.

## Tests

`tests/run.sh` parses every `.luau` file with LuaJIT, runs the mocked tests and
then checks the manifest, catalog, translations, entry files, thumbnail and
layout with Python. No live shell is needed.
