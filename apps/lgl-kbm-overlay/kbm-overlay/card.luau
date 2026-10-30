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
  frame_until = now_ms() + 320
  dirty = true
end

function update()
  if dirty or now_ms() < frame_until then
    dirty = false
    render()
  end
end

noctalia.setUpdateInterval(50)
noctalia.state.watch("kbm_hidden", function(value)
  hidden = value == true
  if not hidden then
    dirty = true
    frame_until = now_ms() + 320
  end
  render()
end)
noctalia.state.watch("kbm_state", function(value)
  state = value
  local signature = state_signature(value)
  if signature == last_signature then
    return
  end
  last_signature = signature
  note_transitions(value)
  schedule()
end)
last_signature = state_signature(state)
note_transitions(state)
render()
