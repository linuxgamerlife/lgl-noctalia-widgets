--!nonstrict
-- Declarative desktop card for AI Usage.
--
-- The headless "poller" service publishes a plain "ai_usage" table. This entry
-- only formats and renders it. Colours default to palette roles so they follow
-- the live Noctalia theme; every colour can still be overridden with a hex value
-- in the widget settings.

local accounts = require("./lib/accounts.luau")
local formatter = require("./lib/formatter.luau")
local view = require("./lib/view.luau")

local function clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

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
  return clamp(value, low, high)
end

-- Color settings accept a hex value or a bare palette role; opacity is a
-- separate setting and the alpha suffix is built here. Hex values get an
-- 8-digit alpha channel instead.
local function color_with_alpha(color, alpha)
  local opacity = clamp(alpha, 0, 1)
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
  title = cfg_text("title", "AI Usage"),
  show_header = cfg_bool("show_header", true),
  show_details = cfg_bool("show_details", true),
  show_reset_times = cfg_bool("show_reset_times", true),
  show_service_icon = cfg_bool("show_service_icon", true),
  content_width = math.floor(cfg_number("content_width", 432, 240, 900) + 0.5),
  bar_height = cfg_number("bar_height", 5, 2, 14),
  divider_width = cfg_number("divider_width", 1, 0.5, 4),
  divider_color = color_with_alpha(
    cfg_text("divider_color", "outline"),
    cfg_number("divider_opacity", 0.5, 0, 1)
  ),
  header_color = cfg_text("header_color", "primary"),
  header_glyph = cfg_text("header_glyph", "chart-bar"),
  normal_color = cfg_text("normal_color", "primary"),
  warning_color = cfg_text("warning_color", "tertiary"),
  critical_color = cfg_text("critical_color", "error"),
  unknown_color = cfg_text("unknown_color", "on_surface_variant"),
  track_color = color_with_alpha(
    cfg_text("track_color", "on_surface"),
    cfg_number("track_opacity", 0.14, 0, 1)
  ),
  text_color = cfg_text("text_color", "on_surface"),
  muted_text_color = cfg_text("muted_text_color", "on_surface_variant"),
  card_color = cfg_text("card_color", "surface_variant"),
  card_opacity = cfg_number("card_opacity", 0, 0, 1),
  card_radius = math.floor(cfg_number("card_radius", 12, 0, 32) + 0.5),
  card_border_color = cfg_text("card_border_color", "outline"),
  card_border_opacity = cfg_number("card_border_opacity", 0, 0, 1),
  card_border_width = cfg_number("card_border_width", 1, 0.5, 4),
}

-- Host-handled surface keys. The card draws no outer surface of its own; these
-- reads keep the lint contract and let the content inset follow the panel state.
local host_surface = {
  background = noctalia.getConfig("background"),
  background_color = noctalia.getConfig("background_color"),
  background_opacity = noctalia.getConfig("background_opacity"),
  background_radius = noctalia.getConfig("background_radius"),
  background_padding = noctalia.getConfig("background_padding"),
}

local style = {
  text_color = settings.text_color,
  muted_text_color = settings.muted_text_color,
  divider_color = settings.divider_color,
  divider_width = settings.divider_width,
  bar_height = settings.bar_height,
  track_color = settings.track_color,
  normal_color = settings.normal_color,
  warning_color = settings.warning_color,
  critical_color = settings.critical_color,
  unknown_color = settings.unknown_color,
  card_fill = settings.card_opacity > 0 and color_with_alpha(settings.card_color, settings.card_opacity) or nil,
  card_border = settings.card_border_opacity > 0
      and color_with_alpha(settings.card_border_color, settings.card_border_opacity)
    or nil,
  card_radius = settings.card_radius,
  card_border_width = settings.card_border_width,
  show_reset_times = settings.show_reset_times,
  show_service_icon = settings.show_service_icon,
}

local refreshSeconds = accounts.refreshSeconds(noctalia.getConfig("refresh_seconds"))
local current = noctalia.state.get("ai_usage")

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function refreshSeq()
  local value = tonumber(noctalia.state.get("ai_usage_refresh_seq")) or 0
  noctalia.state.set("ai_usage_refresh_seq", value + 1)
end

local function openPanel(add)
  noctalia.state.set("ai_usage_open_add", add == true)
  noctalia.togglePanel("lukk17/ai-usage:panel")
end

local function isStale()
  if type(current) ~= "table" or type(current.ts) ~= "number" then
    return true
  end
  local threshold = math.max(180, refreshSeconds * 3)
  return os.time() - current.ts > threshold
end

local function header(entries)
  local count = #(entries or {})
  return ui.row({ key = "header", gap = 12, align = "center" }, {
    ui.column({
      key = "header-badge",
      width = 34,
      height = 34,
      radius = 17,
      fill = "on_surface/0.08",
      border = settings.header_color,
      borderWidth = 1.5,
      align = "center",
      justify = "center",
    }, {
      ui.glyph({ key = "header-glyph", name = settings.header_glyph, size = 20, color = settings.header_color }),
    }),
    ui.column({ key = "header-titles", gap = 0, flexGrow = 1 }, {
      ui.label({
        key = "header-title",
        text = settings.title,
        fontSize = 18,
        fontWeight = "semibold",
        color = settings.text_color,
        maxLines = 1,
        maxWidth = math.max(80, settings.content_width - 150),
      }),
      ui.label({
        key = "header-subtitle",
        text = tr("status.accounts", "{n} accounts", { n = count }),
        fontSize = 11,
        color = settings.muted_text_color,
        maxLines = 1,
      }),
    }),
    ui.button({
      key = "header-refresh",
      glyph = "refresh",
      glyphSize = 16,
      variant = "ghost",
      controlSize = "sm",
      onClick = "onRefresh",
    }),
    ui.button({
      key = "header-settings",
      glyph = "settings",
      glyphSize = 16,
      variant = "ghost",
      controlSize = "sm",
      onClick = "onSettings",
    }),
  })
end

local function render()
  local now = os.time() * 1000
  local children = {}

  if settings.show_header then
    table.insert(children, header(type(current) == "table" and current.accounts or {}))
    table.insert(children, view.divider(style, "header-divider"))
  end

  if isStale() then
    table.insert(children, view.waitingCard("onRefresh", { style = style }))
  else
    local model = formatter.buildViewModel(current.accounts or {}, now)
    if not model.hasAccounts then
      table.insert(children, view.emptyCard("onAddAccount", { style = style }))
    else
      for index, section in ipairs(model.sections) do
        if index > 1 then
          table.insert(children, view.divider(style, "account-divider-" .. section.key))
        end
        table.insert(children, view.card(section, {
          show_details = settings.show_details,
          style = style,
        }))
      end
      if model.walletLocked then
        table.insert(children, ui.label({
          key = "wallet-hint",
          text = tr("wallet.hint", "The keyring is locked or unavailable. Unlock it with your keyring app, then refresh."),
          fontSize = 11,
          color = settings.warning_color,
          maxLines = 3,
        }))
      end
    end
  end

  desktopWidget.render(ui.column({
    key = "card",
    width = settings.content_width,
    gap = 10,
    align = "stretch",
    padding = host_surface.background == false and 6 or 0,
  }, children))
end

function onRefresh()
  refreshSeq()
end

function onSettings()
  openPanel(false)
end

function onAddAccount()
  openPanel(true)
end

function update()
  render()
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("ai_usage", function(value)
  current = value
  render()
end)
render()
