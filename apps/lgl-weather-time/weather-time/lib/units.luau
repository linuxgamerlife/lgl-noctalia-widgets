-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Unit-system resolution and display strings. Canonical state is metric.

local M = {}

M.METRIC = "metric"
M.IMPERIAL = "imperial"

function M.normalize(value, fallback)
  if value == "metric" or value == "celsius" or value == "si" then
    return M.METRIC
  end
  if value == "imperial" or value == "fahrenheit" then
    return M.IMPERIAL
  end
  return fallback or M.METRIC
end

function M.system(configured, host_unit)
  if configured == "metric" or configured == "imperial" then
    return configured
  end
  return M.normalize(host_unit, M.METRIC)
end

function M.temperature_unit(system)
  return system == M.IMPERIAL and "°F" or "°C"
end

function M.wind_unit(system)
  return system == M.IMPERIAL and "mph" or "km/h"
end

function M.precipitation_unit(system)
  return system == M.IMPERIAL and "in" or "mm"
end

return M
