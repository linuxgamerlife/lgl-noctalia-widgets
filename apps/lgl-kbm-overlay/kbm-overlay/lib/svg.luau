--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- SVG renderer for the desktop widget. The reference is the black/white/cyan
-- input-overlay look: outlined, slightly skewed keycaps, a large mouse
-- silhouette, and a cyan fill for pressed keys/buttons.

local config = require("./config.luau")
local layout = require("./layout.luau")

local M = {}

local function esc(value)
  return tostring(value)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
end

local function num(value)
  return string.format("%.2f", value)
end

local function behind(list, item)
  table.insert(list, item)
end

local function pressed_set(state)
  local set = {}
  if type(state) == "table" and type(state.pressed) == "table" then
    for _, name in ipairs(state.pressed) do
      set[name] = true
    end
  end
  return set
end

local function reported_buttons(state)
  local set = {}
  local mouse = type(state) == "table" and state.mouse or nil
  if type(mouse) == "table" and type(mouse.buttons) == "table" then
    for _, name in ipairs(mouse.buttons) do
      set[name] = true
    end
  end
  return set
end

local function key_label_size(spec, key_size, label_scale)
  local length = #tostring(spec.label or "")
  local factor = 0.30
  if length >= 5 then
    factor = 0.22
  elseif length == 4 then
    factor = 0.25
  end
  return key_size * factor * label_scale
end

local function key_svg(cfg, spec, x, y, key_size, active, glow, colors)
  local gap = cfg.key_gap
  local width = key_size * (spec.w or 1) + gap * ((spec.w or 1) - 1)
  local cx = x + width / 2
  local cy = y + key_size / 2
  local radius = cfg.key_radius
  local skew = 8
  local transform = string.format(
    "translate(%s,%s) skewX(-%s) translate(%s,%s)",
    num(cx), num(cy), num(skew), num(-cx), num(-cy)
  )
  local parts = {}
  if cfg.effects_glow and (active or glow) then
    parts[#parts + 1] = string.format(
      '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" stroke="%s" stroke-width="%s" opacity="%s" transform="%s"/>',
      num(x - 4), num(y - 4), num(width + 8), num(key_size + 8), num(radius + 3),
      colors.glow, num(math.max(4, cfg.key_border_width * 2.4)),
      num(cfg.glow_opacity * (active and 1 or 0.55)), transform
    )
  end
  parts[#parts + 1] = string.format(
    '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round" transform="%s"/>',
    num(x), num(y), num(width), num(key_size), num(radius),
    active and colors.accent or colors.key_fill,
    active and "1" or num(cfg.key_idle_opacity),
    active and colors.accent or colors.key_border,
    num(cfg.key_border_width), transform
  )
  if cfg.show_key_labels then
    local font = key_label_size(spec, key_size, cfg.label_scale)
    parts[#parts + 1] = string.format(
      '<text x="%s" y="%s" text-anchor="middle" font-family="sans-serif" font-size="%s" font-weight="bold" font-style="italic" fill="%s">%s</text>',
      num(cx), num(cy + font * 0.35), num(font),
      active and colors.accent_text or colors.key_text, esc(spec.label)
    )
  end
  return table.concat(parts)
end

local function mouse_button_svg(name, x, y, width, height, radius, active, glow, cfg, colors, label_size, show_label)
  local parts = {}
  if cfg.effects_glow and (active or glow) then
    parts[#parts + 1] = string.format(
      '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" stroke="%s" stroke-width="%s" opacity="%s"/>',
      num(x - 3), num(y - 3), num(width + 6), num(height + 6), num(radius + 3),
      colors.glow, num(math.max(4, cfg.mouse_border_width * 2.2)),
      num(cfg.glow_opacity * (active and 1 or 0.55))
    )
  end
  parts[#parts + 1] = string.format(
    '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
    num(x), num(y), num(width), num(height), num(radius),
    active and colors.accent or colors.mouse_fill,
    active and "1" or num(cfg.mouse_body_opacity),
    active and colors.accent or colors.mouse_border,
    num(cfg.mouse_border_width)
  )
  if show_label and name ~= nil then
    parts[#parts + 1] = string.format(
      '<text x="%s" y="%s" text-anchor="middle" font-family="sans-serif" font-size="%s" font-weight="bold" fill="%s">%s</text>',
      num(x + width / 2), num(y + height / 2 + label_size * 0.35), num(label_size),
      active and colors.accent_text or colors.key_text, esc(layout.mouse_button_label(name))
    )
  end
  return table.concat(parts)
