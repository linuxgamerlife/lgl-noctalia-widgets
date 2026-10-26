-- Shared provider helpers.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")

local M = {}

M.BEARER_AUTH = { header = "Authorization", prefix = "Bearer " }
M.ACCEPT_JSON = "Accept: application/json"
M.NO_FIELDS = {}
M.SPEND_MIN_INTERVAL_SECONDS = 300
M.NO_MIN_INTERVAL_SECONDS = 0

function M.monthStartUtcMs(now)
  local parts = os.date("!*t", math.floor(now / 1000))
  return values.daysFromCivil(parts.year, parts.month, 1) * 86400 * 1000
end

function M.readDailyBuckets(result)
  local body = http.parseJsonBody(result.reply)
  if not body.ok or not values.isPlainObject(body.value) or type(body.value.data) ~= "table" then
    return nil
  end
  local data = body.value.data
  if next(data) ~= nil and data[1] == nil then
    return nil
  end
  local items = {}
  for _, bucket in ipairs(data) do
    if not values.isPlainObject(bucket) or type(bucket.results) ~= "table" then
      return nil
    end
    if next(bucket.results) ~= nil and bucket.results[1] == nil then
      return nil
    end
    for _, item in ipairs(bucket.results) do
      table.insert(items, item)
    end
  end
  return items
end

return M
