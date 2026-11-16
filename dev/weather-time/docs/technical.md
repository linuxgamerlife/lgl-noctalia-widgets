# Weather & Time — plugin reference

This is the technical companion to the app [README](../README.md). It covers
entries, the published state, the cache format, the provider, the procedural
scene and debugging.

## Entries

| Entry | Kind | File | Role |
| --- | --- | --- | --- |
| `fetcher` | `[[service]]` | `service.luau` | Location file, HTTP, cache, scheduling, scene generation, state |
| `card` | `[[desktop_widget]]` | `card.luau` | Full clock + weather card |
| `bar` | `[[widget]]` | `bar.luau` | Compact clock/temperature capsule |
| `setup` | `[[panel]]` | `panel.luau` | Location search, manual coordinates, import, status/privacy |

`plugin_api = 24` gives relative module `require`, services starting on enable,
timezone-aware `formatTime`, and direct-argv `runAsync` for `chmod`.

## Modules

| File | Responsibility |
| --- | --- |
| `lib/config.luau` | Clamped settings readers and colour-alpha helper |
| `lib/location.luau` | Coordinate validation, 2-decimal rounding, public projection |
| `lib/forecast.luau` | Open-Meteo payload normalization, past-day filtering, cache restore |
| `lib/privacy.luau` | Public state projection, sanitized errors, coordinate-key guard |
| `lib/cache.luau` | Atomic `location.json` / `weather.json`, mode `600` |
| `lib/scheduler.luau` | Refresh interval, due checks, bounded exponential backoff |
| `lib/scene.luau` | Deterministic static SVG scene writing |
| `lib/wmo.luau` | WMO code → condition key / glyph / scene category |
| `lib/date.luau` | ISO date parsing, weekday, noon epoch, day arithmetic |
| `lib/format.luau` | Rounding, units, age, display strings |
| `lib/units.luau` | Unit-system resolution and display unit names |
| `providers/openmeteo.luau` | Forecast URL builder + HTTP transport |
| `providers/geocode.luau` | Explicit city search + result validation |

The service composes the data modules. The card, bar and panel import only pure
format/render modules; they never call HTTP or read location coordinates.

## State

Key: `weather_time`

```lua
{
  ts, seq,
  units = { temperature = "c", wind = "kmh", precipitation = "mm" },
  provider = "open-meteo",
  location = { label, timezone, source },  -- no coordinates
  timezone, timezone_abbreviation, utc_offset_seconds,
  current = {
    temp_c, feels_like_c, code, is_day, wind_kmh, wind_direction_deg,
    humidity, precipitation_mm, uv_index, condition_key, category,
  },
  today = { max_c, min_c, sunrise, sunset },
  forecast = { { date, code, max_c, min_c, precip_prob, sunrise, sunset }, ... },
  fetched_at, refresh_minutes, next_refresh_at,
  stale, error,          -- error = { reason, status? } | nil
  scene = { variant, image = "/abs/scene.svg" } | nil,
}
```

`current`, `today` and `forecast` are canonical metric. The card converts at
render time so the same state serves metric and imperial surfaces. `forecast[1]`
is today; the card's strip starts at `forecast[2]`.

The service calls `privacy.assert_public()` before every publish. A coordinate
key in the public tree is a hard error in tests.

## Cache

| File | Contents | Mode |
| --- | --- | --- |
| `location.json` | `version`, `label`, `latitude`, `longitude`, `timezone`, `source` | `600` |
| `weather.json` | `version`, `provider`, `location` (no coordinates), `timezone`, `utc_offset_seconds`, `current`, `today`, `forecast`, `fetched_at` | `600` |

Writes are `write temp → chmod 600 → rename`. Existing scene images are reused
on restart; corrupt JSON is ignored and rewritten on the next success.

On a location change the service clears `weather.json` before the new fetch so
the old city's forecast cannot be shown under a new label.

## Refresh and errors

- Default refresh: 15 minutes; selectable 5/10/15/30/60/120.
- One in-flight request; a second due tick is ignored.
- Failure backoff: `refresh × 2^(failures-1)` minutes, capped at 60.
- A request still in flight after 45 s is abandoned and counted as a failure.
- `noctalia.http` returns no response headers, so `Retry-After` is not read.
- Sanitized reasons: `offline`, `parse`, `timeout`, `http_status`, `request`.
- The last good forecast stays visible with `stale = true` and a dimmed card.

## Forecast request

