--!nonstrict
-- Declarative desktop card for Modern SysMonitor Plus.
--
-- The headless `poller` service publishes one `stats` table. This entry keeps
-- the network history, formats the values and renders a `ui.*` tree. The outer
-- surface is Noctalia's host panel; the plugin deliberately draws no second
-- outer background, so the host opacity slider always affects the visible panel.

local format = require("./lib/format.luau")

local function cfg_text(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) ~= "string" or value == "" then
    return fallback
  end
  return value
end

local function cfg_bool(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) == "boolean" then
    return value
  end
  return fallback
end

local function cfg_number(key, fallback, low, high)
  local value = tonumber(noctalia.getConfig(key))
  if value == nil then
    value = fallback
  end
  return format.clamp(value, low, high)
end

-- Color settings accept a bare palette role or a hex value. The manifest does
-- not accept a role with an alpha suffix, so translucency is built here.
local function color_with_alpha(color, alpha)
  local opacity = format.clamp(alpha or 1, 0, 1)
  if opacity >= 0.999 then
    return color
  end

  local suffix = string.format("%02x", math.floor(opacity * 255 + 0.5))
  local r, g, b = color:match("^#(%x)(%x)(%x)$")
  if r then
    return "#" .. r .. r .. g .. g .. b .. b .. suffix
  end
  r, g, b = color:match("^#(%x)(%x)(%x)(%x)$")
  if r then
    return "#" .. r .. r .. g .. g .. b .. b .. suffix
  end
  r, g, b = color:match("^#(%x%x)(%x%x)(%x%x)$")
  if r then
    return "#" .. r .. g .. b .. suffix
  end
  if color:match("^#%x%x%x%x%x%x%x%x$") then
    return color:sub(1, 7) .. suffix
  end
  return string.format("%s/%.2f", color, opacity)
end

local settings = {
  title = cfg_text("title", noctalia.tr("meta.name")),
  show_header = cfg_bool("show_header", true),
  -- Settings-editor hint only: the card always renders with the stored styling.
  show_styling = cfg_bool("show_styling", false),
  show_card_settings = cfg_bool("show_card_settings", false),
  show_sections = cfg_bool("show_sections", false),
  show_network = cfg_bool("show_network", true),
  show_cpu = cfg_bool("show_cpu", true),
  show_ram = cfg_bool("show_ram", true),
  show_gpu = cfg_bool("show_gpu", true),
  show_vram = cfg_bool("show_vram", true),
  show_disks = cfg_bool("show_disks", true),
  show_cpu_fan = cfg_bool("show_cpu_fan", true),
  allow_gpu_details = cfg_bool("allow_gpu_details", true),

  content_width = math.floor(cfg_number("content_width", 320, 240, 900) + 0.5),
  card_gap = math.floor(cfg_number("card_gap", 10, 0, 32) + 0.5),
  card_padding = math.floor(cfg_number("card_padding", 10, 0, 32) + 0.5),
  card_radius = math.floor(cfg_number("card_radius", 8, 0, 32) + 0.5),
  card_fill_color = cfg_text("card_fill_color", "surface_variant"),
  card_fill_opacity = cfg_number("card_fill_opacity", 0.35, 0, 1),
  card_border_color = cfg_text("card_border_color", "outline"),
  card_border_width = cfg_number("card_border_width", 1, 0, 4),

  accent_color = cfg_text("accent_color", "primary"),
  text_color = cfg_text("text_color", "on_surface"),
  muted_text_color = cfg_text("muted_text_color", "on_surface_variant"),
  track_color = cfg_text("track_color", "on_surface"),
  track_opacity = cfg_number("track_opacity", 0.14, 0, 1),

  bar_height = cfg_number("bar_height", 8, 4, 16),
  segment_count = math.floor(cfg_number("segment_count", 20, 8, 40) + 0.5),
  segment_gap = cfg_number("segment_gap", 3, 0, 6),

  temp_warm = math.floor(cfg_number("temp_warm", 70, 30, 110) + 0.5),
  temp_hot = math.floor(cfg_number("temp_hot", 85, 40, 120) + 0.5),
  temp_warm_color = cfg_text("temp_warm_color", "tertiary"),
  critical_color = cfg_text("critical_color", "error"),
  disk_warning = cfg_number("disk_warning", 90, 50, 100),

  usage_chart_height = math.floor(cfg_number("usage_chart_height", 20, 12, 48) + 0.5),
  network_chart_height = math.floor(cfg_number("network_chart_height", 32, 16, 80) + 0.5),
  network_line_width = cfg_number("network_line_width", 1.5, 0.5, 4),
  network_fill_opacity = cfg_number("network_fill_opacity", 0.15, 0, 1),
  network_scale_kbps = math.floor(cfg_number("network_scale_kbps", 10, 1, 1024) + 0.5),

  divider_width = cfg_number("divider_width", 1, 0.5, 4),
  divider_color = cfg_text("divider_color", "outline"),
  history_points = math.floor(cfg_number("history_points", 30, 10, 120) + 0.5),
}

