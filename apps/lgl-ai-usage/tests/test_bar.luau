-- Bar widget rendering tests.

local mock = dofile("tests/support/mock.luau")
local now = os.time()

local context = mock.new({
  config = {
    show_percent = true,
    glyph = "chart-bar",
    mode = "worst",
    refresh_seconds = "30",
  },
})

context.state.ai_usage = {
  ts = now,
  accounts = {
    {
      key = "a1",
      providerId = "minimax",
      title = "MiniMax",
      account = { name = "work" },
      usage = {
        windows = {
          { period = "five_hour", usedPercent = 92, canBeMain = true },
        },
      },
      isLoading = false,
    },
  },
}

mock.loadEntry("bar.luau")
assert(context.barTree ~= nil, "bar did not render")
assert(mock.findText(context.barTree, "92%") ~= nil, "worst percent missing")
assert(mock.find(context.barTree, "bar-glyph") ~= nil, "glyph missing")
assert(context.barTree.type == "row", "horizontal bar should be a row")

onClick()
assert(context.panels[#context.panels] == "lukk17/ai-usage:panel", "bar click did not open panel")

-- Error count mode -----------------------------------------------------------
context.config.mode = "errors"
context.state.ai_usage = {
  ts = now,
  accounts = {
    { key = "a1", providerId = "openai", title = "OpenAI", account = { name = "x" }, usage = nil, error = { kind = "key_rejected", reason = "http_status" }, isLoading = false },
  },
}
mock.loadEntry("bar.luau")
assert(mock.findText(context.barTree, "1") ~= nil, "error count missing")

-- Account count mode ---------------------------------------------------------
context.config.mode = "count"
context.config.show_percent = true
mock.loadEntry("bar.luau")
assert(mock.findText(context.barTree, "1") ~= nil, "account count missing")

-- Stale state shows only the glyph -------------------------------------------
context.config.mode = "worst"
context.state.ai_usage = { ts = now - 10000, accounts = { { key = "a1", providerId = "m", title = "M", account = { name = "x" }, usage = { windows = { { period = "five_hour", usedPercent = 50 } } }, isLoading = false } } }
mock.loadEntry("bar.luau")
assert(mock.find(context.barTree, "bar-value") == nil, "stale bar should hide the value")

print("BAR TEST OK")
