--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

local mock = dofile("tests/support/mock.luau")

local PLUGIN = arg[1] or "kbm-overlay"
local ctx = mock.new({
  config = {
    keyboard_device = "",
    mouse_device = "",
  },
  data_dir = "/data/kbm",
  commands_available = { python3 = true },
})

mock.loadEntry("service.luau")

assert(#ctx.streams == 1, "service must start one reader stream")
assert(string.find(ctx.streams[1], "kbm_daemon.py", 1, true) ~= nil)
assert(string.find(ctx.streams[1], "--config", 1, true) ~= nil)
assert(ctx.files["/data/kbm/runtime.json"] ~= nil, "runtime config must be written")

ctx.stream_callback('{"type":"state","pressed":["KEY_W"],"wheel_up":0,"wheel_down":0,"keyboard":{"name":"Kbd"},"mouse":{"name":"Mouse","buttons":["BTN_LEFT"]}}')
assert(ctx.state.kbm_state ~= nil)
assert(ctx.state.kbm_state.pressed[1] == "KEY_W")
assert(ctx.state.kbm_state.mouse.name == "Mouse")

ctx.stream_callback('{"type":"devices","devices":[{"name":"Kbd","path":"/dev/input/event1","keyboard":true}]}')
assert(#ctx.state.kbm_devices == 1)

ctx.stream_callback('{"type":"error","code":"permission","message":"Denied"}')
assert(ctx.state.kbm_error.code == "permission")

ctx.stream_callback('{"type":"status","state":"ok","keyboard":"Kbd","mouse":"Mouse"}')
assert(ctx.state.kbm_status.state == "ok")

ctx.state.kbm_config_rev = 1
noctalia.state.set("kbm_config_rev", 1)
assert(#ctx.streams == 2, "config revision must restart the reader")

onIpc("restart")
assert(#ctx.streams == 3, "IPC restart must start a new reader")

onIpc("hide")
assert(ctx.state.kbm_hidden == true)
onIpc("show")
assert(ctx.state.kbm_hidden == false)
onIpc("toggle")
assert(ctx.state.kbm_hidden == true)
onIpc("toggle")
assert(ctx.state.kbm_hidden == false)

assert(#ctx.intervals == 1 and ctx.intervals[1] == 2000)

print("test_service OK")
