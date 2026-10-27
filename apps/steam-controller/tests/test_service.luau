-- Minimal Noctalia mock for the service logic.
local stored = {}
local notifications = {}
local stream_cb = nil
local config = { low_threshold = 20, notify_low = true }

noctalia = {
  getenv = function() return "/tmp/opencode/mock-runtime" end,
  getConfig = function(k) return config[k] end,
  log = function(m) print("LOG " .. tostring(m)) end,
  pluginDir = function() return "/tmp/opencode/plugin" end,
  readFile = function() return nil end,
  removeFile = function() return true end,
  runAsync = function(cmd) print("ASYNC " .. tostring(cmd)); return true end,
  commandExists = function() return true end,
  fileExists = function() return true end,
  runStream = function(cmd, cb) print("STREAM " .. cmd); stream_cb = cb; return true end,
  state = {
    get = function(k) return stored[k] end,
    set = function(k, v) stored[k] = v end,
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
      -- Enough for the flat daemon payload.
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

local plugin_dir = arg[1] or "steam-controller"
dofile(plugin_dir .. "/battery.luau")

assert(type(stream_cb) == "function", "runStream callback was not registered")
stream_cb('{"battery_pct":12,"connected":true,"charging":false,"provisional":false,"docked":false,"internal":false,"connection":"bluetooth","ts":' .. os.time() .. '}')
assert(stored.controller.battery_pct == 12, "state did not publish")
assert(stored.low_notified == true, "low notification not recorded")
assert(#notifications == 1, "expected one notification, got " .. #notifications)

stream_cb('{"battery_pct":40,"connected":true,"charging":false,"provisional":false,"ts":' .. os.time() .. '}')
assert(stored.low_notified == false, "low flag should reset above threshold")
assert(#notifications == 1, "should not notify twice")

stream_cb('{"battery_pct":30,"connected":true,"charging":true,"provisional":false,"ts":' .. os.time() .. '}')
assert(stored.controller.charging == true, "charging state not published")

print("SERVICE TEST OK")
