--!nonstrict
-- Headless poller for Modern SysMonitor Plus.
--
-- Reads the sources the KDE widget used: /proc/stat, /proc/meminfo,
-- /proc/net/dev, /sys/class/drm (AMD), nvidia-smi (Nvidia), hwmon (temperatures,
-- fans, clocks, power) and `df` (disks). Publishes one plain `stats` table; the
-- desktop card only watches and renders it.
--
-- plugin_api 22 (module require). Services start on enable at 17.

local format = require("./lib/format.luau")
local sampler = require("./lib/sampler.luau")
local gpu_reader = require("./lib/gpu.luau")
local disk_reader = require("./lib/disks.luau")
local hwmon = require("./lib/hwmon.luau")

local DISK_REFRESH_MS = 10000
local NVIDIA_CACHE_MS = 15000
local NVIDIA_REFRESH_MS = 5000
local NVIDIA_RETRY_MS = 60000
local ASYNC_TIMEOUT_MS = 30000

local update_interval = 2
local cpu_fan_number = 0
local sampler_state = sampler.new()
local seq = 0

local cached_disks = nil
local disks_pending = false
local disks_at = 0

local nvidia_cached = nil
local nvidia_cached_at = 0
local nvidia_pending = false
local nvidia_pending_at = 0
local nvidia_disabled_until = 0
local nvidia_stage = 0
local has_nvidia_smi = false

local function now_ms()
  if type(noctalia.nowMs) == "function" then
    local value = noctalia.nowMs()
    if type(value) == "number" then
      return value
    end
  end
  return os.time() * 1000
end

local function load_settings()
  local interval = tonumber(noctalia.getConfig("update_interval")) or 2
  update_interval = math.floor(format.clamp(interval, 1, 60) + 0.5)

  local fan = tonumber(noctalia.getConfig("cpu_fan_number")) or 0
  cpu_fan_number = math.floor(format.clamp(fan, 0, 16) + 0.5)
end

local function normalize_gpu(gpu)
  if type(gpu) ~= "table" then
    return nil
  end
  return {
    present = true,
    vendor = gpu.vendor,
    usage = format.round(gpu.usage, 1),
    temp_c = format.round(gpu.temp_c, 1),
    vram_used_gb = format.round(gpu.vram_used_gb, 1),
    vram_total_gb = format.round(gpu.vram_total_gb, 1),
    vram_pct = format.round(gpu.vram_pct, 1),
    temp_junction = format.round(gpu.temp_junction, 1),
    temp_mem = format.round(gpu.temp_mem, 1),
    clock_mhz = format.round(gpu.clock_mhz, 0),
    mem_clock_mhz = format.round(gpu.mem_clock_mhz, 0),
    fan_rpm = format.round(gpu.fan_rpm, 0),
    fan_pct = format.round(gpu.fan_pct, 0),
    power_w = format.round(gpu.power_w, 1),
    power_cap_w = format.round(gpu.power_cap_w, 0),
  }
end

local function publish(sample, gpu)
  seq = seq + 1
  local ram = sample.ram or {}
  noctalia.state.set("stats", {
    ts = os.time(),
    seq = seq,
    cpu = {
      usage = format.round(sample.cpu_usage, 1),
      temp_c = format.round(sample.cpu_temp_c, 1),
      fan_rpm = format.round(sample.cpu_fan_rpm, 0),
    },
    ram = {
      used_gb = format.round(ram.used_gb, 1),
      total_gb = format.round(ram.total_gb, 1),
      pct = format.round(ram.pct, 1),
    },
    net = {
      down_bps = format.round(sample.net_down_bps, 0),
      up_bps = format.round(sample.net_up_bps, 0),
    },
    gpu = normalize_gpu(gpu),
    disks = cached_disks or {},
  })
end

local function request_disks(now)
  if disks_pending then
    return
  end
  disks_pending = true
  disks_at = now

  local accepted = disk_reader.request(function(entries)
    disks_pending = false
    if entries ~= nil then
      cached_disks = entries
    end
  end)
  if not accepted then
    disks_pending = false
  end
end

local function request_nvidia()
  if nvidia_pending or not has_nvidia_smi or now_ms() < nvidia_disabled_until then
    return
  end

  nvidia_pending = true
  nvidia_pending_at = now_ms()
  local full = nvidia_stage == 0

  local accepted = noctalia.runAsync(gpu_reader.nvidia_command(full), function(result)
    nvidia_pending = false
    if result and result.exitCode == 0 then
      local parsed = gpu_reader.parse_nvidia(result.stdout)
      if parsed ~= nil then
        nvidia_cached = parsed
        nvidia_cached_at = now_ms()
        nvidia_stage = 0
        return
      end
    end

    if full and nvidia_stage == 0 then
      nvidia_stage = 1
      request_nvidia()
    else
      nvidia_stage = 0
      nvidia_disabled_until = now_ms() + NVIDIA_RETRY_MS
    end
  end)

  if not accepted then
    nvidia_pending = false
    nvidia_disabled_until = now_ms() + NVIDIA_RETRY_MS
  end
end

local function current_gpu(now)
  local amd = gpu_reader.read_amd()
  if amd ~= nil then
    return amd
  end

  if nvidia_cached ~= nil and now - nvidia_cached_at <= NVIDIA_CACHE_MS then
    return nvidia_cached
  end

  if has_nvidia_smi and (nvidia_cached == nil or now - nvidia_cached_at > NVIDIA_REFRESH_MS) then
    request_nvidia()
    -- A synchronous runAsync (tests, and some hosts) fills the cache before we
    -- return, so use it rather than waiting for the next poll.
    if nvidia_cached ~= nil and now_ms() - nvidia_cached_at <= NVIDIA_CACHE_MS then
      return nvidia_cached
    end
  end

  return gpu_reader.read_host()
end

local function poll()
  local now = now_ms()
  local sample = sampler.sample(sampler_state)
  sample.cpu_fan_rpm = hwmon.cpu_fan(cpu_fan_number)

  if now - disks_at >= DISK_REFRESH_MS then
    request_disks(now)
  end
  if disks_pending and now - disks_at > ASYNC_TIMEOUT_MS then
    disks_pending = false
  end

  local gpu = current_gpu(now)
  if nvidia_pending and now - nvidia_pending_at > ASYNC_TIMEOUT_MS then
    nvidia_pending = false
  end

  publish(sample, gpu)
end

function update()
  poll()
end

function onConfigChanged()
  local previous = update_interval
  load_settings()
  if update_interval ~= previous then
    noctalia.setUpdateInterval(update_interval * 1000)
  end
end

load_settings()
has_nvidia_smi = type(noctalia.commandExists) == "function"
  and noctalia.commandExists("nvidia-smi") == true
noctalia.setUpdateInterval(update_interval * 1000)
poll()