end

local function top_button_svg(left, x, y, width, height, active, glow, cfg, colors, label_size, show_label)
  local function p(nx, ny)
    local mx = left and nx or (1 - nx)
    return string.format("%s %s", num(x + mx * width), num(y + ny * height))
  end
  -- A trapezoid with a pronounced outward slant on the outer edge and a bite
  -- on the inner edge for the wheel. Mirrored for the right-hand button.
  local d = "M " .. p(0.30, 0) .. " L " .. p(0.78, 0)
    .. " C " .. p(0.90, 0) .. ", " .. p(0.96, 0.06) .. ", " .. p(0.96, 0.16)
    .. " L " .. p(0.96, 0.50)
    .. " C " .. p(0.96, 0.58) .. ", " .. p(0.92, 0.62) .. ", " .. p(0.86, 0.62)
    .. " L " .. p(0.80, 0.62)
    .. " C " .. p(0.74, 0.62) .. ", " .. p(0.72, 0.66) .. ", " .. p(0.72, 0.72)
    .. " L " .. p(0.72, 0.84)
    .. " C " .. p(0.72, 0.94) .. ", " .. p(0.64, 0.98) .. ", " .. p(0.52, 0.98)
    .. " L " .. p(0.14, 0.98)
    .. " C " .. p(0.06, 0.98) .. ", " .. p(0.00, 0.92) .. ", " .. p(0.00, 0.84)
    .. " L " .. p(0.14, 0.18)
    .. " C " .. p(0.18, 0.08) .. ", " .. p(0.22, 0.00) .. ", " .. p(0.30, 0.00) .. " Z"
  local parts = {}
  if cfg.effects_glow and (active or glow) then
    parts[#parts + 1] = string.format(
      '<path d="%s" fill="none" stroke="%s" stroke-width="%s" opacity="%s" stroke-linejoin="round"/>',
      d, colors.glow, num(math.max(5, cfg.mouse_border_width * 2.4)),
      num(cfg.glow_opacity * (active and 1 or 0.55))
    )
  end
  parts[#parts + 1] = string.format(
    '<path d="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
    d,
    active and colors.accent or colors.mouse_fill,
    active and "1" or num(cfg.mouse_body_opacity),
    active and colors.accent or colors.mouse_border,
    num(cfg.mouse_border_width)
  )
  if show_label then
    parts[#parts + 1] = string.format(
      '<text x="%s" y="%s" text-anchor="middle" font-family="sans-serif" font-size="%s" font-weight="bold" fill="%s">%s</text>',
      num(x + width / 2), num(y + height / 2 + label_size * 0.35), num(label_size),
      active and colors.accent_text or colors.key_text,
      esc(left and "LMB" or "RMB")
    )
  end
  return table.concat(parts)
end

