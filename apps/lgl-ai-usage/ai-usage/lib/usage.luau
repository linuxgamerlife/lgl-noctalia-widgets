-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Usage value objects and period classification. Port of core/usage.mjs.

local http = require("./http.luau")
local units = require("./units.luau")

local M = {}

M.MAX_NAME_LENGTH = 64

local CUT_MARK = "..."
local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 24 * MINUTES_PER_HOUR
local FIVE_HOURS_MINUTES = 5 * MINUTES_PER_HOUR
local WEEK_MINUTES = 7 * MINUTES_PER_DAY
local SHORTEST_MONTH_MINUTES = 28 * MINUTES_PER_DAY
local LONGEST_MONTH_MINUTES = 31 * MINUTES_PER_DAY

M.PERIOD = {
  FIVE_HOUR = "five_hour",
  DAILY = "daily",
  WEEKLY = "weekly",
  MONTHLY = "monthly",
  HOURS = "hours",
  DAYS = "days",
  MINUTES = "minutes",
  INTERVAL = "interval",
  TOP_UP = "top_up",
}

M.DEFAULT_CURRENCY = "usd"

M.LABEL = {
  SPENT_THIS_MONTH = "spent_this_month",
  BALANCE = "balance",
  INPUT_TOKENS_THIS_MONTH = "input_tokens_this_month",
  OUTPUT_TOKENS_THIS_MONTH = "output_tokens_this_month",
  MEMBER_SPEND = "member_spend",
  BUDGET_LEFT = "budget_left",
  MEMBER_BUDGET_LEFT = "member_budget_left",
  INCLUDED_CREDITS_LEFT = "included_credits_left",
  PLAN = "plan",
  BILLING_MODE = "billing_mode",
}

M.DISCOVERY = {
  CLAUDE_READING = "claude_reading",
  CLAUDE_NONE_NEW = "claude_none_new",
}

function M.cutName(name)
  local text = type(name) == "string" and name or ""
  if #text > M.MAX_NAME_LENGTH then
    return text:sub(1, M.MAX_NAME_LENGTH - #CUT_MARK) .. CUT_MARK
  end
  return text
end

function M.periodForMinutes(minutes)
  if type(minutes) ~= "number" or minutes ~= minutes or minutes <= 0 then
    return { period = M.PERIOD.INTERVAL, count = nil }
  end
  local rounded = math.floor(minutes + 0.5)
  if rounded == FIVE_HOURS_MINUTES then
    return { period = M.PERIOD.FIVE_HOUR, count = nil }
  end
  if rounded == MINUTES_PER_DAY then
    return { period = M.PERIOD.DAILY, count = nil }
  end
  if rounded == WEEK_MINUTES then
    return { period = M.PERIOD.WEEKLY, count = nil }
  end
  if rounded >= SHORTEST_MONTH_MINUTES and rounded <= LONGEST_MONTH_MINUTES then
    return { period = M.PERIOD.MONTHLY, count = nil }
  end
  if rounded % MINUTES_PER_DAY == 0 then
    return { period = M.PERIOD.DAYS, count = rounded / MINUTES_PER_DAY }
  end
  if rounded % MINUTES_PER_HOUR == 0 then
    return { period = M.PERIOD.HOURS, count = rounded / MINUTES_PER_HOUR }
  end
  return { period = M.PERIOD.MINUTES, count = rounded }
end

function M.usageWindow(period, name, usedPercent, resetsAt, options)
  local settings = options or {}
  return {
    period = period,
    count = settings.count,
    name = M.cutName(name),
    usedPercent = usedPercent,
    resetsAt = resetsAt,
    validUntil = settings.validUntil,
    estimated = settings.estimated == true,
    canBeMain = settings.canBeMain ~= false,
    status = settings.status,
  }
end

function M.usageAmount(label, name, value, limit, noLimit, currency)
  return {
    label = label,
    name = M.cutName(name),
    value = value,
    limit = limit,
    noLimit = noLimit == true,
    currency = M.cutName(currency or M.DEFAULT_CURRENCY),
    problem = nil,
  }
end

function M.usageAmountProblem(label, problem)
  local amount = M.usageAmount(label, "", nil, nil, false)
  amount.problem = problem
  return amount
end

function M.usageCount(label, value)
  return { label = label, value = value }
end

function M.usageText(label, value)
  return { label = label, value = M.cutName(value) }
end

function M.makeUsage(parts)
  return {
    windows = parts.windows or {},
    amounts = parts.amounts or {},
    counts = parts.counts or {},
    texts = parts.texts or {},
  }
end

function M.succeeded(usage)
  return { ok = true, usage = usage }
end

function M.unexpected(reason, params)
  return { ok = false, error = http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, reason, nil, params) }
end

function M.notAvailable(reason, params)
  return { ok = false, error = http.failure(http.ERROR_KIND.NOT_AVAILABLE, reason, nil, params) }
end

-- Kept here so provider modules do not each import units just for a percentage.
M.PERCENT = units.PERCENT

return M
