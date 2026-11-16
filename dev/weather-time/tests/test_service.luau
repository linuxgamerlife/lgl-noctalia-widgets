-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Service: fetch, cache, sanitized failure and privacy invariants.
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

local location = {
  version = 1,
  label = "London, United Kingdom",
  latitude = 51.51,
  longitude = -0.13,
  timezone = "Europe/London",
  source = "manual",
}

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
  files = { ["/data/location.json"] = location },
  data_dir = "/data",
  http_responses = { { ok = true, status = 200, body = payload } },
  now_ms = 1761744000000,
  dark = true,
})

mock.loadEntry("service.luau")
assert(#ctx.http_requests == 1, "one forecast request")
local request = ctx.http_requests[1]
assert(request.url:find("latitude=51.51", 1, true), "rounded latitude")
assert(request.url:find("longitude=-0.13", 1, true), "rounded longitude")
assert(request.url:find("timezone=auto", 1, true), "timezone auto")
assert(request.follow_redirects == false, "no redirects")
assert(request.url:find("api.open-meteo.com", 1, true), "open-meteo")

local state = ctx.state.weather_time
assert(type(state) == "table", "published state")
assert(state.current.temp_c == 16.6, "temperature")
assert(state.current.condition_key == "conditions.overcast", "condition")
assert(state.location.label == "London, United Kingdom", "label")
assert(state.location.latitude == nil and state.location.longitude == nil, "no coords in state")
assert(ctx.state.weather_time.scene ~= nil, "scene published")
assert(type(ctx.state.weather_time.scene.image) == "string", "scene image")

local cache = noctalia.json.decode(ctx.files["/data/weather.json"])
assert(type(cache) == "table", "weather cache")
assert(cache.location.latitude == nil and cache.location.longitude == nil, "no coords in cache")
assert(cache.current.temp_c == 16.6, "cache temperature")

-- Refresh failure keeps the last good data and publishes a sanitized error.
ctx.http_responses = { { ok = true, status = 500, body = "" } }
onIpc("refresh")
local failed = ctx.state.weather_time
assert(failed.error ~= nil, "error published")
assert(failed.error.reason == "http_status" and failed.error.status == 500, "sanitized http error")
assert(failed.current.temp_c == 16.6, "last good data kept")

-- Scaling outside the service's declared settings must never happen.
assert(ctx.requested["location.latitude"] == nil, "service does not read native location")

print("SERVICE TEST OK")
