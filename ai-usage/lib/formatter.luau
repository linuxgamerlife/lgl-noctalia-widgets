-- Turn raw usage into the plain view model the card and panel render.
-- Port of core/formatter.mjs, with noctalia.tr() for user-visible text.

local http = require("./http.luau")
local units = require("./units.luau")
local usage = require("./usage.luau")
local curl = require("./curlcommand.luau")
local privacy = require("./privacy.luau")

local M = {}

M.SEVERITY = {
  NORMAL = "normal",
  WARNING = "warning",
  CRITICAL = "critical",
  UNKNOWN = "unknown",
}

local WARNING_PERCENT = 75
local CRITICAL_PERCENT = 90
local NO_VALUE = "--"
local MAIN_PERIODS = {
  usage.PERIOD.FIVE_HOUR,
  usage.PERIOD.DAILY,
  usage.PERIOD.WEEKLY,
  usage.PERIOD.MONTHLY,
}
local MAIN_AMOUNT_LABELS = {
  usage.LABEL.BALANCE,
  usage.LABEL.INCLUDED_CREDITS_LEFT,
  usage.LABEL.BUDGET_LEFT,
  usage.LABEL.SPENT_THIS_MONTH,
}
local CRITICAL_ERRORS = {
  [http.ERROR_KIND.KEY_REJECTED] = true,
  [http.ERROR_KIND.NO_KEY] = true,
}
local LOCKED_WALLET_REASONS = {
  [http.REASON.WALLET_LOCKED] = true,
  [http.REASON.SECRET_SERVICE_UNAVAILABLE] = true,
  [http.REASON.SECRET_SERVICE_TIMEOUT] = true,
}

M.EMPTY_SECTION = {
  key = "",
  title = "",
  account = "",
  windows = {},
  mainRows = {},
  rows = {},
  isLoading = false,
  hasError = false,
  errorText = "",
  errorSeverity = M.SEVERITY.UNKNOWN,
}

local function fill(template, valuesTable)
  if type(template) ~= "string" then
    return ""
  end
  return (template:gsub("{([%w_]+)}", function(key)
    local value = valuesTable and valuesTable[key]
    if value == nil then
      return "unknown"
    end
    return tostring(value)
  end))
end

local function tr(key, subst)
  local text = noctalia.tr(key, subst)
  if text == nil or text == key then
    return nil
  end
  return text
end

local function translated(key, fallback, subst)
  local text = tr(key, subst)
  return text or fill(fallback, subst)
end

function M.formatBytes(bytes)
  if bytes >= units.MIB and bytes % units.MIB == 0 then
    return string.format("%d MiB", bytes / units.MIB)
  end
  if bytes >= units.KIB and bytes % units.KIB == 0 then
    return string.format("%d KiB", bytes / units.KIB)
  end
  return tostring(bytes) .. " bytes"
end

function M.periodText(item)
  local key = "period." .. tostring(item.period)
  local fallback = ({
    five_hour = "5hr",
    daily = "daily",
    weekly = "weekly",
    monthly = "monthly",
    hours = "{count}hr",
    days = "{count} days",
    minutes = "{count} min",
    interval = "interval",
    top_up = "top-up",
  })[item.period] or tostring(item.period)
  return translated(key, fallback, { count = item.count })
end

function M.windowLabel(item)
  local period = M.periodText(item)
  if item.name and item.name ~= "" then
    return item.name .. " " .. period
  end
  return period
end

function M.labelText(item)
  local key = "label." .. tostring(item.label)
  local fallback = ({
    spent_this_month = "Spent this month",
    balance = "Balance",
    input_tokens_this_month = "Input tokens this month",
    output_tokens_this_month = "Output tokens this month",
    member_spend = "{name}",
    budget_left = "Budget left",
    member_budget_left = "{name} budget left",
    included_credits_left = "Included credits left",
    plan = "Plan",
    billing_mode = "Billing mode",
  })[item.label] or tostring(item.label)
  return translated(key, fallback, { name = item.name })
end

