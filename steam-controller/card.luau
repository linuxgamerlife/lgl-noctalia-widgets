--!nonstrict
-- Declarative desktop card for the Steam Controller 2.
--
-- By default the card mirrors the controller's LED: the battery fill is white
-- through the puck, blue over Bluetooth, green on USB-C, orange while charging
-- off-dock, red when low. The controller line/body and the battery fill (or a
-- custom fill) are configurable. Charging pulses. The battery service publishes
-- the live state; this entry only renders it.

local STALE_AFTER = 20 -- seconds without a daemon heartbeat

local settings = {
  illustration_color = noctalia.getConfig("illustration_color") or "#e8ebef",
  controller_body_color = noctalia.getConfig("controller_body_color") or "#2c3035",
  controller_stroke_width = tonumber(noctalia.getConfig("controller_stroke_width")) or 3.4,
  battery_color_mode = noctalia.getConfig("battery_color_mode") or "connection",
  battery_fill_color = noctalia.getConfig("battery_fill_color") or "#fcfcfc",
  battery_fill_opacity = tonumber(noctalia.getConfig("battery_fill_opacity")) or 1.0,
  battery_low_color = noctalia.getConfig("battery_low_color") or "#ed4c4c",
  text_color = noctalia.getConfig("text_color") or "on_surface",
  muted_text_color = noctalia.getConfig("muted_text_color") or "on_surface_variant",
  show_signal = noctalia.getConfig("show_signal"),
  signal_style = noctalia.getConfig("signal_style") or "bars",
}
if settings.battery_color_mode ~= "custom" then
  settings.battery_color_mode = "connection"
end
if settings.battery_fill_color == "" then
  settings.battery_fill_color = "#fcfcfc"
end
if settings.battery_low_color == "" then
  settings.battery_low_color = "#ed4c4c"
end
if settings.battery_fill_opacity < 0 then
  settings.battery_fill_opacity = 0
elseif settings.battery_fill_opacity > 1 then
  settings.battery_fill_opacity = 1
end
if settings.text_color == "" then
  settings.text_color = "on_surface"
end
if settings.muted_text_color == "" then
  settings.muted_text_color = "on_surface_variant"
end
if settings.controller_stroke_width < 0.5 then
  settings.controller_stroke_width = 0.5
elseif settings.controller_stroke_width > 8 then
  settings.controller_stroke_width = 8
end
if settings.show_signal == nil then
  settings.show_signal = true
end
if settings.signal_style ~= "bars"
  and settings.signal_style ~= "bars_dbm"
  and settings.signal_style ~= "dbm"
then
  settings.signal_style = "bars"
end

local low_threshold = tonumber(noctalia.getConfig("low_threshold")) or 20

local LED = {
  wireless = "#fcfcfc",
  bluetooth = "#3daee9",
  cable = "#3ec47a",
  docked = "#ff9a3c",
}

local BODY_W = 58
local BODY_H = 150
local INNER_H = BODY_H - 10

local current_state = nil
local pulse = 1
local pulse_phase = 0
local frame_accum = 0

local function resolve_color(value, fallback)
  if value == nil or value == "" then
    return fallback
  end
  if string.sub(value, 1, 1) == "#" then
    return value
  end
  if type(noctalia.getColor) == "function" then
    return noctalia.getColor(value) or fallback
  end
  return fallback
end

local function valid_hex(color)
  return string.match(color, "^#%x%x%x$")
    or string.match(color, "^#%x%x%x%x$")
    or string.match(color, "^#%x%x%x%x%x%x$")
    or string.match(color, "^#%x%x%x%x%x%x%x%x$")
end

local function color_key(color)
  return string.gsub(tostring(color), "[^%w]", "")
end

-- Draw the controller line art and body in the configured colours. A generated
-- SVG is used because ui.image cannot tint; fall back to the bundled one.
-- Re-resolve role tokens on update() so the art follows a live palette change.
local art_path = nil

local function controller_art()
  local fallback = "assets/controller.svg"
  local line = resolve_color(settings.illustration_color, "#e8ebef")
  local body = resolve_color(settings.controller_body_color, "#2c3035")
  if not valid_hex(line) then
    line = "#e8ebef"
  end
  if not valid_hex(body) then
    body = "#2c3035"
  end
  local stroke = settings.controller_stroke_width
  local stroke_text = string.format("%.2f", stroke)
  local grip_text = string.format("%.2f", stroke * 0.94)

  local dir = noctalia.pluginDataDir()
  if not dir then
    return fallback
  end
  local path = dir .. "/controller-v3-" .. color_key(line) .. "-" .. color_key(body)
    .. "-" .. color_key(stroke_text) .. ".svg"
  if path == art_path then
    return path
  end
  local template = noctalia.readFile("assets/controller-template.svg")
  if not template then
    return fallback
  end

  local svg = string.gsub(template, "{{BODY}}", body)
  svg = string.gsub(svg, "{{COLOR}}", line)
  svg = string.gsub(svg, "{{STROKE_BODY}}", stroke_text)
  svg = string.gsub(svg, "{{STROKE_GRIP}}", grip_text)
  local written = noctalia.writeFile(path, svg)
  if not written then
    return fallback
  end
  return path
