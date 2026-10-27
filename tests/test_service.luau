-- Service test: mocked /proc, /sys, hwmon, AMD sysfs and df inputs.
local mock = dofile("tests/support/mock.luau")

local function close(actual, expected, epsilon, label)
  assert(type(actual) == "number", label .. ": expected a number, got " .. tostring(actual))
  assert(math.abs(actual - expected) <= epsilon,
    ("%s: expected %.4f, got %.4f"):format(label, expected, actual))
end

local function count_command(commands, fragment)
  local count = 0
  for _, command in ipairs(commands) do
    if command:find(fragment, 1, true) then
      count = count + 1
    end
  end
  return count
end

local function disk_by_key(disks, key)
  for _, disk in ipairs(disks or {}) do
    if disk.key == key then
      return disk
    end
  end
end

local function base_files()
  return {
    ["/proc/stat"] = "cpu  100 0 100 800 0 0 0 0\n",
    ["/proc/cpuinfo"] = "model name\t: AMD Ryzen 9 9950X3D 16-Core Processor\n",
    ["/proc/meminfo"] = "MemTotal:       16777216 kB\nMemAvailable:    8388608 kB\n",
    ["/proc/net/dev"] = table.concat({
      "Inter-|   Receive                                                |  Transmit",
      " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
      "  eth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0",
      "    lo: 9999 0 0 0 0 0 0 0 9999 0 0 0 0 0 0 0",
    }, "\n"),

    ["/sys/class/hwmon/hwmon0/name"] = "k10temp\n",
    ["/sys/class/hwmon/hwmon0/temp1_input"] = "55000\n",
    ["/sys/class/hwmon/hwmon0/temp2_input"] = "60000\n",
    ["/sys/class/hwmon/hwmon0/fan1_input"] = "1200\n",
    ["/sys/class/hwmon/hwmon0/fan1_label"] = "CPU Fan\n",
    ["/sys/class/hwmon/hwmon0/fan2_input"] = "800\n",
    ["/sys/class/hwmon/hwmon1/name"] = "amdgpu\n",
    ["/sys/class/hwmon/hwmon1/fan1_input"] = "1500\n",

    ["/sys/class/drm/card0/device/uevent"] = "DRIVER=amdgpu\nPCI_SLOT_NAME=0000:03:00.0\n",
    ["/sys/class/drm/card0/device/vendor"] = "0x1002\n",
    ["/sys/class/drm/card0/device/gpu_busy_percent"] = "37\n",
    ["/sys/class/drm/card0/device/mem_info_vram_total"] = "8589934592\n",
    ["/sys/class/drm/card0/device/mem_info_vram_used"] = "2147483648\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp1_input"] = "61000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp1_label"] = "edge\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp2_input"] = "70000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp2_label"] = "junction\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp3_input"] = "65000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/temp3_label"] = "mem\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/freq1_input"] = "2500000000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/freq1_label"] = "sclk\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/freq2_input"] = "1000000000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/freq2_label"] = "mclk\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/fan1_input"] = "1500\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/pwm1"] = "128\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/pwm1_max"] = "255\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/power1_average"] = "120000000\n",
    ["/sys/class/drm/card0/device/hwmon/hwmon2/power1_cap"] = "200000000\n",

    -- sda / sda1 / sda2
    ["/sys/class/block/sda1/partition"] = "1\n",
    ["/sys/class/block/sda2/partition"] = "2\n",
    ["/sys/class/block/sda/device/model"] = "Samsung SSD\n",
    ["/sys/class/block/sda/device/hwmon/hwmon3/temp1_input"] = "35000\n",

    -- nvme0n1 / nvme0n1p2
    ["/sys/class/block/nvme0n1p2/partition"] = "2\n",
    ["/sys/class/block/nvme0n1/device/model"] = "NVMe Drive\n",
    ["/sys/class/block/nvme0n1/device/hwmon1/temp1_input"] = "40000\n",

    -- LVM: /dev/mapper/vg-root -> dm-0 -> sdb1 -> sdb
    ["/sys/class/block/dm-0/dm/name"] = "vg-root\n",
    ["/sys/class/block/sdb1/partition"] = "1\n",
    ["/sys/class/block/sdb/device/model"] = "LVM Disk\n",
  }
