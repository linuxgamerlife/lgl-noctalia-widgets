--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Declarative Weather & Time desktop card.
--
-- The service publishes "weather_time". This entry only formats and renders it.
-- When a scene is available, the generated SVG is placed behind real UI text
-- with a negative flex gap, giving a full-bleed effect without a z-index API.

local config = require("./lib/config.luau")
local date = require("./lib/date.luau")
local format = require("./lib/format.luau")
local units = require("./lib/units.luau")
local wmo = require("./lib/wmo.luau")

local PLUGIN_ID = "linuxgamerlife/weather-time"
local PANEL_ID = PLUGIN_ID .. ":setup"

local cfg = config.card()
local service_cfg = config.service()
-- Host-handled surface keys. Reading them keeps the manifest lint contract and
-- lets the card add a small inset when the host panel is off.
local host = {
  background = noctalia.getConfig("background"),
  background_color = noctalia.getConfig("background_color"),
  background_opacity = noctalia.getConfig("background_opacity"),
  background_radius = noctalia.getConfig("background_radius"),
  background_padding = noctalia.getConfig("background_padding"),
}
local host_background = host.background ~= false

local CONDITION_FALLBACK = {
  ["conditions.clear"] = "Clear",
  ["conditions.mainly_clear"] = "Mainly clear",
  ["conditions.partly_cloudy"] = "Partly cloudy",
  ["conditions.overcast"] = "Overcast",
  ["conditions.fog"] = "Fog",
  ["conditions.drizzle"] = "Drizzle",
  ["conditions.rain"] = "Rain",
  ["conditions.freezing_rain"] = "Freezing rain",
  ["conditions.snow"] = "Snow",
  ["conditions.showers"] = "Showers",
  ["conditions.snow_showers"] = "Snow showers",
  ["conditions.thunderstorm"] = "Thunderstorm",
  ["conditions.thunderstorm_hail"] = "Thunderstorm with hail",
  ["conditions.unknown"] = "Unknown",
}

local current = noctalia.state.get("weather_time")
local current_scene = current and current.scene or nil
local last_key = nil

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function text_size(value)
  return math.max(1, math.floor(value * cfg.text_scale + 0.5))
end

-- Labels, dates, forecast text and footers have their own multiplier so the
-- clock and temperature can stay large while the small print is made readable.
local function small_text_size(value)
  return math.max(1, math.floor(value * cfg.text_scale * cfg.small_text_scale + 0.5))
end

local function layout_padding()
  if cfg.compact_layout then
    return math.min(cfg.card_padding, 10)
  end
  return cfg.card_padding
end

local function layout_gap()
  return cfg.compact_layout and 4 or 8
end

local function layout_clock_px()
  local value = cfg.clock_size
  if cfg.content_width < 320 then
    value = math.min(value, 48)
  end
  if cfg.compact_layout then
    value = math.min(value, 40)
  end
  return math.floor(value * cfg.text_scale + 0.5)
end

local function layout_weather_glyph()
  if cfg.compact_layout then
    return math.min(cfg.content_width < 320 and 22 or 26, 26)
  end
  return cfg.content_width < 320 and 24 or 30
end

local function layout_weather_temp()
  if cfg.compact_layout then
    return cfg.content_width < 320 and 26 or 30
  end
  return cfg.content_width < 320 and 30 or 38
end

local function layout_forecast_glyph()
  local value = cfg.forecast_glyph_size
  if cfg.compact_layout then
    value = math.min(value, 14)
  elseif cfg.content_width < 320 then
    value = math.min(value, 16)
  end
  return value
end

local function layout_main_height()
  local clock_px = layout_clock_px()
  local show_date = cfg.show_date and service_cfg.date_style ~= "hidden"
  local date_h = (show_date or not cfg.compact_layout)
      and small_text_size(cfg.compact_layout and 10 or 11) or 0
  local secondary_h = (not cfg.compact_layout and service_cfg.secondary_timezone ~= "")
      and small_text_size(10) or 0
  local clock_h = clock_px + 4 + date_h + secondary_h
  local weather_h = text_size(layout_weather_temp())
    + (cfg.show_condition_text and small_text_size(cfg.compact_layout and 10 or 12) or 0)
    + small_text_size(cfg.compact_layout and 9 or 11)
    + 6
  return math.max(clock_h, weather_h)
end

