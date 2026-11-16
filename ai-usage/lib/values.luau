-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Value helpers: finite numbers, ISO timestamps, plain tables, random ids.

local M = {}

local DECIMAL_PATTERN = "^%-?%d+%.?%d*[eE]?[-+]?%d*$"
local ISO_PATTERN = "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d"

function M.toFiniteNumber(value)
  local number = nil
  if type(value) == "number" then
    number = value
  elseif type(value) == "string" and (value:match(DECIMAL_PATTERN) or value:match("^%-?%d+%.?%d*$")) then
    number = tonumber(value)
  end
  if number == nil then
    return nil
  end
  if number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

-- Days since 1970-01-01 for a civil date. Avoids the host's local time zone.
function M.daysFromCivil(year, month, day)
  if month <= 2 then
    year = year - 1
  end
  local era = math.floor(year / 400)
  local yoe = year - era * 400
  local mp = (month + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + day - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

function M.parseIsoTime(value)
  if type(value) ~= "string" or not value:match(ISO_PATTERN) then
    return nil
  end
  local year, month, day, hour, minute, rest =
    value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)(.*)$")
  if year == nil then
    return nil
  end
  local second = 0
  local zone = nil

  -- Strip ":SS" and an optional fractional part. OpenCode and OpenCode Zen
  -- return "2026-10-26T20:02:24.000Z", while other providers use a plain "Z"
  -- or a numeric offset.
  local secondsPart, afterSeconds = rest:match("^:(%d%d)(.*)$")
  if secondsPart ~= nil then
    second = tonumber(secondsPart)
    rest = afterSeconds
    local fractionRest = rest:match("^%.%d+(.*)$")
    if fractionRest ~= nil then
      rest = fractionRest
    end
  end

  local zoneSign, zoneHour, zoneMinute = rest:match("^([%+%-])(%d%d):(%d%d)$")
  if zoneSign ~= nil then
    zone = (zoneSign == "-" and -1 or 1) * (tonumber(zoneHour) * 3600 + tonumber(zoneMinute) * 60)
  elseif rest == "Z" then
    zone = 0
  end
  if zone == nil then
    return nil
  end
  local y, mo, d, h, mi, s = tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute), second
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or s > 60 then
    return nil
  end
  local seconds = M.daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s - zone
  return seconds * 1000
end

function M.isPlainObject(value)
  return type(value) == "table" and (next(value) == nil or value[1] == nil)
end

function M.randomHex(digits)
  local text = ""
  for _ = 1, digits do
    text = text .. string.format("%x", math.floor(math.random() * 16))
  end
  return text
end

function M.isoUtc(ms)
  return os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor(ms / 1000))
end

return M