end

art_path = controller_art()

local function fresh()
  if type(current_state) ~= "table" then
    return false
  end
  local ts = tonumber(current_state.ts)
  if not ts then
    return false
  end
  return os.time() - ts <= STALE_AFTER
end

local function mode_of()
  local s = type(current_state) == "table" and current_state or {}
  local is_fresh = fresh()
  local connected = is_fresh and s.connected == true
  local charging = is_fresh and s.charging == true
  local pct = is_fresh and tonumber(s.battery_pct) or -1
  if not pct then
    pct = -1
  end
  local known = pct >= 0
  local low = connected and not charging and known and pct <= low_threshold

  local mode = "disconnected"
  if charging then
    mode = "charging"
  elseif connected then
    mode = low and "low" or "ok"
  end

  return mode, connected, charging, pct, known, is_fresh
end

local function state_color(mode, connected, s)
  if mode == "low" then
    return settings.battery_low_color
  end
  if mode == "disconnected" then
    return "on_surface_variant/0.55"
  end
  if settings.battery_color_mode == "custom" then
    return settings.battery_fill_color
  end
  if mode == "charging" and not connected then
    return LED.docked
  end
  local connection = s.connection or ""
  if connection == "usb" then
    return LED.cable
  end
  if connection == "bluetooth" then
    return LED.bluetooth
  end
  return LED.wireless
end

local function status_text(mode, s, is_fresh)
  if not is_fresh then
    return noctalia.tr("status.waiting")
  end
  if type(s) == "table" and s.error == "python3" then
    return noctalia.tr("status.no_python")
  end
  if mode == "charging" then
    if s.docked then
      return noctalia.tr("status.charging_puck")
    end
    if s.connection == "usb" then
      return noctalia.tr("status.charging_usb")
    end
    return noctalia.tr("status.charging_cable")
  end
  if mode == "low" then
    return noctalia.tr("status.low")
  end
  if mode == "ok" then
    return noctalia.tr("status.connected")
  end
  return noctalia.tr("status.disconnected")
end

local function link_glyph(mode, connected, s)
  if mode == "charging" then
    return "bolt"
  end
  if not connected then
    return nil
  end
  local connection = s.connection or ""
  if connection == "bluetooth" then
    return "bluetooth"
  end
  if connection == "usb" then
    return "usb"
  end
  if s.internal then
    return "device-gamepad-2"
  end
  return "wifi"
end

local function marker_color(mode, connected, s)
  if mode == "low" then
    return settings.battery_low_color
  end
  if mode == "charging" then
    if s.connection == "usb" then
      return LED.cable
    end
    if s.connection == "bluetooth" then
      return LED.bluetooth
    end
    -- White on a light card disappears; the battery keeps the LED colour.
    return connected and settings.text_color or LED.docked
  end
  if not connected then
    return settings.muted_text_color
  end
  if s.connection == "bluetooth" then
    return LED.bluetooth
  end
  if s.connection == "usb" then
    return LED.cable
  end
  return settings.text_color
end

local function signal_level(connected, s)
  if not connected then
    return 0, nil
  end
  local dbm = tonumber(s.signal_dbm)
  if not dbm then
    return 0, nil
  end
  local level = 1
  if dbm >= -55 then
    level = 4
  elseif dbm >= -65 then
    level = 3
  elseif dbm >= -75 then
    level = 2
  end
  return level, dbm
end

local function pct_row(pct, known, shown, provisional, mode)
  local children = {}

  if shown and known then
    local opacity = provisional and 0.55 or 1
    table.insert(children, ui.label({
      key = "pct-value",
      text = tostring(math.floor(pct + 0.5)),
      fontSize = 30,
      fontWeight = "semibold",
      color = mode == "low" and settings.battery_low_color or settings.text_color,
      opacity = opacity,
    }))
    table.insert(children, ui.label({
      key = "pct-sign",
      text = "%",
      fontSize = 16,
      fontWeight = "medium",
      color = mode == "low" and settings.battery_low_color or settings.muted_text_color,
      opacity = opacity,
    }))
    if provisional then
      table.insert(children, ui.glyph({
        key = "pct-clock",
        name = "clock",
        size = 12,
        color = settings.muted_text_color,
        opacity = 0.7,
      }))
    end
  else
    table.insert(children, ui.label({
      key = "pct-value",
      text = "—",
      fontSize = 30,
      fontWeight = "semibold",
      color = settings.muted_text_color,
    }))
  end

  return ui.row({ key = "pct-row", gap = 2, align = "end", justify = "center" }, children)
end