local function color_with_alpha(color, alpha)
  return config.color_with_alpha(color, alpha)
end

local function scene_active()
  return cfg.show_scene
    and current_scene ~= nil
    and type(current_scene.image) == "string"
    and current_scene.image ~= ""
end

local function custom_color(value, default)
  return type(value) == "string" and value ~= "" and value ~= default
end

local function palette()
  local light = scene_active() and cfg.scene_auto_text
  local text = cfg.text_color
  local muted = cfg.muted_text_color
  local weather = cfg.weather_color
  local divider = cfg.divider_color
  -- Automatic scene colours only replace untouched palette defaults. Any
  -- explicit role or hex value is a user choice and wins in both modes.
  if light and not custom_color(cfg.text_color, "on_surface") then
    text = "#F6F9FF"
  end
  if light and not custom_color(cfg.muted_text_color, "on_surface_variant") then
    muted = "#C9D8EA"
  end
  if light and not custom_color(cfg.weather_color, "primary") then
    weather = "#DCEBFF"
  end
  if light and not custom_color(cfg.divider_color, "outline") then
    divider = "#FFFFFF"
  end
  return {
    text = text,
    muted = muted,
    weather = weather,
    divider = divider,
    warning = light and "#FFD7A8" or "tertiary",
    error = light and "#FFB4B4" or "error",
  }
end

local function condition_text(model)
  if model == nil or type(model.current) ~= "table" then
    return tr("status.no_weather", "No weather data")
  end
  local key = model.current.condition_key or wmo.condition_key(model.current.code)
  return tr(key, CONDITION_FALLBACK[key] or "Unknown")
end

local function tz_valid(value)
  if type(value) ~= "string" or value == "" then
    return false
  end
  if type(noctalia.isValidTimezone) == "function" then
    return noctalia.isValidTimezone(value) == true
  end
  return value:match("^[A-Za-z0-9_%+%-/]+$") ~= nil
end

local function clock_timezone()
  if service_cfg.clock_source == "system" then
    return nil
  end
  local tz = current and current.timezone or nil
  if tz_valid(tz) then
    return tz
  end
  return nil
end

local function format_time(pattern, timestamp, timezone)
  if type(noctalia.formatTime) == "function" then
    local ok, value = pcall(noctalia.formatTime, pattern, timestamp, timezone)
    if ok and type(value) == "string" and value ~= "" then
      return value
    end
  end
  if timezone ~= nil and type(noctalia.formatTime) ~= "function" then
    return os.date(pattern, timestamp)
  end
  return os.date(pattern, timestamp)
end

local function clock_text(tz)
  local pattern
  local auto_pattern = nil
  if type(noctalia.timeFormat) == "function" then
    auto_pattern = noctalia.timeFormat()
  end
  if service_cfg.clock_format == "24h" then
    pattern = service_cfg.show_seconds and "%H:%M:%S" or "%H:%M"
  elseif service_cfg.clock_format == "12h" then
    pattern = service_cfg.show_seconds and "%I:%M:%S %p" or "%I:%M %p"
  else
    pattern = auto_pattern or "%H:%M"
    if service_cfg.show_seconds and not pattern:find("%%S") then
      local twelve = pattern:find("%%I") or pattern:find("%%l") or pattern:find("%%p")
      pattern = twelve and "%I:%M:%S %p" or "%H:%M:%S"
    end
  end
  return format_time(pattern, os.time(), tz)
end

local function date_text(tz)
  if not cfg.show_date then
    return nil
  end
  local auto = nil
  if type(noctalia.dateFormat) == "function" then
    auto = noctalia.dateFormat()
  end
  local pattern = auto or "%A, %B %d"
  if service_cfg.date_style == "weekday" then
    pattern = "%A"
  elseif service_cfg.date_style == "short" then
    pattern = "%a, %b %d"
  elseif service_cfg.date_style == "hidden" then
    return nil
  end
  return format_time(pattern, os.time(), tz)
end

local function secondary_text(tz)
  local zone = service_cfg.secondary_timezone
  if not tz_valid(zone) then
    return nil
  end
  local label = service_cfg.secondary_label
  if label == nil or label == "" then
    label = tr("labels.secondary", "Home")
  end
  local value = format_time(service_cfg.show_seconds and "%H:%M:%S" or "%H:%M", os.time(), zone)
  return label .. " " .. value
