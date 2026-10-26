-- Provider parsing tests. Run with: luajit tests/test_providers.luau ai-usage

local mock = dofile("tests/support/mock.luau")
mock.new({})

local registry = require("./providers/init.luau")
local formatter = require("./lib/formatter.luau")

local now = 1760000000000

local function reply(status, body)
  return {
    kind = "response",
    status = status,
    body = body,
    header = function()
      return nil
    end,
  }
end

local function results(values)
  local out = {}
  for id, body in pairs(values) do
    out[id] = { reply = reply(200, type(body) == "string" and body or mock.jsonEncode(body)), error = nil }
  end
  return out
end

local function windows(usageValue)
  local out = {}
  for _, item in ipairs(usageValue.windows) do
    out[item.period] = item
  end
  return out
end

-- Claude desktop history -----------------------------------------------------
local claude = registry.find("claude")
local history = {
  version = 2,
  samples = {
    { org = "org-a", t = now - 3600000, u = { fh = 10, sd = 5 } },
    { org = "org-a", t = now - 1800000, u = { fh = 40, sd = 7 } },
  },
}
local claudeResult = claude.interpret({ found = true, text = mock.jsonEncode(history) }, { org = "org-a" }, now)
assert(claudeResult.ok, "claude parse failed")
local claudeWindows = windows(claudeResult.usage)
assert(math.floor(claudeWindows.five_hour.usedPercent) == 40, "claude 5hr percent")
assert(math.floor(claudeWindows.weekly.usedPercent) == 7, "claude weekly percent")
assert(claudeWindows.five_hour.estimated == true, "claude reset is estimated")

local missingOrg = claude.interpret({ found = true, text = mock.jsonEncode(history) }, { org = "nope" }, now)
assert(not missingOrg.ok and missingOrg.error.reason == "claude_org_missing", "claude missing org")

-- ChatGPT / Codex ------------------------------------------------------------
local chatgpt = registry.find("chatgpt")
local codexLine = mock.jsonEncode({
  timestamp = "2026-10-26T10:00:00Z",
  payload = {
    rate_limits = {
      primary = { used_percent = 12.5, window_minutes = 300, resets_at = 1760003600 },
      secondary = { used_percent = 33, window_minutes = 10080, resets_in_seconds = 3600 },
    },
  },
})
local chatgptResult = chatgpt.interpret({ found = true, text = codexLine }, {}, now)
assert(chatgptResult.ok, "chatgpt parse failed")
local chatgptWindows = windows(chatgptResult.usage)
assert(math.floor(chatgptWindows.five_hour.usedPercent) == 12, "chatgpt 5hr")
assert(math.floor(chatgptWindows.weekly.usedPercent) == 33, "chatgpt weekly")

-- JetBrains ------------------------------------------------------------------
local jetbrains = registry.find("jetbrains")
local jetbrainsLine = "2026-10-26 10:00:00,123 [x] INFO QuotaManager2Impl - New quota state is: Available("
  .. "tariffQuota=Details(current=50.0, maximum=100.0), topUpQuota=Details(current=1.0, maximum=10.0))"
local jetbrainsResult = jetbrains.interpret({ found = true, text = jetbrainsLine }, {}, now)
assert(jetbrainsResult.ok, "jetbrains parse failed")
local jetbrainsWindows = windows(jetbrainsResult.usage)
assert(math.floor(jetbrainsWindows.monthly.usedPercent) == 50, "jetbrains monthly")
assert(math.floor(jetbrainsWindows.top_up.usedPercent) == 10, "jetbrains top-up")

-- OpenAI ---------------------------------------------------------------------
local openai = registry.find("openai")
local openaiResult = openai.interpret(results({
  costs = {
    data = {
      { results = { { amount = { value = 1.25, currency = "usd" } } } },
      { results = { { amount = { value = 0.25, currency = "usd" } } } },
    },
  },
  usage = {
    data = {
      { results = { { input_tokens = 1000, output_tokens = 200 } } },
    },
  },
}), now)
assert(openaiResult.ok, "openai parse failed")
assert(math.abs(openaiResult.usage.amounts[1].value - 1.5) < 0.001, "openai spend")
assert(openaiResult.usage.counts[1].value == 1000, "openai input tokens")
assert(openaiResult.usage.counts[2].value == 200, "openai output tokens")

-- Anthropic ------------------------------------------------------------------
local anthropic = registry.find("anthropic")
local anthropicResult = anthropic.interpret(results({
  cost = { data = { { results = { { currency = "USD", amount = "150" } } } } },
  usage = {
    data = {
      {
        results = {
          {
            uncached_input_tokens = 100,
            cache_read_input_tokens = 50,
            cache_creation = { ephemeral_1h_input_tokens = 10, ephemeral_5m_input_tokens = 5 },
            output_tokens = 20,
          },
        },
      },
    },
  },
}), now)
assert(anthropicResult.ok, "anthropic parse failed")
assert(math.abs(anthropicResult.usage.amounts[1].value - 1.5) < 0.001, "anthropic spend")
assert(anthropicResult.usage.counts[1].value == 165, "anthropic input tokens")

