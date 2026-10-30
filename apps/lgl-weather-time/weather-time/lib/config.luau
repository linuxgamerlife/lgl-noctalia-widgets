-- Config readers shared by the entries. Values are clamped here so a bad
-- settings file cannot make the service or a card misbehave.

local format = require("./format.luau")
local scheduler = require("./scheduler.luau")
local units = require("./units.luau")

local M = {}

local function text(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) ~= "string" or value == "" then
    return fallback
  end
  return value
end

local function bool(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) == "boolean" then
    return value
  end
  if value == "true" then
    return true
  end
  if value == "false" then
    return false
  end
  return fallback
end

local function number(key, fallback, low, high)
  local value = tonumber(noctalia.getConfig(key))
  if value == nil then
    value = fallback
  end
  return format.clamp(value, low, high)
end

local function integer(key, fallback, low, high)
  return math.floor(number(key, fallback, low, high) + 0.5)
end

local function one_of(value, allowed, fallback)
  for _, candidate in ipairs(allowed) do
    if value == candidate then
      return value
    end
  end
  return fallback
end

function M.service()
  local refresh = scheduler.refresh_minutes(noctalia.getConfig("refresh_minutes"), 15)
  local configured_units = text("units", "auto")
  local host_unit = nil
  if type(noctalia.getSetting) == "function" then
    host_unit = noctalia.getSetting("weather.unit")
  end
  local system = units.system(configured_units, host_unit)
  return {
    refresh_minutes = refresh,
    units = system,
    clock_source = one_of(text("clock_source", "auto"), { "auto", "system", "location" }, "auto"),
    clock_format = one_of(text("clock_format", "auto"), { "auto", "24h", "12h" }, "auto"),
    show_seconds = bool("show_seconds", false),
    date_style = one_of(text("date_style", "auto"), { "auto", "weekday", "short", "hidden" }, "auto"),
    secondary_timezone = text("secondary_timezone", ""),
    secondary_label = text("secondary_label", "Home"),
    scene = one_of(text("scene", "auto"), { "auto", "off", "clear", "cloudy", "rain", "snow", "thunder", "fog" }, "auto"),
    scene_theme = one_of(text("scene_theme", "auto"), { "auto", "night", "day" }, "auto"),
  }
end

function M.card()
  local content_width = integer("content_width", 380, 260, 900)
  return {
    title = text("title", "Weather & Time"),
    show_header = bool("show_header", false),
    show_date = bool("show_date", true),
    show_condition_text = bool("show_condition_text", true),
    show_forecast = bool("show_forecast", true),
    forecast_days = integer("forecast_days", 3, 3, 7),
    show_details = bool("show_details", true),
    show_location = bool("show_location", true),
    show_updated = bool("show_updated", true),
    show_attribution = bool("show_attribution", true),
    compact_layout = bool("compact_layout", false),

    content_width = content_width,
    card_gap = integer("card_gap", 8, 0, 32),
    card_padding = integer("card_padding", 16, 8, 32),
    card_radius = integer("card_radius", 14, 0, 48),
    card_fill_color = text("card_fill_color", "surface_variant"),
    card_fill_opacity = number("card_fill_opacity", 0.0, 0, 1),
    card_border_color = text("card_border_color", "outline"),
    card_border_width = number("card_border_width", 0.0, 0, 4),

    text_color = text("text_color", "on_surface"),
    muted_text_color = text("muted_text_color", "on_surface_variant"),
    weather_color = text("weather_color", "primary"),
    divider_color = text("divider_color", "outline"),
    divider_width = number("divider_width", 1, 0.5, 4),
    scene_auto_text = bool("scene_auto_text", true),

    text_scale = number("text_scale", 1, 0.5, 2),
    small_text_scale = number("small_text_scale", 1, 0.5, 2),
    clock_size = integer("clock_size", 64, 28, 96),
    forecast_glyph_size = integer("forecast_glyph_size", 20, 12, 36),

    show_scene = bool("show_scene", true),
    show_card_settings = bool("show_card_settings", false),
    show_styling = bool("show_styling", false),
    show_scaling = bool("show_scaling", false),
    show_sections = bool("show_sections", false),
  }
end

function M.bar()
  return {
    mode = one_of(text("mode", "weather"), { "weather", "time", "both" }, "weather"),
    show_temperature = bool("show_temperature", true),
    show_condition = bool("show_condition", false),
    glyph = text("glyph", "weather-cloud"),
  }
end

function M.text_size(settings, value)
  return math.max(1, math.floor(value * settings.text_scale + 0.5))
end

function M.color_with_alpha(color, alpha)
  local opacity = format.clamp(alpha or 1, 0, 1)
  if opacity >= 0.999 then
    return color
  end
  local suffix = string.format("%02x", math.floor(opacity * 255 + 0.5))
  local r, g, b = color:match("^#(%x)(%x)(%x)$")
  if r then
    return "#" .. r .. r .. g .. g .. b .. b .. suffix
  end
  r, g, b = color:match("^#(%x)(%x)(%x)(%x)$")
  if r then
    return "#" .. r .. r .. g .. g .. b .. b .. suffix
  end
  r, g, b = color:match("^#(%x%x)(%x%x)(%x%x)$")
  if r then
    return "#" .. r .. g .. b .. suffix
  end
  if color:match("^#%x%x%x%x%x%x%x%x$") then
    return color:sub(1, 7) .. suffix
  end
  return string.format("%s/%.2f", color, opacity)
end

return M