end

local function forecast_weekday(day, tz, model)
  local epoch = date.noon_epoch(day.date)
  if epoch == nil then
    return ""
  end
  -- Noon UTC is not noon everywhere. Shift by the provider's offset so the
  -- weekday is stable for UTC+13/+14 zones too.
  epoch = epoch - (tonumber(model and model.utc_offset_seconds) or 0)
  return format_time("%a", epoch, tz)
end

local function temperature(value)
  return format.temperature(value, service_cfg.units)
end

local function temp_text(value)
  return format.temperature_text(value, service_cfg.units, units.temperature_unit(service_cfg.units))
end

local function high_low(model)
  if model == nil or type(model.today) ~= "table" then
    return format.DASH
  end
  local low = temperature(model.today.min_c)
  local high = temperature(model.today.max_c)
  if low == nil or high == nil then
    return format.DASH
  end
  return string.format("%d / %d %s", math.floor(low + 0.5), math.floor(high + 0.5),
    units.temperature_unit(service_cfg.units))
end

local function is_stale(model)
  if model == nil then
    return false
  end
  if model.stale == true then
    return true
  end
  local fetched = tonumber(model.fetched_at)
  if fetched == nil then
    return true
  end
  return os.time() - fetched > (tonumber(model.refresh_minutes) or 15) * 60 * 2
end

local function status_text(model)
  if model == nil then
    return nil
  end
  if model.location == nil then
    return tr("status.set_location", "Set a location")
  end
  if model.current == nil then
    if model.error ~= nil then
      return tr("status.error", "Weather unavailable")
    end
    return tr("status.loading", "Loading weather…")
  end
  if model.error ~= nil then
    return tr("status.cached", "Cached weather — refresh failed")
  end
  if is_stale(model) then
    return tr("status.stale", "Cached weather")
  end
  return nil
end

local function setup_button(colors)
  return ui.button({
    key = "setup",
    text = tr("actions.set_location", "Set location"),
    fontSize = small_text_size(11),
    variant = "secondary",
    controlSize = "sm",
    height = small_text_size(26),
    onClick = "openSetup",
  })
end

local function weather_column(model, colors)
  if model == nil or model.current == nil then
    local no_location = model == nil or model.location == nil
    local children = {
      ui.glyph({ key = "weather-glyph", name = "weather-cloud-off", size = text_size(30), color = colors.muted }),
    }
    if not no_location then
      table.insert(children, ui.label({
        key = "weather-status",
        text = status_text(model) or tr("status.no_weather", "No weather data"),
        fontSize = small_text_size(11),
        color = colors.muted,
        maxLines = 2,
        textAlign = "right",
      }))
    end
    if no_location then
      table.insert(children, setup_button(colors))
    end
    return ui.column({
      key = "weather",
      width = math.min(176, math.floor(cfg.content_width * 0.46)),
      gap = 4,
      align = "end",
      justify = "center",
    }, children)
  end

  local value = temp_text(model.current.temp_c)
  local glyph = wmo.glyph(model.current.code, model.current.is_day)
  local children = {
    ui.row({ key = "weather-value", gap = 8, align = "center", justify = "end" }, {
      ui.glyph({ key = "weather-glyph", name = glyph, size = text_size(layout_weather_glyph()), color = colors.weather }),
      ui.label({
        key = "weather-temp",
        text = value,
        fontSize = text_size(layout_weather_temp()),
        fontWeight = "regular",
        color = colors.text,
        maxLines = 1,
      }),
    }),
  }
  if cfg.show_condition_text then
    table.insert(children, ui.label({
      key = "weather-condition",
      text = condition_text(model),
      fontSize = small_text_size(cfg.compact_layout and 10 or 12),
      color = colors.muted,
      maxLines = 1,
      textAlign = "right",
    }))
  end
  table.insert(children, ui.label({
    key = "weather-high-low",
    text = high_low(model),
    fontSize = small_text_size(cfg.compact_layout and 9 or 11),
    color = colors.muted,
    maxLines = 1,
    textAlign = "right",
  }))
  return ui.column({
    key = "weather",
    width = math.min(176, math.floor(cfg.content_width * 0.46)),
    gap = 2,
    align = "end",
    justify = "center",
  }, children)
end

