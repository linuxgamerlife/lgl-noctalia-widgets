local shared = {}
local watchers = {}
local stream_cb = nil
local tree = nil
local config = {
  low_threshold = 20,
  notify_low = true,
  show_profile = true,
  show_player_leds = true,
  show_model_badge = true,
  illustration_color = "#e8ebef",
  controller_body_color = "#2c3035",
  controller_body_opacity = 1.0,
  controller_stroke_width = 2.8,
  profile_settings_opacity = 0.65,
  battery_color_mode = "lightbar",
  battery_fill_color = "#0080ff",
  battery_fill_opacity = 1.0,
  battery_low_color = "#ed4c4c",
  text_color = "on_surface",
  muted_text_color = "on_surface_variant",
}
local notifications = 0
local async_cmds = {}

local function ctor(t)
  return function(props, children)
    return { type = t, props = props or {}, children = children or {} }
  end
end
ui = { column=ctor("column"), row=ctor("row"), box=ctor("box"), label=ctor("label"), glyph=ctor("glyph"), image=ctor("image"), spacer=ctor("spacer"), select=ctor("select"), button=ctor("button") }

noctalia = {
  getenv = function() return "/tmp/opencode/mock-runtime" end,
  getConfig = function(k) return config[k] end,
  log = function() end,
  pluginDir = function() return "/tmp/opencode/plugin" end,
  pluginDataDir = function() return "/tmp/opencode/plugin-data" end,
  readFile = function(p)
    if p == "assets/controller-template.svg" then
      return "<svg>{{BODY}}|{{BODY_OPACITY}}|{{COLOR}}|{{LIGHTBAR}}|{{STROKE_BODY}}|{{STROKE_GRIP}}</svg>"
    end
    if p == "assets/settings-button-template.svg" then
      return "<svg>{{BACKGROUND}}|{{BACKGROUND_OPACITY}}|{{ICON}}</svg>"
    end
    return nil
  end,
  writeFile = function() return true end,
  removeFile = function() return true end,
  runAsync = function(cmd) table.insert(async_cmds, cmd); return true end,
  commandExists = function() return true end,
  fileExists = function() return true end,
  runStream = function(_, cb) stream_cb = cb; return true end,
  notify = function() notifications = notifications + 1 end,
  notifyError = function() end,
  tr = function(k, s) if k == "notification.low.body" then return tostring(s.pct) end; return k end,
  setUpdateInterval = function() end,
  json = {
    decode = function(str)
      local out = {}
      for k, v in string.gmatch(str, '"([%w_]+)":([^,}]+)') do
        local n = tonumber(v)
        if n then out[k] = n elseif v == "true" then out[k] = true elseif v == "false" then out[k] = false elseif v ~= "null" then out[k] = v:gsub('^"',''):gsub('"$','') end
      end
      return out
    end,
  },
  state = {
    get = function(k) return shared[k] end,
    set = function(k, v)
      shared[k] = v
      if watchers[k] then for _, cb in ipairs(watchers[k]) do cb(v) end end
    end,
    watch = function(k, cb) watchers[k] = watchers[k] or {}; table.insert(watchers[k], cb) end,
  },
}
desktopWidget = {
  setNeedsFrameTick = function() end,
  render = function(t) tree = t end,
}

local plugin_dir = arg[1] or "dualsense"
dofile(plugin_dir .. "/battery.luau")
dofile(plugin_dir .. "/card.luau")

assert(tree, "card did not render before state arrived")
local function find_text(t, text)
  if t.props.text == text then return t end
  for _, c in ipairs(t.children or {}) do local r = find_text(c, text); if r then return r end end
end
local function find_key(t, key)
  if t.props.key == key then return t end
  for _, c in ipairs(t.children or {}) do local r = find_key(c, key); if r then return r end end
end
assert(find_text(tree, "status.waiting"), "initial waiting state missing")

stream_cb('{"battery_pct":15,"connected":true,"charging":false,"full":false,"provisional":false,"model":"dualsense","profile":"FPS","lightbar_color":"#a855f7","player_leds":1,"connection":"bluetooth","ts":' .. os.time() .. '}')
assert(find_text(tree, "15"), "card did not receive the battery percentage")
assert(find_text(tree, "status.low"), "card did not show the low state")
assert(find_key(tree, "profile-name").props.text == "FPS", "card did not show the ds4u profile")
assert(notifications == 1, "expected exactly one low notification")
assert(shared.low_notified == true, "low notification flag not published")

stream_cb('{"battery_pct":75,"connected":true,"charging":true,"full":false,"provisional":false,"model":"edge","profile":"Default","lightbar_color":"#0080ff","player_leds":2,"connection":"usb","ts":' .. os.time() .. '}')
assert(find_text(tree, "75"), "charging percentage missing")
assert(find_text(tree, "status.charging_usb"), "charging USB status missing")
assert(find_text(tree, "status.model_edge"), "DualSense Edge badge missing")

-- Verify profile selector -> service action round-trip
async_cmds = {}
onProfileChanged("1", "FPS")
assert(#async_cmds == 1 and string.find(async_cmds[1], "--switch-profile 'FPS'", 1, true), "profile selector did not switch to FPS")

print("INTEGRATION TEST OK")
