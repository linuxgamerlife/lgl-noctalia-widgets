--!nonstrict

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Joao Gabriel Medeiros
-- Copyright (C) 2026 UnsaidSpeech
-- Copyright (C) 2026 LinuxGamerLife

-- sysfs/hwmon helpers. Every read is defensive: a missing sensor is nil, not 0.

local M = {}

local HWMON_ROOT = "/sys/class/hwmon"
local THERMAL_ROOT = "/sys/class/thermal"

local CPU_CHIPS = {
  coretemp = true,
  k10temp = true,
  zenpower = true,
  cpu_thermal = true,
  soc_thermal = true,
}

local GPU_CHIPS = {
  amdgpu = true,
  radeon = true,
  nouveau = true,
  nvidia = true,
}

function M.list(path)
  local entries = noctalia.listDir(path)
  if type(entries) ~= "table" then
    return {}
  end
  return entries
end

function M.read_text(path)
  local text = noctalia.readFile(path)
  if type(text) ~= "string" then
    return nil
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.read_number(path)
  local text = M.read_text(path)
  if text == nil or text == "" then
    return nil
  end
  local match = text:match("%-?%d+%.?%d*")
  return match and tonumber(match) or nil
end

local function valid_celsius(value)
  return value ~= nil and value > 1 and value < 150
end

-- hwmon directories appear either directly below a device (NVMe exposes
-- device/hwmon1) or in a device/hwmon/ directory (amdgpu). Accept both.
function M.first_hwmon(base)
  for _, entry in ipairs(M.list(base)) do
    if entry:match("^hwmon%d+$") then
      return base .. "/" .. entry
    end
  end
  for _, entry in ipairs(M.list(base .. "/hwmon")) do
    if entry:match("^hwmon%d+$") then
      return base .. "/hwmon/" .. entry
    end
  end
  return nil
end

function M.is_gpu(name, path)
  if name and GPU_CHIPS[name] then
    return true
  end
  local class = M.read_text(path .. "/device/class")
  return class ~= nil and class:sub(1, 4) == "0x03"
end

-- Prefer a real CPU package sensor, then any non-GPU hwmon sensor, then a CPU
-- thermal zone. The KDE widget used coretemp/temp1 and then any temp1; taking
-- the hottest valid package sensor is the same intent without accidentally
-- reporting a GPU temperature as the CPU.
function M.cpu_temp()
  local best = nil
  local fallback = nil

  for _, entry in ipairs(M.list(HWMON_ROOT)) do
    local base = HWMON_ROOT .. "/" .. entry
    local name = M.read_text(base .. "/name")
    local is_cpu = name ~= nil and CPU_CHIPS[name] == true
    local is_gpu = M.is_gpu(name, base)

    for _, file in ipairs(M.list(base)) do
      if file:match("^temp%d+_input$") then
        local raw = M.read_number(base .. "/" .. file)
        if raw ~= nil then
          local celsius = raw / 1000
          if valid_celsius(celsius) then
            if is_cpu then
              if best == nil or celsius > best then
                best = celsius
              end
            elseif not is_gpu then
              if fallback == nil or celsius > fallback then
                fallback = celsius
              end
            end
          end
        end
      end
    end
  end

  if best ~= nil then
    return best
  end
  if fallback ~= nil then
    return fallback
  end

  for _, entry in ipairs(M.list(THERMAL_ROOT)) do
    if entry:match("^thermal_zone%d+$") then
      local base = THERMAL_ROOT .. "/" .. entry
      local kind = string.lower(M.read_text(base .. "/type") or "")
      if kind:find("x86_pkg_temp", 1, true)
        or kind:find("cpu", 1, true)
        or kind:find("soc_thermal", 1, true)
        or kind:find("package", 1, true)
      then
        local raw = M.read_number(base .. "/temp")
        if raw ~= nil then
          local celsius = raw / 1000
          if valid_celsius(celsius) and (best == nil or celsius > best) then
            best = celsius
          end
        end
      end
    end
  end

  return best
end

-- Find the CPU fan. number > 0 selects fan<N> on the motherboard chip with the
-- most fan inputs; 0 means automatic (a fan label containing "cpu"). A known
-- fan that reads 0 RPM is returned as 0, so the card can show a stopped fan.
function M.cpu_fan(number)
  local chips = {}

  for _, entry in ipairs(M.list(HWMON_ROOT)) do
    local base = HWMON_ROOT .. "/" .. entry
    local name = M.read_text(base .. "/name") or entry
    if not M.is_gpu(name, base) then
      local numbers = {}
      for _, file in ipairs(M.list(base)) do
        local fan = file:match("^fan(%d+)_input$")
        if fan then
          numbers[#numbers + 1] = tonumber(fan)
        end
      end
      if #numbers > 0 then
        table.sort(numbers)
        chips[#chips + 1] = { base = base, name = name, numbers = numbers }
      end
    end
  end

  if #chips == 0 then
    return nil
  end

  local main = chips[1]
  for _, chip in ipairs(chips) do
    if #chip.numbers > #main.numbers then
      main = chip
    end
  end

  local wanted = math.floor(tonumber(number) or 0)
  if wanted > 0 then
    return M.read_number(main.base .. "/fan" .. wanted .. "_input")
  end

  for _, chip in ipairs(chips) do
    for _, fan in ipairs(chip.numbers) do
      local label = string.lower(M.read_text(chip.base .. "/fan" .. fan .. "_label") or "")
      if label:find("cpu", 1, true) then
        local rpm = M.read_number(chip.base .. "/fan" .. fan .. "_input")
        if rpm ~= nil then
          return rpm
        end
      end
    end
  end

  return nil
end

-- A block device's own hwmon (NVMe, and SATA disks with drivetemp loaded).
function M.disk_temp(disk)
  local bases = {
    "/sys/class/block/" .. disk .. "/device",
    "/sys/class/block/" .. disk .. "/device/device",
  }
  for _, base in ipairs(bases) do
    local hwmon = M.first_hwmon(base)
    if hwmon then
      local raw = M.read_number(hwmon .. "/temp1_input")
      if raw ~= nil then
        local celsius = raw / 1000
        if valid_celsius(celsius) then
          return celsius
        end
      end
    end
  end
  return nil
end

return M