```text
https://api.open-meteo.com/v1/forecast
  ?latitude=<2dp>&longitude=<2dp>
  &current=temperature_2m,apparent_temperature,relative_humidity_2m,
           weather_code,is_day,wind_speed_10m,wind_direction_10m,
           precipitation,uv_index
  &daily=weather_code,temperature_2m_max,temperature_2m_min,
          sunrise,sunset,precipitation_probability_max
  &timezone=auto
  &forecast_days=8
  &temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm
```

`follow_redirects = false`. Bodies larger than 2 MiB are rejected. The request
is one GET per refresh; there is no polling on the card.

Geocoding is a separate, explicit request:

```text
https://geocoding-api.open-meteo.com/v1/search?name=<query>&count=5&language=en&format=json
```

## Full-bleed scene

Noctalia's declarative UI has no z-index. The card creates a two-child column:

```lua
ui.column({ width = W, gap = -H }, {
  ui.image({ path = scene.image, width = W, height = H, fit = "cover", radius = R }),
  ui.column({ width = W, height = H, padding = P, gap = 8 }, content),
})
```

The negative gap makes the second child overlap the first; the content is drawn
after the image, so real text sits on top. The scene is generated by the service
as an SVG at 800 × 460 and cropped with `fit = "cover"`.

Variants: `clear`, `cloudy`, `rain`, `snow`, `thunder`, `fog`, each in `_day`
and `_night`. Each variant is one static SVG image. There is no frame swapping,
texture rotation or per-frame render; this is deliberate so large cards stay
cheap. A different condition or day/night state swaps to another static image.

Scene element groups:

- linear sky gradient;
- deterministic starfield;
- sun/moon with glow (only on clear scenes);
- soft clouds with day/night palettes;
- rain lines, snow circles, lightning polyline or fog bands;
- two grass silhouette layers;
- bottom shade and vignette for text contrast.

The scene contains no text and no personal data. If scene generation fails, the
card falls back to the plain themed surface.

**Show background scene** is a per-card toggle. Turning it off skips the image
layer and renders the clock, condition glyphs and text directly. The plain card
fill defaults to transparent (`card_fill_opacity = 0`) and the border to `0`, so
only the text and icons remain; the Noctalia host panel background is separate.

**Compact layout** uses 10 px padding, caps the clock at 40 px, hides the
details row, hides the timezone/secondary clock and hides footer labels. Its
height is computed from the visible rows so short tiles never compress the main
row into the forecast row.

## Settings

Plugin-level: `refresh_minutes`, `units`, `clock_source`, `clock_format`,
`show_seconds`, `date_style`, `secondary_timezone`, `secondary_label`, `scene`,
`scene_theme`.

Desktop card: host background controls, group toggles, `show_scene`
(background image on/off), title/width/layout,
header/date/condition/forecast/details/location/update/attribution/compact,
plain-card fill/border, text/muted/weather-icon/divider colours, automatic
scene text, text scale, small-text scale, clock size, forecast glyph size. Explicit
colour values override the automatic scene colours.

Bar: `mode`, `show_temperature`, `show_condition`, `glyph`.

See `plugin.toml` and `translations/en.json` for defaults and descriptions.

## Debugging

```bash
noctalia-kwe plugins lint weather-time
noctalia-kwe msg config-reload
noctalia-kwe msg plugins disable linuxgamerlife/weather-time
noctalia-kwe msg plugins enable linuxgamerlife/weather-time
journalctl --user -n 200 --no-pager | grep -iE 'weather-time|script-runtime'
```

Useful checks:

```bash
# Confirm the cache has no coordinates:
grep -iE 'latitude|longitude' \
  ~/.local/state/noctalia-kwe/plugins/data/linuxgamerlife/weather-time/weather.json

# Confirm the state is in memory only:
noctalia-kwe msg plugin linuxgamerlife/weather-time:fetcher focused refresh
```

## Tests

```bash
./tests/run.sh
```

The runner parses every `.luau` file with LuaJIT, runs the mocked tests, then
validates the manifest, catalog, translations, entry files and layout with
Python. The tests cover formatting, units, WMO codes, dates, location privacy,
forecast normalization, scene generation, service fetch/failure, no-location
privacy, location-clock timezone selection, card, bar, panel and service+card
integration.

## Licence

MIT — see [LICENSE](LICENSE). Weather data by
[Open-Meteo](https://open-meteo.com/) under
[CC BY 4.0](https://open-meteo.com/en/license).