if settings.temp_hot <= settings.temp_warm then
  settings.temp_hot = settings.temp_warm + 1
end

local update_interval = math.floor(cfg_number("update_interval", 2, 1, 60) + 0.5)
local stale_after = math.max(3, update_interval * 3)

-- Host-handled surface keys. DesktopWidget consumes these before the script
-- runs; reading them keeps lint's declared-key contract and tells us whether
-- the host panel is on (so the card can add a small inset when it is off).
local host_surface = {
  background = noctalia.getConfig("background"),
  background_color = noctalia.getConfig("background_color"),
  background_opacity = noctalia.getConfig("background_opacity"),
  background_radius = noctalia.getConfig("background_radius"),
  background_padding = noctalia.getConfig("background_padding"),
}
local host_background = host_surface.background ~= false

local DASH = noctalia.tr("labels.unknown")
local NA = noctalia.tr("labels.na")

local units = {
  bps = noctalia.tr("units.bps"),
  kbps = noctalia.tr("units.kbps"),
  mbps = noctalia.tr("units.mbps"),
  gbps = noctalia.tr("units.gbps"),
  gb = noctalia.tr("units.gb"),
  tb = noctalia.tr("units.tb"),
  rpm = noctalia.tr("units.rpm"),
  celsius = noctalia.tr("units.celsius"),
  mhz = noctalia.tr("units.mhz"),
  watts = noctalia.tr("units.watts"),
}

local track_color = color_with_alpha(settings.track_color, settings.track_opacity)
local card_fill = color_with_alpha(settings.card_fill_color, settings.card_fill_opacity)

local current = nil
local last_token = nil
local gpu_expanded = false
local cpu_history = {}
local gpu_history = {}
local down_history = {}
local up_history = {}

local function fresh()
  if type(current) ~= "table" then
    return false
  end
  local timestamp = tonumber(current.ts)
  return timestamp ~= nil and os.time() - timestamp <= stale_after
end

