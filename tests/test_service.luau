-- Minimal Noctalia mock for the DualSense service logic.
local stored = {}
local watchers = {}
local notifications = {}
local async_cmds = {}
local stream_cb = nil
local config = { low_threshold = 20, notify_low = true }

noctalia = {
  getenv = function() return "/tmp/opencode/mock-runtime" end,
  getConfig = function(k) return config[k] end,
  log = function(m) print("LOG " .. tostring(m)) end,
  pluginDir = function() return "/tmp/opencode/plugin" end,
  readFile = function() return nil end,
  removeFile = function() return true end,
  runAsync = function(cmd, cb)
    table.insert(async_cmds, cmd)
    print("ASYNC " .. tostring(cmd))
    if type(cb) == "function" then cb({ exitCode = 0 }) end
    return true
  end,
  commandExists = function() return true end,
  fileExists = function() return true end,
  runStream = function(cmd, cb) print("STREAM " .. cmd); stream_cb = cb; return true end,
  state = {
    get = function(k) return stored[k] end,
    set = function(k, v)
      stored[k] = v
      if watchers[k] then
        for _, fn in ipairs(watchers[k]) do fn(v) end
      end
    end,
    watch = function(k, fn)
      watchers[k] = watchers[k] or {}
      table.insert(watchers[k], fn)
    end,
  },
  tr = function(k, subst)
    if k == "notification.low.title" then return "low" end
    if k == "notification.low.body" then return tostring(subst.pct) .. "% left" end
    return k
  end,
  notify = function(t, b) table.insert(notifications, t .. ": " .. b); print("NOTIFY " .. t .. ": " .. b) end,
  notifyError = function(t, b) print("ERROR " .. t .. ": " .. b) end,
  setUpdateInterval = function(ms) print("INTERVAL " .. ms) end,
  json = {
    decode = function(s)
      local out = {}
      for k, v in string.gmatch(s, '"([%w_]+)":([^,}]+)') do
        local n = tonumber(v)
        if n then out[k] = n
        elseif v == "true" then out[k] = true
        elseif v == "false" then out[k] = false
        elseif v ~= "null" then out[k] = v:gsub('^"', ''):gsub('"$', '') end
      end
      return out
    end,
  },
}

local plugin_dir = arg[1] or "dualsense"
dofile(plugin_dir .. "/battery.luau")

assert(type(stream_cb) == "function", "runStream callback was not registered")
stream_cb('{"battery_pct":15,"connected":true,"charging":false,"full":false,"provisional":false,"model":"dualsense","profile":"Default","lightbar_color":"#0080ff","player_leds":1,"connection":"bluetooth","ts":' .. os.time() .. '}')
assert(stored.controller.battery_pct == 15, "state did not publish")
assert(stored.low_notified == true, "low notification not recorded")
assert(#notifications == 1, "expected one notification, got " .. #notifications)

stream_cb('{"battery_pct":45,"connected":true,"charging":false,"full":false,"provisional":false,"ts":' .. os.time() .. '}')
assert(stored.low_notified == false, "low flag should reset above threshold")
assert(#notifications == 1, "should not notify twice")

stream_cb('{"battery_pct":35,"connected":true,"charging":true,"full":false,"provisional":false,"ts":' .. os.time() .. '}')
assert(stored.controller.charging == true, "charging state not published")

-- Test IPC and state actions
async_cmds = {}
onIpc("buzz", nil)
assert(#async_cmds >= 1 and string.find(async_cmds[1], "--buzz", 1, true), "buzz IPC did not run daemon --buzz")

async_cmds = {}
noctalia.state.set("action", { action = "cycle-profile", seq = 1 })
assert(#async_cmds >= 1 and string.find(async_cmds[1], "--cycle-profile", 1, true), "cycle-profile action did not run")

print("SERVICE TEST OK")
