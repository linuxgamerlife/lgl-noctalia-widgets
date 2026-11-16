-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Service privacy invariant: no location means no HTTP request.
local mock = dofile("tests/support/mock.luau")

local ctx = mock.new({
  config = {
    refresh_minutes = "15",
    units = "auto",
    clock_source = "auto",
    clock_format = "auto",
    show_seconds = false,
    date_style = "auto",
    secondary_timezone = "",
    secondary_label = "Home",
    scene = "auto",
    scene_theme = "auto",
  },
  data_dir = "/data",
  dark = true,
})

mock.loadEntry("service.luau")
assert(#ctx.http_requests == 0, "no request before a location exists")
local state = ctx.state.weather_time
assert(type(state) == "table", "state published")
assert(state.location == nil, "no location")
assert(state.current == nil, "no weather")
assert(state.scene ~= nil, "clock-only scene still rendered")
assert(ctx.files["/data/weather.json"] == nil, "no weather cache")

print("NO-LOCATION TEST OK")
