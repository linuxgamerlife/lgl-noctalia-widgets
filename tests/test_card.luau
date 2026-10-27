local tree = nil
local frame_tick = false
local watch_cb = nil
local written = nil
local last_action = nil
local state = {
  battery_pct = 65,
  battery_status = "Discharging",
  connected = true,
  charging = false,
  full = false,
  provisional = false,
  connection = "bluetooth",
  model = "dualsense",
  profile = "Default",
  lightbar_color = "#0080ff",
  player_leds = 2,
  ds4u_daemon = true,
  ts = os.time(),
}

local config = {
  illustration_color = "#ff8800",
  controller_body_color = "#112233",
  controller_body_opacity = 0.4,
  controller_stroke_width = 4.0,
  battery_color_mode = "lightbar",
  battery_fill_color = "#33cc99",
  battery_fill_opacity = 0.5,
  battery_low_color = "#ed4c4c",
  text_color = "#abcdef",
  muted_text_color = "#123456",
  show_profile = true,
  show_player_leds = true,
  show_model_badge = true,
  low_threshold = 20,
}

local function ctor(t)
  return function(props, children)
    return { type = t, props = props or {}, children = children or {} }
  end
end

ui = {
  column = ctor("column"), row = ctor("row"), box = ctor("box"),
  label = ctor("label"), glyph = ctor("glyph"), image = ctor("image"),
  spacer = ctor("spacer"), separator = ctor("separator"),
}

noctalia = {
  getConfig = function(k) return config[k] end,
  tr = function(k) return k end,
  state = {
    get = function() return state end,
    set = function(k, v) if k == "action" then last_action = v end end,
    watch = function(_, cb) watch_cb = cb end,
  },
  pluginDataDir = function() return "/tmp/opencode/plugin-data" end,
  readFile = function() return "<svg>{{BODY}}|{{BODY_OPACITY}}|{{COLOR}}|{{LIGHTBAR}}|{{STROKE_BODY}}|{{STROKE_GRIP}}</svg>" end,
  writeFile = function(path, content) written = { path = path, content = content }; return true end,
  setUpdateInterval = function() end,
  log = function() end,
}

desktopWidget = {
  setNeedsFrameTick = function(v) frame_tick = v end,
  render = function(t) tree = t end,
}

local plugin_dir = arg[1] or "dualsense"
dofile(plugin_dir .. "/card.luau")

local function walk(node, out)
  out = out or {}
  table.insert(out, node)
  for _, child in ipairs(node.children or {}) do walk(child, out) end
  return out
end
local function find_key(t, key)
  for _, node in ipairs(walk(t)) do if node.props.key == key then return node end end
end
local function find_text(t, text)
  for _, node in ipairs(walk(t)) do if node.props.text == text then return node end end
end

assert(tree and tree.type == "column", "card tree missing")
assert(
  written and written.content == "<svg>#112233|0.40|#ff8800|#0080ff|4.00|2.50</svg>",
  "generated SVG wrong: " .. tostring(written and written.content)
)
assert(find_key(tree, "controller-art"), "controller art missing")
assert(find_key(tree, "battery-fill"), "battery fill missing")
assert(find_key(tree, "player-leds-row"), "player LEDs missing")
assert(find_key(tree, "profile-row"), "profile row missing")
assert(find_key(tree, "ds4u-daemon-badge"), "ds4u daemon badge missing")
assert(find_text(tree, "65"), "battery percentage missing")
assert(find_text(tree, "Default"), "profile label missing")
assert(find_text(tree, "status.connected"), "connected status missing")
assert(find_text(tree, "65").props.color == "#abcdef", "primary text colour not applied")
assert(find_text(tree, "%").props.color == "#123456", "secondary text colour not applied")
assert(find_text(tree, "status.connected").props.color == "#abcdef", "status text colour not applied")
assert(find_key(tree, "battery-fill").props.fill == "#0080ff", "lightbar fill mode should use lightbar_color")
assert(find_key(tree, "battery-fill").props.opacity == 0.5, "fill opacity setting not applied")
assert(frame_tick == false, "should not request frame ticks while idle")

-- Test profile click callback
onCycleProfile()
assert(last_action and last_action.action == "cycle-profile", "onCycleProfile did not publish action")

-- Test buzz click callback
onBuzzController()
assert(last_action and last_action.action == "buzz", "onBuzzController did not publish action")

-- Charging: pulse frames should change the fill opacity.
state.charging = true
watch_cb(state)
assert(frame_tick == true, "charging should request frame ticks")
local before = find_key(tree, "battery-fill").props.opacity
for _ = 1, 4 do onFrameTick(33) end
local after = find_key(tree, "battery-fill").props.opacity
assert(before == 0.5 and after < before, ("pulse did not change opacity: %s -> %s"):format(before, after))

-- Full battery while plugged in: no pulse, shows full status.
state.full = true
watch_cb(state)
assert(frame_tick == false, "full should stop charging pulse")
assert(find_text(tree, "status.full"), "full status missing")

-- DualSense Edge model badge.
state.full = false
state.charging = false
state.model = "edge"
watch_cb(state)
assert(find_text(tree, "status.model_edge"), "DualSense Edge badge missing")

-- Low battery: red fill, low status.
state.battery_pct = 15
watch_cb(state)
assert(find_text(tree, "status.low"), "low status missing")
assert(find_key(tree, "battery-fill").props.fill == "#ed4c4c", "low fill should be red")
assert(find_text(tree, "15").props.color == "#ed4c4c", "low percentage should use low colour")
assert(find_text(tree, "status.low").props.color == "#ed4c4c", "low status should use low colour")

-- Stale state: show the waiting status and no fill.
state.ts = os.time() - 100
watch_cb(state)
assert(find_text(tree, "status.waiting"), "waiting status missing")
assert(find_key(tree, "battery-fill") == nil, "stale state should hide the fill")

-- Connection fill mode: Bluetooth = blue, USB = green.
config.battery_color_mode = "connection"
state.ts = os.time()
state.connection = "bluetooth"
state.battery_pct = 55
state.charging = false
state.connected = true
dofile(plugin_dir .. "/card.luau")
assert(find_key(tree, "battery-fill").props.fill == "#3daee9", "Bluetooth fill should be blue")
assert(find_key(tree, "status-glyph").props.name == "bluetooth", "Bluetooth glyph missing")

state.connection = "usb"
watch_cb(state)
assert(find_key(tree, "battery-fill").props.fill == "#3ec47a", "USB fill should be green")
assert(find_key(tree, "status-glyph").props.name == "usb", "USB glyph missing")

-- Custom fill mode: uses battery_fill_color, while low keeps low colour.
config.battery_color_mode = "custom"
dofile(plugin_dir .. "/card.luau")
assert(find_key(tree, "battery-fill").props.fill == "#33cc99", "custom fill should be used")
state.battery_pct = 5
watch_cb(state)
assert(find_key(tree, "battery-fill").props.fill == "#ed4c4c", "low should override custom fill")

-- Theme role: update() re-resolves the controller art when the palette changes.
local theme_color = "#010203"
noctalia.getColor = function(role)
  if role == "primary" then return theme_color end
  return nil
end
config.illustration_color = "primary"
config.controller_body_color = "primary"
dofile(plugin_dir .. "/card.luau")
assert(written.content:find("#010203", 1, true), "theme colour not baked into SVG")
local old_art = find_key(tree, "controller-art").props.path
theme_color = "#040506"
update()
assert(written.content:find("#040506", 1, true), "theme change did not regenerate SVG")
assert(find_key(tree, "controller-art").props.path ~= old_art, "theme change did not swap art path")

print("CARD TEST OK")
