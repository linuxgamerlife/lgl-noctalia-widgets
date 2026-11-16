--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Declarative desktop card for SteamDB Stats.
--
-- The host panel is the outer surface. The card uses the same inner surface,
-- spacing and ui.graph metrics as Modern SysMonitor Plus, so the two cards can
-- sit in the same desktop column and line up.

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
  show_card_settings = cfg_bool("show_card_settings", false),
  show_styling = cfg_bool("show_styling", false),
  show_scaling = cfg_bool("show_scaling", false),
  show_sections = cfg_bool("show_sections", false),

  hide_when_idle = cfg_bool("hide_when_idle", false),
  show_title = cfg_bool("show_title", true),
  show_settings_button = cfg_bool("show_settings_button", true),
  show_cover = cfg_bool("show_cover", true),
  show_current = cfg_bool("show_current", true),
  show_peak_24h = cfg_bool("show_peak_24h", true),
  show_peak_all_time = cfg_bool("show_peak_all_time", true),
  show_graph = cfg_bool("show_graph", true),
  show_attribution = cfg_bool("show_attribution", true),

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
  graph_color = cfg_text("graph_color", "primary"),

  graph_height = math.floor(cfg_number("graph_height", 32, 16, 80) + 0.5),
  graph_line_width = cfg_number("graph_line_width", 1.5, 0.5, 4),
  graph_fill_opacity = cfg_number("graph_fill_opacity", 0.15, 0, 1),
  text_scale = cfg_number("text_scale", 1, 0.5, 2),
}

local detect_interval = math.floor(cfg_number("detect_interval", 3, 2, 15) + 0.5)
local stale_after = math.max(10, detect_interval * 3)

local function text_size(value)
  return math.max(1, math.floor(value * settings.text_scale + 0.5))
end

local host_surface = {
  background = noctalia.getConfig("background"),
  background_color = noctalia.getConfig("background_color"),
  background_opacity = noctalia.getConfig("background_opacity"),
  background_radius = noctalia.getConfig("background_radius"),
  background_padding = noctalia.getConfig("background_padding"),
}
local host_background = host_surface.background ~= false

local DASH = noctalia.tr("labels.unknown")
local card_fill = color_with_alpha(settings.card_fill_color, settings.card_fill_opacity)

local current = nil
local last_key = nil

local function fresh()
  if type(current) ~= "table" then
    return false
  end
  local timestamp = tonumber(current.ts)
  return timestamp ~= nil and os.time() - timestamp <= stale_after
end

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

local function fmt_number(value)
  local text = format.thousands(value)
  return text or DASH
end

local function game_of(model)
  if type(model) ~= "table" or type(model.game) ~= "table" then
    return nil
  end
  return model.game
end

local function stats_of(model)
  if type(model) ~= "table" or type(model.stats) ~= "table" then
    return {}
  end
  return model.stats
end

local function settings_button()
  if not settings.show_settings_button then
    return nil
  end
  return ui.button({
    key = "header-settings",
    glyph = "settings",
    glyphSize = text_size(16),
    variant = "ghost",
    controlSize = "sm",
    onClick = "openSettings",
  })
end

local function header(game)
  local children = {}

  if settings.show_cover then
    if type(game.header) == "string" and game.header ~= "" then
      -- Steam headers arrive in several aspect ratios (SteamCharts 184x69,
      -- Steam store 460x215). "contain" shows the whole image instead of
      -- cropping the logo at the sides.
      table.insert(children, ui.image({
        key = "game-cover",
        path = game.header,
        width = 92,
        height = 43,
        fit = "contain",
        radius = 4,
      }))
    else
      table.insert(children, ui.column({
        key = "game-cover-placeholder",
        width = 92,
        height = 43,
        radius = 4,
        fill = color_with_alpha(settings.accent_color, 0.12),
        align = "center",
        justify = "center",
      }, {
        ui.glyph({
          key = "game-cover-glyph",
          name = "brand-steam",
          size = text_size(22),
          color = settings.accent_color,
        }),
      }))
    end
  end

  table.insert(children, ui.column({
    key = "game-title",
    gap = 1,
    flexGrow = 1,
  }, {
    ui.label({
      key = "game-name",
      text = tostring(game.name or ""),
      fontSize = text_size(14),
      fontWeight = "bold",
      color = settings.text_color,
      maxLines = 1,
      maxWidth = math.max(80, settings.content_width - 2 * settings.card_padding - (settings.show_cover and 134 or 42)),
    }),
    ui.label({
      key = "now-playing",
      text = noctalia.tr("labels.now_playing"),
      fontSize = text_size(9),
      color = settings.muted_text_color,
      maxLines = 1,
    }),
  }))

  local button = settings_button()
  if button ~= nil then
    table.insert(children, button)
  end
  return ui.row({ key = "header", gap = 8, align = "center" }, children)
end

local function stat_cell(key, value, label, color)
  return ui.column({
    key = key,
    gap = 2,
    flexGrow = 1,
    align = "center",
  }, {
    ui.label({
      key = key .. "-value",
      text = value,
      fontSize = text_size(18),
      fontWeight = "bold",
      color = color,
      maxLines = 1,
      textAlign = "center",
    }),
    ui.label({
      key = key .. "-label",
      text = label,
      fontSize = text_size(9),
      color = settings.muted_text_color,
      maxLines = 1,
      textAlign = "center",
    }),
  })
end

