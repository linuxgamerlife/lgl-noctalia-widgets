-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Integration: real service publishes state, real card renders it.
local mock = dofile("tests/support/mock.luau")

local payload = {
  timezone = "Europe/London",
  timezone_abbreviation = "GMT",
  utc_offset_seconds = 0,
  current = {
    time = "2026-10-29T13:56",
    temperature_2m = 16.6,
    apparent_temperature = 14.8,
    relative_humidity_2m = 53,
    weather_code = 3,
    is_day = 1,
    wind_speed_10m = 7.2,
    wind_direction_10m = 100,
    precipitation = 0,
    uv_index = 0.1,
  },
  daily = {
    time = { "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05" },
    weather_code = { 3, 1, 3, 51, 51, 51, 51, 2 },
    temperature_2m_max = { 16.6, 15.7, 14.4, 11, 12.3, 11.8, 12.1, 12 },
    temperature_2m_min = { 12.4, 10.6, 10.1, 9.5, 8.6, 7.7, 8.2, 8 },
    precipitation_probability_max = { 2, 0, 0, 4, 12, 8, 4, 1 },
    sunrise = { "2026-10-29T06:48", "2026-10-30T06:50", "2026-10-31T06:52", "2026-11-01T06:53", "2026-11-02T06:55", "2026-11-03T06:57", "2026-11-04T06:59", "2026-11-05T07:01" },
    sunset = { "2026-10-29T16:39", "2026-10-30T16:37", "2026-10-31T16:35", "2026-11-01T16:33", "2026-11-02T16:31", "2026-11-03T16:30", "2026-11-04T16:28", "2026-11-05T16:26" },
  },
}

local ctx = mock.new({
  config = {
    refresh_minutes = "15",
    units = "metric",
    clock_source = "auto",
    clock_format = "24h",
    show_seconds = false,
    date_style = "short",
    secondary_timezone = "",
    secondary_label = "Home",
    scene = "auto",
    scene_theme = "auto",
    content_width = 380,
    card_gap = 8,
    card_padding = 16,
    card_radius = 14,
    card_fill_color = "surface_variant",
    card_fill_opacity = 0.35,
    card_border_color = "outline",
    card_border_width = 1,
    text_color = "on_surface",
    muted_text_color = "on_surface_variant",
    weather_color = "primary",
    divider_color = "outline",
    divider_width = 1,
    scene_auto_text = true,
    text_scale = 1,
    clock_size = 64,
    forecast_glyph_size = 20,
    show_header = false,
    show_date = true,
    show_condition_text = true,
    show_forecast = true,
    forecast_days = "3",
    show_details = true,
    show_location = true,
    show_updated = true,
    show_attribution = true,
    compact_layout = false,
  },
  files = {
    ["/data/location.json"] = {
      version = 1,
      label = "London, United Kingdom",
      latitude = 51.51,
      longitude = -0.13,
      timezone = "Europe/London",
      source = "manual",
    },
  },
  data_dir = "/data",
  http_responses = { { ok = true, status = 200, body = payload } },
  dark = true,
})

mock.loadEntry("service.luau")
assert(ctx.state.weather_time ~= nil, "service state")
mock.loadEntry("card.luau")
local tree = ctx.desktop_tree
assert(mock.find(tree, "weather-temp") ~= nil, "card temperature")
assert(mock.find(tree, "scene-image") ~= nil, "card scene")
assert(mock.find(tree, "forecast") ~= nil, "card forecast")
assert(mock.find(tree, "clock") ~= nil, "card clock")

print("INTEGRATION TEST OK")