-- xAI ------------------------------------------------------------------------
local xai = registry.find("xai")
local xaiResult = xai.interpret(results({
  balance = { total = { val = "1000" } },
  invoice = { coreInvoice = { lines = { { amount = "100" }, { amount = "150" } } } },
}), now)
assert(xaiResult.ok, "xai parse failed")
assert(math.abs(xaiResult.usage.amounts[1].value + 10) < 0.001, "xai balance is negative")
assert(math.abs(xaiResult.usage.amounts[2].value - 2.5) < 0.001, "xai spend")

-- OpenCode Go ----------------------------------------------------------------
local opencodeGo = registry.find("opencodeGo")
local opencodeGoResult = opencodeGo.interpret(results({
  usage = {
    usage = {
      rolling = { percent = 11, status = "ok", resetsAt = "2026-10-26T15:00:00Z" },
      weekly = { percent = 22, status = "ok", resetsAt = "2026-11-02T15:00:00Z" },
      monthly = { percent = 33, status = "ok", resetsAt = "2026-11-26T15:00:00Z" },
    },
  },
}), now)
assert(opencodeGoResult.ok, "opencodeGo parse failed")
assert(#opencodeGoResult.usage.windows == 3, "opencodeGo windows")

-- OpenCode Zen ---------------------------------------------------------------
local opencodeZen = registry.find("opencodeZen")
local opencodeZenResult = opencodeZen.interpret(results({
  members = {
    {
      email = "alice@example.com",
      spent_micro_cents = "250000000",
      limit_micro_cents = "1000000000",
      resets_at = "2026-11-01T00:00:00Z",
    },
    {
      email = "bob@example.com",
      spent_micro_cents = "100000000",
      limit_micro_cents = nil,
      resets_at = "2026-11-01T00:00:00Z",
    },
  },
}), now)
assert(opencodeZenResult.ok, "opencodeZen parse failed")
assert(math.abs(opencodeZenResult.usage.amounts[1].value - 7.5) < 0.001, "zen budget left")
assert(opencodeZenResult.usage.amounts[1].label == "budget_left", "zen main label")
assert(math.abs(opencodeZenResult.usage.windows[1].usedPercent - 25) < 0.001, "zen percent")

-- MiniMax --------------------------------------------------------------------
local minimax = registry.find("minimax")
local minimaxResult = minimax.interpret(results({
  remains = {
    base_resp = { status_code = 0 },
    model_remains = {
      {
        model_name = "MiniMax-M2",
        current_interval_status = 1,
        current_interval_total_count = 100,
        current_interval_usage_count = 25,
        start_time = now,
        end_time = now + 5 * 3600 * 1000,
        current_interval_remains_time = 3600 * 1000,
        current_weekly_status = 1,
        current_weekly_total_count = 0,
        current_weekly_usage_count = 0,
        current_weekly_remains_time = 86400 * 1000,
      },
    },
  },
}), now)
assert(minimaxResult.ok, "minimax parse failed")
assert(#minimaxResult.usage.windows >= 1, "minimax windows")
assert(math.abs(minimaxResult.usage.windows[1].usedPercent - 75) < 0.001, "minimax used percent")

-- Requesty -------------------------------------------------------------------
local requesty = registry.find("requesty")
local requestyResult = requesty.interpret(results({
  key = { monthly_spend = 20, monthly_limit = 100 },
  org = { balance = 30 },
}), now)
assert(requestyResult.ok, "requesty parse failed")
assert(math.abs(requestyResult.usage.amounts[1].value - 20) < 0.001, "requesty spend")
assert(math.abs(requestyResult.usage.amounts[2].value - 30) < 0.001, "requesty balance")

-- Hugging Face ---------------------------------------------------------------
local huggingFace = registry.find("huggingFace")
local huggingFaceResult = huggingFace.interpret(results({
  whoami = { isPro = true, billingMode = "prepaid" },
  usage = {
    currency = "usd",
    periods = { { sessions = { { costCents = 50 }, { costCents = 25 } } } },
  },
}), now)
assert(huggingFaceResult.ok, "huggingFace parse failed")
assert(math.abs(huggingFaceResult.usage.amounts[1].value - 1.25) < 0.001, "hf included credits")
assert(math.abs(huggingFaceResult.usage.amounts[2].value - 0.75) < 0.001, "hf spend")
assert(huggingFaceResult.usage.texts[1].value == "PRO", "hf plan")

-- 401 classification ---------------------------------------------------------
local error = formatter.describeError({
  kind = "key_rejected",
  reason = "http_status",
  params = { status = 401 },
})
assert(error:find("Key rejected", 1, true) ~= nil, "error text")

print("PROVIDER TEST OK")
