--!nonstrict
-- CPU, RAM and network sampling with the delta state kept between calls.

local hwmon = require("./hwmon.luau")

local M = {}

local function now_ms()
  if type(noctalia.nowMs) == "function" then
    local value = noctalia.nowMs()
    if type(value) == "number" then
      return value
    end
  end
  return os.time() * 1000
end

function M.new()
  return {
    prev_total = nil,
    prev_idle = nil,
    prev_rx = nil,
    prev_tx = nil,
    prev_time_ms = nil,
  }
end

local function read_cpu_ticks()
  local raw = noctalia.readFile("/proc/stat")
  if type(raw) ~= "string" then
    return nil
  end
  local line = raw:match("^([^\n]*)")
  if not line or not line:match("^cpu%s") then
    return nil
  end

  local values = {}
  for value in line:gmatch("%d+") do
    values[#values + 1] = tonumber(value)
  end
  if #values < 4 then
    return nil
  end

  local total = 0
  for index = 1, #values do
    total = total + values[index]
  end
  return total, values[4] + (values[5] or 0)
end

local function read_ram()
  local raw = noctalia.readFile("/proc/meminfo")
  if type(raw) ~= "string" then
    return nil
  end

  local values = {}
  for key, value in raw:gmatch("([%w_]+):%s+(%d+)") do
    values[key] = tonumber(value)
  end

  local total_kb = values.MemTotal
  if not total_kb or total_kb <= 0 then
    return nil
  end

  local available_kb = values.MemAvailable
  if not available_kb then
    available_kb = (values.MemFree or 0) + (values.Buffers or 0) + (values.Cached or 0)
  end

  local used_kb = math.max(0, total_kb - available_kb)
  return {
    used_gb = used_kb / 1024 / 1024,
    total_gb = total_kb / 1024 / 1024,
    pct = used_kb / total_kb * 100,
  }
end

local function read_net_bytes()
  local raw = noctalia.readFile("/proc/net/dev")
  if type(raw) ~= "string" then
    return nil
  end

  local rx = 0
  local tx = 0
  for line in raw:gmatch("[^\n]+") do
    local name, rest = line:match("^%s*([%w%._%-]+):%s*(.+)$")
    if name and name ~= "lo" then
      local fields = {}
      for value in rest:gmatch("%d+") do
        fields[#fields + 1] = tonumber(value)
      end
      if #fields >= 9 then
        rx = rx + fields[1]
        tx = tx + fields[9]
      end
    end
  end
  return rx, tx
end

-- One sample. The first call primes the CPU/network deltas and returns nil for
-- those values; later calls return rates. Missing files stay nil.
function M.sample(state)
  local result = {
    cpu_usage = nil,
    cpu_temp_c = hwmon.cpu_temp(),
    cpu_fan_rpm = nil,
    ram = read_ram(),
    net_down_bps = nil,
    net_up_bps = nil,
  }

  local total, idle = read_cpu_ticks()
  if total ~= nil then
    if state.prev_total ~= nil and total > state.prev_total then
      local delta_total = total - state.prev_total
      local delta_idle = idle - state.prev_idle
      if delta_total >= 1 then
        local usage = (1 - (delta_idle / delta_total)) * 100
        if usage < 0 then
          usage = 0
        elseif usage > 100 then
          usage = 100
        end
        result.cpu_usage = usage
      end
    end
    state.prev_total = total
    state.prev_idle = idle
  end

  local rx, tx = read_net_bytes()
  if rx ~= nil then
    local stamp = now_ms()
    if state.prev_rx ~= nil and state.prev_time_ms ~= nil then
      local seconds = (stamp - state.prev_time_ms) / 1000
      if seconds > 0 then
        result.net_down_bps = math.max(0, (rx - state.prev_rx) / seconds)
        result.net_up_bps = math.max(0, (tx - state.prev_tx) / seconds)
      end
    end
    state.prev_rx = rx
    state.prev_tx = tx
    state.prev_time_ms = stamp
  end

  return result
end

return M