end

local function base_dirs()
  local dirs = {
    ["/sys/class/hwmon"] = { "hwmon0", "hwmon1" },
    ["/sys/class/hwmon/hwmon0"] = { "name", "temp1_input", "temp2_input", "fan1_input", "fan1_label", "fan2_input" },
    ["/sys/class/hwmon/hwmon1"] = { "name", "fan1_input" },
    ["/sys/class/thermal"] = {},
    ["/sys/class/drm"] = { "card0", "card0-DP-1", "renderD128" },
    ["/sys/class/drm/card0/device/hwmon"] = { "hwmon2" },
    ["/sys/class/drm/card0/device/hwmon/hwmon2"] = {
      "temp1_input", "temp1_label", "temp2_input", "temp2_label", "temp3_input", "temp3_label",
      "freq1_input", "freq1_label", "freq2_input", "freq2_label", "fan1_input", "pwm1", "pwm1_max",
      "power1_average", "power1_cap",
    },
    ["/sys/class/block"] = {
      "sda", "sda1", "sda2", "nvme0n1", "nvme0n1p2", "sdb", "sdb1", "dm-0",
    },
    ["/sys/class/block/sda1/slaves"] = {},
    ["/sys/class/block/sda2/slaves"] = {},
    ["/sys/class/block/sda/device/hwmon"] = { "hwmon3" },
    ["/sys/class/block/sda/device/hwmon/hwmon3"] = { "temp1_input" },
    ["/sys/class/block/nvme0n1p2/slaves"] = {},
    ["/sys/class/block/nvme0n1/device"] = { "model", "hwmon1" },
    ["/sys/class/block/nvme0n1/device/hwmon1"] = { "temp1_input" },
    ["/sys/class/block/dm-0/slaves"] = { "sdb1" },
    ["/sys/class/block/sdb1/slaves"] = {},
  }
  return dirs
end

local df_stdout = table.concat({
  "Filesystem Type 1024-blocks Used Available Capacity Mounted on",
  "/dev/sda1 ext4 1000000 400000 600000 40% /",
  "/dev/sda2 ext4 2000000 600000 1400000 30% /home",
  "/dev/nvme0n1p2 btrfs 3000000 1500000 1500000 50% /var",
  "/dev/mapper/vg-root ext4 4000000 1000000 3000000 25% /srv",
  "tmpfs tmpfs 500 100 400 20% /run",
}, "\n")

local ctx = mock.new({
  config = { update_interval = 2, cpu_fan_number = 0 },
  files = base_files(),
  dirs = base_dirs(),
  df_stdout = df_stdout,
  lspci_stdout = "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0)\n",
  now_ms = 1000000,
})

mock.loadEntry("service.luau")
local service_update = update
local service_config = onConfigChanged

-- First sample primes CPU and network deltas but still publishes everything
-- that is immediately available.
local stats = ctx.state.stats
assert(stats ~= nil, "service did not publish stats")
assert(stats.seq == 1, "first sequence should be 1")
assert(stats.cpu.name == "AMD Ryzen 9 9950X3D", "cleaned CPU name")
assert(stats.gpu.name == "AMD Radeon RX 9070/9070 XT/9070 GRE", "AMD GPU name from lspci")
assert(stats.cpu.usage == nil, "first CPU sample must wait for a delta")
close(stats.cpu.temp_c, 60, 0.001, "CPU temperature is the hottest package sensor")
close(stats.cpu.fan_rpm, 1200, 0.001, "automatic CPU fan")
close(stats.ram.used_gb, 8, 0.001, "RAM used")
close(stats.ram.total_gb, 16, 0.001, "RAM total")
close(stats.ram.pct, 50, 0.001, "RAM percent")
assert(stats.net.down_bps == nil and stats.net.up_bps == nil, "first network sample must wait")
assert(ctx.intervals[1] == 2000, "update interval was not applied")

