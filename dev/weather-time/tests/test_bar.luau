-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Bar widget: weather + clock, click and refresh behaviour.
local mock = dofile("tests/support/mock.luau")

local ctx = mock.new({
  config = {
    refresh_minutes = "15",
    units = "metric",
    clock_source = "system",
    clock_format = "24h",
    show_seconds = false,
    date_style = "auto",
    secondary_timezone = "",
    secondary_label = "Home",
    scene = "off",
    scene_theme = "auto",
    mode = "both",
    show_temperature = true,
    show_condition = true,
    glyph = "weather-cloud",
  },
  state = {
    weather_time = {
      seq = 1,
      location = { label = "London", timezone = "Europe/London", source = "manual" },
      timezone = "Europe/London",
      current = { temp_c = 16.6, code = 3, is_day = true, condition_key = "conditions.overcast" },
      fetched_at = os.time(),
      refresh_minutes = 15,
    },
  },
  dark = true,
})

mock.loadEntry("bar.luau")
assert(type(ctx.bar_tree) == "table", "bar rendered")
assert(mock.find(ctx.bar_tree, "bar-temp") ~= nil, "bar temperature")
assert(mock.find(ctx.bar_tree, "bar-condition") ~= nil, "bar condition")
assert(mock.find(ctx.bar_tree, "bar-time") ~= nil, "bar clock")
assert(mock.find(ctx.bar_tree, "bar-temp").props.text == "17°", "bar temp text")

-- Vertical bars are one control tall: no long condition text, and one value.
ctx.vertical = true
update()
assert(ctx.bar_tree.type == "column", "vertical layout")
assert(mock.find(ctx.bar_tree, "bar-condition") == nil, "no condition in vertical bar")
assert(mock.find(ctx.bar_tree, "bar-temp") ~= nil, "vertical temperature")

onClick()
assert(ctx.toggled_panel == "linuxgamerlife/weather-time:setup", "panel id")

local before = tonumber(noctalia.state.get("weather_time_refresh_seq")) or 0
onRightClick()
local after = tonumber(noctalia.state.get("weather_time_refresh_seq")) or 0
assert(after == before + 1, "refresh sequence")
assert(#ctx.notifications == 1, "refresh notification")

print("BAR TEST OK")
