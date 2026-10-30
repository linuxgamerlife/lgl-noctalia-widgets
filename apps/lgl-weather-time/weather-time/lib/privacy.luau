-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Privacy projections and assertions.
--
-- `public_weather` is the only shape that may be published through
-- noctalia.state. It deliberately has no latitude/longitude fields, no raw
-- provider body and no request URL.

local format = require("./format.luau")
local location = require("./location.luau")

local M = {}

local COORD_KEYS = {
  latitude = true,
  longitude = true,
  lat = true,
  lon = true,
  lng = true,
  coordinates = true,
  coords = true,
}

local function clean_number(value, decimals)
  local number = tonumber(value)
  if number == nil or number ~= number then
    return nil
  end
  return format.round(number, decimals)
end

local function copy_day(day)
  if type(day) ~= "table" then
    return nil
  end
  return {
    date = day.date,
    code = clean_number(day.code, 0),
    max_c = clean_number(day.max_c, 1),
    min_c = clean_number(day.min_c, 1),
    precip_prob = clean_number(day.precip_prob, 0),
    sunrise = day.sunrise,
    sunset = day.sunset,
  }
end

function M.error(reason, status)
  local error = { reason = reason or "unknown" }
  local code = tonumber(status)
  if code ~= nil then
    error.status = math.floor(code + 0.5)
  end
  return error
end

function M.weather(model, location_record)
  if type(model) ~= "table" then
    return nil
  end
  local current = type(model.current) == "table" and model.current or {}
  local today = type(model.today) == "table" and model.today or {}
  local forecast = {}
  for _, day in ipairs(type(model.forecast) == "table" and model.forecast or {}) do
    local public = copy_day(day)
    if public ~= nil then
      forecast[#forecast + 1] = public
    end
  end
  return {
    provider = model.provider or "open-meteo",
    location = location.public(location_record),
    timezone = model.timezone or "",
    timezone_abbreviation = model.timezone_abbreviation or "",
    utc_offset_seconds = clean_number(model.utc_offset_seconds, 0),
    current = {
      temp_c = clean_number(current.temp_c, 1),
      feels_like_c = clean_number(current.feels_like_c, 1),
      code = clean_number(current.code, 0),
      is_day = current.is_day == true,
      wind_kmh = clean_number(current.wind_kmh, 1),
      wind_direction_deg = clean_number(current.wind_direction_deg, 0),
      humidity = clean_number(current.humidity, 0),
      precipitation_mm = clean_number(current.precipitation_mm, 1),
      uv_index = clean_number(current.uv_index, 1),
      condition_key = current.condition_key,
      category = current.category,
    },
    today = {
      max_c = clean_number(today.max_c, 1),
      min_c = clean_number(today.min_c, 1),
      sunrise = today.sunrise,
      sunset = today.sunset,
    },
    forecast = forecast,
    fetched_at = clean_number(model.fetched_at, 0),
  }
end

-- Normalized cache payload: no coordinates, no raw provider response.
function M.cache(model, location_record)
  local public = M.weather(model, location_record)
  if public == nil then
    return nil
  end
  return {
    version = 1,
    provider = public.provider,
    location = public.location,
    timezone = public.timezone,
    timezone_abbreviation = public.timezone_abbreviation,
    utc_offset_seconds = public.utc_offset_seconds,
    current = public.current,
    today = public.today,
    forecast = public.forecast,
    fetched_at = public.fetched_at,
  }
end

function M.has_coordinate_key(value, depth)
  local level = depth or 0
  if level > 8 or type(value) ~= "table" then
    return false
  end
  for key, item in pairs(value) do
    if type(key) == "string" and COORD_KEYS[string.lower(key)] then
      return true
    end
    if type(item) == "table" and M.has_coordinate_key(item, level + 1) then
      return true
    end
  end
  return false
end

function M.assert_public(value)
  if M.has_coordinate_key(value) then
    error("privacy: coordinate key in public state")
  end
  return value
end

return M
