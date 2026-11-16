--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = {
    keyboard_layout = "invalid",
    content_width = 9999,
    key_size = 999,
    key_gap = 99,
    overlay_background = false,
    key_idle_opacity = -1,
    custom_keys = { "W", "A", "S", "D", "SPACE" },
  },
  data_dir = "/data/kbm",
})

local config = mock.loadEntry("lib/config.luau")
local cfg = config.visual()

assert(cfg.keyboard_layout == "fps", "invalid layout must fall back to fps")
assert(cfg.content_width == 1000, "content width must clamp")
assert(cfg.key_size == 64, "key size must clamp")
assert(cfg.key_gap == 16, "key gap must clamp")
assert(cfg.overlay_background == false, "bool setting")
assert(cfg.key_idle_opacity == 0, "opacity must clamp to min")
assert(#cfg.custom_keys == 5, "string list must pass through")
assert(config.color_with_alpha("primary", 0.5) == "primary/0.50")
assert(config.color_with_alpha("#112233", 0.5) == "#11223380")
assert(config.color_with_alpha("#11223344", 0.25) == "#11223340")
assert(config.color_with_alpha("primary", 1) == "primary")
assert(config.resolve_color("#22e6ff", "#000000") == "#22e6ff")
assert(config.resolve_color("primary", "#000000") == "#000000")

assert(config.devices_path() == "/data/kbm/devices.json")
assert(config.runtime_path() == "/data/kbm/runtime.json")

local bar = config.bar()
assert(bar.glyph == "keyboard")

print("test_config OK")
