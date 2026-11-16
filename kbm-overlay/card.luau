--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Movable desktop widget. No layer-shell surface and no overlay panel: the
-- user places this in the desktop-widget editor, and all look-and-feel
-- settings live in the widget's own settings.

local config = require("./lib/config.luau")
local svg = require("./lib/svg.luau")

local cfg = config.visual()
local data_dir = config.data_dir()
local state = noctalia.state.get("kbm_state")
local hidden = noctalia.state.get("kbm_hidden") == true
local dirty = true
local frame_until = 0
local frame_seq = 0
local frame_path = nil
local glow_until = {}
local wheel_up_until = 0
local wheel_down_until = 0
local last_pressed = {}
local last_wheel_up = 0
local last_wheel_down = 0
local last_signature = nil
local arrow = { speed = 0, dx = 0, dy = 0, distance = 0, use_distance = false, fade = 0 }
local last_arrow_ms = 0
local last_move_seen = 0
local last_move_speed = 0
local last_move_dx = 0
local last_move_dy = 0
local motion_x = 0
local motion_y = 0
local reacquire_arrow = false
local last_cursor_change = 0
local last_cursor_x = nil
local last_cursor_y = nil

local FRAME_SLOTS = 16

local function now_ms()
  if type(noctalia.nowMs) == "function" then
    return noctalia.nowMs()
  end
  return os.clock() * 1000
end

local function pressed_map(value)
  local set = {}
  if type(value) == "table" and type(value.pressed) == "table" then
    for _, name in ipairs(value.pressed) do
      set[name] = true
    end
  end
  return set
end

