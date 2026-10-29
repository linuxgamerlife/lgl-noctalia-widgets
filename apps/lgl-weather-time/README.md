<div align="center">

# LGL Weather & Time

**A privacy-first, location-aware clock and weather card for Noctalia,
with a full-bleed procedural weather scene.**

[![Version](https://img.shields.io/badge/version-0.1.0-purple)](weather-time/plugin.toml)
[![Plugin API](https://img.shields.io/badge/Noctalia_API-24-blue)](weather-time/plugin.toml)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-yellow)](LICENSE)

</div>

---

## Overview

LGL Weather & Time is a Noctalia v5 plugin built in the same style as
[LGL Modern SysMonitor Plus](../lgl-modern-sysmonitor-plus/) and
[LGL AI Usage](../lgl-ai-usage/): a headless Luau service owns the data and a
thin desktop card, bar widget and setup panel only render the published state.

It combines:

- a large, locale-aware clock and date;
- current conditions, temperature, high/low and feels-like;
- a 3/5/7-day forecast strip;
- optional wind, humidity and precipitation details;
- an optional secondary timezone;
- a full-bleed procedural scene with stars, sun/moon, clouds, grass, rain,
  snow, fog and lightning;
- a compact bar widget and a location/privacy panel.

The card's clock always works. Weather is optional until you set a location.

| Field | Value |
| --- | --- |
| Plugin ID | `linuxgamerlife/weather-time` |
| Version | `0.1.0` |
| Entries | Service `fetcher`, desktop `card`, bar `bar`, panel `setup` |
| Plugin API | 24 |
| Weather provider | [Open-Meteo](https://open-meteo.com/) |
| License | GPL-3.0-or-later |

## Privacy first

- **No automatic IP geolocation.** The plugin never calls an IP lookup and
  never reuses Noctalia's `auto_locate` result.
- **No request before a location exists.** The card starts as a clock.
- **Coordinates are rounded to two decimal places** before the forecast
  request (roughly 1.1 km of latitude).
- **Coordinates never appear in `noctalia.state`, logs, or the weather cache.**
- **Location and cache files are written atomically with mode `600`.**
- **City search is explicit.** No request is made while typing.
- **No history, analytics, cookies, accounts, or API key.**
- **Offline mode is respected** through `noctalia.http`; cached weather is
  labelled and dimmed instead of pretending to be live.

Read [PRIVACY.md](PRIVACY.md) for the full data-flow table and retention rules.
Weather data is provided by Open-Meteo under
[CC BY 4.0](https://open-meteo.com/en/license); the card and documentation credit
Open-Meteo.

## Feature map

| Mockup / expectation | Noctalia port |
| --- | --- |
| Large clock over a night scene | Real `ui.label` text over a generated SVG scene |
| Starfield, grass silhouette | Deterministic procedural SVG stars and two grass layers |
| Stars / clouds / fog | Six-frame ambient loops at 420 ms: twinkle, drift and fog breathing |
| Rain / snow / lightning | Six-frame SVG loops at 180 ms |
| Sun or moon | Scene palette and `is_day` from the forecast; shown on clear scenes |
| Current condition, temperature, high/low | Current Open-Meteo data, WMO code mapping |
| Three-day forecast | Next 3/5/7 days, excluding today |
| Location-bound time | IANA timezone returned by Open-Meteo, with system fallback; timezone shown on the date line |
| Host-panel glass | Noctalia host panel plus optional plain inner surface |
| Theme colours | Palette roles for the plain card; automatic light text over scenes |
| Settings | Plugin-level behaviour, per-card display and styling |

## Project layout

| Path | What it is |
| --- | --- |
| `weather-time/` | Plugin payload: manifest, service, card, bar, panel, `lib/`, `providers/`, translations, thumbnail |
| `docs/noctalia.md` | API levels, state flow, reload/debug notes |
| `tests/` | LuaJIT tests with a mocked Noctalia host and Python manifest checks |
| `install.sh` / `install-kwe.sh` | Install for upstream Noctalia / KineticWE's `noctalia-kwe` |
| `uninstall.sh` / `uninstall-kwe.sh` | Remove the plugin, data and widget instances |
| `remove-plugin-widgets.py` | Safe settings.toml cleanup helper |
| `catalog.toml` | Plugin-source catalog entry |

## Install

From this directory:

```bash
# KineticWE's noctalia-kwe fork
./install-kwe.sh

# Upstream Noctalia
./install.sh
```

Then open **Settings → Desktop → Toggle Editor**, add **Weather & Time**, and
click the card to set a location. The setup panel also supports manual
coordinates and an optional import of Noctalia's manual location.

## Settings summary

Plugin-level:

- refresh interval (5–120 minutes);
- units (auto / metric / imperial);
- clock source (auto / system / weather location);
- clock format (auto / 24-hour / 12-hour);
- seconds, date style, secondary timezone and label;
- scene (auto / off / fixed condition), scene theme, effect animation.

Desktop card:

- host panel background controls;
- title, width, gaps, padding, radius, plain-card fill and border;
- header, date, condition text, forecast days, details, location, update age,
  attribution, compact layout;
- primary/muted/weather-icon/divider colours, with explicit overrides applying over the scene too;
- a per-card **Show background scene** toggle for text-and-icons-only mode;
- text scale, small-text scale, clock size, forecast glyph size.

**Text-only mode:** turn off **Show background scene** to keep the clock,
weather glyphs and text without the generated image. The plain card has no fill
or border by default; the host panel background is a separate Noctalia setting.
Setting the plugin-level **Weather scene** to **Off** also stops scene
generation, while the per-card toggle only hides the image.
**Compact layout** reduces padding and the clock size, hides the details row and
hides the footer labels so the card fits a short desktop tile without overlap.

Bar widget:

- weather / clock / both;
- temperature, condition text and fallback glyph.

## Limitations

- The procedural scene is intentionally stylised; it is not a live radar or
  particle simulation.
- The forecast is refreshed every 5–120 minutes; it is not minute-by-minute.
- Open-Meteo sees the requesting IP and the rounded coordinates. Local weather
  cannot be fetched without telling a weather service roughly where you are.
- The scene is full-bleed to the widget tile, with starfield, grass and animated
  rain/snow/lightning. It does not replace Noctalia's shell-wide wallpaper
  effects; those remain owned by Noctalia.

## Related

- [PRIVACY.md](PRIVACY.md) — data flows, retention, third parties
- [weather-time/README.md](weather-time/README.md) — technical reference
- [docs/noctalia.md](docs/noctalia.md) — API, state and debugging
