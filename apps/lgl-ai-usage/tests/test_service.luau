-- Service publishing and reload tests with a mocked curl/local transport.

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

local accounts = {
  {
    version = 1,
    accounts = {
      { id = "a111111111111", service = "minimax", name = "work" },
      { id = "a222222222222", service = "claude", name = "personal", org = "org-a" },
    },
  },
}

local function commandText(command)
  if type(command) == "table" then
    return table.concat(command, " ")
  end
  return command
end

local function runAsync(command, callback, _timeout, context)
  local text = commandText(command)
  if text:find("plan-usage-history.json", 1, true) then
    local content = mock.jsonEncode(history)
    callback({ exitCode = 0, stdout = "found " .. #content .. "\n" .. content, stderr = "", timedOut = false })
    return true
  end
  if text:find("curl --disable", 1, true) then
    local boundary = text:match("(aiu%x+)")
    if context.failLookup then
      callback({ exitCode = 0, stdout = boundary .. " lookup 127\n", stderr = "", timedOut = false })
      return true
    end
    local body = mock.jsonEncode(minimaxBody)
    local stdout = boundary .. " begin remains\n" .. body .. "\n" .. boundary
      .. " end 200 \n\n" .. boundary .. " curl 0\n"
    callback({ exitCode = 0, stdout = stdout, stderr = "", timedOut = false })
    return true
  end
  callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
  return true
end

local realTime = os.time
local fakeNow = 1760000000
os.time = function(value)
  if value ~= nil then
    return realTime(value)
  end
  return fakeNow
end

local context = mock.new({
  config = { refresh_seconds = "30" },
  files = {
    [ACCOUNTS_PATH] = mock.jsonEncode(accounts[1]),
  },
  runAsync = runAsync,
})

local service = require("./lib/service.luau")
service.start()

local published = context.state.ai_usage
assert(published ~= nil, "service did not publish")
assert(published.has_accounts == true, "accounts missing")
assert(#published.accounts == 2, "expected two entries, got " .. #published.accounts)

local byService = {}
for _, entry in ipairs(published.accounts) do
  byService[entry.providerId] = entry
end
assert(byService.minimax ~= nil, "minimax entry missing")
assert(byService.minimax.usage ~= nil, "minimax usage missing")
assert(#byService.minimax.usage.windows >= 1, "minimax windows missing")
assert(byService.claude ~= nil, "claude entry missing")
assert(byService.claude.usage ~= nil, "claude usage missing")

-- Account list changes are picked up through the shared state key.
fakeNow = fakeNow + 31
accounts[1].accounts = {
  { id = "a111111111111", service = "minimax", name = "work" },
}
context.files[ACCOUNTS_PATH] = mock.jsonEncode(accounts[1])
noctalia.state.set("ai_usage_accounts_rev", 1)
published = context.state.ai_usage
assert(#published.accounts == 1, "reload did not remove the deleted account")
assert(published.accounts[1].providerId == "minimax", "reload kept the wrong account")

-- A missing tool is published as a per-account error and a global hint.
fakeNow = fakeNow + 31
context.failLookup = true
context.files[ACCOUNTS_PATH] = mock.jsonEncode({ version = 1, accounts = {
  { id = "a111111111111", service = "minimax", name = "work" },
} })
noctalia.state.set("ai_usage_accounts_rev", 2)
published = context.state.ai_usage
assert(published.accounts[1].error ~= nil, "tool failure not published")
assert(published.accounts[1].error.reason == "tool_missing", "wrong tool failure reason")
assert(published.tools_missing == true, "tools_missing hint missing")

-- A refresh request is accepted and does not crash.
noctalia.state.set("ai_usage_refresh_seq", 1)

-- Stale detection is delegated to the widget, but the payload carries a clock.
assert(type(published.ts) == "number", "timestamp missing")
assert(published.refresh_seconds == 30, "refresh seconds missing")

service.stop()
os.time = realTime
print("SERVICE TEST OK")
