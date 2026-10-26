-- Read-only local sources with a hard timeout and a byte cap. Port of
-- core/localRead.mjs. The shell commands contain no user input.

local http = require("./http.luau")
local shell = require("./shell.luau")

local M = {}

M.LOCAL_TOOL_TIMEOUT_SECONDS = 8
M.OVERALL_TIMEOUT_SECONDS = 9
M.LOCAL_READ_TIMEOUT_MS = 15000
M.LIMIT = "timeout " .. M.LOCAL_TOOL_TIMEOUT_SECONDS
M.FOUND_LINE = "found"
M.MISSING_LINE = "missing"

local FOUND_PATTERN = "^found (%d+)$"

M.MISSING_OUTPUT = "printf \"" .. M.MISSING_LINE .. "\\n\""

function M.wrapRead(script)
  return "timeout " .. M.OVERALL_TIMEOUT_SECONDS .. " sh -c " .. shell.quote(script)
end

function M.foundOutput(variable)
  return "printf \"" .. M.FOUND_LINE .. " %s\\n\" \"$(printf \"%s\" \"$" .. variable
    .. "\" | wc -c | tr -d \" \")\"; printf \"%s\" \"$" .. variable .. "\""
end

function M.fileReadCommand(pathExpression, maxBytes)
  return M.wrapRead("f=" .. pathExpression .. "; "
    .. "if [ -f \"$f\" ] && [ ! -L \"$f\" ]; then size=$(" .. M.LIMIT .. " wc -c < \"$f\" | tr -d \" \"); "
    .. "printf \"" .. M.FOUND_LINE .. " %s\\n\" \"$size\"; " .. M.LIMIT .. " head -c " .. maxBytes .. " -- \"$f\"; "
    .. "else " .. M.MISSING_OUTPUT .. "; fi")
end

local function readFailed()
  return { ok = false, error = http.failure(http.ERROR_KIND.CANNOT_CONNECT, http.REASON.FILE_READ_FAILED) }
end

local function tooLarge(maxBytes)
  return {
    ok = false,
    error = http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, http.REASON.FILE_TOO_LARGE, nil, { size = maxBytes }),
  }
end

function M.parseLocalRead(result, maxBytes)
  if not result or result.timedOut or type(result.stdout) ~= "string" then
    return readFailed()
  end
  local lineEnd = result.stdout:find("\n", 1, true)
  local first = lineEnd == nil and result.stdout or result.stdout:sub(1, lineEnd - 1)
  local text = lineEnd == nil and "" or result.stdout:sub(lineEnd + 1)
  if first == M.MISSING_LINE then
    return { ok = true, found = false, text = "" }
  end
  local size = first:match(FOUND_PATTERN)
  if size == nil then
    return readFailed()
  end
  if tonumber(size) > maxBytes then
    return tooLarge(maxBytes)
  end
  return { ok = true, found = true, text = text }
end

function M.readLocalFile(provider, runCommand, callback)
  runCommand(provider.readCommand, M.LOCAL_READ_TIMEOUT_MS, function(result)
    local parsed = M.parseLocalRead(result, provider.maxReadBytes)
    if not parsed.ok then
      callback(parsed)
      return
    end
    callback(parsed)
  end)
end

return M
