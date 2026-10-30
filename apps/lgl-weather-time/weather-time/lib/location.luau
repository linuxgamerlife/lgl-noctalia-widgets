-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Location record validation and privacy projection.
--
-- A location record is the only place coordinates live. `public()` strips them
-- before a record crosses the service/state boundary.

local M = {}

M.VERSION = 1
M.MAX_LABEL = 120
M.MAX_TIMEZONE = 64

function M.round_coord(value)
  local number = tonumber(value)
  if number == nil then
    return nil
  end
  local factor = 100 -- two decimal places: roughly 1.1 km of latitude
  if number >= 0 then
    return math.floor(number * factor + 0.5) / factor
  end
  return math.ceil(number * factor - 0.5) / factor
end

function M.valid_coords(latitude, longitude)
  local lat = tonumber(latitude)
  local lon = tonumber(longitude)
  if lat == nil or lon == nil then
    return false
  end
  if lat ~= lat or lon ~= lon then -- NaN
    return false
  end
  return lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180
end

function M.valid_timezone(value)
  if value == nil or value == "" then
    return true
  end
  if type(value) ~= "string" or #value > M.MAX_TIMEZONE then
    return false
  end
  return value:match("^[A-Za-z0-9_%+%-/]+$") ~= nil
end

function M.clean_label(value)
  if type(value) ~= "string" then
    return ""
  end
  local label = value:gsub("[\r\n\t]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #label > M.MAX_LABEL then
    label = label:sub(1, M.MAX_LABEL)
  end
  return label
end

function M.new(label, latitude, longitude, timezone, source)
  if not M.valid_coords(latitude, longitude) then
    return nil, "invalid coordinates"
  end
  local tz = timezone or ""
  if not M.valid_timezone(tz) then
    return nil, "invalid timezone"
  end
  local record = {
    version = M.VERSION,
    label = M.clean_label(label),
    latitude = M.round_coord(latitude),
    longitude = M.round_coord(longitude),
    timezone = tz,
    source = source or "manual",
  }
  if record.label == "" then
    record.label = string.format("%.2f, %.2f", record.latitude, record.longitude)
  end
  return record
end

function M.validate(record)
  if type(record) ~= "table" then
    return nil, "not a table"
  end
  local normalized, err = M.new(
    record.label,
    record.latitude,
    record.longitude,
    record.timezone,
    record.source
  )
  if normalized == nil then
    return nil, err
  end
  return normalized
end

-- Strip coordinates before publishing to any widget entry or writing the
-- weather cache. Keep only the display label, timezone and source.
function M.public(record)
  if type(record) ~= "table" then
    return nil
  end
  return {
    label = M.clean_label(record.label),
    timezone = record.timezone or "",
    source = record.source or "manual",
  }
end

function M.has_coordinates(record)
  return type(record) == "table" and record.latitude ~= nil and record.longitude ~= nil
end

return M
