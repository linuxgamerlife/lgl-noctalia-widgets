--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = { show_label = true, label = "KBM" },
  data_dir = "/data/kbm",
})

mock.loadEntry("bar.luau")
assert(ctx.bar_tree ~= nil, "bar widget renders")
assert(mock.find(ctx.bar_tree, "bar-glyph") ~= nil)
assert(mock.findText(ctx.bar_tree, "KBM") ~= nil)

onClick()
assert(ctx.toggled_panel == "linuxgamerlife/kbm-overlay:devices")

noctalia.state.set("kbm_state", { pressed = { "KEY_W" }, keyboard = { name = "Kbd" }, mouse = { name = "Mouse" } })
assert(mock.find(ctx.bar_tree, "bar-glyph").props.color == "primary")

noctalia.state.set("kbm_error", { code = "permission", message = "Denied" })
assert(mock.find(ctx.bar_tree, "bar-warning") ~= nil)

print("test_bar OK")
