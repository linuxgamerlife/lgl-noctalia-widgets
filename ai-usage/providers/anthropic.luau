-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Anthropic organization usage and costs. Port of providers/anthropic.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local BASE_URL = "https://api.anthropic.com/v1/organizations"
local API_VERSION = "2023-06-01"
local DAYS_IN_LONGEST_MONTH = 31
local API_KEY_AUTH = { header = "x-api-key", prefix = "" }

local function monthStartUtc(now)
  return os.date("!%Y-%m-01T00:00:00Z", math.floor(now / 1000))
end

local function reportUrl(path, now)
  return BASE_URL .. path
    .. "?starting_at=" .. noctalia.string.urlEncode(monthStartUtc(now))
    .. "&bucket_width=1d&limit=" .. DAYS_IN_LONGEST_MONTH
end

local function classify(reply)
  if reply.status == 401 then
    return http.failure(http.ERROR_KIND.KEY_REJECTED, http.REASON.ADMIN_KEY_REQUIRED)
  end
  if reply.status == 403 or reply.status == 404 then
    return http.failure(http.ERROR_KIND.NOT_AVAILABLE, http.REASON.TEAM_ORGANIZATION_REQUIRED)
  end
  return nil
end

local function sumCostCents(items)
  local total = 0
  for _, item in ipairs(items) do
    local cents = nil
    if values.isPlainObject(item) and item.currency == "USD" and type(item.amount) == "string" then
      cents = values.toFiniteNumber(item.amount)
    end
    if cents == nil then
      return nil
    end
    total = total + cents
  end
  return total
end

local function tokenNumber(value)
  local number = values.toFiniteNumber(value == nil and 0 or value)
  if number == nil or number < 0 then
    return nil
  end
  return number
end

local function sumTokens(items)
  local input, output = 0, 0
  for _, item in ipairs(items) do
    if not values.isPlainObject(item) then
      return nil
    end
    local cache = values.isPlainObject(item.cache_creation) and item.cache_creation or {}
    local parts = {
      tokenNumber(item.uncached_input_tokens),
      tokenNumber(item.cache_read_input_tokens),
      tokenNumber(cache.ephemeral_1h_input_tokens),
      tokenNumber(cache.ephemeral_5m_input_tokens),
    }
    local out = tokenNumber(item.output_tokens)
    for _, part in ipairs(parts) do
      if part == nil then
        return nil
      end
    end
    if out == nil then
      return nil
    end
    for _, part in ipairs(parts) do
      input = input + part
    end
    output = output + out
  end
  return { input = input, output = output }
end

local function interpret(results)
  local cost = common.readDailyBuckets(results.cost)
  local tokenBuckets = common.readDailyBuckets(results.usage)
  local cents = cost and sumCostCents(cost) or nil
  local tokens = tokenBuckets and sumTokens(tokenBuckets) or nil
  if cents == nil or tokens == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({
    amounts = { usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", cents / units.CENTS_PER_DOLLAR, nil, false) },
    counts = {
      usage.usageCount(usage.LABEL.INPUT_TOKENS_THIS_MONTH, tokens.input),
      usage.usageCount(usage.LABEL.OUTPUT_TOKENS_THIS_MONTH, tokens.output),
    },
  }))
end

return {
  id = "anthropic",
  title = "Anthropic API",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Admin API key, from the Claude Console (team organizations only)",
  fields = common.NO_FIELDS,
  auth = API_KEY_AUTH,
  buildRequests = function(now)
    local headers = { common.ACCEPT_JSON, "anthropic-version: " .. API_VERSION }
    return {
      { id = "cost", url = reportUrl("/cost_report", now), headers = headers },
      { id = "usage", url = reportUrl("/usage_report/messages", now), headers = headers },
    }
  end,
  classify = classify,
  interpret = interpret,
  sumCostCents = sumCostCents,
  sumTokens = sumTokens,
}
