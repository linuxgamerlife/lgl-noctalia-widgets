-- xAI billing. Port of providers/xai.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local accounts = require("../lib/accounts.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local BASE_URL = "https://management-api.x.ai/v1/billing/teams/"

local function teamUrl(account, path)
  if not accounts.isValidField(account.teamId) then
    error("the team ID is not allowed")
  end
  return BASE_URL .. account.teamId .. path
end

local function cents(value)
  if values.isPlainObject(value) and type(value.val) == "string" then
    return values.toFiniteNumber(value.val)
  end
  return nil
end

local function readBalance(result)
  local body = http.parseJsonBody(result.reply)
  local total = body.ok and values.isPlainObject(body.value) and cents(body.value.total) or nil
  if total == nil then
    return nil
  end
  return -total / units.CENTS_PER_DOLLAR
end

local function readSpend(result)
  local body = http.parseJsonBody(result.reply)
  local invoice = body.ok and values.isPlainObject(body.value) and body.value.coreInvoice or nil
  if not values.isPlainObject(invoice) or type(invoice.lines) ~= "table" then
    return nil
  end
  local total = 0
  for _, line in ipairs(invoice.lines) do
    local amount = nil
    if values.isPlainObject(line) and type(line.amount) == "string" then
      amount = values.toFiniteNumber(line.amount)
    end
    if amount == nil then
      return nil
    end
    total = total + amount
  end
  return total / units.CENTS_PER_DOLLAR
end

local function interpret(results)
  local balance = readBalance(results.balance)
  local spend = readSpend(results.invoice)
  if balance == nil or spend == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({
    amounts = {
      usage.usageAmount(usage.LABEL.BALANCE, "", balance, nil, false),
      usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", spend, nil, false),
    },
  }))
end

return {
  id = "xai",
  title = "xAI API",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Management key, from the xAI Console",
  fields = { { id = "teamId", label = "Team ID", typed = true } },
  auth = common.BEARER_AUTH,
  buildRequests = function(_, account)
    return {
      { id = "balance", url = teamUrl(account, "/prepaid/balance"), headers = { common.ACCEPT_JSON } },
      { id = "invoice", url = teamUrl(account, "/postpaid/invoice/preview"), headers = { common.ACCEPT_JSON } },
    }
  end,
  interpret = interpret,
  readBalance = readBalance,
  readSpend = readSpend,
}
