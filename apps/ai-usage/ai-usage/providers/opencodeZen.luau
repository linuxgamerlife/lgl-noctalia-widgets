-- OpenCode Zen member budgets. Port of providers/opencodeZen.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.MAX_MEMBERS = 50

local MEMBERS_URL = "https://opencode.ai/console/api/v1/budgets/members"
local MICROCENTS_PER_DOLLAR = 100000000
local FORBIDDEN = 403

local function classify(reply)
  if reply.status == FORBIDDEN then
    return http.failure(http.ERROR_KIND.KEY_REJECTED, http.REASON.ZEN_ALL_PERMISSIONS)
  end
  return nil
end

local function emailName(email)
  local at = email:find("@", 1, true)
  return at == nil and email or email:sub(1, at - 1)
end

local function readLimit(value)
  if value == nil then
    return { ok = true, usd = nil }
  end
  local limit = type(value) == "string" and values.toFiniteNumber(value) or nil
  if limit == nil then
    return { ok = false }
  end
  return { ok = true, usd = limit / MICROCENTS_PER_DOLLAR }
end

local function readMember(value)
  if not values.isPlainObject(value) or type(value.email) ~= "string" or type(value.spent_micro_cents) ~= "string" then
    return nil
  end
  local spent = values.toFiniteNumber(value.spent_micro_cents)
  local limit = readLimit(value.limit_micro_cents)
  local resetsAt = values.parseIsoTime(value.resets_at)
  if spent == nil or not limit.ok or resetsAt == nil then
    return nil
  end
  return {
    name = emailName(value.email),
    spentUsd = spent / MICROCENTS_PER_DOLLAR,
    limitUsd = limit.usd,
    resetsAt = resetsAt,
  }
end

local function hasLimit(member)
  return member.limitUsd ~= nil and member.limitUsd > 0
end

local function usedPercent(member)
  return (member.spentUsd / member.limitUsd) * units.PERCENT
end

local function mainAmount(member)
  if hasLimit(member) then
    return usage.usageAmount(usage.LABEL.BUDGET_LEFT, "", member.limitUsd - member.spentUsd, nil, false)
  end
  return usage.usageAmount(usage.LABEL.SPENT_THIS_MONTH, "", member.spentUsd, nil, true)
end

local function memberAmount(member)
  if hasLimit(member) then
    return usage.usageAmount(usage.LABEL.MEMBER_BUDGET_LEFT, member.name, member.limitUsd - member.spentUsd, nil, false)
  end
  return usage.usageAmount(usage.LABEL.MEMBER_SPEND, member.name, member.spentUsd, nil, true)
end

local function interpret(results)
  local body = http.parseJsonBody(results.members.reply)
  if not body.ok or type(body.value) ~= "table" then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  if next(body.value) ~= nil and body.value[1] == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  local members = {}
  for _, value in ipairs(body.value) do
    local member = readMember(value)
    if member == nil then
      return usage.unexpected(http.REASON.SHAPE_CHANGED)
    end
    table.insert(members, member)
  end
  local shown = {}
  for index = 1, math.min(#members, M.MAX_MEMBERS) do
    table.insert(shown, members[index])
  end
  local limited = {}
  for _, member in ipairs(shown) do
    if hasLimit(member) then
      table.insert(limited, member)
    end
  end
  local main = shown[1]
  if #limited > 0 then
    main = limited[1]
    for _, member in ipairs(limited) do
      if usedPercent(member) > usedPercent(main) then
        main = member
      end
    end
  end
  local windows = {}
  for _, member in ipairs(limited) do
    table.insert(windows, usage.usageWindow(usage.PERIOD.MONTHLY, member.name, usedPercent(member), member.resetsAt))
  end
  local amounts = {}
  for _, member in ipairs(shown) do
    table.insert(amounts, member == main and mainAmount(member) or memberAmount(member))
  end
  return usage.succeeded(usage.makeUsage({ windows = windows, amounts = amounts }))
end

return {
  id = "opencodeZen",
  title = "OpenCode Zen",
  kind = kind.REMOTE,
  minIntervalSeconds = common.SPEND_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Service account key, from the OpenCode console",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function()
    return { { id = "members", url = MEMBERS_URL, headers = { common.ACCEPT_JSON } } }
  end,
  classify = classify,
  interpret = interpret,
  MAX_MEMBERS = M.MAX_MEMBERS,
}
