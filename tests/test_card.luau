-- Card test: mocked settings/state, declarative tree assertions only.
local mock = dofile("tests/support/mock.luau")

local GIB = 1024 * 1024 * 1024

local state = {
  ts = os.time(),
  seq = 1,
  cpu = { usage = 42.5, temp_c = 90, fan_rpm = 1500 },
  ram = { used_gb = 8.5, total_gb = 32, pct = 26.5 },
  net = { down_bps = 2048, up_bps = 512 },
  gpu = {
    present = true,
    vendor = "amd",
    usage = 37.4,
    temp_c = 61.2,
    vram_used_gb = 2,
    vram_total_gb = 8,
    vram_pct = 25,
    temp_junction = 70,
    temp_mem = 65,
    clock_mhz = 2500,
    mem_clock_mhz = 1000,
    fan_rpm = 1500,
    fan_pct = 50,
    power_w = 120,
    power_cap_w = 200,
  },
  disks = {
    { key = "sda", name = "Samsung SSD", temp_c = 35, used_gb = 100, total_gb = 500, pct = 20 },
    { key = "nvme0n1", name = "NVMe Drive", temp_c = 41, used_gb = 460, total_gb = 500, pct = 92 },
  },
}

local function base_config()
  return {
    update_interval = 2,
    title = "Lab Rig",
    show_header = true,
    show_styling = false,
    show_card_settings = false,
    show_sections = false,
    show_network = true,
    show_cpu = true,
    show_ram = true,
    show_gpu = true,
    show_vram = true,
    show_disks = true,
    show_cpu_fan = true,
    allow_gpu_details = true,
    content_width = 500,
    card_gap = 10,
    card_padding = 10,
    card_radius = 8,
    card_fill_color = "#112233",
    card_fill_opacity = 0.5,
    card_border_color = "#445566",
    card_border_width = 2,
    accent_color = "#ff8800",
    text_color = "#abcdef",
    muted_text_color = "#123456",
    track_color = "#00ff00",
    track_opacity = 0.5,
    bar_height = 8,
    temp_warm = 70,
    temp_hot = 85,
    temp_warm_color = "#ffaa00",
    critical_color = "#ff0000",
    disk_warning = 90,
    chart_scale_mode = "auto",
    cpu_chart_height = 24,
    cpu_chart_scale = 10,
    gpu_chart_height = 26,
    gpu_chart_scale = 10,
    network_chart_height = 40,
    network_line_width = 2,
    network_fill_opacity = 0.4,
    network_scale_kbps = 10,
    divider_width = 2,
    divider_color = "#8899aa",
    history_points = 10,
    background = true,
    background_color = "surface",
    background_opacity = 0.8,
    background_radius = 14,
    background_padding = 14,
  }
end

local function copy_config(overrides)
  local config = base_config()
  for key, value in pairs(overrides or {}) do
    config[key] = value
  end
  return config
end

local function fresh_state()
  return {
    ts = os.time(),
    seq = 1,
    cpu = { usage = 42.5, temp_c = 90, fan_rpm = 1500 },
    ram = { used_gb = 8.5, total_gb = 32, pct = 26.5 },
    net = { down_bps = 2048, up_bps = 512 },
    gpu = {
      present = true,
      vendor = "amd",
      usage = 37.4,
      temp_c = 61.2,
      vram_used_gb = 2,
      vram_total_gb = 8,
      vram_pct = 25,
      temp_junction = 70,
      temp_mem = 65,
      clock_mhz = 2500,
      mem_clock_mhz = 1000,
      fan_rpm = 1500,
      fan_pct = 50,
      power_w = 120,
      power_cap_w = 200,
    },
    disks = {
      { key = "sda", name = "Samsung SSD", temp_c = 35, used_gb = 100, total_gb = 500, pct = 20 },
      { key = "nvme0n1", name = "NVMe Drive", temp_c = 41, used_gb = 460, total_gb = 500, pct = 92 },
    },
  }
end

local ctx = mock.new({ config = base_config(), state = { stats = state } })
mock.loadEntry("card.luau")
local tree = ctx.desktop_tree
local watch = ctx.watchers.stats and ctx.watchers.stats[1]

local function find(key)
  return mock.find(tree, key)
end

local function find_text(text)
  return mock.findText(tree, text)
end

