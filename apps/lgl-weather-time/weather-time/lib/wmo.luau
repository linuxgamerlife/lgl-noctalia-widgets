-- WMO weather-code mapping used by both the card and the scene generator.
-- Keys are translation keys; glyphs are Noctalia's built-in weather glyphs.

local M = {}

local function is_between(code, low, high)
  return code >= low and code <= high
end

function M.category(code)
  local value = tonumber(code)
  if value == nil then
    return "unknown"
  end
  if value == 0 or value == 1 then
    return "clear"
  end
  if value == 2 or value == 3 then
    return "cloudy"
  end
  if value == 45 or value == 48 then
    return "fog"
  end
  if is_between(value, 51, 57) then
    return "rain"
  end
  if is_between(value, 61, 67) then
    return "rain"
  end
  if is_between(value, 71, 77) then
    return "snow"
  end
  if is_between(value, 80, 82) then
    return "rain"
  end
  if is_between(value, 85, 86) then
    return "snow"
  end
  if is_between(value, 95, 99) then
    return "thunder"
  end
  return "unknown"
end

function M.condition_key(code)
  local value = tonumber(code)
  if value == nil then
    return "conditions.unknown"
  end
  if value == 0 then
    return "conditions.clear"
  end
  if value == 1 then
    return "conditions.mainly_clear"
  end
  if value == 2 then
    return "conditions.partly_cloudy"
  end
  if value == 3 then
    return "conditions.overcast"
  end
  if value == 45 or value == 48 then
    return "conditions.fog"
  end
  if is_between(value, 51, 57) then
    return "conditions.drizzle"
  end
  if is_between(value, 61, 65) then
    return "conditions.rain"
  end
  if value == 66 or value == 67 then
    return "conditions.freezing_rain"
  end
  if is_between(value, 71, 77) then
    return "conditions.snow"
  end
  if is_between(value, 80, 82) then
    return "conditions.showers"
  end
  if is_between(value, 85, 86) then
    return "conditions.snow_showers"
  end
  if is_between(value, 95, 96) then
    return "conditions.thunderstorm"
  end
  if is_between(value, 97, 99) then
    return "conditions.thunderstorm_hail"
  end
  return "conditions.unknown"
end

function M.glyph(code, is_day)
  local value = tonumber(code)
  if value == nil then
    return "weather-cloud-off"
  end
  if value == 0 then
    return is_day and "weather-sun" or "weather-moon"
  end
  if value == 1 then
    return is_day and "weather-sun" or "weather-moon-stars"
  end
  if value == 2 then
    return is_day and "weather-cloud-sun" or "weather-cloud"
  end
  if value == 3 then
    return "weather-cloud"
  end
  if value == 45 or value == 48 then
    return "weather-cloud-haze"
  end
  if is_between(value, 51, 67) or is_between(value, 80, 82) then
    return "weather-cloud-rain"
  end
  if is_between(value, 71, 77) or is_between(value, 85, 86) then
    return "weather-cloud-snow"
  end
  if is_between(value, 95, 99) then
    return "weather-cloud-lightning"
  end
  return "weather-cloud-off"
end

function M.scene_category(code)
  local category = M.category(code)
  if category == "unknown" then
    return "cloudy"
  end
  return category
end

return M
