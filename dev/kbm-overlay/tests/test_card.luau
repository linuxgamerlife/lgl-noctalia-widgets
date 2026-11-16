--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = {
    content_width = 620,
  },
  data_dir = "/data/kbm",
})

mock.loadEntry("card.luau")
assert(ctx.desktop_tree ~= nil, "desktop card renders at load")
assert(ctx.desktop_tree ~= nil, "card must render an image")

local first_path = ctx.desktop_tree.props.path
assert(first_path ~= nil)
assert(ctx.files[first_path] ~= nil, "SVG frame must be written")
assert(string.find(ctx.files[first_path], "<svg", 1, true) ~= nil)
assert(string.find(ctx.files[first_path], "NO MOUSE", 1, true) ~= nil)

noctalia.state.set("kbm_state", {
  pressed = { "KEY_W", "BTN_LEFT" },
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE" } },
})
update()
local second_path = ctx.desktop_tree.props.path
assert(second_path ~= first_path, "a new frame path forces the image to reload")
local svg = ctx.files[second_path]
assert(string.find(svg, ">W<", 1, true) ~= nil, "W label must be in the SVG")
assert(string.find(svg, "#22e6ff", 1, true) ~= nil, "pressed key must use the accent colour")
assert(string.find(svg, "LMB", 1, true) == nil, "mouse labels are off by default")
assert(ctx.files["/data/kbm/frame.tmp.svg"] == nil, "frame must be renamed atomically")

-- A heartbeat-only update (same pressed/wheel data, new seq/ts) must not
-- redraw. This is what caused the wheel and scroll arrows to blink.
local stable = {
  pressed = { "KEY_W", "BTN_LEFT" },
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE" } },
  seq = 99,
  ts = 999,
}
ctx.now_ms = ctx.now_ms + 1000
noctalia.state.set("kbm_state", stable)
update()
assert(ctx.desktop_tree.props.path == second_path, "heartbeat must not redraw")

local changed = {
  pressed = { "KEY_W", "KEY_A", "BTN_LEFT" },
  keyboard = { name = "Kbd" },
  mouse = { name = "Mouse", buttons = { "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE" } },
  move_x = 80,
  move_y = -40,
  move_at = ctx.now_ms - 10,
  move_seq = 1,
}
noctalia.state.set("kbm_state", changed)
update()
assert(ctx.desktop_tree.props.path ~= second_path, "input change must redraw")
local movement_svg = ctx.files[ctx.desktop_tree.props.path]
assert(string.find(movement_svg, "<polygon", 1, true) ~= nil, "motion arrow must be in the rendered frame")
noctalia.state.set("kbm_hidden", true)
assert(ctx.desktop_tree.props.key == "kbm-hidden", "hide must blank the widget")
noctalia.state.set("kbm_hidden", false)
assert(ctx.desktop_tree.props.key ~= "kbm-hidden", "show must restore the widget")
print("test_card OK")
