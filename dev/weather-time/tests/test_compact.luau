-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Compact layout and explicit colour overrides.
local mock = dofile("tests/support/mock.luau")

local function base_config()
  return {
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
    text_color = "#ff0000",
    muted_text_color = "#00ff00",
    weather_color = "#0000ff",
    divider_color = "outline",
    divider_width = 1,
    scene_auto_text = true,
    text_scale = 1,
    clock_size = 64,
    forecast_glyph_size = 20,
    show_scene = true,
    show_header = false,
    show_date = true,
    show_condition_text = true,
    show_forecast = true,
    forecast_days = "7",
    show_details = true,
    show_location = true,
    show_updated = true,
    show_attribution = true,
    compact_layout = true,
  }
end

local function state()
  local forecast = {}
  for index = 1, 8 do
    forecast[index] = {
      date = string.format("2026-10-%02d", 28 + index),
      code = 3,
      max_c = 16,
      min_c = 10,
      precip_prob = 0,
    }
  end
  return {
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
    forecast = forecast,
    fetched_at = os.time(),
    refresh_minutes = 15,
    scene = { variant = "cloudy_day", image = "/data/scene.svg" },
  }
end

local ctx = mock.new({
  config = base_config(),
  state = { weather_time = state() },
  data_dir = "/data",
  dark = true,
})
mock.loadEntry("card.luau")

local stack = mock.find(ctx.desktop_tree, "scene-stack")
assert(stack ~= nil, "scene stack")
local height = -stack.props.gap
assert(height <= 170, "compact height should fit a short tile, got " .. tostring(height))
assert(mock.find(ctx.desktop_tree, "details") == nil, "details hidden in compact")
assert(mock.find(ctx.desktop_tree, "timezone") == nil, "timezone hidden in compact")
assert(mock.find(ctx.desktop_tree, "footer-location") == nil, "footer labels hidden in compact")
assert(mock.find(ctx.desktop_tree, "forecast") ~= nil, "forecast remains")

-- Explicit colours win over the automatic scene palette.
local clock = mock.find(ctx.desktop_tree, "clock")
assert(clock.props.color == "#ff0000", "text colour override: " .. tostring(clock.props.color))
local glyph = mock.find(ctx.desktop_tree, "weather-glyph")
assert(glyph.props.color == "#0000ff", "weather colour override: " .. tostring(glyph.props.color))

-- Turning the background image off leaves the text/icons on the plain card.
local plain_config = base_config()
plain_config.show_scene = false
local plain = mock.new({
  config = plain_config,
  state = { weather_time = state() },
  data_dir = "/data",
  dark = true,
})
mock.loadEntry("card.luau")
assert(mock.find(plain.desktop_tree, "scene-image") == nil, "scene hidden")
assert(mock.find(plain.desktop_tree, "scene-stack") == nil, "no scene stack")
assert(mock.find(plain.desktop_tree, "clock") ~= nil, "clock remains")
assert(mock.find(plain.desktop_tree, "weather-temp") ~= nil, "weather remains")
assert(mock.find(plain.desktop_tree, "forecast") ~= nil, "forecast remains")

print("COMPACT TEST OK")
