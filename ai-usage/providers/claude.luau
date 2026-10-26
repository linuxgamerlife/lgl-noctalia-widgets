-- Claude desktop app history file. Port of providers/claudeDesktop.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local accounts = require("../lib/accounts.luau")
local localread = require("../lib/localread.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.MAX_HISTORY_BYTES = 1048576
M.HISTORY_VERSION = 2

local FIVE_HOURS_MS = 5 * units.HOUR_MS
local CLEAR_DROP_POINTS = 10
local MAX_SAMPLE_GAP_MS = 30 * units.MINUTE_MS
local WINDOWS = {
  {
    field = "fh",
    period = usage.PERIOD.FIVE_HOUR,
    lengthMs = FIVE_HOURS_MS,
    estimate = function(samples, now)
      return M.estimateFiveHourReset(samples, now)
    end,
  },
  {
    field = "sd",
    period = usage.PERIOD.WEEKLY,
    lengthMs = units.WEEK_MS,
    estimate = function(samples, now)
      return M.estimateWeeklyReset(samples, now)
    end,
  },
}

M.READ_HISTORY_COMMAND = localread.fileReadCommand(
  "\"${XDG_CONFIG_HOME:-$HOME/.config}/Claude/plan-usage-history.json\"",
  M.MAX_HISTORY_BYTES
)

local function readSample(value)
  if not values.isPlainObject(value) or not accounts.isValidField(value.org) or not values.isPlainObject(value.u) then
    return nil
  end
  local time = values.toFiniteNumber(value.t)
  if time == nil then
    return nil
  end
  return { org = value.org, time = time, valuesTable = value.u }
end

function M.samplesByOrg(text)
  local decoded, _ = noctalia.json.decode(text)
  if not values.isPlainObject(decoded) or decoded.version ~= M.HISTORY_VERSION or type(decoded.samples) ~= "table" then
    return nil
  end
  local byOrg = {}
  local order = {}
  for _, sampleValue in ipairs(decoded.samples) do
    local sample = readSample(sampleValue)
    if sample ~= nil then
      if byOrg[sample.org] == nil then
        byOrg[sample.org] = {}
        table.insert(order, sample.org)
      end
      table.insert(byOrg[sample.org], sample)
    end
  end
  for _, org in ipairs(order) do
    table.sort(byOrg[org], function(first, second)
      return first.time < second.time
    end)
  end
  return byOrg, order
end

local function seriesOf(samples, field)
  local series = {}
  for _, sample in ipairs(samples) do
    local value = sample.valuesTable[field]
    if type(value) == "number" then
      table.insert(series, { time = sample.time, percent = values.toFiniteNumber(value) })
    end
  end
  return series
end

local function isClearDrop(previous, current)
  return previous.percent - current.percent >= CLEAR_DROP_POINTS
end

local function midpointOf(previous, current)
  if current.time - previous.time > MAX_SAMPLE_GAP_MS then
    return nil
  end
  return (previous.time + current.time) / 2
end

function M.estimateFiveHourReset(samples, now)
  local series = seriesOf(samples, "fh")
  for index = #series, 2, -1 do
    local previous = series[index - 1]
    local current = series[index]
    if current.percent > 0 and (previous.percent == 0 or isClearDrop(previous, current)) then
      local start = midpointOf(previous, current)
      local reset = nil
      if start ~= nil then
        reset = start + FIVE_HOURS_MS
      end
      if reset ~= nil and reset > now then
        return reset
      end
    end
  end
  return nil
end

function M.estimateWeeklyReset(samples, now)
  local series = seriesOf(samples, "sd")
  for index = #series, 2, -1 do
    local previous = series[index - 1]
    local current = series[index]
    if isClearDrop(previous, current) or (current.percent == 0 and previous.percent > 0) then
      local reset = midpointOf(previous, current)
      if reset == nil then
        return nil
      end
      local nextReset = reset + units.WEEK_MS
      while nextReset <= now do
        nextReset = nextReset + units.WEEK_MS
      end
      return nextReset
    end
  end
  return nil
end

local function usageOf(samples, now)
  local sample = samples[#samples]
  local windows = {}
  for _, spec in ipairs(WINDOWS) do
    local value = sample.valuesTable[spec.field]
    if type(value) == "number" then
      table.insert(windows, usage.usageWindow(
        spec.period,
        "",
        values.toFiniteNumber(value),
        spec.estimate(samples, now),
        { validUntil = sample.time + spec.lengthMs, estimated = true }
      ))
    end
  end
  if #windows == 0 then
    return nil
  end
  return usage.makeUsage({ windows = windows })
end

local function interpret(read, account, now)
  if not read.found then
    return usage.notAvailable(http.REASON.CLAUDE_FILE_MISSING)
  end
  local byOrg = M.samplesByOrg(read.text)
  if byOrg == nil then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  if byOrg[account.org] == nil then
    return usage.notAvailable(http.REASON.CLAUDE_ORG_MISSING)
  end
  local result = usageOf(byOrg[account.org], now)
  if result == nil then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  return usage.succeeded(result)
end

local function discover(read, now)
  if not read.found then
    return usage.notAvailable(http.REASON.CLAUDE_FILE_MISSING)
  end
  local byOrg, order = M.samplesByOrg(read.text)
  if byOrg == nil then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  table.sort(order)
  local items = {}
  for _, org in ipairs(order) do
    local orgUsage = usageOf(byOrg[org], now)
    if orgUsage ~= nil then
      table.insert(items, { fields = { org = org }, usage = orgUsage })
    end
  end
  return { ok = true, items = items }
end

return {
  id = "claude",
  title = "Claude",
  kind = kind.LOCAL,
  minIntervalSeconds = common.NO_MIN_INTERVAL_SECONDS,
  needsKey = false,
  keyHelp = "",
  fields = { { id = "org", label = "Organization", typed = false } },
  readCommand = M.READ_HISTORY_COMMAND,
  maxReadBytes = M.MAX_HISTORY_BYTES,
  interpret = interpret,
  discover = discover,
  discoveryText = {
    reading = usage.DISCOVERY.CLAUDE_READING,
    none = usage.DISCOVERY.CLAUDE_NONE_NEW,
  },
  samplesByOrg = M.samplesByOrg,
  estimateFiveHourReset = M.estimateFiveHourReset,
  estimateWeeklyReset = M.estimateWeeklyReset,
}
