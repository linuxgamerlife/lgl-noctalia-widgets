--!nonstrict
-- GPU readers: AMD through /sys/class/drm, Nvidia through nvidia-smi, and the
-- host's own system monitor as a last resort (Intel or an NVML-only setup).

local hwmon = require("./hwmon.luau")

local M = {}

local GIB = 1024 * 1024 * 1024

local NVIDIA_FULL = "name,utilization.gpu,temperature.gpu,memory.used,memory.total,"
  .. "clocks.gr,clocks.mem,fan.speed,power.draw,power.limit"
local NVIDIA_SHORT = "name,utilization.gpu,temperature.gpu,memory.used,memory.total"

local function trim(text)
  if type(text) ~= "string" then
    return ""
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The AMD card with the most VRAM wins, so an APU does not hide a discrete
-- card. This is the same rule the KDE widget used.
function M.read_amd()
  local best = nil
  local best_vram = -1

  for _, entry in ipairs(hwmon.list("/sys/class/drm")) do
    if entry:match("^card%d+$") then
      local device = "/sys/class/drm/" .. entry .. "/device"
      if trim(hwmon.read_text(device .. "/vendor") or "") == "0x1002" then
        local vram = hwmon.read_number(device .. "/mem_info_vram_total")
        local busy = hwmon.read_number(device .. "/gpu_busy_percent")
        if vram ~= nil and busy ~= nil and vram > best_vram then
          best = device
          best_vram = vram
        end
      end
    end
  end

  if best == nil then
    return nil
  end

  local total = hwmon.read_number(best .. "/mem_info_vram_total") or 0
  local used = hwmon.read_number(best .. "/mem_info_vram_used") or 0
  local gpu = {
    present = true,
    vendor = "amd",
    usage = hwmon.read_number(best .. "/gpu_busy_percent") or 0,
    vram_used_gb = used / GIB,
    vram_total_gb = total / GIB,
    vram_pct = total > 0 and (used / total * 100) or 0,
  }

  local uevent = hwmon.read_text(best .. "/uevent")
  if uevent then
    local slot = uevent:match("PCI_SLOT_NAME=([^\n]+)")
    if slot then
      gpu.pci_slot = slot:match("(%x%x:%x%x%.%x)$") or slot
    end
  end

  local base = hwmon.first_hwmon(best)
  if base == nil then
    return gpu
  end

  local temps = {}
  for index = 1, 6 do
    local raw = hwmon.read_number(base .. "/temp" .. index .. "_input")
    if raw ~= nil then
      local label = string.lower(hwmon.read_text(base .. "/temp" .. index .. "_label") or "")
      temps[#temps + 1] = { label = label, celsius = raw / 1000 }
    end
  end

  local edge, junction, memory
  for _, item in ipairs(temps) do
    if item.label == "edge" then
      edge = item.celsius
    elseif item.label == "junction" then
      junction = item.celsius
    elseif item.label == "mem" then
      memory = item.celsius
    end
  end
  gpu.temp_junction = junction
  gpu.temp_mem = memory
  if edge ~= nil then
    gpu.temp_c = edge
  elseif junction ~= nil then
    gpu.temp_c = junction
  elseif #temps > 0 then
    gpu.temp_c = temps[1].celsius
  end

  -- sysfs reports Hz. Labels are sclk/mclk on amdgpu; on older filesystems the
  -- first input is the core clock and the second the memory clock.
  for index = 1, 4 do
    local raw = hwmon.read_number(base .. "/freq" .. index .. "_input")
    if raw ~= nil then
      local label = string.lower(hwmon.read_text(base .. "/freq" .. index .. "_label") or "")
      local mhz = raw / 1e6
      if label == "sclk" or (label == "" and index == 1) then
        gpu.clock_mhz = mhz
      elseif label == "mclk" or (label == "" and index == 2) then
        gpu.mem_clock_mhz = mhz
      end
    end
  end

  local rpm = hwmon.read_number(base .. "/fan1_input")
  if rpm ~= nil then
    gpu.fan_rpm = rpm
  end
  local pwm = hwmon.read_number(base .. "/pwm1")
  local pwm_max = hwmon.read_number(base .. "/pwm1_max") or 255
  if pwm ~= nil and pwm_max > 0 then
    gpu.fan_pct = pwm / pwm_max * 100
  end

  -- sysfs reports microwatts.
  local power = hwmon.read_number(base .. "/power1_average")
  if power == nil then
    power = hwmon.read_number(base .. "/power1_input")
  end
  if power ~= nil then
    gpu.power_w = power / 1e6
  end
  local cap = hwmon.read_number(base .. "/power1_cap")
  if cap ~= nil and cap > 0 then
    gpu.power_cap_w = cap / 1e6
  end

  return gpu
end

function M.nvidia_command(full)
  local fields = full and NVIDIA_FULL or NVIDIA_SHORT
  return "nvidia-smi --query-gpu=" .. fields
    .. " --format=csv,noheader,nounits 2>/dev/null"
end

function M.parse_nvidia(stdout)
  if type(stdout) ~= "string" or stdout == "" then
    return nil
  end
  local line = stdout:match("[^\n]+")
  if line == nil then
    return nil
  end

  local parts = {}
  for part in line:gmatch("([^,]+)") do
    parts[#parts + 1] = trim(part)
  end
  local offset = 0
  local name = nil
  if parts[1] ~= nil and tonumber(parts[1]) == nil then
    name = parts[1]
    offset = 1
  end
  if #parts < 4 + offset then
    return nil
  end

  local usage = tonumber(parts[1 + offset])
  local temp = tonumber(parts[2 + offset])
  local used_mib = tonumber(parts[3 + offset])
  local total_mib = tonumber(parts[4 + offset])
  if usage == nil or temp == nil or used_mib == nil or total_mib == nil then
    return nil
  end

  local gpu = {
    present = true,
    vendor = "nvidia",
    name = name,
    usage = usage,
    temp_c = temp,
    vram_used_gb = used_mib / 1024,
    vram_total_gb = total_mib / 1024,
    vram_pct = total_mib > 0 and (used_mib / total_mib * 100) or 0,
  }

  if #parts >= 9 + offset then
    gpu.clock_mhz = tonumber(parts[5 + offset])
    gpu.mem_clock_mhz = tonumber(parts[6 + offset])
    gpu.fan_pct = tonumber(parts[7 + offset])
    gpu.power_w = tonumber(parts[8 + offset])
    gpu.power_cap_w = tonumber(parts[9 + offset])
  end

  return gpu
end

-- Noctalia's host monitor can provide Intel/NVML data even when the direct
-- readers above cannot. Use it only as a fallback.
function M.read_host()
  if type(noctalia.systemStats) ~= "function" then
    return nil
  end
  local stats = noctalia.systemStats()
  if type(stats) ~= "table" or type(stats.gpu) ~= "table" then
    return nil
  end

  local source = stats.gpu
  local usage = tonumber(source.usagePercent)
  local temp = tonumber(source.tempC)
  local used = tonumber(source.vramUsedBytes)
  local total = tonumber(source.vramTotalBytes)
  if usage == nil and temp == nil and used == nil and total == nil then
    return nil
  end

  local gpu = {
    present = true,
    vendor = "host",
    usage = usage,
    temp_c = temp,
  }
  if used ~= nil and total ~= nil and total > 0 then
    gpu.vram_used_gb = used / GIB
    gpu.vram_total_gb = total / GIB
    gpu.vram_pct = used / total * 100
  elseif total ~= nil then
    gpu.vram_total_gb = total / GIB
  end
  return gpu
end

return M
