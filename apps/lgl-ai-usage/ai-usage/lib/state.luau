-- Immutable per-account state. Port of core/state.mjs.

local scheduler = require("./scheduler.luau")

local M = {}

function M.createEntry(spec)
  local lastAttemptAt = spec.lastAttemptAt
  return {
    key = spec.account.id,
    providerId = spec.account.service,
    account = spec.account,
    title = spec.title,
    intervalMs = spec.intervalMs,
    usage = nil,
    error = nil,
    lastSuccessAt = nil,
    lastAttemptAt = lastAttemptAt,
    nextAttemptAt = lastAttemptAt == nil and 0 or lastAttemptAt + spec.intervalMs,
    consecutiveFailures = 0,
    isLoading = false,
  }
end

local function update(entry, changes)
  local copy = {}
  for key, value in pairs(entry) do
    copy[key] = value
  end
  for key, value in pairs(changes) do
    copy[key] = value
  end
  return copy
end

function M.markLoading(entry, now)
  return update(entry, { isLoading = true, lastAttemptAt = now })
end

function M.applySuccess(entry, usage, now)
  return update(entry, {
    usage = usage,
    error = nil,
    lastSuccessAt = now,
    lastAttemptAt = now,
    nextAttemptAt = scheduler.nextAttemptAfterSuccess(now, entry.intervalMs),
    consecutiveFailures = 0,
    isLoading = false,
  })
end

function M.applyFailure(entry, error, now)
  local failures = entry.consecutiveFailures + 1
  return update(entry, {
    error = error,
    lastAttemptAt = now,
    nextAttemptAt = scheduler.nextAttemptAfterFailure(now, entry.intervalMs, failures, error),
    consecutiveFailures = failures,
    isLoading = false,
  })
end

function M.withInterval(entry, intervalMs)
  if entry.intervalMs == intervalMs then
    return entry
  end
  local isHealthy = entry.consecutiveFailures == 0 and entry.lastAttemptAt ~= nil
  return update(entry, {
    intervalMs = intervalMs,
    nextAttemptAt = isHealthy and entry.lastAttemptAt + intervalMs or entry.nextAttemptAt,
  })
end

function M.withAccount(entry, account)
  if entry.account == account then
    return entry
  end
  return update(entry, { account = account })
end

function M.dueNow(entry, now)
  if entry.isLoading then
    return entry
  end
  return update(entry, { nextAttemptAt = now })
end

return M
