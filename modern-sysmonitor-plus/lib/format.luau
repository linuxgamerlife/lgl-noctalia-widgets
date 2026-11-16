--!nonstrict

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Joao Gabriel Medeiros
-- Copyright (C) 2026 UnsaidSpeech
-- Copyright (C) 2026 LinuxGamerLife

-- Small, dependency-free formatters shared by the sampler and the card.

local M = {}

function M.clamp(value, low, high)
  local number = tonumber(value)
  if number == nil then
    return low
  end
  if number < low then
    return low
  end
  if number > high then
    return high
  end
  return number
end

function M.round(value, digits)
  local number = tonumber(value)
  if number == nil then
    return nil
  end
  local places = math.floor(tonumber(digits) or 0)
  local factor = 10 ^ places
  if factor <= 1 then
    return math.floor(number + 0.5)
  end
  return math.floor(number * factor + 0.5) / factor
end

function M.trim(text)
  if type(text) ~= "string" then
    return ""
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.number(value, digits)
  local number = tonumber(value)
  if number == nil then
    return "—"
  end
  local places = math.floor(tonumber(digits) or 0)
  return string.format("%." .. tostring(places) .. "f", number)
end

function M.pct(value)
  local number = tonumber(value)
  if number == nil then
    return "—"
  end
  return string.format("%d%%", math.floor(number + 0.5))
end

-- Speed values are bytes per second. The unit labels are passed in so the
-- card can translate them without this module depending on the host.
function M.format_speed(value, units)
  local labels = units or {}
  local number = tonumber(value) or 0
  if number < 0 then
    number = 0
  end
  if number < 1024 then
    return string.format("%.0f %s", number, labels.bps or "B/s")
  elseif number < 1024 * 1024 then
    return string.format("%.1f %s", number / 1024, labels.kbps or "KB/s")
  elseif number < 1024 * 1024 * 1024 then
    return string.format("%.1f %s", number / (1024 * 1024), labels.mbps or "MB/s")
  end
  return string.format("%.1f %s", number / (1024 * 1024 * 1024), labels.gbps or "GB/s")
end

-- Sizes are in the same 1024-based "GB" the KDE widget used.
function M.format_size_gb(value, units)
  local labels = units or {}
  local number = tonumber(value)
  if number == nil then
    return "—"
  end
  if number >= 1000 then
    return string.format("%.2f %s", number / 1024, labels.tb or "TB")
  end
  return string.format("%.0f %s", number, labels.gb or "GB")
end

return M
