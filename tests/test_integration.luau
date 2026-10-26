local shared = {}
local watchers = {}
local stream_cb = nil
local tree = nil
local config = { low_threshold = 20, notify_low = true, show_signal = true, signal_style = "bars", illustration_color = "#e8ebef", controller_body_color = "#2c3035", controller_stroke_width = 3.4, battery_color_mode = "connection", battery_fill_color = "#fcfcfc", battery_low_color = "#ed4c4c", text_color = "on_surface", muted_text_color = "on_surface_variant" }
local notifications = 0

local function ctor(t)
  return function(props, children)
    return { type = t, props = props or {}, children = children or {} }
  end
end
ui = { column=ctor("column"), row=ctor("row"), box=ctor("box"), label=ctor("label"), glyph=ctor("glyph"), image=ctor("image"), spacer=ctor("spacer") }

noctalia = {
  getenv = function() return "/tmp/opencode/mock-runtime" end,
  getConfig = function(k) return config[k] end,
  log = function() end,
  pluginDir = function() return "/tmp/opencode/plugin" end,
  pluginDataDir = function() return "/tmp/opencode/plugin-data" end,
  readFile = function(p)
    if p == "assets/controller-template.svg" then return "<svg>{{BODY}}|{{COLOR}}|{{STROKE_BODY}}|{{STROKE_GRIP}}</svg>" end
    return nil
  end,
  writeFile = function() return true end,
  removeFile = function() return true end,
  runAsync = function() return true end,
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

local plugin_dir = arg[1] or "steam-controller"
dofile(plugin_dir .. "/battery.luau")
dofile(plugin_dir .. "/card.luau")

assert(tree, "card did not render before state arrived")
local function find_text(t, text)
  if t.props.text == text then return t end
  for _, c in ipairs(t.children or {}) do local r = find_text(c, text); if r then return r end end
end
assert(find_text(tree, "status.waiting"), "initial waiting state missing")

stream_cb('{"battery_pct":7,"connected":true,"charging":false,"provisional":false,"docked":false,"internal":false,"connection":"receiver","signal_dbm":-70,"ts":' .. os.time() .. '}')
assert(find_text(tree, "7"), "card did not receive the battery percentage")
assert(find_text(tree, "status.low"), "card did not show the low state")
assert(notifications == 1, "expected exactly one low notification")
assert(shared.low_notified == true, "low notification flag not published")

stream_cb('{"battery_pct":55,"connected":true,"charging":true,"provisional":false,"docked":true,"internal":false,"connection":"receiver","signal_dbm":-60,"ts":' .. os.time() .. '}')
assert(find_text(tree, "55"), "charging percentage missing")
assert(find_text(tree, "status.charging_puck"), "charging status missing")

print("INTEGRATION TEST OK")
