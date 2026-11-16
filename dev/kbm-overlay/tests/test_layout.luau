--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
mock.new({ data_dir = "/data/kbm" })

local layout = mock.loadEntry("lib/layout.luau")

assert(layout.normalize("w") == "KEY_W")
assert(layout.normalize("SPACE") == "KEY_SPACE")
assert(layout.normalize("esc") == "KEY_ESC")
assert(layout.normalize("~") == "KEY_GRAVE")
assert(layout.normalize("GRAVE") == "KEY_GRAVE")
assert(layout.normalize("F1") == "KEY_F1")
assert(layout.normalize("BTN_LEFT") == "BTN_LEFT")
assert(layout.normalize("") == nil)

local fps = layout.rows("fps", {})
assert(#fps == 5, "fps layout has five rows")
assert(fps[1][1].key == "KEY_GRAVE")
assert(fps[5][3].key == "KEY_SPACE")
assert(fps[5][3].w == 3, "space spans three units")
assert(fps[2][3].label == "W")

local wasd = layout.rows("wasd", {})
assert(#wasd == 4)
assert(wasd[1][1].key == "KEY_1")
assert(wasd[4][2].w == 2)

local custom = layout.rows("custom", { "w", "a", "s", "d", "space" })
assert(#custom == 1)
assert(custom[1][1].key == "KEY_W")
assert(custom[1][5].key == "KEY_SPACE")

local keys = layout.all_keys("fps", {})
local seen = {}
for _, name in ipairs(keys) do
  assert(not seen[name], "duplicate key " .. name)
  seen[name] = true
end
assert(seen.KEY_W and seen.KEY_GRAVE and seen.BTN_LEFT == nil)

assert(layout.mouse_button_label("BTN_SIDE") == "MB4")
assert(layout.mouse_side_order()[1] == "BTN_FORWARD")
assert(layout.mouse_side_order()[2] == "BTN_EXTRA")
assert(layout.mouse_side_order()[3] == "BTN_SIDE")
assert(layout.mouse_button_label("BTN_EXTRA") == "MB5")

print("test_layout OK")
