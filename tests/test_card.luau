-- Desktop card rendering tests.

local mock = dofile("tests/support/mock.luau")

local now = os.time()
local function entry(overrides)
  local base = {
    key = "a1",
    providerId = "minimax",
    title = "MiniMax",
    account = { id = "a1", service = "minimax", name = "work" },
    usage = {
      windows = {
        { period = "five_hour", count = nil, name = "", usedPercent = 92, resetsAt = (now + 3600) * 1000, validUntil = nil, estimated = false, canBeMain = true },
      },
      amounts = {
        { label = "balance", name = "", value = -1.5, limit = nil, noLimit = false, currency = "usd", problem = nil },
      },
      counts = {
        { label = "input_tokens_this_month", value = 1500 },
      },
      texts = {},
    },
    error = nil,
    isLoading = false,
  }
  for key, value in pairs(overrides or {}) do
    base[key] = value
  end
  return base
end

local context = mock.new({
  config = {
    title = "Lab AI",
    show_header = true,
    show_details = true,
    show_reset_times = true,
    show_service_icon = true,
    content_width = 500,
    bar_height = 8,
    divider_width = 2,
    divider_color = "#8899aa",
    divider_opacity = 0.5,
    header_color = "#aabbcc",
    header_glyph = "chart-bar",
    normal_color = "#8ab4f8",
    warning_color = "tertiary",
    critical_color = "#ff0000",
    unknown_color = "on_surface_variant",
    track_color = "on_surface",
    track_opacity = 0.14,
    text_color = "#abcdef",
    muted_text_color = "#123456",
    card_color = "surface_variant",
    card_opacity = 0.0,
    card_radius = 12,
    card_border_color = "outline",
    card_border_opacity = 0.0,
    card_border_width = 1,
    background = true,
    background_color = "surface",
    background_opacity = 0.8,
    background_radius = 12,
    background_padding = 10,
    refresh_seconds = "30",
  },
  files = {},
})

context.state.ai_usage = {
  ts = now,
  refresh_seconds = 30,
  accounts = {
    entry(),
    entry({
      key = "a2",
      providerId = "openai",
      title = "OpenAI API",
      account = { id = "a2", service = "openai", name = "team" },
      usage = nil,
      error = { kind = "key_rejected", reason = "http_status", params = { status = 401 } },
    }),
  },
}

mock.loadEntry("card.luau")

local tree = context.desktopTree
assert(tree ~= nil, "card did not render")
assert(tree.type == "column", "card root is not a column")
assert(tree.props.width == 500, "content width")
assert(mock.find(tree, "header") ~= nil, "header missing")
assert(mock.find(tree, "header-title").props.text == "Lab AI", "title missing")
assert(mock.find(tree, "header-glyph").props.color == "#aabbcc", "header colour")
assert(mock.find(tree, "header-divider").props.thickness == 2, "divider width")
assert(mock.find(tree, "header-divider").props.color == "#8899aa80", "divider colour")
assert(mock.find(tree, "card-a1") ~= nil, "first card missing")
assert(mock.find(tree, "card-a2") ~= nil, "second card missing")
assert(mock.find(tree, "card-window-a1-1") ~= nil, "bar missing")
assert(mock.find(tree, "card-window-a1-1-bar").props.height == 8, "bar height")
assert(mock.find(tree, "card-window-a1-1-bar").props.fill == "#ff0000", "critical bar colour")
assert(mock.find(tree, "card-a1").props.fill == nil, "default section should be divider-only")
assert(mock.find(tree, "card-error-a2") ~= nil, "error text missing")
assert(mock.findText(tree, "92%") ~= nil, "percent text missing")
assert(mock.findText(tree, "-$1.50") ~= nil, "balance text missing")
assert(mock.findText(tree, "1.5k") ~= nil, "token text missing")

-- The refresh button asks the service; the add button opens the panel with the
-- add form flag.
local refresh = mock.find(tree, "header-refresh")
assert(refresh ~= nil, "refresh button missing")
mock.click(refresh)
assert(context.state.ai_usage_refresh_seq == 1, "refresh request not published")

-- Empty state ----------------------------------------------------------------
context.state.ai_usage = {
  ts = now,
  refresh_seconds = 30,
  accounts = {},
}
mock.loadEntry("card.luau")
tree = context.desktopTree
assert(mock.find(tree, "empty-card") ~= nil, "empty state missing")
local add = mock.find(tree, "empty-add")
assert(add ~= nil, "empty add button missing")
mock.click(add)
assert(context.state.ai_usage_open_add == true, "add flag missing")
assert(context.panels[#context.panels] == "lukk17/ai-usage:panel", "panel not opened")

-- Stale state ----------------------------------------------------------------
context.state.ai_usage = {
  ts = now - 10000,
  refresh_seconds = 30,
  accounts = { entry() },
}
mock.loadEntry("card.luau")
tree = context.desktopTree
assert(mock.find(tree, "waiting-card") ~= nil, "stale state missing")

-- No header when the setting is off -----------------------------------------
context.config.show_header = false
mock.loadEntry("card.luau")
tree = context.desktopTree
assert(mock.find(tree, "header") == nil, "header should be hidden")

print("CARD TEST OK")
