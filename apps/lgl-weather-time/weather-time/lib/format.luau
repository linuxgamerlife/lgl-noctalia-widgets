-- Small numeric and display helpers shared by the service and the UI entries.
-- Pure functions only: no noctalia.* access, so every helper is testable.

local M = {}

local DASH = "—"

function M.clamp(value, low, high)
  if type(value) ~= "number" then
    return low
  end
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

function M.round(value, decimals)
  if type(value) ~= "number" then
    return nil
  end
  local factor = 10 ^ (decimals or 0)
  if value >= 0 then
    return math.floor(value * factor + 0.5) / factor
  end
  return math.ceil(value * factor - 0.5) / factor
end

function M.trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.number(value, decimals)
  if type(value) ~= "number" then
    return DASH
  end
  local places = decimals or 0
  if places <= 0 then
    return string.format("%.0f", value)
  end
  local text = string.format("%." .. tostring(places) .. "f", value)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  return text
end

function M.temperature(value_c, system)
  if type(value_c) ~= "number" then
    return nil
  end
  if system == "imperial" then
    return value_c * 9 / 5 + 32
  end
  return value_c
end

function M.temperature_text(value_c, system, unit)
  local value = M.temperature(value_c, system)
  if value == nil then
    return DASH
  end
  return string.format("%d %s", math.floor(value + 0.5), unit or "")
end

function M.wind(value_kmh, system)
  if type(value_kmh) ~= "number" then
    return nil
  end
  if system == "imperial" then
    return value_kmh * 0.621371
  end
  return value_kmh
end

function M.wind_text(value_kmh, system, unit)
  local value = M.wind(value_kmh, system)
  if value == nil then
    return DASH
  end
  return string.format("%d %s", math.floor(value + 0.5), unit or "")
end

function M.precipitation(value_mm, system)
  if type(value_mm) ~= "number" then
    return nil
  end
  if system == "imperial" then
    return value_mm / 25.4
  end
  return value_mm
end

function M.precipitation_text(value_mm, system, unit)
  local value = M.precipitation(value_mm, system)
  if value == nil then
    return DASH
  end
  if system == "imperial" then
    return string.format("%.2f %s", value, unit or "in")
  end
  return string.format("%.1f %s", value, unit or "mm")
end

function M.percent(value)
  if type(value) ~= "number" then
    return DASH
  end
  return string.format("%d%%", math.floor(value + 0.5))
end

function M.age_parts(seconds)
  local value = math.max(0, math.floor(tonumber(seconds) or 0))
  if value < 60 then
    return value, "now"
  elseif value < 3600 then
    return math.floor(value / 60), "minutes"
  elseif value < 86400 then
    return math.floor(value / 3600), "hours"
  end
  return math.floor(value / 86400), "days"
end

function M.age_text(seconds, tr)
  local value, unit = M.age_parts(seconds)
  if unit == "now" then
    return tr("age.now", "just now")
  end
  local key = "age." .. unit
  local fallback = unit == "minutes" and "{n} min ago" or ("{n} " .. unit .. " ago")
  local text = tr(key, fallback, { n = value })
  return text
end

function M.moon_phase_icon(is_day)
  return is_day and "weather-sun" or "weather-moon"
end

M.DASH = DASH

return M