local gpu = stats.gpu
assert(gpu and gpu.present and gpu.vendor == "amd", "AMD GPU missing")
close(gpu.usage, 37, 0.001, "GPU usage")
close(gpu.temp_c, 61, 0.001, "GPU edge temperature")
close(gpu.temp_junction, 70, 0.001, "GPU junction temperature")
close(gpu.temp_mem, 65, 0.001, "GPU memory temperature")
close(gpu.vram_used_gb, 2, 0.001, "VRAM used")
close(gpu.vram_total_gb, 8, 0.001, "VRAM total")
close(gpu.vram_pct, 25, 0.001, "VRAM percent")
close(gpu.clock_mhz, 2500, 0.001, "GPU core clock")
close(gpu.mem_clock_mhz, 1000, 0.001, "GPU memory clock")
close(gpu.fan_rpm, 1500, 0.001, "GPU fan RPM")
close(gpu.fan_pct, 50, 0.001, "GPU fan percent")
close(gpu.power_w, 120, 0.001, "GPU power")
close(gpu.power_cap_w, 200, 0.001, "GPU power cap")

assert(#stats.disks == 3, "expected three physical disks, got " .. tostring(#stats.disks))
local sda = disk_by_key(stats.disks, "sda")
local nvme = disk_by_key(stats.disks, "nvme0n1")
local sdb = disk_by_key(stats.disks, "sdb")
assert(sda and nvme and sdb, "disk keys missing")
assert(sda.name == "Samsung SSD", "sda model")
close(sda.used_gb, 1000000 / 1024 / 1024, 0.001, "sda used")
close(sda.total_gb, 3000000 / 1024 / 1024, 0.001, "sda total")
close(sda.pct, 100 / 3, 0.1, "sda percent")
close(sda.temp_c, 35, 0.001, "sda temperature")
assert(nvme.name == "NVMe Drive", "nvme model")
close(nvme.temp_c, 40, 0.001, "nvme temperature")
assert(sdb.name == "LVM Disk", "LVM model")
close(sdb.used_gb, 1000000 / 1024 / 1024, 0.001, "LVM used")
close(sdb.total_gb, 4000000 / 1024 / 1024, 0.001, "LVM total")
assert(sdb.temp_c == nil, "LVM disk has no temperature sensor")
assert(count_command(ctx.commands, "df -kPT") == 1, "df was not sampled once")

-- Second sample: 250 total ticks with 50 idle -> 80% busy. 2048 bytes in one
-- second -> 2048 B/s each way.
ctx.files["/proc/stat"] = "cpu  200 0 200 850 0 0 0 0\n"
ctx.files["/proc/net/dev"] = table.concat({
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "  eth0: 3048 0 0 0 0 0 0 0 4048 0 0 0 0 0 0 0",
  "    lo: 9999 0 0 0 0 0 0 0 9999 0 0 0 0 0 0 0",
}, "\n")
ctx.advance(1000)
service_update()
stats = ctx.state.stats
close(stats.cpu.usage, 80, 0.001, "CPU after second sample")
close(stats.net.down_bps, 2048, 0.5, "download rate")
close(stats.net.up_bps, 2048, 0.5, "upload rate")
assert(count_command(ctx.commands, "df -kPT") == 1, "disk must not be sampled again before 10 seconds")

-- A setting change is applied in place; an explicit fan number selects fan2 on
-- the board chip, and the update interval is pushed to the host.
ctx.config.update_interval = 5
ctx.config.cpu_fan_number = 2
service_config()
assert(ctx.intervals[#ctx.intervals] == 5000, "config change did not update the interval")
ctx.advance(1000)
service_update()
close(ctx.state.stats.cpu.fan_rpm, 800, 0.001, "explicit CPU fan number")

-- Missing sensors publish nil rather than zero.
ctx.dirs["/sys/class/hwmon"] = {}
ctx.files["/proc/meminfo"] = nil
ctx.files["/proc/net/dev"] = nil
ctx.advance(1000)
service_update()
stats = ctx.state.stats
assert(stats.cpu.temp_c == nil, "missing CPU temperature should be nil")
assert(stats.cpu.fan_rpm == nil, "missing CPU fan should be nil")
assert(stats.ram.total_gb == nil, "missing RAM should be nil")
assert(stats.net.down_bps == nil and stats.net.up_bps == nil, "missing network should be nil")

-- A malformed /proc/stat is unknown, not a stale value with a fresh timestamp.
ctx.files["/proc/stat"] = "not a stat file\n"
ctx.advance(1000)
service_update()
assert(ctx.state.stats.cpu.usage == nil, "malformed CPU sample should be nil")

-- Disk sampling resumes after ten seconds and keeps the previous cache if df
-- fails.
local before = count_command(ctx.commands, "df -kPT")
ctx.advance(11000)
service_update()
assert(count_command(ctx.commands, "df -kPT") == before + 1, "disk sample did not resume after ten seconds")

-- Nvidia through nvidia-smi, including the short-query fallback.
local nvidia_ctx = mock.new({
  config = { update_interval = 2, cpu_fan_number = 0 },
  files = { ["/proc/stat"] = "cpu 1 0 1 8 0 0 0 0\n", ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n" },
  dirs = { ["/sys/class/hwmon"] = {}, ["/sys/class/drm"] = {}, ["/sys/class/thermal"] = {} },
  nvidia_smi = true,
  nvidia_stdout = "42, 63, 3072, 8192, 1800, 7000, 45, 180, 250\n",
  now_ms = 2000000,
  run_async = function(command, callback, context)
    if command:find("clocks.gr", 1, true) then
      callback({ exitCode = 1, stdout = "", stderr = "unsupported field" })
    else
      callback({ exitCode = 0, stdout = "42, 63, 3072, 8192\n", stderr = "" })
    end
    return true
  end,
})
mock.loadEntry("service.luau")
local ngpu = nvidia_ctx.state.stats.gpu
assert(ngpu and ngpu.vendor == "nvidia", "Nvidia GPU missing after short query")
close(ngpu.usage, 42, 0.001, "Nvidia usage")
close(ngpu.temp_c, 63, 0.001, "Nvidia temperature")
close(ngpu.vram_used_gb, 3, 0.001, "Nvidia VRAM used")
close(ngpu.vram_total_gb, 8, 0.001, "Nvidia VRAM total")
assert(ngpu.clock_mhz == nil, "short query has no clocks")

-- Host fallback for Intel or an NVML-only setup.
local host_ctx = mock.new({
  config = { update_interval = 2, cpu_fan_number = 0 },
  files = { ["/proc/stat"] = "cpu 1 0 1 8 0 0 0 0\n", ["/proc/meminfo"] = "MemTotal: 1000 kB\nMemAvailable: 500 kB\n" },
  dirs = { ["/sys/class/hwmon"] = {}, ["/sys/class/drm"] = {}, ["/sys/class/thermal"] = {} },
  now_ms = 3000000,
  system_stats = {
    gpu = {
      usagePercent = 12,
      tempC = 48,
      vramUsedBytes = 1073741824,
      vramTotalBytes = 4294967296,
    },
  },
})
mock.loadEntry("service.luau")
local hgpu = host_ctx.state.stats.gpu
assert(hgpu and hgpu.vendor == "host", "host GPU fallback missing")
close(hgpu.usage, 12, 0.001, "host GPU usage")
close(hgpu.temp_c, 48, 0.001, "host GPU temperature")
close(hgpu.vram_used_gb, 1, 0.001, "host VRAM used")
close(hgpu.vram_total_gb, 4, 0.001, "host VRAM total")

print("SERVICE TEST OK")
