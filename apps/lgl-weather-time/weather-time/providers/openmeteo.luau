-- Open-Meteo forecast transport.
--
-- One HTTPS GET per refresh, no API key, no redirects. Coordinates are rounded
-- to two decimals by lib/location before they reach this module.

local M = {}

M.ENDPOINT = "https://api.open-meteo.com/v1/forecast"
M.MAX_BODY = 2 * 1024 * 1024

local CURRENT_FIELDS = table.concat({
  "temperature_2m",
  "apparent_temperature",
  "relative_humidity_2m",
  "weather_code",
  "is_day",
  "wind_speed_10m",
  "wind_direction_10m",
  "precipitation",
  "uv_index",
}, ",")

local DAILY_FIELDS = table.concat({
  "weather_code",
  "temperature_2m_max",
  "temperature_2m_min",
  "sunrise",
  "sunset",
  "precipitation_probability_max",
}, ",")

local function coord(value)
  local number = tonumber(value)
  if number == nil then
    return nil
  end
  if number >= 0 then
    return string.format("%.2f", math.floor(number * 100 + 0.5) / 100)
  end
  return string.format("%.2f", math.ceil(number * 100 - 0.5) / 100)
end

function M.build_url(location, days)
  if type(location) ~= "table" then
    return nil
  end
  local latitude = coord(location.latitude)
  local longitude = coord(location.longitude)
  if latitude == nil or longitude == nil then
    return nil
  end
  local forecast_days = math.max(4, math.min(8, (tonumber(days) or 3) + 1))
  return table.concat({
    M.ENDPOINT,
    "?latitude=", latitude,
    "&longitude=", longitude,
    "&current=", CURRENT_FIELDS,
    "&daily=", DAILY_FIELDS,
    "&timezone=auto",
    "&forecast_days=", tostring(forecast_days),
    "&temperature_unit=celsius",
    "&wind_speed_unit=kmh",
    "&precipitation_unit=mm",
  })
end

function M.parse(body)
  if type(body) ~= "string" or body == "" then
    return nil, "empty response"
  end
  if #body > M.MAX_BODY then
    return nil, "response too large"
  end
  local decoded, err = noctalia.json.decode(body)
  if decoded == nil then
    return nil, err or "invalid json"
  end
  if type(decoded) ~= "table" then
    return nil, "response is not an object"
  end
  if type(decoded.current) ~= "table" or type(decoded.daily) ~= "table" then
    return nil, "response is missing current/daily"
  end
  return decoded
end

-- callback({ ok = bool, status = number, body = string, error = string? })
function M.request(location, days, callback)
  local url = M.build_url(location, days)
  if url == nil then
    callback({ ok = false, status = 0, body = "", error = "invalid location" })
    return false
  end
  if type(noctalia.http) ~= "function" then
    callback({ ok = false, status = 0, body = "", error = "http unavailable" })
    return false
  end
  local accepted = noctalia.http({
    url = url,
    method = "GET",
    headers = { "Accept: application/json" },
    follow_redirects = false,
    allow_insecure_tls = false,
  }, function(response)
    callback({
      ok = response ~= nil and response.ok == true,
      status = response ~= nil and tonumber(response.status) or 0,
      body = response ~= nil and response.body or "",
      error = nil,
    })
  end)
  if not accepted then
    callback({ ok = false, status = 0, body = "", error = "request not accepted" })
  end
  return accepted
end

return M