local function assert_eq(actual, expected, label)
  assert(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

local function assert_close(actual, expected, epsilon, label)
  assert(type(actual) == "number", label .. ": expected a number, got " .. tostring(actual))
  assert(math.abs(actual - expected) <= epsilon,
    ("%s: expected %.4f, got %.4f"):format(label, expected, actual))
end

assert(tree and tree.type == "column", "card tree missing")
assert(watch, "card did not watch the stats state")
assert_eq(tree.props.key, "card", "root key")
assert_eq(tree.props.width, 500, "content width")
assert_eq(tree.props.padding, 0, "host panel padding")
assert_eq(tree.props.fill, nil, "card must not draw its own outer surface")
assert_eq(tree.props.border, nil, "card must not draw an outer border")

-- Header and divider.
assert_eq(find("header-title").props.text, "Lab Rig", "title")
assert_eq(find("header-title").props.color, "#abcdef", "title colour")
assert_eq(find("header-settings").props.glyph, "settings", "settings glyph")
assert_eq(find("header-settings").props.onClick, "openSettings", "settings callback")
assert_eq(find("header-divider").props.thickness, 2, "divider thickness")
assert_eq(find("header-divider").props.color, "#8899aa", "divider colour")
assert_eq(find("content").props.opacity, 1, "live content opacity")

-- Network values and charts.
assert_eq(find("network-down-value").props.text, "2.0 KB/s", "download value")
assert_eq(find("network-up-value").props.text, "512 B/s", "upload value")
assert_eq(find("network-down-value").props.color, "#abcdef", "download text colour")
assert_close(find("network-down-graph").props.values[1], 2048 / 10240, 1e-9, "download history normalised")
assert_close(find("network-up-graph").props.values[1], 512 / 10240, 1e-9, "upload history normalised")
assert_eq(find("network-down-graph").props.lineWidth, 2, "chart line width")
assert_eq(find("network-down-graph").props.fillOpacity, 0.4, "chart fill opacity")
assert_eq(find("network-down-graph").props.height, 40, "download chart height")
assert_eq(find("network-up-graph").props.height, 26, "upload chart height")
assert_eq(find("network-down-graph").props.color, "#ff8800", "chart accent colour")

-- CPU: 42.5% is rendered as a usage chart.
assert_eq(find("cpu-usage-value").props.text, "43%", "CPU value")
assert_eq(find("cpu-usage-value").props.color, "#abcdef", "CPU text colour")
assert_eq(find("cpu-usage-graph").props.height, 24, "CPU usage chart height")
assert_eq(find("cpu-usage-graph").props.lineWidth, 2, "CPU usage chart line width")
assert_eq(find("cpu-usage-graph").props.fillOpacity, 0.4, "CPU usage chart fill opacity")
assert_eq(find("cpu-usage-graph").props.color, "#ff8800", "CPU usage chart colour")
assert_close(find("cpu-usage-graph").props.values[1], 1.0, 1e-9, "CPU usage history normalised")
assert_eq(find("cpu-fan-value").props.text, "1500 RPM", "CPU fan")
assert_eq(find("cpu-temp-value").props.text, "90 °C", "CPU temperature")
assert_eq(find("cpu-temp-value").props.color, "#ff0000", "critical CPU temperature colour")
assert(find("cpu-temp-alert"), "critical CPU temperature needs a warning glyph")

-- RAM.
local ram_text = find("ram-summary-label").props.text
assert(ram_text:find("8.5", 1, true), "RAM used value missing: " .. ram_text)
assert(ram_text:find("32", 1, true), "RAM total value missing: " .. ram_text)
assert_eq(find("ram-pct").props.text, "27%", "RAM percent")
assert_eq(find("ram-pct").props.color, "#ff8800", "RAM percentage matches the bar accent")
assert_close(find("ram-bar").props.progress, 0.265, 1e-9, "RAM solid bar progress")
assert_eq(find("ram-bar").props.fill, "#ff8800", "RAM solid bar fill")
assert_eq(find("ram-bar").props.track, "#00ff0080", "RAM solid bar track")
assert_eq(find("ram-bar").props.height, 8, "RAM solid bar height")

-- GPU and VRAM.
assert_eq(find("gpu-usage-value").props.text, "37%", "GPU usage")
assert_eq(find("gpu-usage-graph").props.height, 26, "GPU usage chart height")
assert_close(find("gpu-usage-graph").props.values[1], 1.0, 1e-9, "GPU usage history normalised")
assert_eq(find("gpu-temp-value").props.text, "61 °C", "GPU temperature")
assert_eq(find("gpu-temp-value").props.color, "#ff8800", "normal GPU temperature colour")
assert_eq(find("gpu-details-toggle").props.text, "More", "GPU details button")
assert_eq(find("gpu-details-toggle").props.onClick, "toggleGpuDetails", "GPU details callback")
assert_eq(find("vram-pct").props.text, "25%", "VRAM percent")
assert_eq(find("vram-pct").props.color, "#ff8800", "VRAM percentage matches the bar accent")
assert_close(find("vram-bar").props.progress, 0.25, 1e-9, "VRAM solid bar progress")
assert_eq(find("vram-bar").props.fill, "#ff8800", "VRAM solid bar fill")
local vram_text = find("vram-summary-label").props.text
assert(vram_text:find("2.0", 1, true), "VRAM used missing: " .. vram_text)
assert(vram_text:find("8", 1, true), "VRAM total missing: " .. vram_text)

-- Inner card surfaces are translucent, and the host panel is not duplicated.
assert_eq(find("network-card").props.fill, "#11223380", "card fill and opacity")
assert_eq(find("network-card").props.border, "#445566", "card border colour")
assert_eq(find("network-card").props.borderWidth, 2, "card border width")
assert_eq(find("network-card").props.radius, 8, "card radius")

-- Disk rows: name, sizes, temperature and warning colour.
assert_eq(find("disk-1-name").props.text, "Samsung SSD", "first disk name")
assert_eq(find("disk-1-size").props.text, "100 GB / 500 GB · 35 °C", "first disk sizes")
assert_eq(find("disk-1-pct").props.text, "20%", "first disk percent")
assert_eq(find("disk-1-pct").props.color, "#ff8800", "first disk percentage matches the bar accent")
assert_close(find("disk-1-bar").props.progress, 0.2, 1e-9, "first disk solid bar progress")
assert_eq(find("disk-1-bar").props.fill, "#ff8800", "first disk solid bar fill")
assert_eq(find("disk-2-name").props.text, "NVMe Drive", "second disk name")
assert_eq(find("disk-2-pct").props.text, "92%", "second disk percent")
assert_eq(find("disk-2-pct").props.color, "#ff0000", "disk warning colour")
assert_close(find("disk-2-bar").props.progress, 0.92, 1e-9, "warning disk solid bar progress")
assert_eq(find("disk-2-bar").props.fill, "#ff0000", "disk warning solid bar fill")
assert(find("disk-2-alert"), "disk warning needs a glyph")
assert(find("disk-2-divider"), "disks should be separated")

-- Host-handled keys are read (lint contract) and the card adds no surface.
for _, key in ipairs({
  "background", "background_color", "background_opacity", "background_radius", "background_padding",
  "show_styling", "show_card_settings", "show_sections",
}) do
  assert(ctx.requested[key], "setting " .. key .. " was not read")
end

-- The settings button opens this plugin's settings.
openSettings()
assert_eq(ctx.openedSettings, 1, "openSettings did not call noctalia.openSettings")

-- GPU details expand and collapse.
toggleGpuDetails()
tree = ctx.desktop_tree
assert(mock.find(tree, "gpu-details-1"), "GPU details did not expand")
assert_eq(mock.find(tree, "gpu-details-1-left-value").props.text, "70 °C", "junction temperature")
assert_eq(mock.find(tree, "gpu-details-1-right-value").props.text, "65 °C", "memory temperature")
assert_eq(mock.find(tree, "gpu-details-2-left-value").props.text, "2500 MHz", "core clock")
assert_eq(mock.find(tree, "gpu-details-2-right-value").props.text, "1000 MHz", "memory clock")
assert_eq(mock.find(tree, "gpu-details-3-left-value").props.text, "1500 RPM · 50%", "GPU fan")
assert_eq(mock.find(tree, "gpu-details-3-right-value").props.text, "120 / 200 W", "GPU power")
toggleGpuDetails()
tree = ctx.desktop_tree
assert(mock.find(tree, "gpu-details-1") == nil, "GPU details did not collapse")

-- A second sample appends one history point and re-scales the chart.
state.seq = 2
state.ts = os.time()
state.cpu.usage = 80
state.gpu.usage = 50
state.net.down_bps = 20480
state.net.up_bps = 10240
watch(state)
tree = ctx.desktop_tree
assert_eq(mock.find(tree, "cpu-usage-value").props.text, "80%", "second CPU sample")
assert_eq(mock.find(tree, "gpu-usage-value").props.text, "50%", "second GPU sample")
local cpu_values = mock.find(tree, "cpu-usage-graph").props.values
assert_eq(#cpu_values, 2, "CPU usage history length")
assert_close(cpu_values[1], 0.425 / 0.8, 1e-9, "first CPU usage point")
assert_close(cpu_values[2], 1.0, 1e-9, "second CPU usage point")
local gpu_values = mock.find(tree, "gpu-usage-graph").props.values
assert_eq(#gpu_values, 2, "GPU usage history length")
assert_close(gpu_values[1], 0.374 / 0.5, 1e-9, "first GPU usage point")
assert_close(gpu_values[2], 1.0, 1e-9, "second GPU usage point")
local down_values = mock.find(tree, "network-down-graph").props.values
assert_eq(#down_values, 2, "network history length")
assert_close(down_values[1], 0.1, 1e-9, "first download point after rescale")
assert_close(down_values[2], 1.0, 1e-9, "second download point after rescale")
local up_values = mock.find(tree, "network-up-graph").props.values
assert_eq(#up_values, 2, "upload history length")
assert_close(up_values[1], 0.05, 1e-9, "first upload point")
assert_close(up_values[2], 1.0, 1e-9, "second upload point")

-- Stale state: values blank, waiting status, history kept.
state.seq = 3
state.ts = os.time() - 100
watch(state)
tree = ctx.desktop_tree
assert_eq(mock.find(tree, "cpu-usage-value").props.text, "—", "stale CPU value")
assert_eq(mock.find(tree, "gpu-usage-value").props.text, "—", "stale GPU value")
assert_eq(mock.find(tree, "content").props.opacity, 0.7, "stale content opacity")
assert_eq(mock.findText(tree, "Waiting for system data") ~= nil, true, "waiting status")
assert_eq(#mock.find(tree, "cpu-usage-graph").props.values, 2, "stale state keeps CPU history")
assert_eq(#mock.find(tree, "network-down-graph").props.values, 2, "stale state keeps history")

-- No GPU probe: explicit message instead of misleading zeros.
state.seq = 4
state.ts = os.time()
state.gpu = nil
watch(state)
tree = ctx.desktop_tree
assert_eq(mock.find(tree, "gpu-unavailable").props.text, "No GPU detected", "GPU unavailable message")
assert_eq(mock.find(tree, "vram-unavailable").props.text, "No GPU detected", "VRAM unavailable message")
assert(mock.find(tree, "gpu-usage-value") == nil, "no GPU usage row without a probe")
assert(mock.find(tree, "gpu-usage-graph") == nil, "no GPU usage chart without a probe")
assert(mock.find(tree, "gpu-details-toggle") == nil, "no details button without a probe")

-- Defaults are palette roles, not fixed hex.
local role_ctx = mock.new({ config = { update_interval = 2 }, state = { stats = fresh_state() } })
mock.loadEntry("card.luau")
local role_tree = role_ctx.desktop_tree
assert_eq(mock.find(role_tree, "card").props.width, 320, "default content width")
assert_eq(mock.find(role_tree, "network-card").props.fill, "surface_variant/0.35", "default card fill role")
assert_eq(mock.find(role_tree, "network-header-glyph").props.color, "primary", "default accent role")
assert_eq(mock.find(role_tree, "ram-bar").props.track, "on_surface/0.14", "default track role")
assert_eq(mock.find(role_tree, "ram-pct").props.color, "primary", "default RAM percentage role")
assert_eq(mock.find(role_tree, "vram-pct").props.color, "primary", "default VRAM percentage role")
assert_eq(mock.find(role_tree, "cpu-usage-graph").props.height, 20, "default CPU chart height")
assert_eq(mock.find(role_tree, "network-down-graph").props.color, "primary", "default chart role")
assert_eq(mock.find(role_tree, "header-divider").props.color, "outline", "default divider role")

-- Hiding every section leaves the header and an explicit status.
local hidden_ctx = mock.new({
  config = copy_config({
    show_network = false,
    show_cpu = false,
    show_ram = false,
    show_gpu = false,
    show_vram = false,
    show_disks = false,
  }),
  state = { stats = fresh_state() },
})
mock.loadEntry("card.luau")
local hidden_tree = hidden_ctx.desktop_tree
for _, key in ipairs({ "network-card", "cpu-card", "ram-card", "gpu-card", "vram-card", "disks-card" }) do
  assert(mock.find(hidden_tree, key) == nil, key .. " should be hidden")
end
assert(mock.findText(hidden_tree, "All sections are hidden"), "hidden sections status missing")

-- Turning the host panel off adds a small content inset but still draws no
-- outer surface.
local off_ctx = mock.new({ config = copy_config({ background = false }), state = { stats = fresh_state() } })
mock.loadEntry("card.luau")
local off_tree = off_ctx.desktop_tree
assert_eq(mock.find(off_tree, "card").props.padding, 6, "plugin-surface inset")
assert_eq(mock.find(off_tree, "card").props.fill, nil, "host panel off should not add an outer fill")
assert_eq(off_ctx.requested.background, true, "background setting was not read")

print("CARD TEST OK")
