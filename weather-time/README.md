# Weather & Time

A location-aware clock and weather plugin for Noctalia with a full desktop card,
a compact bar capsule, a setup panel and an optional procedural full-bleed
weather scene.

## Plugin

| Field | Value |
| --- | --- |
| ID | `linuxgamerlife/weather-time` |
| Bar widget | `bar` |
| Desktop widget | `card` |
| Panel | `setup` |
| Service | `fetcher` |

## Requirements

- Noctalia Shell with plugin API 24 or newer.
- Network access for weather and city search. The clock works offline; weather
  is opt-in until you choose a location.
- No external CLI tools or manifest dependencies.

## Usage

Enable **Weather & Time** in **Settings → Plugins**, then add the desktop card
and/or the bar capsule. The clock works immediately; choose a location to enable
weather.

Open the setup panel with:

```sh
noctalia msg panel-toggle linuxgamerlife/weather-time:setup
```

The panel supports city search, manual latitude/longitude entry, importing a
manual location from Noctalia, unit and clock settings, and privacy status. No
automatic IP geolocation is performed.

The desktop card shows the clock, date, current conditions, a three-day forecast,
feels-like temperature, wind, humidity, precipitation, location and data age.
The optional **scene** draws a static procedural sky, grass and rain/snow image
behind the card text. If the scene is off, the card uses a plain surface.

The bar capsule shows the clock or weather summary; click it to open the setup
panel.

## Settings

### Plugin settings

| Setting | Default | Description |
| --- | --- | --- |
| `refresh_minutes` | `15` min | Forecast refresh interval. |
| `units` | `auto` | `auto`, metric or imperial display units. |
| `clock_source` | `auto` | Clock source: automatic, system or a configured timezone. |
| `clock_format` | `auto` | 12-hour, 24-hour or automatic. |
| `show_seconds` | off | Show seconds in the clock. |
| `date_style` | `auto` | Date format style. |
| `secondary_timezone` | empty | Optional second timezone. |
| `secondary_label` | `Home` | Label for the second timezone. |
| `scene` | `auto` | Scene mode: automatic, off or a fixed scene category. |
| `scene_theme` | `auto` | Scene colour theme: automatic, light or dark. |

### Desktop card

The card starts with the host background controls and group toggles:

- **Show card settings** — title, content width, layout, plain-card fill/border
  and host panel controls.
- **Show styling controls** — text, muted, weather-icon and divider colours,
  automatic scene text.
- **Show scaling controls** — text scale, small-text scale, clock size and
  forecast glyph size.
- **Show section toggles** — header, date, condition text, forecast, details,
  location, update age, attribution and compact layout.

Key settings:

| Setting | Default | Description |
| --- | --- | --- |
| `content_width` | `380` px | Card content width. |
| `show_scene` | on | Draw the procedural weather scene behind the card text. |
| `text_scale` | `1.0` | Main text scale multiplier. |
| `small_text_scale` | `1.0` | Small-text scale multiplier. |
| `clock_size` | `64` px | Clock size. |
| `forecast_glyph_size` | `20` px | Forecast icon size. |
| `forecast_days` | `3` | Number of forecast days shown. |
| `show_date` | on | Show the date line. |
| `show_condition_text` | on | Show the current condition text. |
| `show_forecast` | on | Show the forecast strip. |
| `show_details` | on | Show feels-like, wind, humidity and precipitation. |
| `show_location` | on | Show the location label. |
| `show_updated` | on | Show the data-age line. |
| `show_attribution` | on | Show the Open-Meteo attribution. |
| `compact_layout` | off | Use the compact card spacing. |
| `text_color` | `on_surface` | Primary text colour; explicit values override the scene colours. |
| `muted_text_color` | `on_surface_variant` | Secondary text colour. |
| `weather_color` | `primary` | Current-condition icon colour. |
| `divider_color` | `outline` | Divider colour. |

The card also declares the standard host-panel settings (`background_color`,
`background_opacity`, `background_radius`, `background_padding`).

### Bar widget

| Setting | Default | Description |
| --- | --- | --- |
| `mode` | `weather` | Show the weather summary or the clock. |
| `show_temperature` | on | Show the temperature beside the glyph. |
| `show_condition` | off | Show the condition text. |
| `glyph` | `weather-cloud` | Bar icon. |

## Notes

- The service writes `location.json` and `weather.json` under the plugin data
  directory with mode 600. `weather.json` contains no coordinates.
- Weather and geocoding use the Open-Meteo APIs. Requests send the rounded
  latitude/longitude (two decimals) for a forecast, or the search text for a
  city lookup. No account key, profile, device id or analytics data is sent.
- The plugin never performs IP-based automatic geolocation and never imports
  Noctalia's IP-derived location unless you explicitly press the import button.
- Offline mode makes no requests and keeps the clock working. A failed forecast
  shows the last cached data with a stale marker and a retry delay.
- The procedural scene is generated locally as an SVG; weather data is by
  Open-Meteo under CC BY 4.0.
- See [PRIVACY.md](PRIVACY.md) for the full data-flow and cache description.

## Credits and License

Weather data by [Open-Meteo](https://open-meteo.com/) under
[CC BY 4.0](https://open-meteo.com/en/license). The widget is an LGL
implementation for Noctalia and Noctalia KWE.

MIT — see [LICENSE](LICENSE).