local function motion_arrow_svg(cfg, state, now, colors, x, y, width, height, anim)
  local mx = tonumber(state.move_x) or 0
  local my = tonumber(state.move_y) or 0
  local speed = math.sqrt(mx * mx + my * my)
  local moved_at = tonumber(state.move_at) or 0
  local fade = 1.0
  local use_distance = false
  local distance = 0
  local arrow_fade = 1.0
  local dx = 0
  local dy = 0
  local arrow = anim and anim.arrow or nil
  if arrow ~= nil then
    speed = tonumber(arrow.speed) or 0
    if speed <= 0.5 then
      return ""
    end
    dx = tonumber(arrow.dx) or 0
    dy = tonumber(arrow.dy) or 0
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag > 0.0001 then
      dx = dx / mag
      dy = dy / mag
    end
    use_distance = arrow.use_distance == true
    distance = math.max(0, math.min(1, tonumber(arrow.distance) or 0))
    arrow_fade = math.max(0, math.min(1, tonumber(arrow.fade) or 1))
  else
    if speed < 0.5 or moved_at <= 0 then
      return ""
    end
    local age = (now - moved_at) / 1000.0
    if age < 0 or age > 0.40 then
      return ""
    end
    fade = 1.0 - age / 0.40
    dx = mx / speed
    dy = my / speed
  end
  if speed < 0.5 then
    return ""
  end
  local cx = x + width / 2
  local cy = y + height * 0.70
  local body_limit = math.min(width * 0.48, height * 0.30)
  local max_len = body_limit * cfg.motion_arrow_scale
  local min_len = 28 * cfg.motion_arrow_scale
  local length
  if use_distance then
    length = max_len * distance * arrow_fade
  else
    length = math.max(min_len, math.min(max_len, speed * 10.0)) * fade
  end
  if length < 6 then
    return ""
  end
  local px = -dy
  local py = dx
  local head_scale = math.max(0.6, math.min(1.8, cfg.motion_arrow_size / 3.0))
  local head = math.max(7, math.min(18, length * 0.28)) * head_scale
  local half = head * 0.55
  local tip_x = cx + dx * length
  local tip_y = cy + dy * length
  local base_x = tip_x - dx * head
  local base_y = tip_y - dy * head
  local tail_x = cx + dx * 4
  local tail_y = cy + dy * 4
  local line_width = math.max(0.8, cfg.motion_arrow_size)
  local parts = {}
  if cfg.effects_glow then
    parts[#parts + 1] = string.format(
      '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s" stroke-linecap="round" opacity="%s"/>',
      num(tail_x), num(tail_y), num(base_x), num(base_y), colors.glow,
      num(line_width * 3), num(cfg.glow_opacity * 0.75 * fade)
    )
    parts[#parts + 1] = string.format(
      '<polygon points="%s,%s %s,%s %s,%s" fill="%s" opacity="%s"/>',
      num(tip_x), num(tip_y),
      num(base_x + px * half), num(base_y + py * half),
      num(base_x - px * half), num(base_y - py * half),
      colors.glow, num(cfg.glow_opacity * 0.75 * fade)
    )
  end
  -- A dark underlay keeps the white arrow readable on light wallpapers.
  parts[#parts + 1] = string.format(
    '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s" stroke-linecap="round"/>',
    num(tail_x), num(tail_y), num(base_x), num(base_y), colors.panel, num(line_width + 3)
  )
  parts[#parts + 1] = string.format(
    '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s" stroke-linecap="round"/>',
    num(tail_x), num(tail_y), num(base_x), num(base_y), colors.arrow, num(line_width)
  )
  parts[#parts + 1] = string.format(
    '<polygon points="%s,%s %s,%s %s,%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
    num(tip_x), num(tip_y),
    num(base_x + px * half), num(base_y + py * half),
    num(base_x - px * half), num(base_y - py * half),
    colors.arrow, colors.panel, num(1.5)
  )
  return table.concat(parts)
end

