-- Service -> card integration: the service publishes, the card renders it.

local mock = dofile("tests/support/mock.luau")

local DATA_DIR = "/tmp/opencode/ai-usage-data"
local ACCOUNTS_PATH = DATA_DIR .. "/accounts.json"

local minimaxBody = {
  base_resp = { status_code = 0 },
  model_remains = {
    {
      model_name = "MiniMax-M2",
      start_time = 1760000000000,
      end_time = 1760018000000,
      remains_time = 3600000,
      current_interval_total_count = 100,
      current_interval_usage_count = 25,
      current_weekly_total_count = 0,
      current_weekly_usage_count = 0,
      weekly_remains_time = 86400000,
    },
  },
}

local history = {
  version = 2,
  samples = {
    { org = "org-a", t = 1760000000000, u = { fh = 40, sd = 10 } },
  },
}

local function runAsync(command, callback)
  if command:find("plan-usage-history.json", 1, true) then
    local text = mock.jsonEncode(history)
    callback({ exitCode = 0, stdout = "found " .. #text .. "\n" .. text, stderr = "", timedOut = false })
    return true
  end
  if command:find("curl --disable", 1, true) then
    local boundary = command:match("(aiu%x+)")
    local body = mock.jsonEncode(minimaxBody)
    callback({
      exitCode = 0,
      stdout = boundary .. " begin remains\n" .. body .. "\n" .. boundary .. " end 200 \n\n" .. boundary .. " curl 0\n",
      stderr = "",
      timedOut = false,
    })
    return true
  end
  callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
  return true
end

local context = mock.new({
  config = {
    refresh_seconds = "30",
    show_header = true,
    show_details = true,
    dense = false,
    background_opacity = 0.85,
  },
  files = {
    [ACCOUNTS_PATH] = mock.jsonEncode({
      version = 1,
      accounts = {
        { id = "a111111111111", service = "minimax", name = "work" },
        { id = "a222222222222", service = "claude", name = "personal", org = "org-a" },
      },
    }),
  },
  runAsync = runAsync,
})

local service = require("./lib/service.luau")
service.start()
mock.loadEntry("card.luau")

local tree = context.desktopTree
assert(tree ~= nil, "card did not render after service start")
assert(mock.find(tree, "card-a111111111111") ~= nil, "MiniMax card missing")
assert(mock.find(tree, "card-a222222222222") ~= nil, "Claude card missing")
assert(mock.find(tree, "card-window-a111111111111-1") ~= nil, "MiniMax bar missing")
assert(mock.findText(tree, "40%") ~= nil, "Claude percentage missing")

-- The widget follows a later state update.
context.state.ai_usage = {
  ts = os.time(),
  refresh_seconds = 30,
  accounts = {
    {
      key = "a333",
      providerId = "requesty",
      title = "Requesty",
      account = { id = "a333", name = "team" },
      usage = {
        windows = {},
        amounts = { { label = "spent_this_month", name = "", value = 12.5, limit = 100, noLimit = false, currency = "usd" } },
        counts = {},
        texts = {},
      },
      isLoading = false,
    },
  },
}
noctalia.state.set("ai_usage", context.state.ai_usage)
tree = context.desktopTree
assert(mock.find(tree, "card-a333") ~= nil, "widget did not follow the state update")
assert(mock.findText(tree, "$12.50 of $100.00") ~= nil, "amount row missing")

service.stop()
print("INTEGRATION TEST OK")
