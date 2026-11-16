# Privacy — LGL Weather & Time

This document describes exactly what LGL Weather & Time sends, stores and
exposes. It is intentionally short and concrete.

## Summary

The plugin is a clock first. Weather is opt-in: until you set a location, it
makes **no network requests**. It never performs IP geolocation and never asks
Noctalia for the result of its own IP-based auto-location.

## What leaves your machine

| Action | Data | Destination | When |
| --- | --- | --- | --- |
| Clock only | Nothing | — | Always |
| City search | The text you type | `geocoding-api.open-meteo.com` | Only when you press Search / Enter |
| Forecast | Latitude/longitude rounded to 2 decimals, your IP address, TLS metadata | `api.open-meteo.com` | One HTTPS GET per refresh, including startup/manual refresh when due |
| Import Noctalia manual coordinates | Rounded coordinates | `api.open-meteo.com` | Explicit button press, then the next forecast request |
| Import Noctalia address | The address text | `geocoding-api.open-meteo.com` | Explicit button press, only when `auto_locate` is false and an address is set |
| Offline mode | Nothing | — | `noctalia.http` refuses the request |

Open-Meteo sees the requesting IP and the approximate location. That is
unavoidable for a local forecast: a weather service cannot answer “what is the
weather here?” without knowing roughly where “here” is.

The plugin does **not** send your precise coordinates, an account id, an API
key, a user profile, a device id, analytics events, or your browsing history.
Requests use `follow_redirects = false` so the coordinates cannot leak to a
third-party host through a redirect.

## What is stored locally

Under Noctalia's per-plugin data directory:

| Path | Contents | Mode |
| --- | --- | --- |
| per-plugin data directory | Container for the files below | `700` |
| `location.json` | Label, latitude/longitude rounded to 2 decimals, IANA timezone, source | `600` |
| `weather.json` | Normalized forecast, display label, timezone, timestamps — **no coordinates** | `600` |
| `scenes/*.svg` | Generated scenery for the card; no personal data | default, inside the `700` directory |

- The plugin requests mode `700` on the per-plugin data directory before
  writing, and mode `600` on the temp and final files. The host's `chmod` runs
  asynchronously, so its final on-disk state is `700`/`600`; during the very
  first write there is a short window where the host-created path still uses the
  process umask. The stored files contain only one coarse location and a
  forecast, and the uninstall scripts remove the directory.
- `location.json` is the only file with coordinates.
- There is exactly one location and one last-good forecast. There is no
  history, no “recently viewed” list and no analytics database.
- The plugin never writes into its git/runtime plugin directory.

## What is published in memory

The service publishes `weather_time` through `noctalia.state`. It contains:

- the display label, timezone and timezone abbreviation;
- current conditions and forecast values;
- timestamps, status and sanitized error reasons;
- generated scene file paths.

It does **not** contain latitude or longitude. The card, bar and panel cannot
read the location file's coordinates through the state channel.

## Logs and errors

Logs contain short reasons such as `fetch failed: http_status (500)` or
`cache write failed`. They do not contain request URLs, coordinates, response
bodies or location labels. The panel's status section shows a sanitized reason
so you can tell “offline” from “rate limited” without exposing the query.

## Deleting your data

- **Forget location** in the setup panel removes both `location.json` and
  `weather.json` and returns the card to clock-only mode. Generated scene files
  are left in place (they contain no personal data) and are removed by the
  uninstall scripts.
- The uninstall scripts remove the plugin payload and its entire per-plugin data
  directory.
- You can also delete the directory manually; nothing else references it.

## Noctalia integration

When the host exposes `noctalia.getSetting`:

- it reads the `location` table only when you press an import button;
- it uses `location.latitude` / `location.longitude` only for **Use manual
  coordinates**, and only if `location.auto_locate` is false;
- it uses `location.address` as the saved label for **Use manual coordinates**
  and as the geocoding query for **Look up address**;
- if `location.auto_locate` is true, the plugin refuses to import it and tells
  you to set a manual location instead.

The plugin may read `weather.unit` to follow your unit preference. It does not
use or reuse any IP-derived coordinates.

## Third parties

- [Open-Meteo](https://open-meteo.com/) — forecast and geocoding. Data is
  provided under [CC BY 4.0](https://open-meteo.com/en/license).
- Noctalia itself — host panel, state channel, HTTP client and configuration.
- No other service is contacted by this plugin.

## Changes

If a future version adds a provider, an account or a new network destination,
this document and the in-plugin privacy note must be updated first.
