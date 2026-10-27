-- Backoff and due-time rules. Port of core/scheduler.mjs.

local http = require("./http.luau")
local units = require("./units.luau")

local M = {}

M.MAX_BACKOFF_MS = units.HOUR_MS

local MAX_DOUBLINGS = 32
local REASONS_WITHOUT_BACKOFF = { [http.REASON.NO_CONNECTION] = true }
local REASONS_BEFORE_ANY_REQUEST = {
  [http.REASON.NO_KEY] = true,
  [http.REASON.KEY_FORMAT] = true,
  [http.REASON.SECRET_SERVICE_TIMEOUT] = true,
  [http.REASON.SECRET_SERVICE_UNAVAILABLE] = true,
  [http.REASON.WALLET_LOCKED] = true,
  [http.REASON.TOOL_MISSING] = true,
}

function M.backoffDelayMs(intervalMs, consecutiveFailures)
  local exponent = math.max(consecutiveFailures - 1, 0)
  local cap = math.max(M.MAX_BACKOFF_MS, intervalMs)
  if exponent >= MAX_DOUBLINGS then
    return cap
  end
  return math.min(intervalMs * math.pow(2, exponent), cap)
end

function M.nextAttemptAfterSuccess(now, intervalMs)
  return now + intervalMs
end

function M.nextAttemptAfterFailure(now, intervalMs, consecutiveFailures, error)
  local failures = REASONS_WITHOUT_BACKOFF[error.reason] and 1 or consecutiveFailures
  local afterBackoff = now + M.backoffDelayMs(intervalMs, failures)
  if error.retryAt then
    return math.max(afterBackoff, error.retryAt)
  end
  return afterBackoff
end

function M.isDue(entry, now)
  if entry.isLoading then
    return false
  end
  local clockMovedBack = entry.lastAttemptAt ~= nil and now < entry.lastAttemptAt
  return clockMovedBack or now >= entry.nextAttemptAt
end

function M.manualRefreshAt(entry, now, minIntervalMs)
  if entry.error and REASONS_BEFORE_ANY_REQUEST[entry.error.reason] then
    return now
  end
  local earliest = entry.lastAttemptAt == nil and now or math.max(now, entry.lastAttemptAt + minIntervalMs)
  if entry.error and entry.error.kind == http.ERROR_KIND.RATE_LIMITED then
    return math.max(earliest, entry.nextAttemptAt)
  end
  local refreshAt = math.min(earliest, math.max(entry.nextAttemptAt, now))
  if entry.error and entry.error.retryAt then
    return math.max(refreshAt, entry.error.retryAt)
  end
  return refreshAt
end

return M
