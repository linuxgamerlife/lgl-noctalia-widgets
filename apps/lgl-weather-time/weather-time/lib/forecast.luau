-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Validate and normalize an Open-Meteo forecast response into the plugin's
-- canonical (metric) weather model. No HTTP, filesystem or host calls.

local date = require("./date.luau")
local format = require("./format.luau")
local wmo = require("./wmo.luau")

local M = {}

local MAX_DAYS = 8

local function number(value)
  local result = tonumber(value)
  if result == nil or result ~= result then
    return nil
  end
  return result
end

local function round(value, decimals)
  return format.round(value, decimals)
end

local function string_value(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function array(value)
  if type(value) ~= "table" then
    return nil
  end
  return value
end

local function index_value(values, index)
  if type(values) ~= "table" then
    return nil
  end
  return values[index]
end

local function iso_date(value)
  local parsed = date.parse_iso(value)
  if parsed == nil then
    return nil
  end
  return string.format("%04d-%02d-%02d", parsed.year, parsed.month, parsed.day)
end

-- Build one forecast day from the parallel daily arrays.
local function build_day(payload, index)
  local daily = payload.daily or {}
  local dates = array(daily.time)
  if dates == nil then
    return nil
  end
  local value = iso_date(index_value(dates, index))
  if value == nil then
    return nil
  end
  return {
    date = value,
    code = number(index_value(daily.weather_code, index)),
    max_c = round(number(index_value(daily.temperature_2m_max, index)), 1),
    min_c = round(number(index_value(daily.temperature_2m_min, index)), 1),
    precip_prob = round(number(index_value(daily.precipitation_probability_max, index)), 0),
    sunrise = string_value(index_value(daily.sunrise, index)),
    sunset = string_value(index_value(daily.sunset, index)),
  }
end

function M.normalize(payload, options)
  if type(payload) ~= "table" then
    return nil, "payload is not a table"
  end
  local current = payload.current
  if type(current) ~= "table" then
    return nil, "missing current"
  end
  local daily = payload.daily
  if type(daily) ~= "table" or type(daily.time) ~= "table" then
    return nil, "missing daily"
  end

  local now = number(current.time) or 0
  local current_model = {
    temp_c = round(number(current.temperature_2m), 1),
    feels_like_c = round(number(current.apparent_temperature), 1),
    code = number(current.weather_code),
    is_day = current.is_day == 1 or current.is_day == true,
    wind_kmh = round(number(current.wind_speed_10m), 1),
    wind_direction_deg = round(number(current.wind_direction_10m), 0),
    humidity = round(number(current.relative_humidity_2m), 0),
    precipitation_mm = round(number(current.precipitation), 1),
    uv_index = round(number(current.uv_index), 1),
  }
  current_model.condition_key = wmo.condition_key(current_model.code)
  current_model.category = wmo.category(current_model.code)

  local days = {}
  local count = math.min(#daily.time, MAX_DAYS)
  local limit = math.min(tonumber(options and options.days) or 3, MAX_DAYS)
  for index = 1, count do
    local day = build_day(payload, index)
    if day ~= nil then
      days[#days + 1] = day
    end
  end
  if #days == 0 then
    return nil, "no forecast days"
  end

  -- Drop yesterday and older if the response is reused from a cache.
  local today = nil
  if type(current.time) == "string" then
    today = iso_date(current.time:sub(1, 10))
  end
  today = today or days[1].date
  local kept = {}
  for _, day in ipairs(days) do
    local is_future = day.date >= today
    if is_future then
      kept[#kept + 1] = day
    end
  end
  if #kept == 0 then
    kept = days
  end
  while #kept > limit do
    table.remove(kept)
  end

  local today_model = kept[1]
  return {
    provider = "open-meteo",
    timezone = string_value(payload.timezone) or "",
    timezone_abbreviation = string_value(payload.timezone_abbreviation) or "",
    utc_offset_seconds = number(payload.utc_offset_seconds) or 0,
    current = current_model,
    today = {
      max_c = today_model.max_c,
      min_c = today_model.min_c,
      sunrise = today_model.sunrise,
      sunset = today_model.sunset,
    },
    forecast = kept,
    fetched_at = tonumber(options and options.now) or os.time(),
  }
end

-- Normalize a cached weather table (already in our shape) without a provider
-- payload. Returns nil when the cache is structurally unusable.
function M.from_cache(value)
  if type(value) ~= "table" or type(value.current) ~= "table" or type(value.forecast) ~= "table" then
    return nil
  end
  local current = value.current
  if number(current.temp_c) == nil and number(current.code) == nil then
    return nil
  end
  local forecast = {}
  for _, day in ipairs(value.forecast) do
    if type(day) == "table" and iso_date(day.date) ~= nil then
      forecast[#forecast + 1] = {
        date = day.date,
        code = number(day.code),
        max_c = round(number(day.max_c), 1),
        min_c = round(number(day.min_c), 1),
        precip_prob = round(number(day.precip_prob), 0),
        sunrise = string_value(day.sunrise),
        sunset = string_value(day.sunset),
      }
    end
  end
  if #forecast == 0 then
    return nil
  end
  return {
    provider = string_value(value.provider) or "open-meteo",
    timezone = string_value(value.timezone) or "",
    timezone_abbreviation = string_value(value.timezone_abbreviation) or "",
    utc_offset_seconds = number(value.utc_offset_seconds) or 0,
    current = {
      temp_c = round(number(current.temp_c), 1),
      feels_like_c = round(number(current.feels_like_c), 1),
      code = number(current.code),
      is_day = current.is_day == true,
      wind_kmh = round(number(current.wind_kmh), 1),
      wind_direction_deg = round(number(current.wind_direction_deg), 0),
      humidity = round(number(current.humidity), 0),
      precipitation_mm = round(number(current.precipitation_mm), 1),
      uv_index = round(number(current.uv_index), 1),
      condition_key = string_value(current.condition_key) or wmo.condition_key(current.code),
      category = string_value(current.category) or wmo.category(current.code),
    },
    today = type(value.today) == "table" and {
      max_c = round(number(value.today.max_c), 1),
      min_c = round(number(value.today.min_c), 1),
      sunrise = string_value(value.today.sunrise),
      sunset = string_value(value.today.sunset),
    } or {
      max_c = forecast[1].max_c,
      min_c = forecast[1].min_c,
      sunrise = forecast[1].sunrise,
      sunset = forecast[1].sunset,
    },
    forecast = forecast,
    fetched_at = number(value.fetched_at) or 0,
  }
end

return M
