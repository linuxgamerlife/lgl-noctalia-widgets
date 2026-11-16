-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Clock uses the weather location's IANA timezone in auto mode.
local mock = dofile("tests/support/mock.luau")

local ctx = mock.new({
  config = {
    refresh_minutes = "15",
    units = "metric",
    clock_source = "auto",
    clock_format = "24h",
    show_seconds = false,
    date_style = "hidden",
    secondary_timezone = "",
    secondary_label = "Home",
    scene = "off",
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
    show_date = false,
    show_condition_text = true,
    show_forecast = false,
    forecast_days = "3",
    show_details = false,
    show_location = false,
    show_updated = false,
    show_attribution = false,
    compact_layout = false,
  },
  state = {
    weather_time = {
      seq = 1,
      location = { label = "New York", timezone = "America/New_York", source = "manual" },
      timezone = "America/New_York",
      timezone_abbreviation = "EDT",
      utc_offset_seconds = -14400,
      current = { temp_c = 20, code = 0, is_day = true, condition_key = "conditions.clear" },
      today = { max_c = 22, min_c = 14 },
      forecast = { { date = "2026-10-29", code = 0, max_c = 22, min_c = 14 } },
      fetched_at = os.time(),
      refresh_minutes = 15,
    },
  },
  valid_timezones = { ["America/New_York"] = true, ["Europe/London"] = true },
  format_time = function(pattern, timestamp, timezone)
    if timezone == "America/New_York" then
      return "08:00"
    end
    return "12:00"
  end,
  dark = true,
})

mock.loadEntry("card.luau")
local clock = mock.find(ctx.desktop_tree, "clock")
assert(clock ~= nil and clock.props.text == "08:00", "location clock: " .. tostring(clock and clock.props.text))

print("TIME TEST OK")
