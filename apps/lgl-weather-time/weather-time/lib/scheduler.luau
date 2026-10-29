-- Refresh scheduling and bounded exponential backoff.

local M = {}

M.MIN_MINUTES = 5
M.MAX_MINUTES = 120
M.MAX_BACKOFF_MINUTES = 60

function M.refresh_minutes(value, fallback)
  local minutes = tonumber(value) or fallback or 15
  if minutes < M.MIN_MINUTES then
    return M.MIN_MINUTES
  end
  if minutes > M.MAX_MINUTES then
    return M.MAX_MINUTES
  end
  return math.floor(minutes + 0.5)
end

function M.is_due(now, next_at)
  if type(now) ~= "number" or type(next_at) ~= "number" then
    return false
  end
  return now >= next_at
end

function M.backoff_minutes(refresh_minutes, failures)
  local exponent = math.max((tonumber(failures) or 1) - 1, 0)
  if exponent > 10 then
    exponent = 10
  end
  local delay = refresh_minutes * (2 ^ exponent)
  if delay > M.MAX_BACKOFF_MINUTES then
    delay = M.MAX_BACKOFF_MINUTES
  end
  return math.max(1, math.floor(delay + 0.5))
end

function M.next_after_success(now, refresh_minutes)
  return now + refresh_minutes * 60
end

function M.next_after_failure(now, refresh_minutes, failures)
  return now + M.backoff_minutes(refresh_minutes, failures) * 60
end

function M.is_stale(now, fetched_at, refresh_minutes)
  if type(now) ~= "number" or type(fetched_at) ~= "number" or fetched_at <= 0 then
    return true
  end
  return now - fetched_at > refresh_minutes * 60 * 2
end

return M