local function clock_column(model, colors)
  local tz = clock_timezone()
  local children = {
    ui.label({
      key = "clock",
      text = clock_text(tz),
      fontSize = layout_clock_px(),
      fontWeight = "regular",
      color = colors.text,
      maxLines = 1,
      maxWidth = math.max(120, math.floor(cfg.content_width * 0.55)),
    }),
  }
  local zone = nil
  if model ~= nil then
    if type(model.timezone_abbreviation) == "string" and model.timezone_abbreviation ~= "" then
      zone = model.timezone_abbreviation
    elseif type(model.timezone) == "string" and model.timezone ~= "" then
      zone = model.timezone
    end
  end
  local value = date_text(tz)
  if value ~= nil and zone ~= nil then
    value = value .. "  ·  " .. zone
  elseif value == nil and not cfg.compact_layout then
    value = zone
  end
  if value ~= nil then
    table.insert(children, ui.label({
      key = "date",
      text = value,
      fontSize = small_text_size(cfg.compact_layout and 10 or 11),
      color = colors.muted,
      maxLines = 1,
    }))
  end
  if not cfg.compact_layout then
    local secondary = secondary_text(tz)
    if secondary ~= nil then
      table.insert(children, ui.label({
        key = "secondary",
        text = secondary,
        fontSize = small_text_size(10),
        color = colors.muted,
        maxLines = 1,
      }))
    end
  end
  return ui.column({
    key = "clock-column",
    flexGrow = 1,
    gap = 1,
    align = "start",
    justify = "center",
  }, children)
end

