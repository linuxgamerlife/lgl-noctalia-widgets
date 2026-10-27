-- Numeric constants shared by every module. Lua 5.1 compatible (LuaJIT tests).

local M = {}

M.PERCENT = 100
M.SECOND_MS = 1000
M.MINUTE_MS = 60 * M.SECOND_MS
M.HOUR_MS = 60 * M.MINUTE_MS
M.DAY_MS = 24 * M.HOUR_MS
M.WEEK_MS = 7 * M.DAY_MS
M.CENTS_PER_DOLLAR = 100
M.KIB = 1024
M.MIB = M.KIB * M.KIB

function M.clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

return M