local function state_signature(value)
  if type(value) ~= "table" then
    return "nil"
  end
  local pressed = {}
  if type(value.pressed) == "table" then
    for _, name in ipairs(value.pressed) do
      pressed[#pressed + 1] = tostring(name)
    end
  end
  table.sort(pressed)
  local mouse = type(value.mouse) == "table" and value.mouse or {}
  local keyboard = type(value.keyboard) == "table" and value.keyboard or {}
  local buttons = {}
  if type(mouse.buttons) == "table" then
    for _, name in ipairs(mouse.buttons) do
      buttons[#buttons + 1] = tostring(name)
    end
  end
  table.sort(buttons)
  return table.concat({
    table.concat(pressed, ","),
    tostring(value.wheel_up or 0),
    tostring(value.wheel_down or 0),
    tostring(value.move_x or 0),
    tostring(value.move_y or 0),
    tostring(value.move_at or 0),
    tostring(value.move_seq or 0),
    tostring(keyboard.name or ""),
    tostring(mouse.name or ""),
    table.concat(buttons, ","),
  }, "|")
end

local function note_transitions(value)
  if type(value) ~= "table" then
    return
  end
  local now = now_ms()
  local pressed = pressed_map(value)
  for name in pairs(pressed) do
    glow_until[name] = nil
  end
  for name in pairs(last_pressed) do
    if not pressed[name] then
      glow_until[name] = now + 160
    end
  end
  last_pressed = pressed

  local wheel_up = tonumber(value.wheel_up) or 0
  local wheel_down = tonumber(value.wheel_down) or 0
  if wheel_up > last_wheel_up then
    wheel_up_until = now + 170
  end
  if wheel_down > last_wheel_down then
    wheel_down_until = now + 170
  end
  last_wheel_up = wheel_up
  last_wheel_down = wheel_down
end

local function cursor_center_vector()
  local cx = tonumber(state and state.cursor_x) or nil
  local cy = tonumber(state and state.cursor_y) or nil
  if cx == nil or cy == nil then
    return nil
  end
  if type(noctalia.outputs) ~= "function" then
    return nil
  end
  local ok, outputs = pcall(noctalia.outputs)
  if not ok or type(outputs) ~= "table" then
    return nil
  end
  local fallback = nil
  for _, output in ipairs(outputs) do
    local x = tonumber(output.x)
    local y = tonumber(output.y)
    local w = tonumber(output.width)
    local h = tonumber(output.height)
    if x and y and w and h then
      if fallback == nil or output.focused == true then
        fallback = output
      end
      if cx >= x and cx < x + w and cy >= y and cy < y + h then
        local dx = cx - (x + w / 2)
        local dy = cy - (y + h / 2)
        local nx = dx / math.max(1, w / 2)
        local ny = dy / math.max(1, h / 2)
        return dx, dy, math.min(1, math.sqrt(nx * nx + ny * ny))
      end
    end
  end
  if fallback then
    local x = tonumber(fallback.x)
    local y = tonumber(fallback.y)
    local w = tonumber(fallback.width)
    local h = tonumber(fallback.height)
    if x and y and w and h then
      local dx = cx - (x + w / 2)
      local dy = cy - (y + h / 2)
      local nx = dx / math.max(1, w / 2)
      local ny = dy / math.max(1, h / 2)
      return dx, dy, math.min(1, math.sqrt(nx * nx + ny * ny))
    end
  end
  return nil
end

local function update_arrow(now)
  local target_speed = 0
  local target_dx = 0
  local target_dy = 0
  local target_distance = 0
  local use_distance = false
  local idle_ms = (tonumber(cfg.motion_arrow_idle) or 0.8) * 1000
  if (now - last_move_seen) < idle_ms then
    target_speed = last_move_speed
    target_dx = last_move_dx
    target_dy = last_move_dy
  end
  -- Direction is relative to the centre of the screen containing the cursor,
  -- not the direction of the last relative mouse delta. Length remains
  -- speed-based. In a game the cursor is often locked, so Auto falls back to
  -- movement direction when the absolute cursor stops changing.
  local mode = cfg.motion_direction or "auto"
  local screen_ok = mode == "screen" or (mode == "auto" and (now - last_cursor_change) < 250)
  local scx, scy, distance = cursor_center_vector()
  if screen_ok and scx ~= nil and scy ~= nil then
    local mag = math.sqrt(scx * scx + scy * scy)
    if mag > 2 then
      target_dx = scx / mag
      target_dy = scy / mag
    end
    target_distance = tonumber(distance) or 0
    use_distance = true
  end
  local dt = math.max(0.016, (now - last_arrow_ms) / 1000.0)
  last_arrow_ms = now
  local was_idle = arrow.speed < 0.5
  if reacquire_arrow and target_speed > 0.5 then
    -- Starting again after a pause should pick the new direction immediately,
    -- not ease out of the old idle direction.
    arrow.speed = target_speed
    arrow.dx = target_dx
    arrow.dy = target_dy
    reacquire_arrow = false
    was_idle = false
  end
  local speed_tau = (target_speed > arrow.speed) and 0.035 or 0.12
  local speed_k = 1.0 - math.exp(-dt / speed_tau)
  local dir_k = 1.0 - math.exp(-dt / 0.06)
  arrow.speed = arrow.speed + (target_speed - arrow.speed) * speed_k
  arrow.use_distance = use_distance
  arrow.distance = arrow.distance + (target_distance - arrow.distance) * dir_k
  arrow.fade = math.min(1, arrow.speed / math.max(0.5, last_move_speed))
  if target_speed > 0.5 then
    if was_idle then
      arrow.dx = target_dx
      arrow.dy = target_dy
    else
      arrow.dx = arrow.dx + (target_dx - arrow.dx) * dir_k
      arrow.dy = arrow.dy + (target_dy - arrow.dy) * dir_k
    end
  end
  local mag = math.sqrt(arrow.dx * arrow.dx + arrow.dy * arrow.dy)
  if mag > 0.0001 then
    arrow.dx = arrow.dx / mag
    arrow.dy = arrow.dy / mag
  end
  if arrow.speed < 0.5 then
    arrow.speed = 0
    arrow.fade = 0
    arrow.distance = 0
    motion_x = 0
    motion_y = 0
    reacquire_arrow = false
  end
end

local function render()
  if hidden then
    desktopWidget.render(ui.column({
      key = "kbm-hidden",
      width = 0,
      height = 0,
      fill = "#00000000",
    }, {}))
    return
  end
  local now = now_ms()
  local body, width, height = svg.build(cfg, state, now, {
    glow_until = glow_until,
    wheel_up_until = wheel_up_until,
    wheel_down_until = wheel_down_until,
    arrow = arrow,
  })
  frame_seq = frame_seq + 1
  local path = data_dir .. "/frame-" .. (frame_seq % FRAME_SLOTS) .. ".svg"
  -- Write to a temporary file and rename it into place. Reading a partially
  -- written SVG is what made the wheel and scroll arrows blink in and out.
  local temporary = data_dir .. "/frame.tmp.svg"
  local ok, err = noctalia.writeFile(temporary, body)
  if ok then
    local renamed, rename_err = noctalia.renameFile(temporary, path)
    if not renamed then
      noctalia.log("[kbm-overlay] could not rename frame: " .. tostring(rename_err))
      noctalia.removeFile(temporary)
      return
    end
  else
    noctalia.log("[kbm-overlay] could not write frame: " .. tostring(err))
    return
  end
  frame_path = path

  desktopWidget.render(ui.image({
    key = "kbm-image",
    path = frame_path,
    width = width,
    height = height,
    fit = "contain",
  }))
end

local function schedule()
  frame_until = now_ms() + 420
  dirty = true
end

function update()
  local now = now_ms()
  update_arrow(now)
  if dirty or now < frame_until or arrow.speed > 0.5 then
    dirty = false
    render()
  end
end

noctalia.setUpdateInterval(16)
noctalia.state.watch("kbm_hidden", function(value)
  hidden = value == true
  if not hidden then
    dirty = true
    frame_until = now_ms() + 420
  end
  render()
end)
noctalia.state.watch("kbm_state", function(value)
  state = value
  if type(value) == "table" then
    local cx = tonumber(value.cursor_x)
    local cy = tonumber(value.cursor_y)
    if cx ~= nil and cy ~= nil and (cx ~= last_cursor_x or cy ~= last_cursor_y) then
      last_cursor_change = now_ms()
      last_cursor_x = cx
      last_cursor_y = cy
    end
    local mx = tonumber(value.move_x) or 0
    local my = tonumber(value.move_y) or 0
    local speed = math.sqrt(mx * mx + my * my)
    if speed > 0.5 then
      local now = now_ms()
      local gap = now - last_move_seen
      -- Blend both axes so diagonal movement does not collapse into N/S/E/W
      -- when the kernel reports one-axis deltas in alternating frames.
      if motion_x == 0 and motion_y == 0 then
        motion_x = mx
        motion_y = my
      else
        local blend = 0.45
        motion_x = motion_x + (mx - motion_x) * blend
        motion_y = motion_y + (my - motion_y) * blend
      end
      local vector_speed = math.sqrt(motion_x * motion_x + motion_y * motion_y)
      if vector_speed > 0.3 then
        if gap > 250 then
          -- New movement after a pause: reset direction and respond on the
          -- first frame instead of sliding out of the old idle direction.
          motion_x = mx
          motion_y = my
          vector_speed = speed
          reacquire_arrow = true
        end
        last_move_seen = now
        last_move_speed = vector_speed
        last_move_dx = motion_x / vector_speed
        last_move_dy = motion_y / vector_speed
      end
    end
  end
  local signature = state_signature(value)
  if signature == last_signature then
    return
  end
  last_signature = signature
  note_transitions(value)
  schedule()
end)
last_signature = state_signature(state)
last_arrow_ms = now_ms()
note_transitions(state)
render()
