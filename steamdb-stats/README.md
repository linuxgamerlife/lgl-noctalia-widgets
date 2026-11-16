# SteamDB Stats

A Noctalia desktop card that detects the Steam game you are playing and shows
live players, the 24-hour peak, the all-time peak and a 24-hour player graph.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/steamdb-stats` |
| Desktop widget | `card` |
| Service | `poller` |

## Requirements

- Noctalia Shell with plugin API 24 or newer.
- A Steam client that writes its normal `logs/gameprocess_log.txt`.
- `curl` for the optional cached game header image.
- Network access for SteamCharts and Valve player-count queries.

Supported Steam layouts include `~/.steam/root`, `~/.steam/steam`,
`~/.local/share/Steam`, `~/.steam/debian-installation`,
`~/.var/app/com.valvesoftware.Steam/.local/share/Steam` and
`~/snap/steam/common/.local/share/Steam`.

## Usage

Enable **SteamDB Stats** in **Settings → Plugins**, then add the **SteamDB
Stats** card from the desktop-widget editor. The `poller` service starts
automatically and follows Steam's process log; no separate daemon or autostart
entry is needed.

The card updates when Steam starts or stops a game. It shows the current player
count, 24-hour peak, all-time peak and a 24-hour graph. The header cog opens the
plugin's settings.

This is a normal desktop widget. It sits on the desktop with your other widgets
and does not draw above a fullscreen game.

## Settings

### Plugin settings

| Setting | Default | Description |
| --- | --- | --- |
| `detect_interval` | `3` s | How often Steam's process log is checked for a running game (2–15 s). |
| `current_refresh` | `60` s | How often the live player count is refreshed (30–300 s). |
| `stats_refresh` | `600` s | How often the peaks and 24-hour graph are refreshed (300–3600 s). |

### Desktop card

| Setting | Default | Description |
| --- | --- | --- |
| `hide_when_idle` | off | Hide the card when Steam is not running a game. |
| `show_title` | on | Show the card title. |
| `show_settings_button` | on | Show the header settings button. |
| `show_cover` | on | Show the cached game header image. |
| `show_current` | on | Show the live player count. |
| `show_peak_24h` | on | Show the 24-hour peak. |
| `show_peak_all_time` | on | Show the all-time peak and its age. |
| `show_graph` | on | Show the 24-hour player graph. |
| `show_attribution` | on | Show the data-source attribution. |
| `content_width` | `320` px | Card content width (240–900). |
| `graph_height` | `32` px | Graph height (16–80). |
| `text_scale` | `1.0` | Card typography scale (0.5–2.0). |

The card also exposes the standard host background settings and the
`show_card_settings`, `show_styling`, `show_scaling` and `show_sections`
grouping toggles.

## Notes

- The service reads Steam's local `gameprocess_log.txt` and library manifests.
  It does not read Steam credentials or use a Steam API key.
- Player counts and the 24-hour series come from SteamCharts; the live count
  comes from Valve's `ISteamUserStats/GetNumberOfCurrentPlayers`. Game headers
  come from Valve's store API with a SteamCharts fallback.
- The plugin makes network requests only while Steam is running a detected game
  and caches the last good values per AppID in the plugin data directory.
- SteamDB itself blocks automated clients, so this port is SteamDB-style and
  not an official SteamDB client.
