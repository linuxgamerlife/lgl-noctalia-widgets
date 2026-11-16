-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Open-Meteo response normalization and cache round-trip.
local mock = dofile("tests/support/mock.luau")
local _ = mock.new({ config = {}, state = {} })
local forecast = mock.loadEntry("lib/forecast.luau")

local function payload()
  return {
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
      time = { "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01" },
      weather_code = { 2, 3, 1, 3, 51 },
      temperature_2m_max = { 15, 16.6, 15.7, 14.4, nil },
      temperature_2m_min = { 9, 12.4, 10.6, 10.1, nil },
      precipitation_probability_max = { 5, 2, 0, 0, nil },
      sunrise = { "2026-10-28T06:46", "2026-10-29T06:48", "2026-10-30T06:50", "2026-10-31T06:52", "2026-11-01T06:53" },
      sunset = { "2026-10-28T16:41", "2026-10-29T16:39", "2026-10-30T16:37", "2026-10-31T16:35", "2026-11-01T16:33" },
    },
  }
end

local model, err = forecast.normalize(payload(), { days = 7, now = 1761744000 })
assert(model ~= nil, "normalize failed: " .. tostring(err))
assert(model.current.temp_c == 16.6, "current temp")
assert(model.current.feels_like_c == 14.8, "feels")
assert(model.current.condition_key == "conditions.overcast", "condition key")
assert(model.current.is_day == true, "is_day")
assert(model.timezone == "Europe/London", "timezone")
assert(model.timezone_abbreviation == "GMT", "tz abbr")
assert(#model.forecast == 4, "past day dropped, #forecast=" .. tostring(#model.forecast))
assert(model.forecast[1].date == "2026-10-29", "first day today")
assert(model.forecast[4].max_c == nil, "null max preserved")
assert(model.today.max_c == 16.6, "today max")

local cached = {
  version = 1,
  provider = "open-meteo",
  location = { label = "London", timezone = "Europe/London", source = "manual" },
  timezone = "Europe/London",
  timezone_abbreviation = "GMT",
  utc_offset_seconds = 0,
  current = model.current,
  today = model.today,
  forecast = model.forecast,
  fetched_at = 1761744000,
}
local restored = forecast.from_cache(cached)
assert(restored ~= nil, "cache restore")
assert(restored.current.temp_c == 16.6, "cache temp")
assert(restored.fetched_at == 1761744000, "cache fetched_at")
assert(#restored.forecast == 4, "cache forecast")

local bad, bad_err = forecast.normalize({ current = {}, daily = {} }, {})
assert(bad == nil and type(bad_err) == "string", "bad payload rejected")

print("FORECAST TEST OK")
