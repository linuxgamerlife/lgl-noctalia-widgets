--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = {},
  data_dir = "/data/kbm",
})

local devices_state = {
  {
    name = "Gaming Keyboard",
    path = "/dev/input/event3",
    vendor = "1234",
    product = "abcd",
    keyboard = true,
    mouse = false,
    readable = true,
    buttons = {},
  },
  {
    name = "Gaming Mouse",
    path = "/dev/input/event4",
    vendor = "5678",
    product = "ef01",
    keyboard = false,
    mouse = true,
    readable = true,
    buttons = { "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE" },
  },
}
ctx.state.kbm_devices = devices_state

mock.loadEntry("devices.luau")
onOpen()

assert(ctx.panel_tree ~= nil, "device panel must render")
assert(mock.find(ctx.panel_tree, "devices-title") ~= nil)
assert(mock.find(ctx.panel_tree, "device-name-/dev/input/event3") ~= nil)
assert(mock.find(ctx.panel_tree, "device-name-/dev/input/event4") ~= nil)

local keyboard_button = mock.find(ctx.panel_tree, "device-use-/dev/input/event3")
assert(keyboard_button ~= nil, "keyboard must have a Use button")
keyboard_button.props.onClick()

local mouse_button = mock.find(ctx.panel_tree, "device-use-/dev/input/event4")
assert(mouse_button ~= nil, "mouse must have a Use button")
mouse_button.props.onClick()

local saved = ctx.files["/data/kbm/devices.json"]
assert(saved ~= nil, "selection must be written")
assert(string.find(saved, "Gaming Keyboard", 1, true) ~= nil)
assert(string.find(saved, "Gaming Mouse", 1, true) ~= nil)
assert(ctx.state.kbm_config_rev == 2, "each selection must bump the revision")

local copy = mock.find(ctx.panel_tree, "permission-copy")
assert(copy ~= nil)
copy.props.onClick()
assert(ctx.clipboard ~= nil and string.find(ctx.clipboard.text, "setup-input-permissions.sh", 1, true) ~= nil)

print("test_devices OK")
