-- Hugging Face plan and inference spend. Port of providers/huggingFace.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.PRO_INCLUDED_CREDITS_USD = 2

local BASE_URL = "https://huggingface.co/api"
local PRO_PLAN = "PRO"
local USD = "usd"
local FREE_PLAN = "free"

local function classify(reply)
  if reply.status == 403 then
    return http.failure(http.ERROR_KIND.KEY_REJECTED, http.REASON.HF_BILLING_PERMISSION)
  end
  return nil
end

local function missing(field)
  return usage.unexpected(http.REASON.FIELD_MISSING, { field = field })
end

local function readUser(result)
  local body = http.parseJsonBody(result.reply)
  if not body.ok or not values.isPlainObject(body.value) then
    return { error = usage.unexpected(http.REASON.SHAPE_CHANGED) }
  end
  local user = body.value
  if type(user.isPro) ~= "boolean" then
    return { error = missing("isPro") }
  end
  if type(user.billingMode) ~= "string" or user.billingMode == "" then
    return { error = missing("billingMode") }
  end
  return { isPro = user.isPro, plan = user.isPro and PRO_PLAN or FREE_PLAN, billingMode = user.billingMode }
end

local function sumSessions(periods)
  local cents = 0
  for _, period in ipairs(periods) do
    if not values.isPlainObject(period) or type(period.sessions) ~= "table" then
      return { error = missing("sessions") }
    end
    for _, session in ipairs(period.sessions) do
      if not values.isPlainObject(session) or type(session.costCents) ~= "number" then
        return { error = missing("costCents") }
      end
      cents = cents + session.costCents
    end
  end
  return { cents = cents }
end

local function readSpend(result)
  local body = http.parseJsonBody(result.reply)
  if not body.ok or not values.isPlainObject(body.value) then
    return { error = usage.unexpected(http.REASON.SHAPE_CHANGED) }
  end
  if type(body.value.currency) ~= "string" or body.value.currency == "" then
    return { error = missing("currency") }
  end
  if type(body.value.periods) ~= "table" then
    return { error = missing("periods") }
  end
  local sum = sumSessions(body.value.periods)
  if sum.error then
    return sum
  end
  return { amount = sum.cents / units.CENTS_PER_DOLLAR, currency = body.value.currency }
end

local function includedCredits(user, spend)
  if not user.isPro or string.lower(spend.currency) ~= USD then
    return {}
  end
  return {
    usage.usageAmount(
      usage.LABEL.INCLUDED_CREDITS_LEFT,
      "",
      math.max(0, M.PRO_INCLUDED_CREDITS_USD - spend.amount),
      nil,
      false,
      USD
    ),
  }
end

local function interpret(results)
  local user = readUser(results.whoami)
  if user.error then
    return user.error
  end
  local spend = readSpend(results.usage)
  if spend.error then
    return spend.error
  end
  local amounts = includedCredits(user, spend)
  table.insert(amounts, usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", spend.amount, nil, false, spend.currency))
  return usage.succeeded(usage.makeUsage({
    texts = {
      usage.usageText(usage.LABEL.PLAN, user.plan),
      usage.usageText(usage.LABEL.BILLING_MODE, user.billingMode),
    },
    amounts = amounts,
  }))
end

return {
  id = "huggingFace",
  title = "Hugging Face",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Fine-grained access token with billing read permission, from Hugging Face settings",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function(now)
    return {
      { id = "whoami", url = BASE_URL .. "/whoami-v2", headers = { common.ACCEPT_JSON } },
      {
        id = "usage",
        url = BASE_URL .. "/settings/billing/usage-by-inference-session?startDate="
          .. noctalia.string.urlEncode(values.isoUtc(common.monthStartUtcMs(now))),
        headers = { common.ACCEPT_JSON },
      },
    }
  end,
  classify = classify,
  interpret = interpret,
  PRO_INCLUDED_CREDITS_USD = M.PRO_INCLUDED_CREDITS_USD,
}
