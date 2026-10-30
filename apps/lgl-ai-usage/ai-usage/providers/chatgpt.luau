-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Codex session rate-limit lines. Port of providers/chatgpt.mjs.

local http = require("../lib/http.luau")
local values = require("../lib/values.luau")
local units = require("../lib/units.luau")
local usage = require("../lib/usage.luau")
local localread = require("../lib/localread.luau")
local kind = require("../lib/providerkind.luau")
local common = require("./common.luau")

local M = {}

M.MAX_LINE_BYTES = 65536
M.MAX_FILES = 20

local WINDOW_FIELDS = { "primary", "secondary" }

M.READ_SESSION_COMMAND = localread.wrapRead(
  "d=\"$HOME/.codex/sessions\"; "
    .. "if [ -n \"${CODEX_HOME:-}\" ] && [ -d \"$CODEX_HOME/sessions\" ]; then d=\"$CODEX_HOME/sessions\"; fi; "
    .. "files=$(" .. localread.LIMIT .. " find \"$d\" -type f -name \"rollout-*.jsonl\" -printf \"%T@ %p\\n\" 2>/dev/null | sort -rn | head -n "
    .. M.MAX_FILES .. " | cut -d \" \" -f 2-); "
    .. "if [ -z \"$files\" ]; then " .. localread.MISSING_OUTPUT .. "; else "
    .. "line=$(printf \"%s\\n\" \"$files\" | while IFS= read -r f; do "
    .. "if [ -f \"$f\" ] && [ ! -L \"$f\" ]; then l=$(" .. localread.LIMIT
    .. " grep -F \"\\\"rate_limits\\\":{\" -- \"$f\" | tail -n 1 | head -c " .. (M.MAX_LINE_BYTES + 1) .. "); "
    .. "if [ -n \"$l\" ]; then printf \"%s\" \"$l\"; break; fi; fi; done); "
    .. localread.foundOutput("line") .. "; fi"
)

local function resetTime(value, lineTime)
  local resetsAt = type(value.resets_at) == "number" and values.toFiniteNumber(value.resets_at) or nil
  if resetsAt ~= nil then
    return resetsAt * units.SECOND_MS
  end
  local resetsIn = type(value.resets_in_seconds) == "number" and values.toFiniteNumber(value.resets_in_seconds) or nil
  if resetsIn ~= nil and lineTime ~= nil then
    return lineTime + resetsIn * units.SECOND_MS
  end
  return nil
end

local function readWindow(value, lineTime)
  if not values.isPlainObject(value) then
    return nil
  end
  local percent = type(value.used_percent) == "number" and values.toFiniteNumber(value.used_percent) or nil
  local minutes = type(value.window_minutes) == "number" and values.toFiniteNumber(value.window_minutes) or nil
  if percent == nil or minutes == nil then
    return nil
  end
  local period = usage.periodForMinutes(minutes)
  return usage.usageWindow(period.period, "", percent, resetTime(value, lineTime), { count = period.count })
end

local function rateLimitsOf(text)
  local decoded = noctalia.json.decode(text)
  if not values.isPlainObject(decoded) or not values.isPlainObject(decoded.payload)
    or not values.isPlainObject(decoded.payload.rate_limits) then
    return nil
  end
  return {
    limits = decoded.payload.rate_limits,
    lineTime = values.parseIsoTime(decoded.timestamp),
  }
end

local function interpret(read)
  if not read.found then
    return usage.notAvailable(http.REASON.CODEX_MISSING)
  end
  if read.text:match("^%s*$") then
    return usage.notAvailable(http.REASON.CODEX_NO_LIMITS)
  end
  local found = rateLimitsOf(read.text)
  if found == nil then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  local windows = {}
  for _, field in ipairs(WINDOW_FIELDS) do
    if found.limits[field] ~= nil then
      local window = readWindow(found.limits[field], found.lineTime)
      if window == nil then
        return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
      end
      table.insert(windows, window)
    end
  end
  if #windows == 0 then
    return usage.unexpected(http.REASON.FILE_FORMAT_CHANGED)
  end
  return usage.succeeded(usage.makeUsage({ windows = windows }))
end

return {
  id = "chatgpt",
  title = "ChatGPT",
  kind = kind.LOCAL,
  minIntervalSeconds = common.NO_MIN_INTERVAL_SECONDS,
  needsKey = false,
  keyHelp = "",
  fields = common.NO_FIELDS,
  readCommand = M.READ_SESSION_COMMAND,
  maxReadBytes = M.MAX_LINE_BYTES,
  interpret = interpret,
  rateLimitsOf = rateLimitsOf,
}
