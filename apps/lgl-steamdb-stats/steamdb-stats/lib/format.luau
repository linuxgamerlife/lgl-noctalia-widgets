-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Pure formatting helpers shared by the service and the card. No host calls.

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
  local places = tonumber(digits) or 0
  local factor = 10 ^ places
  if number >= 0 then
    return math.floor(number * factor + 0.5) / factor
  end
  return math.ceil(number * factor - 0.5) / factor
end

-- Group a non-negative integer with commas: 113946 -> "113,946".
function M.thousands(value)
  local number = tonumber(value)
  if number == nil or number < 0 then
    return nil
  end
  local text = string.format("%d", math.floor(number + 0.5))
  local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if grouped:sub(1, 1) == "," then
    grouped = grouped:sub(2)
  end
  return grouped
end

-- Short relative age for the chart footer: "just now", "4m ago", "2h ago".
function M.since(timestamp, now)
  local then_value = tonumber(timestamp)
  local now_value = tonumber(now) or os.time()
  if then_value == nil or then_value <= 0 then
    return nil
  end
  local seconds = now_value - then_value
  if seconds < 45 then
    return "just now"
  end
  if seconds < 3600 then
    return string.format("%dm ago", math.floor(seconds / 60 + 0.5))
  end
  if seconds < 86400 then
    return string.format("%dh ago", math.floor(seconds / 3600 + 0.5))
  end
  return string.format("%dd ago", math.floor(seconds / 86400 + 0.5))
end

-- Age of the all-time peak, shown beside the value like SteamDB does.
function M.age(timestamp, now)
  local then_value = tonumber(timestamp)
  local now_value = tonumber(now) or os.time()
  if then_value == nil or then_value <= 0 or then_value > now_value then
    return nil
  end
  local days = (now_value - then_value) / 86400
  if days < 45 then
    return string.format("%dd ago", math.floor(days + 0.5))
  end
  local months = days / 30.44
  if months < 18 then
    return string.format("%.1fmo ago", months)
  end
  return string.format("%.1fy ago", days / 365.25)
end

return M