local function status_row(mode, connected, charging, s, is_fresh)
  local children = {}
  local glyph = link_glyph(mode, connected, s)

  if glyph then
    table.insert(children, ui.glyph({
      key = "status-glyph",
      name = glyph,
      size = 13,
      color = marker_color(mode, connected, s),
      opacity = charging and pulse or 1,
    }))
  end

  local text_color = mode == "low" and settings.battery_low_color
    or (is_fresh and settings.text_color or settings.muted_text_color)

  table.insert(children, ui.label({
    key = "status-text",
    text = status_text(mode, s, is_fresh),
    fontSize = 12,
    color = text_color,
  }))

  return ui.row({ key = "status-row", gap = 5, align = "center", justify = "center" }, children)
end

local function signal_node(level, dbm)
  if level <= 0 or not settings.show_signal then
    return nil
  end

  local children = {}
  local style = settings.signal_style

  if style ~= "dbm" then
    local heights = { 4, 6, 8, 10 }
    for i = 1, 4 do
      local active = i <= level
      table.insert(children, ui.box({
        key = "signal-bar-" .. i,
        width = 3,
        height = heights[i],
        radius = 1.5,
        fill = active and (level == 1 and settings.battery_low_color or settings.text_color)
          or settings.muted_text_color,
        opacity = active and 1 or 0.35,
      }))
    end
  end

  if style ~= "bars" then
    table.insert(children, ui.label({
      key = "signal-dbm",
      text = tostring(dbm) .. " dBm",
      fontSize = 11,
      color = style == "dbm" and (level == 1 and settings.battery_low_color or settings.text_color)
        or settings.muted_text_color,
    }))
  end

  return ui.row({ key = "signal-row", gap = 4, align = "end", justify = "center" }, children)
end

local function render()
  local s = type(current_state) == "table" and current_state or {}
  local mode, connected, charging, pct, known, is_fresh = mode_of()
  local off = mode == "disconnected"
  local dim = off and (is_fresh and 0.55 or 0.8) or 1
  local color = state_color(mode, connected, s)
  local level, dbm = signal_level(connected, s)

  local left_children = {
    ui.image({
      key = "controller-art",
      path = art_path,
      width = 123,
      height = 92,
      fit = "contain",
    }),
    ui.spacer({ key = "art-gap", height = 8, flexGrow = 0 }),
    pct_row(pct, known, known and not off, s.provisional == true, mode),
    status_row(mode, connected, charging, s, is_fresh),
  }

  if connected and s.internal then
    table.insert(left_children, ui.label({
      key = "via-internal",
      text = noctalia.tr("status.via_internal"),
      fontSize = 11,
      color = settings.muted_text_color,
      opacity = 0.85,
    }))
  end

  local signal = signal_node(level, dbm)
  if signal then
    table.insert(left_children, signal)
  end

  local left = ui.column({
    key = "left",
    width = 138,
    gap = 2,
    align = "center",
    opacity = dim,
  }, left_children)

  local fill_height = 0
  if known and not off then
    fill_height = math.floor(INNER_H * math.max(0, math.min(100, pct)) / 100 + 0.5)
  end

  local body_children = {}
  if fill_height > 0 then
    table.insert(body_children, ui.box({
      key = "battery-fill",
      width = BODY_W - 10,
      height = fill_height,
      radius = 7,
      fill = color,
      opacity = (charging and pulse or 1) * settings.battery_fill_opacity,
    }))
  end

  local battery = ui.column({ key = "battery", gap = 3, align = "center", opacity = dim }, {
    ui.box({
      key = "battery-nub",
      width = 22,
      height = 5,
      radius = 2,
      fill = "outline",
    }),
    ui.column({
      key = "battery-body",
      width = BODY_W,
      height = BODY_H,
      radius = 12,
      border = "outline",
      borderWidth = 2,
      padding = 5,
      justify = "end",
      align = "stretch",
    }, body_children),
  })

  local row = ui.row({
    key = "content",
    gap = 20,
    align = "center",
    justify = "center",
  }, { left, battery })

  if type(desktopWidget.setNeedsFrameTick) == "function" then
    desktopWidget.setNeedsFrameTick(mode == "charging")
  end

  desktopWidget.render(ui.column({
    key = "card",
    align = "center",
    padding = 2,
  }, { row }))
end

function onFrameTick(delta_ms)
  local mode = mode_of()
  if mode ~= "charging" then
    return
  end

  frame_accum = frame_accum + (tonumber(delta_ms) or 16)
  if frame_accum < 33 then
    return
  end

  pulse_phase = (pulse_phase + frame_accum / 380) % (math.pi * 2)
  frame_accum = 0
  pulse = 0.35 + 0.65 * (0.5 + 0.5 * math.cos(pulse_phase))
  render()
end

function update()
  art_path = controller_art()
  render()
end

current_state = noctalia.state.get("controller")
noctalia.setUpdateInterval(1000)
noctalia.state.watch("controller", function(value)
  current_state = value
  render()
end)
render()
