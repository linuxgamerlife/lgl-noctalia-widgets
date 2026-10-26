-- OpenCode Go limits. Port of providers/opencodeGo.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
local WINDOWS = {
  { field = "rolling", period = usage.PERIOD.FIVE_HOUR },
  { field = "weekly", period = usage.PERIOD.WEEKLY },
  { field = "monthly", period = usage.PERIOD.MONTHLY },
}

local function classify(reply)
  if reply.status ~= 403 then
    return nil
  end
  local body = http.parseJsonBody(reply)
  local isEntitlement = body.ok and values.isPlainObject(body.value) and values.isPlainObject(body.value.error)
    and body.value.error.type == "EntitlementError"
  if isEntitlement then
    return http.failure(http.ERROR_KIND.NOT_AVAILABLE, http.REASON.GO_SUBSCRIPTION_REQUIRED)
  end
  return nil
end

local function readWindow(value)
  if not values.isPlainObject(value) or type(value.percent) ~= "number" or type(value.status) ~= "string" then
    return nil
  end
  local resetsAt = values.parseIsoTime(value.resetsAt)
  if resetsAt == nil then
    return nil
  end
  return { percent = value.percent, resetsAt = resetsAt, status = value.status }
end

local function interpret(results)
  local body = http.parseJsonBody(results.usage.reply)
  if not body.ok or not values.isPlainObject(body.value) or not values.isPlainObject(body.value.usage) then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  local source = body.value.usage
  local windows = {}
  for _, spec in ipairs(WINDOWS) do
    if source[spec.field] ~= nil then
      local item = readWindow(source[spec.field])
      if item == nil then
        return usage.unexpected(http.REASON.SHAPE_CHANGED)
      end
      local percent = item.percent
      if item.status == "rate-limited" then
        -- The API floors the percentage and says rate-limited at the cap; a
        -- floored 99 still means spent.
        percent = 100
      end
      table.insert(windows, usage.usageWindow(spec.period, "", percent, item.resetsAt, { status = item.status }))
    end
  end
  if #windows == 0 then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({ windows = windows }))
end

return {
  id = "opencodeGo",
  title = "OpenCode Go",
  kind = kind.REMOTE,
  minIntervalSeconds = common.NO_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Go API key, from the OpenCode console",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function()
    return { { id = "usage", url = USAGE_URL, headers = { common.ACCEPT_JSON } } }
  end,
  classify = classify,
  interpret = interpret,
}