local function push(series, value)
  if value == nil then
    return
  end
  series[#series + 1] = value
  while #series > settings.history_points do
    table.remove(series, 1)
  end
end

local function copy(series)
  local values = {}
  for index = 1, #series do
    values[index] = series[index]
  end
  return values
end

local function ingest(value)
  current = value
  if type(value) ~= "table" or not fresh() then
    return
  end

  local token = tostring(value.ts or 0) .. ":" .. tostring(value.seq or -1)
  if token == last_token then
    return
  end
  last_token = token

  local net = value.net
  if type(net) == "table" then
    push(down_history, tonumber(net.down_bps))
    push(up_history, tonumber(net.up_bps))
  end

  local cpu = value.cpu
  if type(cpu) == "table" then
    local usage = tonumber(cpu.usage)
    if usage ~= nil then
      push(cpu_history, format.clamp(usage, 0, 100) / 100)
    end
  end

  local gpu = value.gpu
  if type(gpu) == "table" then
    local usage = tonumber(gpu.usage)
    if usage ~= nil then
      push(gpu_history, format.clamp(usage, 0, 100) / 100)
    end
  end
end

local function normalize_history(series)
  local max_value = settings.network_scale_kbps * 1024
  for _, value in ipairs(series) do
    if value > max_value then
      max_value = value
    end
  end

  local values = {}
  for _, value in ipairs(series) do
    values[#values + 1] = format.clamp(value / max_value, 0, 1)
  end
  return values
end

local function has_any(stats)
  if type(stats) ~= "table" then
    return false
  end
  if type(stats.cpu) == "table" and (stats.cpu.usage ~= nil or stats.cpu.temp_c ~= nil) then
    return true
  end
  if type(stats.ram) == "table" and stats.ram.total_gb ~= nil then
    return true
  end
  if type(stats.net) == "table" and (stats.net.down_bps ~= nil or stats.net.up_bps ~= nil) then
    return true
  end
  if type(stats.gpu) == "table" then
    return true
  end
  return type(stats.disks) == "table" and #stats.disks > 0
end

local function value_color(known)
  return known and settings.text_color or settings.muted_text_color
end

local function temp_severity(temp)
  if temp == nil then
    return settings.muted_text_color
  end
  if temp >= settings.temp_hot then
    return settings.critical_color
  end
  if temp >= settings.temp_warm then
    return settings.temp_warm_color
  end
  return settings.accent_color
end

local function fmt_temp(value)
  local number = tonumber(value)
  if number == nil then
    return NA
  end
  return string.format("%d %s", math.floor(number + 0.5), units.celsius)
end

local function fmt_mhz(value)
  local number = tonumber(value)
  if number == nil then
    return NA
  end
  return string.format("%.0f %s", number, units.mhz)
end

local function fmt_fan(rpm, pct)
  local speed = tonumber(rpm)
  local percent = tonumber(pct)
  if speed ~= nil and percent ~= nil then
    return string.format("%.0f %s · %.0f%%", speed, units.rpm, percent)
  elseif speed ~= nil then
    return string.format("%.0f %s", speed, units.rpm)
  elseif percent ~= nil then
    return string.format("%.0f%%", percent)
  end
  return NA
end

local function fmt_power(watts, cap)
  local value = tonumber(watts)
  local limit = tonumber(cap)
  if value == nil then
    return NA
  end
  if limit ~= nil and limit > 0 then
    return string.format("%.0f / %.0f %s", value, limit, units.watts)
  end
  return string.format("%.0f %s", value, units.watts)
end

-- ── Shared nodes ────────────────────────────────────────────────────────────

local function surface(key, children)
  return ui.column({
    key = key,
    gap = 6,
    padding = settings.card_padding,
    radius = settings.card_radius,
    fill = card_fill,
    border = settings.card_border_color,
    borderWidth = settings.card_border_width,
  }, children)
end

local function section_header(key, glyph, label, extra)
  local children = {
    ui.glyph({ key = key .. "-glyph", name = glyph, size = 14, color = settings.accent_color }),
    ui.label({
      key = key .. "-label",
      text = label,
      fontSize = 11,
      fontWeight = "bold",
      color = settings.accent_color,
      maxLines = 1,
    }),
  }
  if extra then
    table.insert(children, ui.spacer({ key = key .. "-spacer", flexGrow = 1 }))
    table.insert(children, extra)
  end
  return ui.row({ key = key, gap = 6, align = "center" }, children)
end

local function segmented(key, percent, fill, known)
  local active = 0
  if known and percent ~= nil then
    active = math.floor(format.clamp(percent, 0, 100) / 100 * settings.segment_count + 0.5)
  end

  local children = {}
  for index = 1, settings.segment_count do
    table.insert(children, ui.box({
      key = key .. "-" .. index,
      height = settings.bar_height,
      flexGrow = 1,
      radius = math.min(settings.bar_height / 2, 3),
      fill = index <= active and fill or track_color,
    }))
  end
  return ui.row({ key = key, gap = settings.segment_gap, align = "center", flexGrow = 1 }, children)
end

local function progress_bar(key, percent, fill, known)
  local value = 0
  if known and percent ~= nil then
    value = format.clamp(percent / 100, 0, 1)
  end
  return ui.progress({
    key = key,
    progress = value,
    fill = fill,
    track = track_color,
    radius = settings.bar_height / 2,
    height = settings.bar_height,
    flexGrow = 1,
  })
end

local function usage_row(key, percent, history, known)
  return ui.row({ key = key, gap = 8, align = "center" }, {
    ui.label({
      key = key .. "-label",
      text = noctalia.tr("labels.usage"),
      width = 48,
      fontSize = 11,
      color = settings.muted_text_color,
      maxLines = 1,
    }),
    ui.graph({
      key = key .. "-graph",
      values = copy(history),
      color = settings.accent_color,
      lineWidth = settings.network_line_width,
      fillOpacity = settings.network_fill_opacity,
      height = settings.usage_chart_height,
      flexGrow = 1,
    }),
    ui.label({
      key = key .. "-value",
      text = known and format.pct(percent) or DASH,
      width = 42,
      textAlign = "end",
      fontSize = 11,
      fontWeight = "bold",
      color = value_color(known),
      maxLines = 1,
    }),
  })
end

local function temp_row(key, temp, known)
  local color = temp_severity(temp)
  local children = {
    ui.label({
      key = key .. "-label",
      text = noctalia.tr("labels.temp"),
      width = 48,
      fontSize = 11,
      color = settings.muted_text_color,
      maxLines = 1,
    }),
    progress_bar(key .. "-bar", temp, color, known),
  }

  if known and temp ~= nil and temp >= settings.temp_hot then
    table.insert(children, ui.glyph({
      key = key .. "-alert",
      name = "alert-triangle",
      size = 12,
      color = settings.critical_color,
    }))
  end

  table.insert(children, ui.label({
    key = key .. "-value",
    text = known and fmt_temp(temp) or DASH,
    width = 46,
    textAlign = "end",
    fontSize = 11,
    fontWeight = "bold",
    color = known and color or settings.muted_text_color,
    maxLines = 1,
  }))

  return ui.row({ key = key, gap = 8, align = "center" }, children)
end

local function fan_row(key, rpm)
  local speed = tonumber(rpm)
  if speed == nil or speed < 0 then
    return nil
  end
  return ui.row({ key = key, gap = 8, align = "center" }, {
    ui.label({
      key = key .. "-label",
      text = noctalia.tr("labels.fan"),
      width = 48,
      fontSize = 11,
      color = settings.muted_text_color,
      maxLines = 1,
    }),
    ui.spacer({ key = key .. "-spacer", flexGrow = 1 }),
    ui.label({
      key = key .. "-value",
      text = string.format("%d %s", math.floor(speed + 0.5), units.rpm),
      fontSize = 11,
      fontWeight = "bold",
      color = settings.text_color,
      maxLines = 1,
    }),
  })
end

local function status_row(key)
  local glyph = key == "status.waiting" and "hourglass-empty" or "alert-circle"
  return ui.row({ key = "status", gap = 6, align = "center", justify = "center" }, {
    ui.glyph({ key = "status-glyph", name = glyph, size = 13, color = settings.muted_text_color }),
    ui.label({
      key = "status-text",
      text = noctalia.tr(key),
      fontSize = 12,
      color = settings.muted_text_color,
    }),
  })
end

-- ── Cards ───────────────────────────────────────────────────────────────────

local function header()
  return ui.row({ key = "header", gap = 8, align = "center" }, {
    ui.label({
      key = "header-title",
      text = settings.title,
      fontSize = 18,
      fontWeight = "light",
      color = settings.text_color,
      flexGrow = 1,
      maxLines = 1,
      maxWidth = math.max(80, settings.content_width - 56),
    }),
    ui.button({
      key = "header-settings",
      glyph = "settings",
      glyphSize = 16,
      variant = "ghost",
      controlSize = "sm",
      onClick = "openSettings",
    }),
  })
end

local function network_card(stats)
  if not settings.show_network then
    return nil
  end

  local net = type(stats.net) == "table" and stats.net or {}
  local down = tonumber(net.down_bps)
  local up = tonumber(net.up_bps)

  return surface("network-card", {
    section_header("network-header", "network", noctalia.tr("labels.network")),
    ui.row({ key = "network-down", gap = 8, align = "center" }, {
      ui.label({
        key = "network-down-label",
        text = noctalia.tr("labels.download"),
        fontSize = 11,
        color = settings.muted_text_color,
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.label({
        key = "network-down-value",
        text = down ~= nil and format.format_speed(down, units) or DASH,
        fontSize = 11,
        fontWeight = "bold",
        color = value_color(down ~= nil),
        maxLines = 1,
      }),
    }),
    ui.graph({
      key = "network-down-graph",
      values = normalize_history(down_history),
      color = settings.accent_color,
      lineWidth = settings.network_line_width,
      fillOpacity = settings.network_fill_opacity,
      height = settings.network_chart_height,
    }),
    ui.row({ key = "network-up", gap = 8, align = "center" }, {
      ui.label({
        key = "network-up-label",
        text = noctalia.tr("labels.upload"),
        fontSize = 11,
        color = settings.muted_text_color,
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.label({
        key = "network-up-value",
        text = up ~= nil and format.format_speed(up, units) or DASH,
        fontSize = 11,
        fontWeight = "bold",
        color = value_color(up ~= nil),
        maxLines = 1,
      }),
    }),
    ui.graph({
      key = "network-up-graph",
      values = normalize_history(up_history),
      color = settings.accent_color,
      lineWidth = settings.network_line_width,
      fillOpacity = settings.network_fill_opacity,
      height = math.max(12, math.floor(settings.network_chart_height * 0.65)),
    }),
  })
end

local function cpu_card(stats)
  if not settings.show_cpu then
    return nil
  end

  local cpu = type(stats.cpu) == "table" and stats.cpu or {}
  local usage = tonumber(cpu.usage)
  local temp = tonumber(cpu.temp_c)

  local children = {
    section_header("cpu-header", "cpu", noctalia.tr("labels.cpu")),
    usage_row("cpu-usage", usage, cpu_history, usage ~= nil),
    temp_row("cpu-temp", temp, temp ~= nil),
  }

  if settings.show_cpu_fan then
    local row = fan_row("cpu-fan", cpu.fan_rpm)
    if row then
      table.insert(children, row)
    end
  end

  return surface("cpu-card", children)
end

local function ram_card(stats)
  if not settings.show_ram then
    return nil
  end

  local ram = type(stats.ram) == "table" and stats.ram or {}
  local used = tonumber(ram.used_gb)
  local total = tonumber(ram.total_gb)
  local percent = tonumber(ram.pct)

  local summary = DASH
  if used ~= nil and total ~= nil then
    summary = string.format(
      "%s: %s %s / %s %s",
      noctalia.tr("labels.usage"),
      format.number(used, 1),
      units.gb,
      format.number(total, 0),
      units.gb
    )
  end

  return surface("ram-card", {
    section_header("ram-header", "server-2", noctalia.tr("labels.ram")),
    ui.row({ key = "ram-summary", gap = 8, align = "center" }, {
      ui.label({
        key = "ram-summary-label",
        text = summary,
        fontSize = 11,
        color = settings.muted_text_color,
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.label({
        key = "ram-pct",
        text = percent ~= nil and format.pct(percent) or DASH,
        width = 42,
        textAlign = "end",
        fontSize = 11,
        fontWeight = "bold",
        color = value_color(percent ~= nil),
        maxLines = 1,
      }),
    }),
    segmented("ram-bar", percent, settings.accent_color, percent ~= nil),
  })
end

local function details_button()
  if not settings.allow_gpu_details then
    return nil
  end
  return ui.button({
    key = "gpu-details-toggle",
    text = gpu_expanded and noctalia.tr("gpu.less") or noctalia.tr("gpu.more"),
    glyph = gpu_expanded and "chevron-up" or "chevron-down",
    glyphSize = 10,
    fontSize = 10,
    variant = "ghost",
    height = 22,
    onClick = "toggleGpuDetails",
  })
end

local function detail_cell(key, label, value)
  return ui.row({ key = key, gap = 4, align = "center", flexGrow = 1 }, {
    ui.label({
      key = key .. "-label",
      text = label,
      fontSize = 11,
      color = settings.muted_text_color,
      maxLines = 1,
    }),
    ui.label({
      key = key .. "-value",
      text = value,
      fontSize = 11,
      fontWeight = "bold",
      color = settings.text_color,
      maxLines = 1,
    }),
  })
end

local function detail_pair(key, left_label, left_value, right_label, right_value)
  return ui.row({ key = key, gap = 10, align = "center" }, {
    detail_cell(key .. "-left", left_label, left_value),
    detail_cell(key .. "-right", right_label, right_value),
  })
end

local function gpu_details(gpu)
  return {
    ui.separator({
      key = "gpu-details-divider",
      orientation = "horizontal",
      thickness = settings.divider_width,
      color = settings.divider_color,
    }),
    detail_pair(
      "gpu-details-1",
      noctalia.tr("gpu.junction"),
      fmt_temp(gpu.temp_junction),
      noctalia.tr("gpu.mem_temp"),
      fmt_temp(gpu.temp_mem)
    ),
    detail_pair(
      "gpu-details-2",
      noctalia.tr("gpu.clock"),
      fmt_mhz(gpu.clock_mhz),
      noctalia.tr("gpu.mem_clock"),
      fmt_mhz(gpu.mem_clock_mhz)
    ),
    detail_pair(
      "gpu-details-3",
      noctalia.tr("gpu.fan"),
      fmt_fan(gpu.fan_rpm, gpu.fan_pct),
      noctalia.tr("gpu.power"),
      fmt_power(gpu.power_w, gpu.power_cap_w)
    ),
  }
end

local function gpu_card(stats)
  if not settings.show_gpu then
    return nil
  end

  local gpu = type(stats.gpu) == "table" and stats.gpu or nil

  if gpu == nil then
    return surface("gpu-card", {
      section_header("gpu-header", "device-desktop", noctalia.tr("labels.gpu")),
      ui.label({
        key = "gpu-unavailable",
        text = noctalia.tr("status.no_gpu"),
        fontSize = 11,
        color = settings.muted_text_color,
      }),
    })
  end

  local usage = tonumber(gpu.usage)
  local temp = tonumber(gpu.temp_c)
  local children = {
    section_header("gpu-header", "device-desktop", noctalia.tr("labels.gpu"), details_button()),
    usage_row("gpu-usage", usage, gpu_history, usage ~= nil),
    temp_row("gpu-temp", temp, temp ~= nil),
  }

  if settings.allow_gpu_details and gpu_expanded then
    for _, node in ipairs(gpu_details(gpu)) do
      table.insert(children, node)
    end
  end

  return surface("gpu-card", children)
end

local function vram_card(stats)
  if not settings.show_vram then
    return nil
  end

  local gpu = type(stats.gpu) == "table" and stats.gpu or nil
  if gpu == nil then
    return surface("vram-card", {
      section_header("vram-header", "server", noctalia.tr("labels.vram")),
      ui.label({
        key = "vram-unavailable",
        text = noctalia.tr("status.no_gpu"),
        fontSize = 11,
        color = settings.muted_text_color,
      }),
    })
  end

  local used = tonumber(gpu.vram_used_gb)
  local total = tonumber(gpu.vram_total_gb)
  local percent = tonumber(gpu.vram_pct)

  local summary = DASH
  if used ~= nil and total ~= nil then
    summary = string.format(
      "%s: %s %s / %s %s",
      noctalia.tr("labels.usage"),
      format.number(used, 1),
      units.gb,
      format.number(total, 0),
      units.gb
    )
  end

  return surface("vram-card", {
    section_header("vram-header", "server", noctalia.tr("labels.vram")),
    ui.row({ key = "vram-summary", gap = 8, align = "center" }, {
      ui.label({
        key = "vram-summary-label",
        text = summary,
        fontSize = 11,
        color = settings.muted_text_color,
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.label({
        key = "vram-pct",
        text = percent ~= nil and format.pct(percent) or DASH,
        width = 42,
        textAlign = "end",
        fontSize = 11,
        fontWeight = "bold",
        color = value_color(percent ~= nil),
        maxLines = 1,
      }),
    }),
    segmented("vram-bar", percent, settings.accent_color, percent ~= nil),
  })
end

local function disks_card(stats)
  if not settings.show_disks then
    return nil
  end

  local list = type(stats.disks) == "table" and stats.disks or {}
  if #list == 0 then
    return nil
  end

  local children = {
    section_header("disks-header", "database", noctalia.tr("labels.disks")),
  }

  for index, disk in ipairs(list) do
    local key = "disk-" .. index
    local name = tostring(disk.name or disk.key or "?")
    local used = tonumber(disk.used_gb)
    local total = tonumber(disk.total_gb)
    local percent = tonumber(disk.pct)
    local temp = tonumber(disk.temp_c)
    local warning = percent ~= nil and percent >= settings.disk_warning

    local sizes = DASH
    if used ~= nil and total ~= nil then
      sizes = format.format_size_gb(used, units) .. " / " .. format.format_size_gb(total, units)
    end
    if temp ~= nil then
      sizes = sizes .. " · " .. string.format("%.0f %s", temp, units.celsius)
    end

    if index > 1 then
      table.insert(children, ui.separator({
        key = key .. "-divider",
        orientation = "horizontal",
        thickness = settings.divider_width,
        color = settings.divider_color,
      }))
    end

    local usage_children = {
      segmented(key .. "-bar", percent, warning and settings.critical_color or settings.accent_color, percent ~= nil),
    }
    if warning then
      table.insert(usage_children, ui.glyph({
        key = key .. "-alert",
        name = "alert-triangle",
        size = 12,
        color = settings.critical_color,
      }))
    end
    table.insert(usage_children, ui.label({
      key = key .. "-pct",
      text = percent ~= nil and format.pct(percent) or DASH,
      width = 42,
      textAlign = "end",
      fontSize = 11,
      fontWeight = "bold",
      color = warning and settings.critical_color or value_color(percent ~= nil),
      maxLines = 1,
    }))

    table.insert(children, ui.column({ key = key, gap = 4 }, {
      ui.row({ key = key .. "-summary", gap = 8, align = "center" }, {
        ui.label({
          key = key .. "-name",
          text = name,
          fontSize = 11,
          color = settings.muted_text_color,
          flexGrow = 1,
          maxLines = 1,
          maxWidth = math.max(80, settings.content_width - 2 * settings.card_padding - 170),
        }),
        ui.label({
          key = key .. "-size",
          text = sizes,
          fontSize = 11,
          fontWeight = "bold",
          color = warning and settings.critical_color or settings.text_color,
          maxLines = 1,
        }),
      }),
      ui.row({ key = key .. "-usage", gap = 8, align = "center" }, usage_children),
    }))
  end

  return surface("disks-card", children)
end

-- ── Render ──────────────────────────────────────────────────────────────────

local function render()
  local live = fresh()
  local stats = {}
  if live then
    stats = current
  elseif type(current) == "table" and type(current.gpu) == "table" then
    -- Keep the GPU/VRAM card shape while stale, but not its values: the card
    -- should show dashes rather than claim the machine has no GPU.
    stats = { gpu = { present = true } }
  end

  local cards = {}
  for _, build in ipairs({ cpu_card, gpu_card, vram_card, ram_card, disks_card, network_card }) do
    local card = build(stats)
    if card then
      table.insert(cards, card)
    end
  end

  local children = {}
  if settings.show_header then
    table.insert(children, header())
    table.insert(children, ui.separator({
      key = "header-divider",
      orientation = "horizontal",
      thickness = settings.divider_width,
      color = settings.divider_color,
    }))
  end

  table.insert(children, ui.column({
    key = "content",
    gap = settings.card_gap,
    opacity = live and 1 or 0.7,
  }, cards))

  local status_key = nil
  if not live then
    status_key = "status.waiting"
  elseif not has_any(stats) then
    status_key = "status.unavailable"
  elseif #cards == 0 then
    status_key = "status.no_sections"
  end
  if status_key then
    table.insert(children, status_row(status_key))
  end

  desktopWidget.render(ui.column({
    key = "card",
    width = settings.content_width,
    gap = settings.card_gap,
    -- With the host panel on, its background padding is the inset. With the
    -- panel off, add a small inset so the content does not sit on the wallpaper.
    padding = host_background and 0 or 6,
  }, children))
end

function openSettings()
  if type(noctalia.openSettings) == "function" then
    noctalia.openSettings()
  end
end

function toggleGpuDetails()
  gpu_expanded = not gpu_expanded
  render()
end

function update()
  render()
end

noctalia.setUpdateInterval(1000)

current = noctalia.state.get("stats")
if current ~= nil then
  ingest(current)
end
render()

noctalia.state.watch("stats", function(value)
  ingest(value)
  render()
end)
