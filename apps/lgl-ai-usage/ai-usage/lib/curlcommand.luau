-- One shell pipeline per check: secret-tool reads the key, curl receives the
-- auth header on stdin, and a random boundary frames each answer. Port of
-- core/curlCommand.mjs. The key never reaches a process argument list.

local http = require("./http.luau")
local secrets = require("./secrets.luau")
local shell = require("./shell.luau")
local units = require("./units.luau")
local values = require("./values.luau")

local M = {}

M.SECRET_TOOL_TIMEOUT_SECONDS = 10
M.CURL_MAX_TIME_SECONDS = 20
M.CURL_KILL_AFTER_SECONDS = 25
M.MAX_RESPONSE_BYTES = 1048576
M.BOUNDARY_PATTERN = "^aiu%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"

local COMMAND_MARGIN_SECONDS = 5
local BOUNDARY_DIGITS = 24
local REQUEST_ID_PATTERN = "^[a-z][a-z0-9]*$"
local SECRET_TOOL_TIMED_OUT = "124"
local TOOL_MISSING_CODES = { ["126"] = true, ["127"] = true }
local CURL_TIMEOUT_CODES = { [28] = true, [124] = true }
local CURL_CONNECTION_CODES = { [6] = true, [7] = true }
local CURL_TOOL_MISSING_CODES = { [126] = true, [127] = true }
local CURL_TOO_LARGE_CODE = 63
local SAFE_START = "ulimit -c 0; set +a +x +v; unset SSLKEYLOGFILE key rc found"
local HEADER_FORMAT = "%s: %s%s\\n"

function M.newBoundary()
  return "aiu" .. values.randomHex(BOUNDARY_DIGITS)
end

function M.commandTimeoutMs(requestCount)
  return (2 * M.SECRET_TOOL_TIMEOUT_SECONDS + requestCount * M.CURL_KILL_AFTER_SECONDS + COMMAND_MARGIN_SECONDS) * units.SECOND_MS
end

local function marker(boundary, word, value)
  return "printf " .. shell.quote("%s " .. word .. " %s\\n") .. " " .. shell.quote(boundary) .. " " .. value
end

local function lineMarker(boundary, word, value)
  return "printf " .. shell.quote("\\n%s " .. word .. " %s\\n") .. " " .. shell.quote(boundary) .. " " .. value
end

local function curlPart(spec, request)
  if not request.id:match(REQUEST_ID_PATTERN) then
    error("the request id is not allowed")
  end
  local fixedHeaders = {}
  for _, header in ipairs(request.headers) do
    table.insert(fixedHeaders, "-H " .. shell.quote(header))
  end
  local headerArgs = #fixedHeaders > 0 and (table.concat(fixedHeaders, " ") .. " ") or ""
  local writeOut = "\\n" .. spec.boundary .. " end %{http_code} %header{retry-after}\\n"
  local curl = "printf " .. shell.quote(HEADER_FORMAT) .. " " .. shell.quote(spec.auth.header) .. " "
    .. shell.quote(spec.auth.prefix) .. " \"$key\" | timeout " .. M.CURL_KILL_AFTER_SECONDS
    .. " curl --disable --silent --show-error --globoff --tlsv1.2 --proto " .. shell.quote("=https")
    .. " --max-redirs 0 --max-time " .. M.CURL_MAX_TIME_SECONDS
    .. " --max-filesize " .. M.MAX_RESPONSE_BYTES
    .. " -H @- " .. headerArgs
    .. "-w " .. shell.quote(writeOut) .. " " .. shell.quoteUrl(request.url)
  return table.concat({
    marker(spec.boundary, "begin", shell.quote(request.id)),
    curl,
    lineMarker(spec.boundary, "curl", "\"$?\""),
  }, "; ")
end

function M.buildCheckCommand(spec)
  if not spec.boundary:match(M.BOUNDARY_PATTERN) then
    error("the boundary is not allowed")
  end
  local lockedGuard = nil
  if not secrets.usesLocalFile() then
    lockedGuard = "found=$(timeout " .. M.SECRET_TOOL_TIMEOUT_SECONDS .. " "
      .. secrets.buildSearchPart(spec.providerId, spec.account) .. " 2>/dev/null); "
      .. "case \"$found\" in \"(@ao [], [objectpath \"*) " .. marker(spec.boundary, "lookup", shell.quote("locked"))
      .. "; exit 0;; esac"
  end
  local lookup = "key=$(timeout " .. M.SECRET_TOOL_TIMEOUT_SECONDS .. " "
    .. secrets.buildLookupPart(spec.providerId, spec.account) .. "); rc=$?"
  local lookupGuard = "if [ \"$rc\" -ne 0 ]; then " .. marker(spec.boundary, "lookup", "\"$rc\"") .. "; exit 0; fi"
  local keyGuard = "case \"$key\" in "
    .. "'') " .. marker(spec.boundary, "lookup", shell.quote("empty")) .. "; exit 0;; "
    .. "*[!!-~]*) " .. marker(spec.boundary, "lookup", shell.quote("invalid")) .. "; exit 0;; esac"
  local parts = { SAFE_START }
  if lockedGuard then
    table.insert(parts, lockedGuard)
  end
  table.insert(parts, lookup)
  table.insert(parts, lookupGuard)
  table.insert(parts, keyGuard)
  for _, request in ipairs(spec.requests) do
    table.insert(parts, curlPart(spec, request))
  end
  return table.concat(parts, "; ")
