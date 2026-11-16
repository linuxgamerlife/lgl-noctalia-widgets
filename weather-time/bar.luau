--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Compact bar widget: current condition/temperature and/or the location clock.

local config = require("./lib/config.luau")
local format = require("./lib/format.luau")
local units = require("./lib/units.luau")
local wmo = require("./lib/wmo.luau")

local cfg = config.bar()
local service_cfg = config.service()
local current = noctalia.state.get("weather_time")

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function timezone()
  if service_cfg.clock_source == "system" then
    return nil
  end
  local tz = current and current.timezone or nil
  if type(tz) ~= "string" or tz == "" then
    return nil
  end
  if type(noctalia.isValidTimezone) == "function" and not noctalia.isValidTimezone(tz) then
    return nil
  end
  return tz
end

local function clock_text()
  local pattern = service_cfg.show_seconds and "%H:%M:%S" or "%H:%M"
  if service_cfg.clock_format == "12h" then
    pattern = service_cfg.show_seconds and "%I:%M:%S %p" or "%I:%M %p"
  elseif service_cfg.clock_format == "auto" and type(noctalia.timeFormat) == "function" then
    pattern = noctalia.timeFormat() or pattern
    if service_cfg.show_seconds and not pattern:find("%%S") then
      pattern = pattern:find("%%I") and "%I:%M:%S %p" or "%H:%M:%S"
    end
  end
  if type(noctalia.formatTime) == "function" then
    local ok, value = pcall(noctalia.formatTime, pattern, os.time(), timezone())
    if ok and type(value) == "string" and value ~= "" then
      return value
    end
  end
  return os.date(pattern)
end

local function glyph_name()
  if current ~= nil and type(current.current) == "table" then
    return wmo.glyph(current.current.code, current.current.is_day)
  end
  return cfg.glyph or "weather-cloud"
end

local function temperature_text()
  if current == nil or type(current.current) ~= "table" then
    return format.DASH
  end
  local value = format.temperature(current.current.temp_c, service_cfg.units)
  if value == nil then
    return format.DASH
  end
  return string.format("%d°", math.floor(value + 0.5))
end

local function condition_text()
  if current == nil or type(current.current) ~= "table" then
    return nil
  end
  local key = current.current.condition_key or wmo.condition_key(current.current.code)
  local text = tr(key, nil)
  if text == nil then
    return nil
  end
  return text
end

local function render()
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {
    ui.glyph({
      key = "bar-glyph",
      name = cfg.mode == "time" and "clock" or glyph_name(),
      size = 14,
      color = "on_surface",
    }),
  }
  if cfg.mode ~= "time" and cfg.show_temperature and current ~= nil and type(current.current) == "table" then
    table.insert(children, ui.label({
      key = "bar-temp",
      text = temperature_text(),
      fontSize = 11,
      fontWeight = "semibold",
      color = "on_surface",
      maxLines = 1,
    }))
  end
  -- A vertical bar is only as thick as the bar. Keep at most one text value
  -- besides the glyph, and never add the long condition text there.
  if not vertical and cfg.mode ~= "time" and cfg.show_condition then
    local text = condition_text()
    if text ~= nil then
      table.insert(children, ui.label({
        key = "bar-condition",
        text = text,
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
      }))
    end
  end
  local show_time = cfg.mode ~= "weather"
    and (not vertical or cfg.mode == "time" or current == nil or type(current.current) ~= "table")
  if show_time then
    table.insert(children, ui.label({
      key = "bar-time",
      text = clock_text(),
      fontSize = 11,
      fontWeight = "semibold",
      color = "on_surface",
      maxLines = 1,
    }))
  end
  barWidget.render(container({ key = "bar-root", gap = 5, align = "center" }, children))
end

function onClick()
  if type(noctalia.togglePanel) == "function" then
    noctalia.togglePanel("linuxgamerlife/weather-time:setup")
  end
end

function onRightClick()
  local value = tonumber(noctalia.state.get("weather_time_refresh_seq")) or 0
  noctalia.state.set("weather_time_refresh_seq", value + 1)
  noctalia.notify(tr("meta.name", "Weather & Time"), tr("status.refreshing", "Refreshing weather now"))
end

function update()
  render()
end

noctalia.setUpdateInterval(service_cfg.show_seconds and 1000 or 15000)
noctalia.state.watch("weather_time", function(value)
  current = value
  render()
end)
render()
