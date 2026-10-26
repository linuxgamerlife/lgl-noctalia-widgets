--!nonstrict
-- Full AI usage cards on the desktop. The service publishes `ai_usage`; this
-- entry only formats and renders it.

local formatter = require("./lib/formatter.luau")
local view = require("./lib/view.luau")
local accounts = require("./lib/accounts.luau")

local showHeader = noctalia.getConfig("show_header")
if showHeader == nil then
  showHeader = true
end
local showDetails = noctalia.getConfig("show_details")
if showDetails == nil then
  showDetails = true
end
local dense = noctalia.getConfig("dense") == true
-- The host draws the outer desktop-widget panel and owns the outer opacity
-- slider. The plugin only draws the contents and the account cards.
local showOuterPanel = noctalia.getConfig("background")
if showOuterPanel == nil then
  showOuterPanel = true
end
local backgroundOpacity = tonumber(noctalia.getConfig("background_opacity"))
if backgroundOpacity == nil then
  backgroundOpacity = 0.85
end
backgroundOpacity = math.max(0, math.min(1, backgroundOpacity))
local cardOpacity = tonumber(noctalia.getConfig("card_opacity"))
if cardOpacity == nil then
  cardOpacity = 0.42
end
cardOpacity = math.max(0, math.min(1, cardOpacity))
local cardWidth = tonumber(noctalia.getConfig("card_width"))
if cardWidth == nil then
  cardWidth = 360
end
cardWidth = math.max(220, math.min(900, cardWidth))
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

local function summary(entries)
  local count = #(entries or {})
  return tr("status.accounts", "{n} accounts", { n = count })
end

local function header(entries)
  local buttons = {
    ui.button({
      key = "header-refresh",
      text = tr("ui.refresh", "Refresh"),
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      onClick = "onRefresh",
    }),
    ui.button({
      key = "header-settings",
      glyph = "settings",
      variant = "ghost",
      onClick = "onSettings",
    }),
  }
  local titleRow = ui.row({ key = "header-title-row", gap = 8, align = "center" }, {
    ui.glyph({ key = "header-glyph", name = "chart-bar", size = 18, color = "primary" }),
    ui.column({ key = "header-titles", gap = 0 }, {
      ui.label({
        key = "header-title",
        text = tr("app.title", "AI Usage"),
        fontSize = dense and 14 or 16,
        fontWeight = "bold",
        color = "on_surface",
      }),
      ui.label({
        key = "header-subtitle",
        text = summary(entries),
        fontSize = 10,
        color = "on_surface_variant",
      }),
    }),
  })
  return ui.row({
    key = "header",
    gap = 8,
    align = "center",
    justify = "space_between",
  }, {
    titleRow,
    ui.row({ key = "header-buttons", gap = 4, align = "center" }, buttons),
  })
end

local function render()
  local now = os.time() * 1000
  local children = {}
  if showHeader then
    table.insert(children, header(type(current) == "table" and current.accounts or {}))
  end

  if isStale() then
    table.insert(children, view.waitingCard("onRefresh", { card_opacity = cardOpacity }))
  else
    local model = formatter.buildViewModel(current.accounts or {}, now)
    if not model.hasAccounts then
      table.insert(children, view.emptyCard("onAddAccount", { card_opacity = cardOpacity }))
    else
      for _, section in ipairs(model.sections) do
        table.insert(children, view.card(section, {
          dense = dense,
          show_details = showDetails,
          card_opacity = cardOpacity,
        }))
      end
      if model.walletLocked then
        table.insert(children, ui.label({
          key = "wallet-hint",
          text = tr(
            "wallet.hint",
            "The keyring is locked or unavailable. Unlock it with your keyring app, then refresh."
          ),
          fontSize = 10,
          color = "tertiary",
          maxLines = 3,
        }))
      end
    end
  end

  -- No fill or border here: the host panel behind the content is the outer
  -- background, so its opacity slider updates live. When the host panel is
  -- disabled the content sits directly on the wallpaper.
  local container = {
    key = "ai-usage",
    width = cardWidth,
    gap = dense and 6 or 10,
    padding = showOuterPanel and (dense and 8 or 14) or 0,
    radius = dense and 10 or 16,
  }
  desktopWidget.render(ui.column(container, children))
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

noctalia.setUpdateInterval(15000)
noctalia.state.watch("ai_usage", function(value)
  current = value
  render()
end)
render()
