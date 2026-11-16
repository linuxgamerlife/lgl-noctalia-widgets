-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Static procedural scene generation: variants and SVG content.
local mock = dofile("tests/support/mock.luau")
local _ = mock.new({ config = {}, state = {} })
local scene = mock.loadEntry("lib/scene.luau")

assert(scene.variant("clear", true) == "clear_day", "clear day")
assert(scene.variant("rain", false) == "rain_night", "rain night")
assert(scene.variant("bogus", false) == "cloudy_night", "unknown category")

local clear = scene.svg("clear_night")
assert(clear:find("<svg", 1, true), "svg root")
assert(clear:find("circle", 1, true), "stars")
assert(clear:find("path", 1, true), "grass")
assert(not clear:find("<line x1=", 1, true), "no rain in clear")
assert(not clear:find("latitude", 1, true), "no coordinates in scene")
assert(clear == scene.svg("clear_night"), "scene is deterministic and static")

local rain = scene.svg("rain_night")
assert(rain:find("<line x1=", 1, true), "rain lines")
assert(rain:find("stroke-linecap", 1, true), "rain style")

local snow = scene.svg("snow_day")
assert(snow:find("circle", 1, true), "snow circles")

local thunder = scene.svg("thunder_day")
assert(thunder:find("polyline", 1, true), "lightning")

local fog = scene.svg("fog_night")
assert(fog:find("<rect", 1, true), "fog bands")

local ctx = mock.new({ config = {}, state = {}, data_dir = "/data" })
local path, err = scene.write("/data", "rain_night")
assert(path ~= nil, "scene write: " .. tostring(err))
assert(type(path) == "string", "one static scene path")
assert(ctx.files[path] ~= nil, "scene file stored")
assert(path:find("/data/scenes/rain_night/scene.svg", 1, true) ~= nil, "scene path")

print("SCENE TEST OK")
