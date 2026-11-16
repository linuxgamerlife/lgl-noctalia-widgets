-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- MiniMax token-plan windows. Port of providers/minimax.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.MAX_MODELS = 50

local REMAINS_URL = "https://api.minimax.io/v1/token_plan/remains"
local STATUS_UNLIMITED = 3
local KEY_REJECTED_CODES = { [1004] = true, [2049] = true }
local RATE_LIMITED_CODES = { [1002] = true, [1039] = true, [1041] = true, [2045] = true, [2056] = true }
local INSUFFICIENT_BALANCE_CODE = 1008
local INTERVAL = { prefix = "current_interval", remainsField = "remains_time", startField = "start_time", endField = "end_time" }
local WEEKLY = { prefix = "current_weekly", remainsField = "weekly_remains_time", startField = nil, endField = nil }
local NO_COUNTS = {}

local function serviceCodeFailure(code)
  local params = { code = code }
  if KEY_REJECTED_CODES[code] then
    return http.failure(http.ERROR_KIND.KEY_REJECTED, http.REASON.SERVICE_CODE, nil, params)
  end
  if RATE_LIMITED_CODES[code] then
    return http.failure(http.ERROR_KIND.RATE_LIMITED, http.REASON.SERVICE_CODE, nil, params)
  end
  if code == INSUFFICIENT_BALANCE_CODE then
    return http.failure(http.ERROR_KIND.NOT_AVAILABLE, http.REASON.INSUFFICIENT_BALANCE, nil, params)
  end
  return http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, http.REASON.SERVICE_CODE, nil, params)
end

local function optionalNumber(value)
  if value == nil then
    return nil
  end
  return values.toFiniteNumber(value)
end

local function isUnlimited(model, spec)
  return optionalNumber(model[spec.prefix .. "_status"]) == STATUS_UNLIMITED
end

local function periodOf(model, spec)
  if spec.startField == nil then
    return { period = usage.PERIOD.WEEKLY, count = nil }
  end
  local start = optionalNumber(model[spec.startField])
  local finish = optionalNumber(model[spec.endField])
  local minutes = nil
  if start ~= nil and finish ~= nil then
    minutes = (finish - start) / units.MINUTE_MS
  end
  return usage.periodForMinutes(minutes)
end

local function readWindow(model, spec, now)
  local period = periodOf(model, spec)
  local remains = values.toFiniteNumber(model[spec.remainsField])
  local resetsAt = nil
  if remains ~= nil then
    resetsAt = now + remains
  end
  local remainingPercent = optionalNumber(model[spec.prefix .. "_remaining_percent"])
  if remainingPercent ~= nil then
    return usage.usageWindow(period.period, model.model_name, units.PERCENT - remainingPercent, resetsAt, { count = period.count })
  end
  local total = values.toFiniteNumber(model[spec.prefix .. "_total_count"])
  local reported = values.toFiniteNumber(model[spec.prefix .. "_usage_count"])
  if total == nil or reported == nil then
    return NO_COUNTS
  end
  if total <= 0 or reported < 0 or reported > total then
    return nil
  end
  local isUsedUpWithoutPlanDetails = reported == 0
  return usage.usageWindow(
    period.period,
    model.model_name,
    ((total - reported) / total) * units.PERCENT,
    resetsAt,
    { count = period.count, canBeMain = not isUsedUpWithoutPlanDetails }
  )
end

local function readModel(model, now)
  if not values.isPlainObject(model) or type(model.model_name) ~= "string" then
    return nil
  end
  local windows = {}
  if not isUnlimited(model, INTERVAL) then
    local interval = readWindow(model, INTERVAL, now)
    if interval == NO_COUNTS then
      return nil
    end
    if interval ~= nil then
      table.insert(windows, interval)
    end
  end
  if not isUnlimited(model, WEEKLY) then
    local weekly = readWindow(model, WEEKLY, now)
    if weekly ~= nil and weekly ~= NO_COUNTS then
      table.insert(windows, weekly)
    end
  end
  return windows
end

local function readModels(models, now)
  local windows = {}
  for _, model in ipairs(models) do
    local modelWindows = readModel(model, now)
    if modelWindows == nil then
      return nil
    end
    for _, window in ipairs(modelWindows) do
      table.insert(windows, window)
    end
  end
  return windows
end

local function interpret(results, now)
  local body = http.parseJsonBody(results.remains.reply)
  if not body.ok or not values.isPlainObject(body.value) then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  local base = body.value.base_resp
  local code = values.isPlainObject(base) and values.toFiniteNumber(base.status_code) or nil
  if code ~= nil and code ~= 0 then
    return { ok = false, error = serviceCodeFailure(code) }
  end
  local source = body.value.model_remains
  if type(source) ~= "table" or (next(source) ~= nil and source[1] == nil) then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  local slices = {}
  for index = 1, math.min(#source, M.MAX_MODELS) do
    table.insert(slices, source[index])
  end
  local windows = readModels(slices, now)
  if windows == nil then
    return usage.unexpected(http.REASON.SHAPE_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({ windows = windows }))
end

return {
  id = "minimax",
  title = "MiniMax",
  kind = kind.REMOTE,
  minIntervalSeconds = common.NO_MIN_INTERVAL_SECONDS,
  needsKey = true,
  keyHelp = "Token Plan key, from the MiniMax Platform",
  fields = common.NO_FIELDS,
  auth = common.BEARER_AUTH,
  buildRequests = function()
    return { { id = "remains", url = REMAINS_URL, headers = { common.ACCEPT_JSON } } }
  end,
  interpret = interpret,
  MAX_MODELS = M.MAX_MODELS,
}
