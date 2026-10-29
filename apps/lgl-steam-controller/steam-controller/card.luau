--!nonstrict
-- Declarative desktop card for the Steam Controller 2.
--
-- By default the card mirrors the controller's LED: the battery fill is white
-- through the puck, blue over Bluetooth, green on USB-C, orange while charging
-- off-dock, red when low. The controller line/body, the battery fill (or a
-- custom fill) and the live input overlay are configurable. Charging pulses.
-- The battery service publishes the live state; this entry only renders it.

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
  input_highlight_color = noctalia.getConfig("input_highlight_color") or "primary",
  show_battery_bar = noctalia.getConfig("show_battery_bar"),
  show_percentage = noctalia.getConfig("show_percentage"),
  show_status = noctalia.getConfig("show_status"),
  show_live_inputs = noctalia.getConfig("show_live_inputs"),
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
if settings.show_battery_bar == nil then
  settings.show_battery_bar = true
end
if settings.show_percentage == nil then
  settings.show_percentage = true
end
if settings.show_status == nil then
  settings.show_status = true
end
if settings.show_live_inputs == nil then
  settings.show_live_inputs = true
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

-- Triton input bitmask from SDL's SDL_hidapi_steam_triton.c.
local TRITON = {
  a = 0x1,
  b = 0x2,
  x = 0x4,
  y = 0x8,
  qam = 0x10,
  r3 = 0x20,
  view = 0x40,
  r4 = 0x80,
  r5 = 0x100,
  r = 0x200,
  dpad_down = 0x400,
  dpad_right = 0x800,
  dpad_left = 0x1000,
  dpad_up = 0x2000,
  menu = 0x4000,
  l3 = 0x8000,
  steam = 0x10000,
  l4 = 0x20000,
  l5 = 0x40000,
  l = 0x80000,
  right_stick_touch = 0x100000,
  right_pad_touch = 0x200000,
  right_pad_click = 0x400000,
  right_trigger_click = 0x800000,
  left_stick_touch = 0x1000000,
  left_pad_touch = 0x2000000,
  left_pad_click = 0x4000000,
  left_trigger_click = 0x8000000,
  right_grip_touch = 0x10000000,
  left_grip_touch = 0x20000000,
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
-- Live input highlights are baked into the same SVG, using a small ring of
-- filenames so ui.image reloads every changed frame.
local art_path = nil
local art_base = nil
local art_base_key = nil
local art_static_path = nil
local art_live_key = nil
local art_live_path = nil
local art_live_seq = 0
local LIVE_SLOTS = 4

local function controller_art(live_overlay)
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
  local base_key = table.concat({ line, body, stroke_text, grip_text }, "|")

  local dir = noctalia.pluginDataDir()
  if not dir then
    return fallback
  end

  if art_base == nil or art_base_key ~= base_key then
    local template = noctalia.readFile("assets/controller-template.svg")
    if not template then
      return fallback
    end
    local svg = string.gsub(template, "{{BODY}}", body)
    svg = string.gsub(svg, "{{COLOR}}", line)
    svg = string.gsub(svg, "{{STROKE_BODY}}", stroke_text)
    svg = string.gsub(svg, "{{STROKE_GRIP}}", grip_text)
    art_base = svg
    art_base_key = base_key
  end

  if live_overlay and live_overlay ~= "" then
    local live_key = base_key .. "\n" .. live_overlay
    if live_key == art_live_key and art_live_path then
      return art_live_path
    end
    local overlay_key = color_key(
      tostring(settings.input_highlight_color) .. "-"
      .. tostring(settings.muted_text_color) .. "-"
      .. tostring(settings.text_color)
    )
    local path = dir .. "/steam-live-" .. color_key(base_key) .. "-"
      .. overlay_key .. "-" .. art_live_seq .. ".svg"
    art_live_seq = (art_live_seq + 1) % LIVE_SLOTS
    local svg = string.gsub(art_base, "{{LIVE_OVERLAY}}", live_overlay)
    if not noctalia.writeFile(path, svg) then
      return fallback
    end
    art_live_key = live_key
    art_live_path = path
    return path
  end

  art_live_key = nil
  art_live_path = nil
  local path = dir .. "/steam-v4-" .. color_key(line) .. "-" .. color_key(body)
    .. "-" .. color_key(stroke_text) .. ".svg"
  if path == art_static_path then
    return path
  end
  local svg = string.gsub(art_base, "{{LIVE_OVERLAY}}", "")
  if not noctalia.writeFile(path, svg) then
    return fallback
  end
  art_static_path = path
  return path
end

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

local function has_button(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

local function svg_hex(value, fallback)
  local color = resolve_color(value, fallback)
  if valid_hex(color) then
    return color
  end
  return fallback
end

local function svg_circle(cx, cy, r, fill, opacity, stroke, stroke_width)
  local out = string.format(
    '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" opacity="%.2f"',
    cx, cy, r, fill, opacity
  )
  if stroke and stroke_width then
    out = out .. string.format(' stroke="%s" stroke-width="%.2f"', stroke, stroke_width)
  end
  return out .. "/>"
end

local function svg_rect(x, y, w, h, rx, fill, opacity, stroke, stroke_width)
  local out = string.format(
    '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="%s" opacity="%.2f"',
    x, y, w, h, rx, fill, opacity
  )
  if stroke and stroke_width then
    out = out .. string.format(' stroke="%s" stroke-width="%.2f"', stroke, stroke_width)
  end
  return out .. "/>"
end

-- Button/stick/trigger/touchpad highlights drawn over the Steam Controller
-- art. Coordinates match the Steam Controller SVG.
local function build_input_overlay(input)
  local accent = svg_hex(settings.input_highlight_color, "#4a9eff")
  local track = svg_hex(settings.muted_text_color, "#9aa0a6")
  local outline = svg_hex(settings.text_color, "#ffffff")
  local parts = {}

  local function add(markup)
    parts[#parts + 1] = markup
  end

  local function circle(cx, cy, r)
    add(svg_circle(cx, cy, r, accent, 0.95))
  end

  local buttons = tonumber(input.buttons) or 0

  -- L2/R2 analog bars above the shoulders.
  local function trigger_bar(cx, value)
    local x, y, w, h = cx - 2.7, 0.4, 5.4, 7.6
    add(svg_rect(x, y, w, h, 1.3, "none", 1.0, track, 0.7))
    local amount = math.max(0, math.min(1, (tonumber(value) or 0) / 32767))
    local inner_h = h - 1.6
    local fill_h = inner_h * amount
    if fill_h > 0.12 then
      add(svg_rect(x + 0.8, y + 0.8 + inner_h - fill_h, w - 1.6, fill_h, 0.7, accent, 0.95))
    end
  end
  trigger_bar(27.7, input.l2)
  trigger_bar(92.3, input.r2)

  -- L1/R1 bumpers.
  if has_button(buttons, TRITON.l) then circle(27.7, 5.3, 2.2) end
  if has_button(buttons, TRITON.r) then circle(92.3, 5.3, 2.2) end

  -- A/B/X/Y face buttons.
  if has_button(buttons, TRITON.y) then circle(92.6, 15.1, 2.2) end
  if has_button(buttons, TRITON.x) then circle(87.2, 21.5, 2.2) end
  if has_button(buttons, TRITON.b) then circle(98.2, 21.5, 2.2) end
  if has_button(buttons, TRITON.a) then circle(92.6, 27.2, 2.2) end

  -- D-pad.
  if has_button(buttons, TRITON.dpad_up) then circle(26.1, 17.25, 1.8) end
  if has_button(buttons, TRITON.dpad_down) then circle(26.1, 25.75, 1.8) end
  if has_button(buttons, TRITON.dpad_left) then circle(21.85, 21.5, 1.8) end
  if has_button(buttons, TRITON.dpad_right) then circle(30.35, 21.5, 1.8) end

  -- Steam, QAM, view and menu buttons.
  if has_button(buttons, TRITON.steam) then circle(60.0, 19.6, 2.3) end
  if has_button(buttons, TRITON.qam) then
    add(svg_rect(55.6, 48.8, 8.8, 2.8, 1.4, accent, 0.95))
  end
  if has_button(buttons, TRITON.view) then circle(57.4, 50.2, 0.9) end
  if has_button(buttons, TRITON.menu) then circle(62.6, 50.2, 0.9) end

  -- Sticks: offset dot plus an L3/R3 press fill.
  local function stick(cx, cy, raw_x, raw_y, pressed)
    local nx = math.max(-1, math.min(1, (tonumber(raw_x) or 0) / 32768))
    local ny = math.max(-1, math.min(1, -(tonumber(raw_y) or 0) / 32768))
    if pressed then
      add(svg_circle(cx, cy, 4.9, accent, 0.22))
    end
    add(svg_circle(cx + nx * 3.1, cy + ny * 3.1, 1.8, accent, 0.95, outline, 0.45))
  end
  stick(44.3, 26.9, input.lx, input.ly, has_button(buttons, TRITON.l3))
  stick(75.7, 26.9, input.rx, input.ry, has_button(buttons, TRITON.r3))

  -- Touchpads: click fill and active touch point.
  local function pad(rect_x, rect_y, rect_w, rect_h, transform, click_bit, touch_bit, px, py, pressure)
    local open, close = '<g transform="' .. transform .. '">', "</g>"
    if has_button(buttons, click_bit) then
      add(open .. svg_rect(rect_x, rect_y, rect_w, rect_h, 4.5, accent, 0.16, accent, 1.0) .. close)
    end
    if has_button(buttons, touch_bit) then
      local nx = math.max(0, math.min(1, (tonumber(px) or 0) / 65536 + 0.5))
      local ny = math.max(0, math.min(1, -(tonumber(py) or 0) / 65536 + 0.5))
      local opacity = 0.45 + 0.5 * math.max(0, math.min(1, (tonumber(pressure) or 0) / 32767))
      add(open .. svg_circle(
        rect_x + nx * rect_w, rect_y + ny * rect_h, 1.4, accent, opacity, outline, 0.4
      ) .. close)
    end
  end
  pad(26.6, 38.2, 21.2, 20.8, "rotate(-6 37.2 48.6)",
    TRITON.left_pad_click, TRITON.left_pad_touch, input.lpx, input.lpy, input.lpp)
  pad(72.2, 38.2, 21.2, 20.8, "rotate(6 82.8 48.6)",
    TRITON.right_pad_click, TRITON.right_pad_touch, input.rpx, input.rpy, input.rpp)

  return "<g>" .. table.concat(parts) .. "</g>"
end

local function input_overlay()
  if not settings.show_live_inputs then
    return nil
  end
  local s = type(current_state) == "table" and current_state or {}
  if not fresh() or s.connected ~= true then
    return nil
  end
  local input = type(s.input) == "table" and s.input or nil
  if not input then
    return nil
  end
  return build_input_overlay(input)
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
  }

  if settings.show_percentage then
    table.insert(left_children, pct_row(pct, known, known and not off, s.provisional == true, mode))
  end
  if settings.show_status then
    table.insert(left_children, status_row(mode, connected, charging, s, is_fresh))
  end

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

  local row_children = { left }

  if settings.show_battery_bar then
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

    table.insert(row_children, ui.column({ key = "battery", gap = 3, align = "center", opacity = dim }, {
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
    }))
  end

  local row = ui.row({
    key = "content",
    gap = 20,
    align = "center",
    justify = "center",
  }, row_children)

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

local function refresh_art()
  art_path = controller_art(input_overlay())
end

function update()
  refresh_art()
  render()
end

current_state = noctalia.state.get("controller")
refresh_art()
noctalia.setUpdateInterval(1000)
noctalia.state.watch("controller", function(value)
  current_state = value
  refresh_art()
  render()
end)
render()
