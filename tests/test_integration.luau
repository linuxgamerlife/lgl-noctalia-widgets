-- Integration test: the real service publishes state, the real card renders it.
local mock = dofile("tests/support/mock.luau")

local function close(actual, expected, epsilon, label)
  assert(type(actual) == "number", label .. ": expected a number, got " .. tostring(actual))
  assert(math.abs(actual - expected) <= epsilon,
    ("%s: expected %.4f, got %.4f"):format(label, expected, actual))
end

local files = {
  ["/proc/stat"] = "cpu  100 0 100 800 0 0 0 0\n",
  ["/proc/meminfo"] = "MemTotal:       16777216 kB\nMemAvailable:    8388608 kB\n",
  ["/proc/net/dev"] = table.concat({
    "Inter-|   Receive                                                |  Transmit",
    " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
    "  eth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0",
  }, "\n"),
  ["/sys/class/hwmon/hwmon0/name"] = "k10temp\n",
  ["/sys/class/hwmon/hwmon0/temp1_input"] = "62000\n",
  ["/sys/class/hwmon/hwmon0/fan1_input"] = "1300\n",
  ["/sys/class/hwmon/hwmon0/fan1_label"] = "CPU Fan\n",
  ["/sys/class/drm/card0/device/vendor"] = "0x1002\n",
  ["/sys/class/drm/card0/device/gpu_busy_percent"] = "37\n",
  ["/sys/class/drm/card0/device/mem_info_vram_total"] = "8589934592\n",
  ["/sys/class/drm/card0/device/mem_info_vram_used"] = "2147483648\n",
  ["/sys/class/drm/card0/device/hwmon/hwmon2/temp1_input"] = "61000\n",
  ["/sys/class/drm/card0/device/hwmon/hwmon2/temp1_label"] = "edge\n",
  ["/sys/class/block/nvme0n1p2/partition"] = "2\n",
  ["/sys/class/block/nvme0n1/device/model"] = "NVMe Drive\n",
  ["/sys/class/block/nvme0n1/device/hwmon1/temp1_input"] = "40000\n",
}

local dirs = {
  ["/sys/class/hwmon"] = { "hwmon0" },
  ["/sys/class/hwmon/hwmon0"] = { "name", "temp1_input", "fan1_input", "fan1_label" },
  ["/sys/class/thermal"] = {},
  ["/sys/class/drm"] = { "card0" },
  ["/sys/class/drm/card0/device/hwmon"] = { "hwmon2" },
  ["/sys/class/drm/card0/device/hwmon/hwmon2"] = { "temp1_input", "temp1_label" },
  ["/sys/class/block"] = { "nvme0n1", "nvme0n1p2" },
  ["/sys/class/block/nvme0n1p2/slaves"] = {},
  ["/sys/class/block/nvme0n1/device"] = { "model", "hwmon1" },
  ["/sys/class/block/nvme0n1/device/hwmon1"] = { "temp1_input" },
}

local df_stdout = table.concat({
  "Filesystem Type 1024-blocks Used Available Capacity Mounted on",
  "/dev/nvme0n1p2 btrfs 3000000 1500000 1500000 50% /",
}, "\n")

local config = {
  update_interval = 1,
  cpu_fan_number = 0,
  title = "System Monitor",
  show_header = true,
  show_network = true,
  show_cpu = true,
  show_ram = true,
  show_gpu = true,
  show_vram = true,
  show_disks = true,
  show_cpu_fan = true,
  allow_gpu_details = true,
  content_width = 320,
  card_gap = 10,
  card_padding = 10,
  card_radius = 8,
  card_fill_color = "surface_variant",
  card_fill_opacity = 0.35,
  card_border_color = "outline",
  card_border_width = 1,
  accent_color = "primary",
  text_color = "on_surface",
  muted_text_color = "on_surface_variant",
  track_color = "on_surface",
  track_opacity = 0.14,
  bar_height = 8,
  segment_count = 20,
  segment_gap = 3,
  temp_warm = 70,
  temp_hot = 85,
  temp_warm_color = "tertiary",
  critical_color = "error",
  disk_warning = 90,
  network_chart_height = 32,
  network_line_width = 1.5,
  network_fill_opacity = 0.15,
  network_scale_kbps = 10,
  divider_width = 1,
  divider_color = "outline",
  history_points = 30,
  background = true,
  background_color = "surface",
  background_opacity = 0.8,
  background_radius = 14,
  background_padding = 14,
}

