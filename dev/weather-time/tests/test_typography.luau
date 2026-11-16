-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Typography: time/temp weight consistency, timezone placement and small-text scale.
local mock = dofile("tests/support/mock.luau")

local config = {
  refresh_minutes = "15",
  units = "metric",
  clock_source = "auto",
  clock_format = "24h",
  show_seconds = false,
  date_style = "short",
  secondary_timezone = "",
  secondary_label = "Home",
  scene = "off",
  scene_theme = "auto",
  content_width = 380,
  card_gap = 8,
  card_padding = 16,
  card_radius = 14,
  card_fill_color = "surface_variant",
  card_fill_opacity = 0,
  card_border_color = "outline",
  card_border_width = 0,
  text_color = "on_surface",
  muted_text_color = "on_surface_variant",
  weather_color = "primary",
  divider_color = "outline",
  divider_width = 1,
  scene_auto_text = true,
  text_scale = 1,
  small_text_scale = 1.5,
  clock_size = 64,
  forecast_glyph_size = 20,
  show_scene = false,
  show_header = false,
  show_date = true,
  show_condition_text = true,
  show_forecast = false,
  forecast_days = "3",
  show_details = false,
  show_location = true,
  show_updated = false,
  show_attribution = false,
  compact_layout = false,
}

local ctx = mock.new({
  config = config,
  state = {
    weather_time = {
      seq = 1,
      location = { label = "London, United Kingdom", timezone = "Europe/London", source = "manual" },
      timezone = "Europe/London",
      timezone_abbreviation = "GMT",
      utc_offset_seconds = 0,
      current = {
        temp_c = 16.6, feels_like_c = 14.8, code = 3, is_day = true,
        wind_kmh = 7.2, humidity = 53, precipitation_mm = 0,
        condition_key = "conditions.overcast", category = "cloudy",
      },
      today = { max_c = 16.6, min_c = 12.4 },
      forecast = {
        { date = "2026-10-29", code = 3, max_c = 16.6, min_c = 12.4 },
        { date = "2026-10-30", code = 1, max_c = 15.7, min_c = 10.6 },
      },
      fetched_at = os.time(),
      refresh_minutes = 15,
    },
  },
  data_dir = "/data",
  dark = true,
})

mock.loadEntry("card.luau")

local clock = mock.find(ctx.desktop_tree, "clock")
assert(clock.props.fontWeight == "normal", "clock weight")
assert(clock.props.fontSize == 64, "clock size should ignore small_text_scale")

local temp = mock.find(ctx.desktop_tree, "weather-temp")
assert(temp.props.fontWeight == "normal", "temperature weight matches clock")
assert(temp.props.fontSize == 38, "temperature size should ignore small_text_scale")

local date = mock.find(ctx.desktop_tree, "date")
assert(date ~= nil, "date line")
assert(date.props.text:find("GMT", 1, true) ~= nil, "timezone sits on the date line")
assert(date.props.fontSize == 17, "date follows small_text_scale: " .. tostring(date.props.fontSize))
assert(mock.find(ctx.desktop_tree, "timezone") == nil, "no floating timezone line")

local location = mock.find(ctx.desktop_tree, "footer-location")
assert(location ~= nil, "footer location")
assert(location.props.fontSize == 14, "footer follows small_text_scale: " .. tostring(location.props.fontSize))

print("TYPOGRAPHY TEST OK")