local function mouse_svg(cfg, state, now, anim, x, y, width, height, colors)
  local parts = {}
  local pressed = pressed_set(state)
  local reported = reported_buttons(state)
  local side = {}
  if cfg.mouse_show_extra then
    for _, name in ipairs(layout.mouse_side_order()) do
      if reported[name] and name ~= "BTN_LEFT" and name ~= "BTN_RIGHT" and name ~= "BTN_MIDDLE" then
        side[#side + 1] = name
        if #side == 2 then
          break
        end
      end
    end
    -- Always draw two side buttons, even on a mouse that reports none.
    if #side == 0 then
      side = { "BTN_EXTRA", "BTN_SIDE" }
    elseif #side == 1 then
      side[2] = side[1] == "BTN_EXTRA" and "BTN_SIDE" or "BTN_EXTRA"
    end
  end
  local has_mouse = type(state) == "table" and type(state.mouse) == "table" and state.mouse.name ~= nil
  if not has_mouse then
    parts[#parts + 1] = string.format(
      '<text x="%s" y="%s" text-anchor="middle" font-family="sans-serif" font-size="%s" font-weight="bold" fill="%s">%s</text>',
      num(x + width / 2), num(y + height / 2), num(math.max(10, width * 0.10)),
      colors.key_text, esc("NO MOUSE")
    )
    return table.concat(parts)
  end

  local body_x = x + width * 0.02
  local body_y = y + height * 0.42
  local body_w = width * 0.96
  local body_h = height * 0.56
  local function bp(nx, ny)
    return string.format("%s %s", num(body_x + nx * body_w), num(body_y + ny * body_h))
  end
  -- Lower body with a U-shaped notch in the top centre for the wheel.
  local body_d = "M " .. bp(0.06, 0) .. " L " .. bp(0.38, 0)
    .. " C " .. bp(0.42, 0) .. ", " .. bp(0.43, 0.03) .. ", " .. bp(0.43, 0.08)
    .. " L " .. bp(0.43, 0.16)
    .. " C " .. bp(0.43, 0.22) .. ", " .. bp(0.46, 0.24) .. ", " .. bp(0.50, 0.24)
    .. " C " .. bp(0.54, 0.24) .. ", " .. bp(0.57, 0.22) .. ", " .. bp(0.57, 0.16)
    .. " L " .. bp(0.57, 0.08)
    .. " C " .. bp(0.57, 0.03) .. ", " .. bp(0.58, 0) .. ", " .. bp(0.62, 0)
    .. " L " .. bp(0.94, 0)
    .. " C " .. bp(0.98, 0) .. ", " .. bp(1.00, 0.03) .. ", " .. bp(1.00, 0.08)
    .. " L " .. bp(0.94, 0.86)
    .. " C " .. bp(0.94, 0.94) .. ", " .. bp(0.90, 1.00) .. ", " .. bp(0.84, 1.00)
    .. " L " .. bp(0.16, 1.00)
    .. " C " .. bp(0.10, 1.00) .. ", " .. bp(0.06, 0.94) .. ", " .. bp(0.06, 0.86)
    .. " L " .. bp(0.00, 0.60)
    .. " C " .. bp(0.02, 0.58) .. ", " .. bp(0.10, 0.58) .. ", " .. bp(0.12, 0.54)
    .. " L " .. bp(0.12, 0.12)
    .. " C " .. bp(0.10, 0.10) .. ", " .. bp(0.02, 0.10) .. ", " .. bp(0.00, 0.08)
    .. " L " .. bp(0.00, 0.03)
    .. " C " .. bp(0.00, 0.01) .. ", " .. bp(0.02, 0) .. ", " .. bp(0.06, 0) .. " Z"
  parts[#parts + 1] = string.format(
    '<path d="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
    body_d, colors.mouse_fill, num(cfg.mouse_body_opacity), colors.mouse_border, num(cfg.mouse_border_width)
  )
  parts[#parts + 1] = motion_arrow_svg(cfg, state, now, colors, x, y, width, height, anim)
  local pivot = math.max(1, cfg.motion_dot_size * cfg.motion_dot_scale)
  parts[#parts + 1] = string.format(
    '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="%s"/>',
    num(x + width / 2), num(y + height * 0.70), num(pivot),
    colors.dot, colors.accent, num(1.5)
  )

  local label_size = math.max(6, width * 0.065 * cfg.label_scale)
  local top_y = y + height * 0.02
  local top_h = height * 0.36
  local top_w = width * 0.42
  local left_active = pressed.BTN_LEFT == true
  local right_active = pressed.BTN_RIGHT == true
  local left_glow = left_active or (anim.glow_until and (anim.glow_until.BTN_LEFT or 0) > now)
  local right_glow = right_active or (anim.glow_until and (anim.glow_until.BTN_RIGHT or 0) > now)
  parts[#parts + 1] = top_button_svg(true, x + width * 0.02, top_y, top_w, top_h, left_active, left_glow, cfg, colors, label_size, cfg.show_mouse_labels)
  parts[#parts + 1] = top_button_svg(false, x + width * 0.56, top_y, top_w, top_h, right_active, right_glow, cfg, colors, label_size, cfg.show_mouse_labels)

  if cfg.mouse_show_wheel then
    local wheel_w = width * 0.15
    local wheel_h = height * 0.30
    local wheel_x = x + (width - wheel_w) / 2
    local wheel_y = y + height * 0.10
    local middle_active = pressed.BTN_MIDDLE == true
    local middle_glow = middle_active or (anim.glow_until and (anim.glow_until.BTN_MIDDLE or 0) > now)
    parts[#parts + 1] = mouse_button_svg(
      "BTN_MIDDLE", wheel_x, wheel_y, wheel_w, wheel_h, wheel_w / 2,
      middle_active, middle_glow, cfg, colors, label_size, cfg.show_mouse_labels
    )
    local up = (anim.wheel_up_until or 0) > now
    local down = (anim.wheel_down_until or 0) > now
    parts[#parts + 1] = string.format(
      '<path d="M %s %s L %s %s L %s %s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>',
      num(wheel_x + wheel_w * 0.25), num(wheel_y + wheel_h * 0.32),
      num(wheel_x + wheel_w * 0.50), num(wheel_y + wheel_h * 0.22),
      num(wheel_x + wheel_w * 0.75), num(wheel_y + wheel_h * 0.32),
      up and colors.accent or colors.mouse_border, num(math.max(1, cfg.mouse_border_width))
    )
    parts[#parts + 1] = string.format(
      '<path d="M %s %s L %s %s L %s %s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>',
      num(wheel_x + wheel_w * 0.25), num(wheel_y + wheel_h * 0.68),
      num(wheel_x + wheel_w * 0.50), num(wheel_y + wheel_h * 0.78),
      num(wheel_x + wheel_w * 0.75), num(wheel_y + wheel_h * 0.68),
      down and colors.accent or colors.mouse_border, num(math.max(1, cfg.mouse_border_width))
    )
  end

  if #side > 0 then
    local side_w = width * 0.10
    local side_h = height * 0.11
    local side_gap = height * 0.02
    local side_x = x + width * 0.03
    local side_y = y + height * 0.49
    for index, name in ipairs(side) do
      local active = pressed[name] == true
      local glow = active or (anim.glow_until and (anim.glow_until[name] or 0) > now)
      parts[#parts + 1] = mouse_button_svg(
        name, side_x, side_y + (index - 1) * (side_h + side_gap), side_w, side_h, side_w * 0.25,
        active, glow, cfg, colors, label_size * 0.85, cfg.show_mouse_labels
      )
    end
  end

  return table.concat(parts)
end

function M.build(cfg, state, now, anim)
  now = now or 0
  anim = anim or {}
  local color_cache = {}
  local function resolve(value, fallback)
    local key = tostring(value)
    if color_cache[key] then
      return color_cache[key]
    end
    local color = config.resolve_color(value, fallback)
    color_cache[key] = color
    return color
  end

  local colors = {
    panel = resolve(cfg.overlay_background_color, "#05070a"),
    panel_border = resolve(cfg.overlay_border_color, "#22e6ff"),
    key_fill = resolve(cfg.key_idle_color, "#05070a"),
    key_border = resolve(cfg.key_border_color, "#f4f8fb"),
    key_text = resolve(cfg.key_text_color, "#f4f8fb"),
    accent = resolve(cfg.accent_color, "#22e6ff"),
    accent_text = resolve(cfg.accent_text_color, "#031014"),
    glow = resolve(cfg.glow_color, "#22e6ff"),
    arrow = resolve(cfg.motion_arrow_color, "#f4f8fb"),
    dot = resolve(cfg.motion_dot_color, "#f4f8fb"),
    mouse_fill = resolve(cfg.mouse_body_color, "#05070a"),
    mouse_border = resolve(cfg.mouse_border_color, "#f4f8fb"),
  }

  local rows = layout.rows(cfg.keyboard_layout, cfg.custom_keys)
  local cols = 1
  for _, row in ipairs(rows) do
    local units = 0
    for _, spec in ipairs(row) do
      units = units + (spec.w or 1)
    end
    if units > cols then
      cols = units
    end
  end

  local margin = 18
  local gap = cfg.key_gap
  local mouse_h = cfg.mouse_size
  local mouse_w = math.floor(mouse_h * 0.62)
  local group_gap = math.max(64, math.floor(cfg.key_size * 0.58))
  local max_keyboard_w = cfg.content_width - margin * 2 - group_gap - mouse_w
  local key_size = cfg.key_size
  if cfg.show_keyboard then
    local fit = math.floor((max_keyboard_w - (cols - 1) * gap) / cols)
    if fit < key_size then
      key_size = math.max(20, fit)
    end
  end
  local keyboard_w = 0
  local keyboard_h = 0
  if cfg.show_keyboard then
    keyboard_w = cols * key_size + (cols - 1) * gap
    keyboard_h = #rows * key_size + (#rows - 1) * gap
  end
  local mouse_w_visible = cfg.show_mouse and mouse_w or 0
  local actual_gap = (cfg.show_keyboard and cfg.show_mouse) and group_gap or 0
  local group_w = keyboard_w + actual_gap + mouse_w_visible
  local width = math.max(cfg.content_width, group_w + margin * 2)
  local height = math.max(keyboard_h, cfg.show_mouse and mouse_h or 0) + margin * 2
  local group_x = (width - group_w) / 2
  local keyboard_x = group_x
  local mouse_x = group_x + keyboard_w + actual_gap
  local keyboard_y = margin + ((height - margin * 2) - keyboard_h) / 2
  local mouse_y = margin + ((height - margin * 2) - (cfg.show_mouse and mouse_h or 0)) / 2

  local parts = {
    string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">',
      num(width), num(height), num(width), num(height)),
  }
  if cfg.overlay_background then
    parts[#parts + 1] = string.format(
      '<rect x="0" y="0" width="%s" height="%s" rx="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="%s"/>',
      num(width), num(height), num(cfg.overlay_radius), colors.panel,
      num(cfg.overlay_background_opacity),
      cfg.overlay_border_width > 0 and colors.panel_border or "none",
      num(cfg.overlay_border_width)
    )
  end

  if cfg.show_keyboard then
    local pressed = pressed_set(state)
    for row_index, row in ipairs(rows) do
      local units = 0
      for _, spec in ipairs(row) do
        units = units + (spec.w or 1)
      end
      local row_w = units * key_size + (units - 1) * gap
      local x = keyboard_x + (keyboard_w - row_w) / 2
      local y = keyboard_y + (row_index - 1) * (key_size + gap)
      for _, spec in ipairs(row) do
        local active = pressed[spec.key] == true
        local glow = active or (anim.glow_until and (anim.glow_until[spec.key] or 0) > now)
        parts[#parts + 1] = key_svg(cfg, spec, x, y, key_size, active, glow, colors)
        x = x + key_size * (spec.w or 1) + gap * (spec.w or 1)
      end
    end
  end

  if cfg.show_mouse then
    parts[#parts + 1] = mouse_svg(cfg, state, now, anim, mouse_x, mouse_y, mouse_w, mouse_h, colors)
  end

  parts[#parts + 1] = "</svg>"
  return table.concat(parts), width, height
end

return M