local ctx = mock.new({
  config = config,
  files = files,
  dirs = dirs,
  df_stdout = df_stdout,
  now_ms = 4000000,
})

-- Load the card first so its initial waiting state is observable.
mock.loadEntry("card.luau")
local card_update = update
local card_watch = ctx.watchers.stats[1]
assert(ctx.desktop_tree ~= nil, "card did not render before service startup")
assert(mock.findText(ctx.desktop_tree, "Waiting for system data"), "card should start waiting")

-- Load the service; its first publish reaches the card synchronously.
mock.loadEntry("service.luau")
local service_update = update

assert(ctx.state.stats ~= nil, "service did not publish state")
local tree = ctx.desktop_tree
assert(mock.findText(tree, "Waiting for system data") == nil, "waiting status should clear")
assert(mock.find(tree, "cpu-usage-value").props.text == "—", "first CPU sample should be pending")
assert(mock.find(tree, "cpu-temp-value").props.text == "62 °C", "CPU temperature missing")
assert(mock.find(tree, "cpu-fan-value").props.text == "1300 RPM", "CPU fan missing")
assert(mock.find(tree, "ram-summary-label").props.text:find("8.0", 1, true), "RAM usage missing")
assert(mock.find(tree, "gpu-usage-value").props.text == "37%", "GPU usage missing")
assert(mock.find(tree, "gpu-temp-value").props.text == "61 °C", "GPU temperature missing")
assert(mock.find(tree, "disk-1-name").props.text == "NVMe Drive", "disk model missing")
assert(mock.find(tree, "disk-1-pct").props.text == "50%", "disk usage missing")
assert(#ctx.commands == 1 and ctx.commands[1]:find("df -kPT", 1, true), "df was not sampled")

-- Second sample: 80% CPU and the first network rate. The card gains one point.
files["/proc/stat"] = "cpu  200 0 200 850 0 0 0 0\n"
files["/proc/net/dev"] = table.concat({
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "  eth0: 3048 0 0 0 0 0 0 0 4048 0 0 0 0 0 0 0",
}, "\n")
ctx.advance(1000)
service_update()
tree = ctx.desktop_tree
assert(mock.find(tree, "cpu-usage-value").props.text == "80%", "CPU sample did not reach the card")
assert(mock.find(tree, "network-down-value").props.text == "2.0 KB/s", "download rate did not reach the card")
assert(mock.find(tree, "network-up-value").props.text == "2.0 KB/s", "upload rate did not reach the card")
assert(#mock.find(tree, "network-down-graph").props.values == 1, "first network history point")
assert(#ctx.commands == 1, "disk must not be sampled again within ten seconds")

-- Third sample: a second network point, still without another df call.
files["/proc/stat"] = "cpu  300 0 300 900 0 0 0 0\n"
files["/proc/net/dev"] = table.concat({
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "  eth0: 5096 0 0 0 0 0 0 0 6096 0 0 0 0 0 0 0",
}, "\n")
ctx.advance(1000)
service_update()
tree = ctx.desktop_tree
assert(mock.find(tree, "cpu-usage-value").props.text == "80%", "third CPU sample")
assert(#mock.find(tree, "network-down-graph").props.values == 2, "second network history point")
assert(#ctx.commands == 1, "disk refresh cadence changed")

-- A stale copy delivered to the card blanks the values and says it is waiting.
local stale = {}
for key, value in pairs(ctx.state.stats) do
  stale[key] = value
end
stale.ts = os.time() - 100
card_watch(stale)
tree = ctx.desktop_tree
assert(mock.find(tree, "cpu-usage-value").props.text == "—", "stale CPU value")
assert(mock.findText(tree, "Waiting for system data"), "stale integration state should wait")

-- The next service sample restores the live card.
files["/proc/stat"] = "cpu  400 0 400 950 0 0 0 0\n"
ctx.advance(1000)
service_update()
tree = ctx.desktop_tree
assert(mock.find(tree, "cpu-usage-value").props.text == "80%", "live CPU value did not return")
assert(mock.findText(tree, "Waiting for system data") == nil, "waiting status should clear again")

-- A stale service does not duplicate chart points.
local before = #mock.find(tree, "network-down-graph").props.values
card_update()
assert(#mock.find(tree, "network-down-graph").props.values == before, "plain update must not append history")

print("INTEGRATION TEST OK")
