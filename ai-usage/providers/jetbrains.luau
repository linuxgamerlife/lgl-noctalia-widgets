-- JetBrains AI quota lines from IDE logs. Port of providers/jetbrains.mjs.
-- Only the timestamp and the quota parts are parsed; any licence or quota ids
-- on the line stay inside the service VM and are never published.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local localread = require("../lib/localread.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.QUOTA_MARKER = "QuotaManager2Impl - New quota state is: Available("
M.LOG_TAIL_BYTES = 4194304
M.MAX_LINE_CHARACTERS = 4000

local NUMBER = "(-?%d+%.?%d+)"
local TARIFF_PATTERN = "tariffQuota=Details%(current=" .. NUMBER .. ", maximum=" .. NUMBER
local TOP_UP_PATTERN = "topUpQuota=Details%(current=" .. NUMBER .. ", maximum=" .. NUMBER

M.READ_LOGS_COMMAND = localread.wrapRead(
  "set -- \"$HOME\"/.cache/JetBrains/*/log/idea.log; "
    .. "if [ -f \"$1\" ]; then line=$("
    .. "for f in \"$@\"; do if [ -f \"$f\" ] && [ ! -L \"$f\" ]; then "
    .. localread.LIMIT .. " tail -c " .. M.LOG_TAIL_BYTES .. " -- \"$f\" | "
    .. localread.LIMIT .. " grep -a -F \"" .. M.QUOTA_MARKER .. "\" | tail -n 1 | cut -c 1-"
    .. M.MAX_LINE_CHARACTERS .. "; fi; done "
    .. "| LC_ALL=C sort | tail -n 1); " .. localread.foundOutput("line") .. "; "
    .. "else " .. localread.MISSING_OUTPUT .. "; fi"
)

local function readDetails(line, pattern)
  local current, maximum = line:match(pattern)
  if current == nil then
    return nil
  end
  local currentNumber = values.toFiniteNumber(current)
  local maximumNumber = values.toFiniteNumber(maximum)
  if currentNumber == nil or maximumNumber == nil then
    return nil
  end
  return { current = currentNumber, maximum = maximumNumber }
end

local function percentOf(details)
  return (details.current / details.maximum) * units.PERCENT
end

local function interpret(read)
  if not read.found then
    return usage.notAvailable(http.REASON.JETBRAINS_LOG_MISSING)
  end
  local line = read.text:match("^%s*(.-)%s*$")
  if line == "" then
    return usage.notAvailable(http.REASON.JETBRAINS_NO_QUOTA)
  end
  local tariff = readDetails(line, TARIFF_PATTERN)
  if tariff == nil or tariff.maximum <= 0 then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  local windows = { usage.usageWindow(usage.PERIOD.MONTHLY, "", percentOf(tariff), nil) }
  local topUp = readDetails(line, TOP_UP_PATTERN)
  if topUp ~= nil and topUp.maximum > 0 then
    table.insert(windows, usage.usageWindow(usage.PERIOD.TOP_UP, "", percentOf(topUp), nil))
  end
  return usage.succeeded(usage.makeUsage({ windows = windows }))
end

return {
  id = "jetbrains",
  title = "JetBrains AI",
  kind = kind.LOCAL,
  minIntervalSeconds = common.NO_MIN_INTERVAL_SECONDS,
  needsKey = false,
  keyHelp = "No key needed, read from the JetBrains IDE log",
  fields = common.NO_FIELDS,
  readCommand = M.READ_LOGS_COMMAND,
  maxReadBytes = 8192,
  interpret = interpret,
  readDetails = readDetails,
}
