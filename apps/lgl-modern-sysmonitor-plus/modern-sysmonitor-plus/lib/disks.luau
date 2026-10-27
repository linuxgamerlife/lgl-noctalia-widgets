--!nonstrict
-- Physical-disk usage from `df -kPT`, grouped the way the KDE widget grouped
-- mounted filesystems: LUKS/LVM/btrfs subvolumes collapse onto their physical
-- disk, and duplicate mounts of the same source are counted once.

local hwmon = require("./hwmon.luau")

local M = {}

M.command = "df -kPT 2>/dev/null"

local SKIP_FS = {
  squashfs = true,
  erofs = true,
  iso9660 = true,
  udf = true,
  tmpfs = true,
  devtmpfs = true,
  overlay = true,
  proc = true,
  sysfs = true,
  cgroup = true,
  cgroup2 = true,
  ramfs = true,
  autofs = true,
  efivarfs = true,
  securityfs = true,
  debugfs = true,
  tracefs = true,
  configfs = true,
  bpf = true,
  pstore = true,
  mqueue = true,
  hugetlbfs = true,
  devpts = true,
  fusectl = true,
  nsfs = true,
  selinuxfs = true,
  rpc_pipefs = true,
  nfsd = true,
  binfmt_misc = true,
}

local SKIP_SOURCE = {
  "^/dev/loop",
  "^/dev/zram",
  "^/dev/ram",
  "^/dev/sr",
  "^/dev/fd",
}

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function build_mapper()
  local mapper = {}
  for _, entry in ipairs(hwmon.list("/sys/class/block")) do
    if entry:match("^dm%-%d+$") then
      local name = hwmon.read_text("/sys/class/block/" .. entry .. "/dm/name")
      if name and name ~= "" then
        mapper[name] = entry
      end
    end
  end
  return mapper
end

local function partition_parent(name)
  local parent = name:match("^(nvme%d+n%d+)p%d+$")
  if parent then
    return parent
  end
  parent = name:match("^(mmcblk%d+)p%d+$")
  if parent then
    return parent
  end
  parent = name:match("^(md%d+)p%d+$")
  if parent then
    return parent
  end
  parent = name:match("^(%a+)%d+$")
  if parent and parent ~= "loop" and parent ~= "zram" and parent ~= "ram" and parent ~= "fd" then
    return parent
  end
  return nil
end

function M.parent_disk(name, depth)
  local level = tonumber(depth) or 0
  if level > 5 then
    return name
  end

  local base = "/sys/class/block/" .. name
  local slaves = hwmon.list(base .. "/slaves")
  if #slaves > 0 then
    return M.parent_disk(slaves[1], level + 1)
  end

  if noctalia.fileExists(base .. "/partition") then
    local parent = partition_parent(name)
    if parent then
      return parent
    end
  end
  return name
end

local function disk_model(disk)
  for _, relative in ipairs({ "device/model", "device/name" }) do
    local text = hwmon.read_text("/sys/class/block/" .. disk .. "/" .. relative)
    if text and text ~= "" then
      return (text:gsub("%s+", " "))
    end
  end
  return disk
end

function M.parse(text)
  if type(text) ~= "string" then
    return {}
  end

  local mapper = nil
  local seen = {}
  local aggregate = {}

  for line in text:gmatch("[^\n]+") do
    local source, fstype, blocks, used =
      line:match("^(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+%d+%s+%S+%s+(.+)$")
    if source ~= nil and source:sub(1, 5) == "/dev/" and not SKIP_FS[fstype] then
      local skip = false
      for _, pattern in ipairs(SKIP_SOURCE) do
        if source:match(pattern) then
          skip = true
          break
        end
      end

      if not skip then
        local device = basename(source)
        if source:sub(1, 12) == "/dev/mapper/" then
          if mapper == nil then
            mapper = build_mapper()
          end
          device = mapper[device] or device
        end

        if not seen[device] then
          seen[device] = true
          local disk = M.parent_disk(device)
          local entry = aggregate[disk]
          if entry == nil then
            entry = { used_kb = 0, total_kb = 0 }
            aggregate[disk] = entry
          end
          entry.used_kb = entry.used_kb + tonumber(used)
          entry.total_kb = entry.total_kb + tonumber(blocks)
        end
      end
    end
  end

  local disks = {}
  for disk in pairs(aggregate) do
    disks[#disks + 1] = disk
  end
  table.sort(disks)

  local result = {}
  for _, disk in ipairs(disks) do
    local entry = aggregate[disk]
    if entry.total_kb > 0 then
      local used_gb = entry.used_kb / 1024 / 1024
      local total_gb = entry.total_kb / 1024 / 1024
      result[#result + 1] = {
        key = disk,
        name = disk_model(disk),
        temp_c = hwmon.disk_temp(disk),
        used_gb = used_gb,
        total_gb = total_gb,
        pct = total_gb > 0 and (used_gb / total_gb * 100) or 0,
      }
    end
  end
  return result
end

-- Async by design: `df` should never block the sampler's update().
function M.request(callback)
  return noctalia.runAsync(M.command, function(result)
    if not result or result.exitCode ~= 0 then
      callback(nil)
      return
    end
    callback(M.parse(result.stdout or ""))
  end)
end

return M
