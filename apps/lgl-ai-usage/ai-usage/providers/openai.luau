-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- OpenAI organization usage and costs. Port of providers/openai.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local BASE_URL = "https://api.openai.com/v1/organization"
local DAYS_IN_LONGEST_MONTH = 31
local CURRENCY = "usd"

local function classify(reply)
  if reply.status == 401 or reply.status == 403 then
    return http.failure(http.ERROR_KIND.KEY_REJECTED, http.REASON.OPENAI_ADMIN_KEY_REQUIRED, nil, { status = reply.status })
  end
  return nil
end

local function reportUrl(path, now)
  return BASE_URL .. path
    .. "?start_time=" .. math.floor(common.monthStartUtcMs(now) / units.SECOND_MS)
    .. "&bucket_width=1d&limit=" .. DAYS_IN_LONGEST_MONTH
end

local function isAmount(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sumCosts(items)
  local total = 0
  for _, item in ipairs(items) do
    local amount = values.isPlainObject(item) and values.isPlainObject(item.amount) and item.amount or nil
    if amount == nil or not isAmount(amount.value) or string.lower(tostring(amount.currency)) ~= CURRENCY then
      return nil
    end
    total = total + amount.value
  end
  return total
end

local function isTokenCount(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function sumTokens(items)
  local input, output = 0, 0
  for _, item in ipairs(items) do
    if not values.isPlainObject(item) or not isTokenCount(item.input_tokens) or not isTokenCount(item.output_tokens) then
      return nil
    end
    input = input + item.input_tokens
    output = output + item.output_tokens
  end
  return { input = input, output = output }
end

local function interpret(results)
  local costs = common.readDailyBuckets(results.costs)
  local tokens = common.readDailyBuckets(results.usage)
  local usd = costs and sumCosts(costs) or nil
  local tokenCounts = tokens and sumTokens(tokens) or nil
  if usd == nil or tokenCounts == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({
    amounts = { usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", usd, nil, false) },
    counts = {
      usage.usageCount(usage.LABEL.INPUT_TOKENS_THIS_MONTH, tokenCounts.input),
      usage.usageCount(usage.LABEL.OUTPUT_TOKENS_THIS_MONTH, tokenCounts.output),
    },
  }))
end

return {
  id = "openai",
  title = "OpenAI API",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Admin API key, from the OpenAI Platform",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function(now)
    return {
      { id = "costs", url = reportUrl("/costs", now), headers = { common.ACCEPT_JSON } },
      { id = "usage", url = reportUrl("/usage/completions", now), headers = { common.ACCEPT_JSON } },
    }
  end,
  classify = classify,
  interpret = interpret,
  sumCosts = sumCosts,
  sumTokens = sumTokens,
}