function M.reasonText(error)
  local params = {}
  for key, value in pairs(error.params or {}) do
    params[key] = value
  end
  params.size = M.formatBytes(type(params.size) == "number" and params.size or curl.MAX_RESPONSE_BYTES)
  return translated("reason." .. tostring(error.reason), tostring(error.reason), params)
end

function M.severityFor(percent)
  if percent == nil then
    return M.SEVERITY.UNKNOWN
  end
  if percent >= CRITICAL_PERCENT then
    return M.SEVERITY.CRITICAL
  end
  if percent >= WARNING_PERCENT then
    return M.SEVERITY.WARNING
  end
  return M.SEVERITY.NORMAL
end

function M.formatPercent(percent)
  if percent == nil then
    return NO_VALUE
  end
  return string.format("%d%%", math.floor(percent + 0.5))
end

local function groupDigits(text)
  local reversed = text:reverse():gsub("(%d%d%d)", "%1,")
  reversed = reversed:gsub("^,", "")
  reversed = reversed:gsub(",$", "")
  return reversed:reverse()
end

function M.formatMoney(value, currency)
  local code = string.lower(currency or usage.DEFAULT_CURRENCY)
  local cents = math.floor((math.abs(value) + 1e-9) * units.CENTS_PER_DOLLAR + 0.5)
  local whole = math.floor(cents / units.CENTS_PER_DOLLAR)
  local fraction = cents % units.CENTS_PER_DOLLAR
  local text = groupDigits(tostring(whole)) .. "." .. string.format("%02d", fraction)
  local sign = value < 0 and cents > 0 and "-" or ""
  if code == usage.DEFAULT_CURRENCY then
    return sign .. "$" .. text
  end
  return sign .. text .. " " .. string.upper(code)
end

local function trimDecimal(value)
  local text = string.format("%.1f", value)
  if text:sub(-2) == ".0" then
    return text:sub(1, -3)
  end
  return text
end

function M.formatCount(value)
  if value >= 1e9 then
    return trimDecimal(value / 1e9) .. "B"
  end
  if value >= 1e6 then
    return trimDecimal(value / 1e6) .. "M"
  end
  if value >= 1e3 then
    return trimDecimal(value / 1e3) .. "k"
  end
  return tostring(math.floor(value + 0.5))
end

function M.refreshChoiceText(seconds)
  if seconds < 60 then
    return translated("duration.seconds", "{n} seconds", { n = seconds })
  end
  local minutes = math.floor(seconds / 60 + 0.5)
  if minutes == 1 then
    return translated("duration.one_minute", "1 minute")
  end
  return translated("duration.minutes", "{n} minutes", { n = minutes })
end

function M.formatDuration(ms)
  if ms < units.MINUTE_MS then
    return translated("duration.less_than_minute", "less than a minute")
  end
  if ms < units.HOUR_MS then
    return translated("duration.minutes", "{n} min", { n = math.floor(ms / units.MINUTE_MS) })
  end
  if ms < units.DAY_MS then
    local hours = math.floor(ms / units.HOUR_MS)
    local minutes = math.floor((ms % units.HOUR_MS) / units.MINUTE_MS)
    if minutes > 0 then
      return translated("duration.hours_minutes", "{h}h {m}min", { h = hours, m = minutes })
    end
    return translated("duration.hours", "{n}h", { n = hours })
  end
  local days = math.floor(ms / units.DAY_MS)
  local hours = math.floor((ms % units.DAY_MS) / units.HOUR_MS)
  if hours > 0 then
    return translated("duration.days_hours", "{d}d {h}h", { d = days, h = hours })
  end
  return translated("duration.days", "{n} days", { n = days })
end

local function sameDay(first, second)
  return first.year == second.year and first.month == second.month and first.day == second.day
end

function M.formatClock(time, now)
  local date = os.date("*t", math.floor(time / 1000))
  local clock = os.date("%H:%M", math.floor(time / 1000))
  local today = os.date("*t", math.floor(now / 1000))
  if sameDay(date, today) then
    return clock
  end
  if math.abs(time - now) < units.WEEK_MS - units.DAY_MS then
    return os.date("%a ", math.floor(time / 1000)) .. clock
  end
  return os.date("%b %d", math.floor(time / 1000))
