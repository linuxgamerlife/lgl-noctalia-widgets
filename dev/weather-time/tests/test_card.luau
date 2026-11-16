-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Desktop card rendering with a published state and a scene.
local mock = dofile("tests/support/mock.luau")

local now = os.time()
local state = {
  ts = now,
  seq = 1,
  units = { temperature = "c", wind = "kmh", precipitation = "mm" },
  location = { label = "London, United Kingdom", timezone = "Europe/London", source = "manual" },
  provider = "open-meteo",
  timezone = "Europe/London",
  timezone_abbreviation = "GMT",
  utc_offset_seconds = 0,
  current = {
    temp_c = 16.6,
    feels_like_c = 14.8,
    code = 3,
    is_day = true,
    wind_kmh = 7.2,
    wind_direction_deg = 100,
    humidity = 53,
    precipitation_mm = 0,
    uv_index = 0.1,
    condition_key = "conditions.overcast",
    category = "cloudy",
  },
  today = { max_c = 16.6, min_c = 12.4, sunrise = "2026-10-29T06:48", sunset = "2026-10-29T16:39" },
  forecast = {
    { date = "2026-10-29", code = 3, max_c = 16.6, min_c = 12.4, precip_prob = 2 },
    { date = "2026-10-30", code = 1, max_c = 15.7, min_c = 10.6, precip_prob = 0 },
    { date = "2026-10-31", code = 3, max_c = 14.4, min_c = 10.1, precip_prob = 0 },
    { date = "2026-11-01", code = 51, max_c = 11, min_c = 9.5, precip_prob = 4 },
  },
  fetched_at = now,
  refresh_minutes = 15,
  stale = false,
  error = nil,
  scene = {
    variant = "cloudy_day",
    image = "/data/scenes/cloudy_day/scene.svg",
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
  state = { weather_time = state },
  data_dir = "/data",
  dark = true,
})

mock.loadEntry("card.luau")
local tree = ctx.desktop_tree
assert(type(tree) == "table", "card rendered")
assert(tree.props.key == "card", "root key")

local clock = mock.find(tree, "clock")
assert(clock ~= nil and type(clock.props.text) == "string" and #clock.props.text > 0, "clock")

local temp = mock.find(tree, "weather-temp")
assert(temp ~= nil and temp.props.text == "17 °C", "temperature: " .. tostring(temp and temp.props.text))

local condition = mock.find(tree, "weather-condition")
assert(condition ~= nil and condition.props.text == "Overcast", "condition")

local scene_image = mock.find(tree, "scene-image")
assert(scene_image ~= nil and scene_image.props.path == "/data/scenes/cloudy_day/scene.svg", "scene image")

local stack = mock.find(tree, "scene-stack")
assert(stack ~= nil and stack.props.gap < 0, "negative gap overlay")

assert(mock.find(tree, "forecast") ~= nil, "forecast row")
assert(mock.findText(tree, "Fri") ~= nil, "forecast weekday")
assert(mock.find(tree, "footer-location") ~= nil, "footer location")

-- Watch updates replace the tree.
state.seq = 2
state.current.temp_c = 18
noctalia.state.set("weather_time", state)
assert(mock.find(ctx.desktop_tree, "weather-temp").props.text == "18 °C", "state watch render")

print("CARD TEST OK")
