-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Setup panel: search, save, manual coordinates and forget.
local mock = dofile("tests/support/mock.luau")

local geo_response = {
  results = {
    {
      id = 2643743,
      name = "London",
      latitude = 51.5074,
      longitude = -0.1278,
      country = "United Kingdom",
      admin1 = "England",
      timezone = "Europe/London",
    },
  },
}

local ctx = mock.new({
  config = {
    refresh_minutes = "15",
    units = "metric",
    clock_source = "auto",
    clock_format = "auto",
    show_seconds = false,
    date_style = "auto",
    secondary_timezone = "",
    secondary_label = "Home",
    scene = "auto",
    scene_theme = "auto",
  },
  state = {},
  data_dir = "/data",
  http_responses = { { ok = true, status = 200, body = geo_response } },
  dark = true,
})

mock.loadEntry("panel.luau")
local tree = ctx.panel_tree
assert(type(tree) == "table", "panel rendered")
assert(mock.find(tree, "panel-title") ~= nil, "panel title")
assert(mock.find(tree, "search-input") ~= nil, "search input")

-- Type and search. The input is uncontrolled, so call its callback directly.
local input = mock.find(tree, "search-input")
input.props.onChange("London")
mock.find(tree, "search-button").props.onClick()
assert(#ctx.http_requests == 1, "geocode request")
assert(ctx.http_requests[1].url:find("geocoding-api.open-meteo.com", 1, true), "geocode endpoint")
assert(ctx.http_requests[1].url:find("name=London", 1, true), "geocode query")
assert(ctx.http_requests[1].follow_redirects == false, "no redirects")

tree = ctx.panel_tree
local result = mock.find(tree, "search-result-1")
assert(result ~= nil, "search result")
assert(result.props.text == "London, England, United Kingdom", "result label")
result.props.onClick()

local saved = noctalia.json.decode(ctx.files["/data/location.json"])
assert(type(saved) == "table", "location saved")
assert(saved.latitude == 51.51 and saved.longitude == -0.13, "coordinates rounded")
assert(saved.timezone == "Europe/London", "timezone saved")
assert(tonumber(noctalia.state.get("weather_time_location_rev")) >= 1, "location revision")

-- Manual coordinates overwrite the saved location.
tree = ctx.panel_tree
mock.find(tree, "manual-lat").props.onChange("40.7128")
mock.find(tree, "manual-lon").props.onChange("-74.006")
mock.find(tree, "manual-label").props.onChange("New York")
mock.find(tree, "manual-save").props.onClick()
local manual = noctalia.json.decode(ctx.files["/data/location.json"])
assert(manual.latitude == 40.71 and manual.longitude == -74.01, "manual coordinates")

-- Forget removes the location and the cached weather.
ctx.files["/data/weather.json"] = { current = { temp_c = 10 } }
tree = ctx.panel_tree
mock.find(tree, "forget").props.onClick()
assert(ctx.files["/data/location.json"] == nil, "location removed")
assert(ctx.files["/data/weather.json"] == nil, "weather removed")

-- Privacy copy is present.
assert(mock.find(ctx.panel_tree, "status-privacy") ~= nil, "privacy note")

print("PANEL TEST OK")
