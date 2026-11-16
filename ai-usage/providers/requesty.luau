-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Requesty spend and balance. Port of providers/requesty.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local BASE_URL = "https://api-v2.requesty.ai/v1/manage"

local function classify(reply)
  if reply.status == 402 then
    return http.failure(http.ERROR_KIND.NOT_AVAILABLE, http.REASON.BALANCE_EXHAUSTED)
  end
  return nil
end

local function readKeyInfo(result)
  local body = http.parseJsonBody(result.reply)
  if not body.ok or not values.isPlainObject(body.value) then
    return nil
  end
  local spend = values.toFiniteNumber(body.value.monthly_spend)
  local limit = body.value.monthly_limit == nil and 0 or values.toFiniteNumber(body.value.monthly_limit)
  if spend == nil or limit == nil then
    return nil
  end
  return { spend = spend, limit = limit }
end

local function balanceProblem(error)
  if error.kind == http.ERROR_KIND.KEY_REJECTED then
    return http.failure(http.ERROR_KIND.NOT_AVAILABLE, http.REASON.BALANCE_NEEDS_MANAGE)
  end
  return error
end

local function readBalance(result)
  if result.error then
    return usage.usageAmountProblem(usage.LABEL.BALANCE, balanceProblem(result.error))
  end
  local body = http.parseJsonBody(result.reply)
  local balance = body.ok and values.isPlainObject(body.value) and values.toFiniteNumber(body.value.balance) or nil
  if balance == nil then
    return usage.usageAmountProblem(
      usage.LABEL.BALANCE,
      http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, http.REASON.SHAPE_CHANGED)
    )
  end
  return usage.usageAmount(usage.LABEL.BALANCE, "", balance, nil, false)
end

local function interpret(results)
  local keyInfo = readKeyInfo(results.key)
  if keyInfo == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  local hasLimit = keyInfo.limit > 0
  local windows = {}
  if hasLimit then
    table.insert(windows, usage.usageWindow(
      usage.PERIOD.MONTHLY,
      "",
      (keyInfo.spend / keyInfo.limit) * units.PERCENT,
      nil
    ))
  end
  local amounts = {
    usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", keyInfo.spend, hasLimit and keyInfo.limit or nil, not hasLimit),
  }
  table.insert(amounts, readBalance(results.org))
  return usage.succeeded(usage.makeUsage({ windows = windows, amounts = amounts }))
end

return {
  id = "requesty",
  title = "Requesty",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "API key with manage permission, from the Requesty dashboard",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function()
    return {
      { id = "key", url = BASE_URL .. "/apikey/self", headers = { common.ACCEPT_JSON } },
      { id = "org", url = BASE_URL .. "/org", headers = { common.ACCEPT_JSON }, optional = true },
    }
  end,
  classify = classify,
  interpret = interpret,
}