local function stats_row(model)
  local stats = stats_of(model)
  local children = {}

  if settings.show_current then
    table.insert(children, stat_cell(
      "stat-current",
      fmt_number(stats.current),
      noctalia.tr("labels.playing_now"),
      settings.accent_color
    ))
  end
  if settings.show_peak_24h then
    table.insert(children, stat_cell(
      "stat-24h",
      fmt_number(stats.peak_24h),
      noctalia.tr("labels.peak_24h"),
      settings.text_color
    ))
  end
  if settings.show_peak_all_time then
    local label = noctalia.tr("labels.peak_all_time")
    local age = format.age(stats.peak_at, os.time())
    if age ~= nil then
      label = label .. " · " .. age
    end
    table.insert(children, stat_cell(
      "stat-all-time",
      fmt_number(stats.peak_all_time),
      label,
      settings.text_color
    ))
  end

  if #children == 0 then
    return nil
  end
  return ui.row({ key = "stats", gap = 6, align = "center" }, children)
end

local function graph(model)
  if not settings.show_graph then
    return nil
  end

  local history = stats_of(model).history
  if type(history) ~= "table" or #history < 2 then
    return ui.column({
      key = "graph-empty",
      height = settings.graph_height,
      align = "center",
      justify = "center",
    }, {
      ui.label({
        key = "graph-empty-label",
        text = noctalia.tr("labels.no_history"),
        fontSize = text_size(10),
        color = settings.muted_text_color,
        maxLines = 1,
      }),
    })
  end

  local values = {}
  for index = 1, #history do
    values[index] = format.clamp(tonumber(history[index]) or 0, 0, 1)
  end

  return ui.graph({
    key = "players-graph",
    values = values,
    color = settings.graph_color,
    lineWidth = settings.graph_line_width,
    fillOpacity = settings.graph_fill_opacity,
    height = settings.graph_height,
  })
end

local function footer(model)
  if not settings.show_attribution then
    return nil
  end

  local stats = stats_of(model)
  local text = noctalia.tr("labels.source")
  local age = format.since(stats.chart_at, os.time())
  if age ~= nil then
    text = text .. " · " .. age
  end

  return ui.label({
    key = "attribution",
    text = text,
    fontSize = text_size(9),
    color = settings.muted_text_color,
    maxLines = 1,
    textAlign = "end",
  })
end

local function status_text(model)
  local status = type(model) == "table" and model.status or nil
  if status == "no_steam" then
    return noctalia.tr("status.no_steam")
  elseif status == "loading" then
    return noctalia.tr("status.loading")
  elseif status == "partial" then
    return noctalia.tr("status.partial")
  elseif status == "error" then
    return noctalia.tr("status.error")
  end
  return noctalia.tr("status.idle")
end

local function idle_card(model)
  local reason = status_text(model)
  local text = {}
  if settings.show_title then
    text[#text + 1] = ui.label({
      key = "idle-name",
      text = settings.title,
      fontSize = text_size(14),
      fontWeight = "bold",
      color = settings.text_color,
      maxLines = 1,
    })
  end
  text[#text + 1] = ui.label({
    key = "idle-reason",
    text = reason,
    fontSize = text_size(settings.show_title and 10 or 12),
    color = settings.muted_text_color,
    maxLines = 1,
  })

  local row = {
    ui.glyph({
      key = "idle-glyph",
      name = "brand-steam",
      size = text_size(20),
      color = settings.accent_color,
    }),
    ui.column({ key = "idle-title", gap = 1, flexGrow = 1 }, text),
  }
  local button = settings_button()
  if button ~= nil then
    row[#row + 1] = button
  end

  return surface("steam-card", {
    ui.row({ key = "idle-header", gap = 8, align = "center" }, row),
  })
end

local function live_card(model)
  local game = game_of(model)
  local children = {
    header(game),
    stats_row(model),
    graph(model),
    footer(model),
  }

  local filtered = {}
  for _, node in ipairs(children) do
    if node ~= nil then
      filtered[#filtered + 1] = node
    end
  end

  return surface("steam-card", filtered)
end

local function render()
  local model = current
  local live = fresh()

  local key = table.concat({
    tostring(model and model.seq or -1),
    tostring(model and model.ts or 0),
    tostring(model and model.status or ""),
    tostring(model and model.game and model.game.appid or ""),
    tostring(model and model.game and model.game.header or ""),
    tostring(model and model.stats and model.stats.current or ""),
    tostring(model and model.stats and model.stats.peak_24h or ""),
    tostring(model and model.stats and model.stats.peak_all_time or ""),
    tostring(settings.content_width),
    tostring(settings.show_cover),
    tostring(settings.show_graph),
    tostring(settings.hide_when_idle),
    tostring(settings.show_title),
    tostring(settings.show_settings_button),
  }, "|")

  if key == last_key then
    return
  end
  last_key = key

  local game = game_of(model)
  if game == nil and settings.hide_when_idle then
    desktopWidget.render(ui.column({
      key = "steam-hidden",
      width = 0,
      height = 0,
      fill = "#00000000",
    }, {}))
    return
  end

  local card
  if game == nil then
    card = idle_card(model)
  else
    card = live_card(model)
  end

  desktopWidget.render(ui.column({
    key = "root",
    width = settings.content_width,
    gap = settings.card_gap,
    -- Host panel on: its padding is the inset. Host panel off: keep the card
    -- off the wallpaper with a small inset, like Modern SysMonitor Plus.
    padding = host_background and 0 or 6,
    opacity = live and 1 or 0.78,
  }, {
    card,
  }))
end

function openSettings()
  if type(noctalia.openSettings) == "function" then
    noctalia.openSettings()
  end
end

function update()
  render()
end

current = noctalia.state.get("steam_stats")
render()

noctalia.setUpdateInterval(1000)
noctalia.state.watch("steam_stats", function(value)
  current = value
  render()
end)
