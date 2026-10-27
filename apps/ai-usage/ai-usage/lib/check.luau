-- Check one account. Remote providers run one curl pipeline; local providers
-- run one read-only shell command. Port of core/fetchUsage.mjs and check.mjs.

local http = require("./http.luau")
local curl = require("./curlcommand.luau")
local localread = require("./localread.luau")
local usage = require("./usage.luau")
local kind = require("./providerkind.luau")

local M = {}

local function latestRetry(failures)
  local latest = nil
  for _, item in ipairs(failures) do
    if item.retryAt ~= nil then
      latest = latest == nil and item.retryAt or math.max(latest, item.retryAt)
    end
  end
  return latest
end

local function evaluate(provider, requests, replies, now)
  local results = {}
  local rateLimits = {}
  local requiredFailure = nil
  for index, request in ipairs(requests) do
    local error = http.classifyReply(replies[index], now, provider.classify)
    results[request.id] = { reply = replies[index], error = error }
    if error and error.kind == http.ERROR_KIND.RATE_LIMITED then
      table.insert(rateLimits, error)
    elseif error and not request.optional and requiredFailure == nil then
      requiredFailure = error
    end
  end
  if #rateLimits > 0 then
    local first = rateLimits[1]
    return {
      ok = false,
      error = http.failure(first.kind, first.reason, latestRetry(rateLimits), first.params),
    }
  end
  if requiredFailure then
    return { ok = false, error = requiredFailure }
  end
  local ok, result = pcall(provider.interpret, results, now)
  if not ok then
    return usage.unexpected(http.REASON.INTERNAL)
  end
  return result
end

local function fetchUsage(provider, account, tools, callback)
  local requests = nil
  local command = nil
  local boundary = tools.newBoundary()
  local ok = pcall(function()
    requests = provider.buildRequests(tools.now(), account)
    command = curl.buildCheckCommand({
      providerId = provider.id,
      account = account.id,
      auth = provider.auth,
      requests = requests,
      boundary = boundary,
    })
  end)
  if not ok then
    callback(usage.unexpected(http.REASON.INTERNAL))
    return
  end
  tools.runCommand(command, curl.commandTimeoutMs(#requests), function(result)
    local parsed = curl.parseCheckOutput(result, requests, boundary)
    if not parsed.ok then
      callback({ ok = false, error = parsed.error })
      return
    end
    callback(evaluate(provider, requests, parsed.replies, tools.now()))
  end)
end

local function readLocalUsage(provider, account, tools, callback)
  localread.readLocalFile(provider, tools.runCommand, function(read)
    if not read.ok then
      callback({ ok = false, error = read.error })
      return
    end
    local ok, result = pcall(provider.interpret, read, account, tools.now())
    if not ok then
      callback(usage.unexpected(http.REASON.INTERNAL))
      return
    end
    callback(result)
  end)
end

function M.checkAccount(provider, account, tools, callback)
  if provider.kind == kind.LOCAL then
    readLocalUsage(provider, account, tools, callback)
    return
  end
  fetchUsage(provider, account, tools, callback)
end

function M.discoverAccounts(provider, tools, callback)
  if type(provider.discover) ~= "function" then
    callback({ ok = true, items = {} })
    return
  end
  localread.readLocalFile(provider, tools.runCommand, function(read)
    if not read.ok then
      callback({ ok = false, error = read.error })
      return
    end
    local ok, result = pcall(provider.discover, read, tools.now())
    if not ok then
      callback(usage.unexpected(http.REASON.INTERNAL))
      return
    end
    callback(result)
  end)
end

return M