local function forecast_row(model, colors)
  if not cfg.show_forecast or model == nil or type(model.forecast) ~= "table" then
    return nil
  end
  local tz = clock_timezone()
  local start = 2
  local columns = {}
  local count = math.min(cfg.forecast_days, math.max(0, #model.forecast - 1))
  for index = start, start + count - 1 do
    local day = model.forecast[index]
    if day ~= nil then
      local children = {
        ui.label({
          key = "forecast-day-" .. tostring(index),
          text = forecast_weekday(day, tz, model),
          fontSize = small_text_size(cfg.compact_layout and 9 or 10),
          fontWeight = "semibold",
          color = colors.muted,
          maxLines = 1,
          textAlign = "center",
        }),
        ui.glyph({
          key = "forecast-glyph-" .. tostring(index),
          name = wmo.glyph(day.code, true),
          size = text_size(layout_forecast_glyph()),
          color = colors.weather,
        }),
      }
      local low = temperature(day.min_c)
      local high = temperature(day.max_c)
      table.insert(children, ui.label({
        key = "forecast-temp-" .. tostring(index),
        text = (low ~= nil and high ~= nil)
          and string.format("%d/%d°", math.floor(low + 0.5), math.floor(high + 0.5))
          or format.DASH,
        fontSize = small_text_size(cfg.compact_layout and 9 or 10),
        color = colors.text,
        maxLines = 1,
        textAlign = "center",
      }))
      columns[#columns + 1] = ui.column({
        key = "forecast-" .. tostring(index),
        flexGrow = 1,
        gap = 2,
        align = "center",
      }, children)
    end
  end
  if #columns == 0 then
    return nil
  end
  return ui.row({ key = "forecast", gap = 6, align = "center", justify = "space_between" }, columns)
end

local function detail_cell(key, label, value, colors)
  return ui.row({ key = key, gap = 4, align = "center" }, {
    ui.label({ key = key .. "-label", text = label, fontSize = small_text_size(9), color = colors.muted, maxLines = 1 }),
    ui.label({ key = key .. "-value", text = value, fontSize = small_text_size(10), fontWeight = "semibold", color = colors.text, maxLines = 1 }),
  })
end

local function details_row(model, colors)
  -- A compact card drops the details row entirely so the clock and forecast
  -- never get squeezed into each other on a short desktop tile.
  if cfg.compact_layout or not cfg.show_details or model == nil or model.current == nil then
    return nil
  end
  local current_model = model.current
  local wind = format.wind_text(current_model.wind_kmh, service_cfg.units, units.wind_unit(service_cfg.units))
  local feels = temp_text(current_model.feels_like_c)
  local humidity = current_model.humidity ~= nil and format.percent(current_model.humidity) or format.DASH
  local children = {
    detail_cell("detail-feels", tr("labels.feels", "Feels"), feels, colors),
    detail_cell("detail-wind", tr("labels.wind", "Wind"), wind, colors),
    detail_cell("detail-humidity", tr("labels.humidity", "Humidity"), humidity, colors),
  }
  if not cfg.compact_layout and cfg.content_width >= 340 then
    local precip = format.precipitation_text(
      current_model.precipitation_mm,
      service_cfg.units,
      units.precipitation_unit(service_cfg.units)
    )
    table.insert(children, detail_cell("detail-precip", tr("labels.precipitation", "Precip"), precip, colors))
  end
  return ui.row({ key = "details", gap = 10, align = "center", justify = "space_between" }, children)
end

local function footer(model, colors)
  local children = {}
  if cfg.compact_layout then
    table.insert(children, ui.spacer({ key = "footer-spacer", flexGrow = 1 }))
  else
    if cfg.show_location then
      local label = model and model.location and model.location.label or tr("labels.no_location", "No location")
      table.insert(children, ui.label({
        key = "footer-location",
        text = label,
        fontSize = small_text_size(9),
        color = colors.muted,
        flexGrow = 1,
        maxLines = 1,
      }))
    else
      table.insert(children, ui.spacer({ key = "footer-spacer", flexGrow = 1 }))
    end
    local status = model ~= nil and model.location ~= nil and status_text(model) or nil
    if cfg.show_updated and model ~= nil and model.fetched_at ~= nil then
      local age = format.age_text(os.time() - model.fetched_at, tr)
      table.insert(children, ui.label({
        key = "footer-updated",
        text = age,
        fontSize = small_text_size(9),
        color = status ~= nil and colors.warning or colors.muted,
        maxLines = 1,
      }))
    elseif status ~= nil then
      table.insert(children, ui.label({
        key = "footer-status",
        text = status,
        fontSize = small_text_size(9),
        color = colors.warning,
        maxLines = 1,
      }))
    end
    if cfg.show_attribution then
      table.insert(children, ui.label({
        key = "footer-attribution",
        text = "Open-Meteo",
        fontSize = small_text_size(8),
        color = colors.muted,
        maxLines = 1,
      }))
    end
  end
  local button_size = cfg.compact_layout and 18 or 22
  table.insert(children, ui.button({
    key = "footer-refresh",
    glyph = "refresh",
    glyphSize = text_size(cfg.compact_layout and 11 or 12),
    variant = "ghost",
    controlSize = "sm",
    height = text_size(button_size),
    onClick = "requestRefresh",
  }))
  table.insert(children, ui.button({
    key = "footer-settings",
    glyph = "settings",
    glyphSize = text_size(cfg.compact_layout and 11 or 12),
    variant = "ghost",
    controlSize = "sm",
    height = text_size(button_size),
    onClick = "openSettings",
  }))
  return ui.row({ key = "footer", gap = 6, align = "center" }, children)
end

local function content_children(model, colors)
  local children = {
    ui.row({
      key = "main",
      flexGrow = 1,
      minHeight = layout_main_height(),
      gap = 10,
      align = "center",
      justify = "space_between",
    }, {
      clock_column(model, colors),
      weather_column(model, colors),
    }),
  }
  local forecast = forecast_row(model, colors)
  local details = details_row(model, colors)
  if forecast ~= nil or details ~= nil then
    table.insert(children, ui.separator({
      key = "content-divider",
      orientation = "horizontal",
      thickness = cfg.divider_width,
      color = color_with_alpha(colors.divider, 0.22),
    }))
  end
  if forecast ~= nil then
    table.insert(children, forecast)
  end
  if details ~= nil then
    table.insert(children, details)
  end
  table.insert(children, footer(model, colors))
  return children
end

local function content_height(model)
  local padding = layout_padding()
  local gap = layout_gap()
  local has_details = cfg.show_details and not cfg.compact_layout
    and model ~= nil and type(model.current) == "table"
  local has_forecast = cfg.show_forecast and cfg.forecast_days > 0
    and model ~= nil and type(model.forecast) == "table" and #model.forecast > 1
  local forecast_h = 0
  if has_forecast then
    forecast_h = small_text_size(cfg.compact_layout and 9 or 10)
      + text_size(layout_forecast_glyph())
      + small_text_size(cfg.compact_layout and 9 or 10)
      + 4
  end
  local details_h = has_details and (small_text_size(10) + 4) or 0
  local footer_h = text_size(cfg.compact_layout and 18 or 22)
  local separator_h = (has_forecast or has_details) and 1 or 0
  local child_count = 2 -- main + footer
  if has_forecast or has_details then
    child_count = child_count + 1
  end
  if has_forecast then
    child_count = child_count + 1
  end
  if has_details then
    child_count = child_count + 1
  end
  local height = padding * 2
    + layout_main_height()
    + footer_h
    + separator_h
    + forecast_h
    + details_h
    + math.max(0, child_count - 1) * gap
  return format.clamp(height, 120, 620)
end

local function header(colors)
  return ui.row({ key = "header", gap = 8, align = "center" }, {
    ui.label({
      key = "header-title",
      text = cfg.title,
      fontSize = text_size(16),
      fontWeight = "regular",
      color = colors.text,
      flexGrow = 1,
      maxLines = 1,
      maxWidth = math.max(80, cfg.content_width - 80),
    }),
    ui.button({
      key = "header-refresh",
      glyph = "refresh",
      glyphSize = text_size(14),
      variant = "ghost",
      controlSize = "sm",
      onClick = "requestRefresh",
    }),
    ui.button({
      key = "header-settings",
      glyph = "settings",
      glyphSize = text_size(14),
      variant = "ghost",
      controlSize = "sm",
      onClick = "openSettings",
    }),
  })
end

local function render()
  local colors = palette()
  local model = current
  if type(model) ~= "table" then
    model = nil
  end
  local tz = clock_timezone()
  local key = table.concat({
    tostring(model and model.seq or -1),
    tostring(model and model.fetched_at or 0),
    tostring(model and model.error and model.error.reason or ""),
    tostring(current_scene and current_scene.variant or ""),
    clock_text(tz),
    tostring(date_text(tz) or ""),
    tostring(math.floor(os.time() / 60)),
    tostring(cfg.content_width),
  }, "|")
  if key == last_key then
    return
  end
  last_key = key

  local children = content_children(model, colors)
  local scene_on = scene_active()
  local stack
  if scene_on then
    local height = content_height(model)
    stack = ui.column({ key = "scene-stack", width = cfg.content_width, gap = -height }, {
      ui.image({
        key = "scene-image",
        path = current_scene.image,
        width = cfg.content_width,
        height = height,
        fit = "cover",
        radius = cfg.card_radius,
      }),
      ui.column({
        key = "content",
        width = cfg.content_width,
        height = height,
        padding = layout_padding(),
        gap = layout_gap(),
        align = "stretch",
        opacity = is_stale(model) and model ~= nil and model.current ~= nil and 0.82 or 1,
      }, children),
    })
  else
    stack = ui.column({
      key = "content",
      width = cfg.content_width,
      padding = layout_padding(),
      gap = layout_gap(),
      align = "stretch",
      radius = cfg.card_radius,
      fill = color_with_alpha(cfg.card_fill_color, cfg.card_fill_opacity),
      border = cfg.card_border_color,
      borderWidth = cfg.card_border_width,
    }, children)
  end

  local root_children = {}
  if cfg.show_header then
    table.insert(root_children, header(colors))
  end
  table.insert(root_children, stack)
  desktopWidget.render(ui.column({
    key = "card",
    width = cfg.content_width,
    gap = cfg.card_gap,
    align = "stretch",
    -- Content padding is owned by the inner layout; the root itself stays
    -- edge-to-edge so the scene and the transparent text-only mode both use the
    -- full tile instead of accumulating an extra inset.
    padding = 0,
  }, root_children))
end

function openSetup()
  if type(noctalia.togglePanel) == "function" then
    noctalia.togglePanel(PANEL_ID)
  end
end

function openSettings()
  if type(noctalia.openSettings) == "function" then
    noctalia.openSettings()
  end
end

function requestRefresh()
  local value = tonumber(noctalia.state.get("weather_time_refresh_seq")) or 0
  noctalia.state.set("weather_time_refresh_seq", value + 1)
end

function update()
  render()
end

local function ingest(value)
  current = value
  current_scene = type(value) == "table" and value.scene or nil
  noctalia.setUpdateInterval(1000)
  last_key = nil
  render()
end

noctalia.setUpdateInterval(1000)
if current ~= nil then
  ingest(current)
else
  render()
end
noctalia.state.watch("weather_time", function(value)
  ingest(value)
end)
