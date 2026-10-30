--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Headless reader service: starts the bundled evdev helper, publishes its
-- state for the overlay/card/bar/panel, and restarts it on config changes.

local config = require("./lib/config.luau")

local RESTART_AFTER = 8 -- seconds without a line
local CONFIG_REV = "kbm_config_rev"

local data_dir = config.data_dir()
local runtime_path = config.runtime_path()
local pid_path = data_dir .. "/reader.pid"
local last_line = 0
local last_restart = 0
local started = false
local last_error = nil

local function log(message)
  noctalia.log("[kbm-overlay] " .. tostring(message))
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function publish_error(code, message)
  last_error = { code = code, message = message, ts = os.time() }
  noctalia.state.set("kbm_error", last_error)
end

local function clear_error()
  if last_error ~= nil then
    last_error = nil
    noctalia.state.set("kbm_error", false)
  end
end

local function kill_stale()
  local raw = noctalia.readFile(pid_path)
  if type(raw) ~= "string" then
    return
  end
  local pid = string.match(raw, "^(%d+)")
  if pid and tonumber(pid) and tonumber(pid) > 1 then
    local cmdline = noctalia.readFile("/proc/" .. pid .. "/cmdline")
    if type(cmdline) == "string" and string.find(cmdline, "kbm_daemon.py", 1, true) then
      noctalia.runAsync("kill " .. pid .. " 2>/dev/null")
    end
  end
  noctalia.removeFile(pid_path)
end

local function write_runtime_config()
  if type(noctalia.mkdirAll) == "function" then
    noctalia.mkdirAll(data_dir)
  end
  local selected = config.read_devices()
  local payload = {
    keyboard = selected.keyboard or "",
    keyboard_path = selected.keyboard_path or "",
    mouse = selected.mouse or "",
    mouse_path = selected.mouse_path or "",
  }
  local encoded = noctalia.json.encode(payload)
  if encoded == nil then
    publish_error("config", "Could not encode the device selection.")
    return false
  end
  local ok, err = noctalia.writeFile(runtime_path, encoded)
  if not ok then
    publish_error("config", "Could not write the device selection: " .. tostring(err))
    return false
  end
  return true
end

local function on_line(line)
  if type(line) ~= "string" or line == "" then
    return
  end
  last_line = os.time()
  local decoded, err = noctalia.json.decode(line)
  if type(decoded) ~= "table" then
    log("could not decode reader output: " .. tostring(err or line))
    return
  end
  if decoded.type == "state" then
    noctalia.state.set("kbm_state", decoded)
  elseif decoded.type == "devices" then
    noctalia.state.set("kbm_devices", decoded.devices or {})
  elseif decoded.type == "error" then
    publish_error(decoded.code or "unknown", decoded.message or "")
  elseif decoded.type == "status" then
    noctalia.state.set("kbm_status", decoded)
  end
end

local function daemon_path()
  local dir = noctalia.pluginDir()
  if not dir then
    return nil
  end
  return dir .. "/code/kbm_daemon.py"
end

local function start_stream()
  last_line = os.time()
  clear_error()
  local path = daemon_path()
  if not path or not noctalia.fileExists(path) then
    publish_error("helper", "The bundled input helper is missing.")
    return false
  end
  if not noctalia.commandExists("python3") then
    publish_error("python", "python3 is required to read input devices.")
    return false
  end
  if not write_runtime_config() then
    return false
  end
  local command = "python3 "
    .. shell_quote(path)
    .. " --config " .. shell_quote(runtime_path)
    .. " --pid-file " .. shell_quote(pid_path)
    .. " --rate 60"
  local ok = noctalia.runStream(command, on_line)
  if not ok then
    publish_error("start", "The input reader could not be started.")
    return false
  end
  started = true
  noctalia.state.set("kbm_service", {
    started = started,
    rate = 60,
    ts = os.time(),
  })
  return true
end

local function restart(force)
  local now = os.time()
  if not force and now - last_restart < RESTART_AFTER then
    return
  end
  last_restart = now
  kill_stale()
  start_stream()
end

function update()
  if started and last_line > 0 and os.time() - last_line > RESTART_AFTER then
    log("reader heartbeat timed out; restarting")
    restart(false)
  end
end

function onIpc(event, _payload)
  if event == "restart" then
    restart(true)
  elseif event == "hide" then
    noctalia.state.set("kbm_hidden", true)
  elseif event == "show" then
    noctalia.state.set("kbm_hidden", false)
  elseif event == "toggle" then
    local hidden = noctalia.state.get("kbm_hidden") == true
    noctalia.state.set("kbm_hidden", not hidden)
  end
end

function onExit(_signal, _reason)
  kill_stale()
end

noctalia.state.watch(CONFIG_REV, function()
  restart(true)
end)

noctalia.setUpdateInterval(2000)
kill_stale()
start_stream()
