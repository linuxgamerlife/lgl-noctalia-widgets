-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Pure helpers: formatting, units, WMO mapping, date math and location privacy.
local mock = dofile("tests/support/mock.luau")
local _ = mock.new({ config = {}, state = {} })

local format = mock.loadEntry("lib/format.luau")
local units = mock.loadEntry("lib/units.luau")
local wmo = mock.loadEntry("lib/wmo.luau")
local date = mock.loadEntry("lib/date.luau")
local location = mock.loadEntry("lib/location.luau")

local function close(actual, expected, epsilon, label)
  assert(type(actual) == "number", label .. ": expected a number, got " .. tostring(actual))
  assert(math.abs(actual - expected) <= epsilon,
    ("%s: expected %.6f, got %.6f"):format(label, expected, actual))
end

close(format.clamp(-4, 0, 10), 0, 0, "clamp low")
close(format.clamp(14, 0, 10), 10, 0, "clamp high")
close(format.round(12.345, 1), 12.3, 1e-9, "round")
close(format.round(-12.345, 1), -12.3, 1e-9, "round negative")
assert(format.trim("  hello \n") == "hello", "trim")
assert(format.number(8.5, 1) == "8.5", "number")
assert(format.number(32, 0) == "32", "number whole")
assert(format.percent(42.5) == "43%", "percent")
assert(format.age_parts(30) == 30, "age seconds")

close(format.temperature(0, "imperial"), 32, 1e-9, "c to f")
close(format.temperature(100, "metric"), 100, 1e-9, "c metric")
close(format.wind(100, "imperial"), 62.1371, 1e-9, "wind mph")
close(format.precipitation(25.4, "imperial"), 1, 1e-9, "precip in")
assert(format.temperature_text(16.4, "metric", "°C") == "16 °C", "temp text")
assert(format.wind_text(7.2, "metric", "km/h") == "7 km/h", "wind text")
assert(format.precipitation_text(0, "metric", "mm") == "0.0 mm", "precip text")

assert(units.system("auto", "imperial") == "imperial", "units host")
assert(units.system("metric", "imperial") == "metric", "units override")
assert(units.temperature_unit("imperial") == "°F", "unit f")
assert(units.wind_unit("metric") == "km/h", "unit kmh")

assert(wmo.category(0) == "clear", "wmo clear")
assert(wmo.category(3) == "cloudy", "wmo cloudy")
assert(wmo.category(61) == "rain", "wmo rain")
assert(wmo.category(75) == "snow", "wmo snow")
assert(wmo.category(95) == "thunder", "wmo thunder")
assert(wmo.category(999) == "unknown", "wmo unknown")
assert(wmo.condition_key(3) == "conditions.overcast", "wmo key")
assert(wmo.glyph(0, false) == "weather-moon", "wmo night glyph")
assert(wmo.glyph(2, true) == "weather-cloud-sun", "wmo day glyph")

assert(date.parse_iso("2026-10-29") ~= nil, "date parse")
assert(date.parse_iso("2026-02-29") == nil, "date leap reject")
assert(date.parse_iso("2024-02-29") ~= nil, "date leap accept")
assert(date.weekday("2026-10-29") == 4, "date thursday")
assert(date.add_days("2026-10-31", 1) == "2026-11-01", "date add")
assert(date.noon_epoch("2026-10-29") ~= nil, "date noon")

assert(location.valid_coords(51.5, -0.1), "coords valid")
assert(not location.valid_coords(91, 0), "coords lat invalid")
assert(not location.valid_coords(0, 181), "coords lon invalid")
assert(location.round_coord(51.50744) == 51.51, "coord rounding")
assert(location.round_coord(-0.1278) == -0.13, "coord rounding neg")
local record = location.new("London", 51.50744, -0.1278, "Europe/London", "manual")
assert(record ~= nil, "location new")
assert(record.latitude == 51.51 and record.longitude == -0.13, "location rounded")
local public = location.public(record)
assert(public.latitude == nil and public.longitude == nil, "location public strips coords")
assert(public.label == "London", "location public label")
assert(location.validate({ label = "X", latitude = 999, longitude = 0 }) == nil, "location invalid")

print("CORE TEST OK")