end

local function lookupFailure(value, stderr)
  if value == "locked" then
    return http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.WALLET_LOCKED)
  end
  if value == SECRET_TOOL_TIMED_OUT then
    return http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.SECRET_SERVICE_TIMEOUT)
  end
  if TOOL_MISSING_CODES[value] then
    return http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.TOOL_MISSING)
  end
  if value == "invalid" then
    return http.failure(http.ERROR_KIND.NO_KEY, http.REASON.KEY_FORMAT)
  end
  if value ~= "empty" and type(stderr) == "string" and stderr:match("%S") then
    return http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.SECRET_SERVICE_UNAVAILABLE)
  end
  return http.failure(http.ERROR_KIND.NO_KEY, http.REASON.NO_KEY)
end

local function findLine(text, prefix, from)
  local start = text:find(prefix, from, true)
  if start == nil then
    return nil
  end
  local finish = text:find("\n", start + #prefix, true)
  local valueEnd = finish == nil and #text or finish - 1
  return {
    start = start,
    finish = finish,
    value = text:sub(start + #prefix, valueEnd),
  }
end

local function replyFromCurl(curlCode, status, body, retryAfter)
  if curlCode == 0 then
    return {
      kind = "response",
      status = status,
      body = body,
      header = function(name)
        if name:lower() == "retry-after" and retryAfter ~= "" then
          return retryAfter
        end
        return nil
      end,
    }
  end
  if CURL_TIMEOUT_CODES[curlCode] then
    return { kind = "timeout" }
  end
  if CURL_CONNECTION_CODES[curlCode] then
    return { kind = "network" }
  end
  if curlCode == CURL_TOO_LARGE_CODE then
    return { kind = "too_large" }
  end
  if CURL_TOOL_MISSING_CODES[curlCode] then
    return { kind = "tool_missing" }
  end
  return { kind = "curl_error", code = curlCode }
end

local INCOMPLETE = { kind = "incomplete" }

local function readBlock(stdout, boundary, id)
  local beginMarker = boundary .. " begin " .. id .. "\n"
  local beginAt = stdout:find(beginMarker, 1, true)
  if beginAt == nil then
    return INCOMPLETE
  end
  local bodyStart = beginAt + #beginMarker
  local curlLine = findLine(stdout, "\n" .. boundary .. " curl ", bodyStart - 1)
  if curlLine == nil then
    return INCOMPLETE
  end
  local curlCode = tonumber(curlLine.value)
  if curlCode ~= 0 then
    return replyFromCurl(curlCode)
  end
  local endMarker = nil
  local searchFrom = math.max(bodyStart - 1, 1)
  while true do
    local found = stdout:find("\n" .. boundary .. " end ", searchFrom, true)
    if found == nil or found >= curlLine.start then
      break
    end
    endMarker = found
    searchFrom = found + 1
  end
  if endMarker == nil or endMarker < bodyStart - 1 then
    return INCOMPLETE
  end
  local endLine = findLine(stdout, boundary .. " end ", endMarker + 1)
  if endLine == nil then
    return INCOMPLETE
  end
  local separator = endLine.value:find(" ", 1, true)
  local status = separator == nil and tonumber(endLine.value) or tonumber(endLine.value:sub(1, separator - 1))
  local retryAfter = separator == nil and "" or endLine.value:sub(separator + 1):match("^%s*(.-)%s*$")
  return replyFromCurl(curlCode, status, stdout:sub(bodyStart, endMarker - 1), retryAfter)
end

function M.parseCheckOutput(result, requests, boundary)
  if not result or result.timedOut or type(result.stdout) ~= "string" then
    return { ok = false, error = http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.REQUEST_TIMEOUT) }
  end
  local lookup = findLine(result.stdout, boundary .. " lookup ", 1)
  if lookup ~= nil then
    return { ok = false, error = lookupFailure(lookup.value, result.stderr) }
  end
  local replies = {}
  for _, request in ipairs(requests) do
    table.insert(replies, readBlock(result.stdout, boundary, request.id))
  end
  return { ok = true, replies = replies }
end

return M