end

function M.formatWeekdayClock(time)
  return os.date("%a %H:%M", math.floor(time / 1000))
end

function M.describeError(error)
  if not error then
    return ""
  end
  local reason = M.reasonText(error)
  if error.kind == http.ERROR_KIND.CANNOT_CONNECT then
    return translated("error.cannot_connect", "Cannot connect ({reason})", { reason = reason })
  end
  if error.kind == http.ERROR_KIND.KEY_REJECTED then
    return translated("error.key_rejected", "Key rejected ({reason})", { reason = reason })
  end
  if error.kind == http.ERROR_KIND.RATE_LIMITED then
    return translated("error.rate_limited", "Rate limited")
  end
  if error.kind == http.ERROR_KIND.UNEXPECTED_ANSWER then
    return translated("error.unexpected_answer", "Unexpected answer ({reason})", { reason = reason })
  end
  local text = reason:sub(1, 1):upper() .. reason:sub(2)
  return text
end

function M.isWindowActive(item, now)
  local reset = item.resetsAt == nil or item.resetsAt > now
  local valid = item.validUntil == nil or item.validUntil > now
  return reset and valid
end

local function resetText(item, now, isExpired)
  if isExpired then
    if item.resetsAt ~= nil and item.resetsAt <= now then
      return translated("reset.at_no_newer", "Reset at {time}, no newer data", { time = M.formatClock(item.resetsAt, now) })
    end
    return translated("reset.no_newer", "No newer data")
  end
  if item.resetsAt == nil then
    return ""
  end
  if item.estimated then
    local time = item.period == usage.PERIOD.WEEKLY and M.formatWeekdayClock(item.resetsAt) or M.formatClock(item.resetsAt, now)
    return translated("reset.about", "Resets about {time}", { time = time })
  end
  return translated("reset.in", "Resets in {duration} ({time})", {
    duration = M.formatDuration(item.resetsAt - now),
    time = M.formatClock(item.resetsAt, now),
  })
end

local function windowView(item, now)
  local isExpired = not M.isWindowActive(item, now)
  return {
    label = M.windowLabel(item),
    percentText = M.formatPercent(item.usedPercent),
    fraction = math.max(0, math.min(item.usedPercent / units.PERCENT, 1)),
    severity = isExpired and M.SEVERITY.UNKNOWN or M.severityFor(item.usedPercent),
    resetText = resetText(item, now, isExpired),
    isExpired = isExpired,
  }
end

local function amountText(item)
  local value = M.formatMoney(item.value, item.currency)
  if item.noLimit then
    return translated("amount.no_limit", "{value}, no limit", { value = value })
  end
  if item.limit == nil then
    return value
  end
  return translated("amount.of_limit", "{value} of {limit}", {
    value = value,
    limit = M.formatMoney(item.limit, item.currency),
  })
end

local function rankOf(item, now)
  return (item.canBeMain and 2 or 0) + (M.isWindowActive(item, now) and 1 or 0)
end

local function bestWindow(candidates, now)
  local best = candidates[1]
  for _, item in ipairs(candidates) do
    local rank = rankOf(item, now)
    local bestRank = rankOf(best, now)
    if rank > bestRank or (rank == bestRank and item.usedPercent > best.usedPercent) then
      best = item
    end
  end
  return best
end

function M.splitWindows(windows, now)
  local main = {}
  local extra = {}
  local inMain = {}
  for _, period in ipairs(MAIN_PERIODS) do
    local candidates = {}
    for _, item in ipairs(windows) do
      if item.period == period then
        table.insert(candidates, item)
      end
    end
    if #candidates > 0 then
      local chosen = bestWindow(candidates, now)
      table.insert(main, chosen)
      inMain[chosen] = true
    end
  end
  for _, item in ipairs(windows) do
    if not inMain[item] then
      table.insert(extra, item)
    end
  end
  return { main = main, extra = extra }
end

local function isMainAmount(item)
  if item.name ~= "" then
    return false
  end
  for _, label in ipairs(MAIN_AMOUNT_LABELS) do
    if item.label == label then
      return true
    end
  end
  return false
