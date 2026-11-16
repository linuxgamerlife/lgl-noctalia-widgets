--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Shared config readers. Visual values are desktop-widget settings so each
-- placed widget can have its own look; the service only reads the device
-- selection file.

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
  if value < low then
    value = low
  elseif value > high then
    value = high
  end
  return value
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

local function string_list(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) == "table" then
    local out = {}
    for _, item in ipairs(value) do
      if type(item) == "string" and item ~= "" then
        out[#out + 1] = item
      end
    end
    if #out > 0 then
      return out
    end
  elseif type(value) == "string" and value ~= "" then
    local out = {}
    for item in string.gmatch(value, "[^,]+") do
      item = noctalia.string.trim(item)
      if item ~= "" then
        out[#out + 1] = item
      end
    end
    if #out > 0 then
      return out
    end
  end
  return fallback
end

function M.visual()
  local visual = {
    content_width = integer("content_width", 620, 420, 1000),
    keyboard_layout = one_of(text("keyboard_layout", "fps"), { "wasd", "fps", "custom" }, "fps"),
    custom_keys = string_list("custom_keys", { "~", "1", "2", "3", "4", "5", "TAB", "Q", "W", "E", "R", "T", "SHIFT", "SPACE", "CTRL" }),
    show_keyboard = bool("show_keyboard", true),
    show_mouse = bool("show_mouse", true),
    show_key_labels = bool("show_key_labels", true),
    show_mouse_labels = bool("show_mouse_labels", false),
    mouse_show_wheel = bool("mouse_show_wheel", true),
    mouse_show_extra = bool("mouse_show_extra", true),

    key_size = integer("key_size", 46, 26, 64),
    key_gap = integer("key_gap", 6, 2, 16),
    key_radius = integer("key_radius", 6, 0, 20),
    mouse_size = integer("mouse_size", 300, 160, 420),
    label_scale = number("label_scale", 1.0, 0.6, 1.8),

    overlay_background = bool("overlay_background", true),
    overlay_background_color = text("overlay_background_color", "#05070a"),
    overlay_background_opacity = number("overlay_background_opacity", 0.94, 0, 1),
    overlay_radius = integer("overlay_radius", 14, 0, 40),
    overlay_border_color = text("overlay_border_color", "#22e6ff"),
    overlay_border_width = number("overlay_border_width", 2.0, 0, 6),

    key_idle_color = text("key_idle_color", "#05070a"),
    key_idle_opacity = number("key_idle_opacity", 1.0, 0, 1),
    key_border_color = text("key_border_color", "#f4f8fb"),
    key_border_width = number("key_border_width", 2.0, 0.5, 5),
    key_text_color = text("key_text_color", "#f4f8fb"),
    accent_color = text("accent_color", "#22e6ff"),
    accent_text_color = text("accent_text_color", "#031014"),
    glow_color = text("glow_color", "#22e6ff"),
    glow_opacity = number("glow_opacity", 0.35, 0, 1),
    effects_glow = bool("effects_glow", true),
    effects_ripple = bool("effects_ripple", true),

    mouse_body_color = text("mouse_body_color", "#05070a"),
    mouse_body_opacity = number("mouse_body_opacity", 1.0, 0, 1),
    mouse_border_color = text("mouse_border_color", "#f4f8fb"),
    mouse_border_width = number("mouse_border_width", 2.5, 0.5, 6),
    motion_direction = one_of(text("motion_direction", "auto"), { "auto", "screen", "movement" }, "auto"),
    motion_arrow_size = number("motion_arrow_size", 3.0, 1.0, 8.0),
    motion_arrow_scale = number("motion_arrow_scale", 1.0, 0.4, 1.0),
    motion_arrow_color = text("motion_arrow_color", "#f4f8fb"),
    motion_arrow_idle = number("motion_arrow_idle", 0.8, 0.2, 2.0),
    motion_dot_size = number("motion_dot_size", 6.0, 2.0, 20.0),
    motion_dot_scale = number("motion_dot_scale", 1.0, 0.5, 2.0),
    motion_dot_color = text("motion_dot_color", "#f4f8fb"),
  }
  return visual
end

function M.bar()
  return {
    glyph = text("glyph", "keyboard"),
    show_label = bool("show_label", false),
    label = text("label", "KBM"),
  }
end

function M.data_dir()
  if type(noctalia.pluginDataDir) == "function" then
    local dir = noctalia.pluginDataDir()
    if type(dir) == "string" and dir ~= "" then
      return dir
    end
  end
  local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
  if runtime and runtime ~= "" then
    return runtime .. "/noctalia-kbm-overlay"
  end
  return "/tmp/noctalia-kbm-overlay"
end

function M.devices_path()
  return M.data_dir() .. "/devices.json"
end

function M.runtime_path()
  return M.data_dir() .. "/runtime.json"
end

function M.read_devices()
  local path = M.devices_path()
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return {}
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

function M.valid_hex(color)
  if type(color) ~= "string" then
    return false
  end
  return string.match(color, "^#%x%x%x%x%x%x$") ~= nil
    or string.match(color, "^#%x%x%x%x%x%x%x%x$") ~= nil
end

function M.resolve_color(color, fallback)
  if M.valid_hex(color) then
    return color
  end
  if type(noctalia.getColor) == "function" then
    local resolved = noctalia.getColor(color)
    if M.valid_hex(resolved) then
      return resolved
    end
  end
  return fallback
end

function M.color_with_alpha(color, alpha)
  local opacity = tonumber(alpha) or 1
  if opacity < 0 then
    opacity = 0
  elseif opacity > 1 then
    opacity = 1
  end
  if opacity >= 0.999 then
    return color
  end
  local suffix = string.format("%02x", math.floor(opacity * 255 + 0.5))
  local r, g, b = color:match("^#(%x)(%x)(%x)$")
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
