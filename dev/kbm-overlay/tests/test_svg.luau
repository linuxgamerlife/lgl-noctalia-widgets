--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = { content_width = 620, keyboard_layout = "fps", show_mouse_labels = true },
  data_dir = "/data/kbm",
})

local config = mock.loadEntry("lib/config.luau")
local svg = mock.loadEntry("lib/svg.luau")
local cfg = config.visual()
local state = {
  pressed = { "KEY_W", "BTN_LEFT", "BTN_SIDE" },
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE" } },
}

local body, width, height = svg.build(cfg, state, 1000, {
  glow_until = {},
  wheel_up_until = 1100,
  wheel_down_until = 0,
})
assert(type(body) == "string")
assert(string.find(body, "<svg", 1, true) ~= nil)
assert(string.find(body, "</svg>", 1, true) ~= nil)
assert(string.find(body, "TAB", 1, true) ~= nil)
assert(string.find(body, "SPACE", 1, true) ~= nil)
assert(string.find(body, ">W<", 1, true) ~= nil)
assert(string.find(body, "<path", 1, true) ~= nil, "mouse body must be a path")
assert(string.find(body, "LMB", 1, true) ~= nil)
assert(string.find(body, "#22e6ff", 1, true) ~= nil)
assert(width >= 620)
assert(height > 200)

local idle_mouse = svg.build(cfg, {
  pressed = {},
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT" } },
}, 1000, {})
assert(string.find(idle_mouse, "<circle", 1, true) ~= nil, "pivot dot must be visible while idle")

local moving = {
  pressed = {},
  move_x = 20,
  move_y = -10,
  move_at = 980,
  move_seq = 1,
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT" } },
}
local moving_body = svg.build(cfg, moving, 1000, {})
assert(string.find(moving_body, "<polygon", 1, true) ~= nil, "motion arrow head must render")
assert(string.find(moving_body, "<circle", 1, true) ~= nil, "motion arrow pivot must render")
local smoothed = svg.build(cfg, { pressed = {}, mouse = { name = "Mouse", buttons = { "BTN_LEFT" } } }, 1000, {
  arrow = { speed = 40, dx = 0.8, dy = -0.6 },
})
assert(string.find(smoothed, "<polygon", 1, true) ~= nil, "smoothed arrow head must render")
local slow = svg.build(cfg, { pressed = {}, mouse = { name = "Mouse", buttons = { "BTN_LEFT" } } }, 1000, {
  arrow = { speed = 1.2, dx = 1, dy = 0 },
})
assert(string.find(slow, "<polygon", 1, true) ~= nil, "slow movement must still render an arrow")
local distance_arrow = svg.build(cfg, { pressed = {}, mouse = { name = "Mouse", buttons = { "BTN_LEFT" } } }, 1000, {
  arrow = { speed = 5, dx = 1, dy = 0, use_distance = true, distance = 0.5, fade = 1 },
})
assert(string.find(distance_arrow, "<polygon", 1, true) ~= nil, "distance-based arrow must render")



local no_mouse = svg.build(cfg, { pressed = {} }, 1000, {})
assert(string.find(no_mouse, "NO MOUSE", 1, true) ~= nil)

local wasd = config.visual()
wasd.keyboard_layout = "wasd"
wasd.show_mouse = false
local wasd_body = svg.build(wasd, { pressed = {} }, 1000, {})
assert(string.find(wasd_body, "CAPS", 1, true) == nil)
assert(string.find(wasd_body, "SHIFT", 1, true) ~= nil)

print("test_svg OK")