end

local function mainAmounts(amounts)
  local result = {}
  for _, label in ipairs(MAIN_AMOUNT_LABELS) do
    for _, item in ipairs(amounts) do
      if item.name == "" and item.label == label then
        table.insert(result, item)
        break
      end
    end
  end
  return result
end

local function amountRow(item)
  if item.problem then
    return { label = M.labelText(item), valueText = M.describeError(item.problem), isProblem = true }
  end
  return { label = M.labelText(item), valueText = amountText(item), isProblem = false }
end

local function extraRows(usageValue, extraWindows)
  local entries = {}
  for _, item in ipairs(extraWindows) do
    if item.period ~= usage.PERIOD.TOP_UP then
      table.insert(entries, { label = M.windowLabel(item), valueText = M.formatPercent(item.usedPercent), isProblem = false })
    end
  end
  for _, item in ipairs(usageValue.amounts) do
    if not isMainAmount(item) then
      table.insert(entries, amountRow(item))
    end
  end
  local topUps = {}
  for _, item in ipairs(extraWindows) do
    if item.period == usage.PERIOD.TOP_UP then
      table.insert(topUps, { label = M.windowLabel(item), valueText = M.formatPercent(item.usedPercent), isProblem = false })
    end
  end
  local rows = {}
  for _, item in ipairs(usageValue.counts) do
    table.insert(rows, { label = M.labelText(item), valueText = M.formatCount(item.value), isProblem = false })
  end
  for _, item in ipairs(usageValue.texts) do
    table.insert(rows, { label = M.labelText(item), valueText = item.value, isProblem = false })
  end
  for _, row in ipairs(entries) do
    table.insert(rows, row)
  end
  for _, row in ipairs(topUps) do
    table.insert(rows, row)
  end
  return rows
end

local NO_USAGE = { windows = {}, amounts = {}, counts = {}, texts = {} }

local function mainBarView(item, now)
  local view = windowView(item, now)
  view.label = M.periodText(item)
  return view
end

local function sectionView(entry, now)
  local usageValue = entry.usage or NO_USAGE
  local split = M.splitWindows(usageValue.windows, now)
  local windows = {}
  for _, item in ipairs(split.main) do
    table.insert(windows, mainBarView(item, now))
  end
  local mainRows = {}
  for _, item in ipairs(mainAmounts(usageValue.amounts)) do
    table.insert(mainRows, amountRow(item))
  end
  local title = entry.title
  local translatedTitle = tr("provider." .. tostring(entry.providerId) .. ".title")
  if translatedTitle ~= nil then
    title = translatedTitle
  end
  return {
    key = entry.key,
    service = entry.providerId,
    title = title,
    account = privacy.displayName(entry.account and entry.account.name or ""),
    windows = windows,
    mainRows = mainRows,
    rows = extraRows(usageValue, split.extra),
    isLoading = entry.isLoading == true,
    hasError = entry.error ~= nil,
    errorText = entry.error and M.describeError(entry.error) or "",
    errorSeverity = entry.error and CRITICAL_ERRORS[entry.error.kind] and M.SEVERITY.CRITICAL or M.SEVERITY.WARNING,
  }
end

function M.buildViewModel(entries, now)
  local sections = {}
  local byKey = {}
  local hasErrors = false
  local walletLocked = false
  for _, entry in ipairs(entries or {}) do
    local section = sectionView(entry, now)
    table.insert(sections, section)
    byKey[section.key] = section
    if section.hasError then
      hasErrors = true
    end
    if entry.error and LOCKED_WALLET_REASONS[entry.error.reason] then
      walletLocked = true
    end
  end
  return {
    sections = sections,
    keys = sections,
    sectionsByKey = byKey,
    hasErrors = hasErrors,
    hasAccounts = #sections > 0,
    walletLocked = walletLocked,
  }
end

function M.summaryText(usageValue)
  local parts = {}
  for _, item in ipairs(usageValue.windows) do
    table.insert(parts, M.windowLabel(item) .. " " .. M.formatPercent(item.usedPercent))
  end
  return table.concat(parts, ", ")
end

return M
