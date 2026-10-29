-- ISO date helpers that do not depend on the host locale or timezone.
-- Used for forecast weekday labels and for dropping past forecast days.

local M = {}

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function M.is_leap(year)
  return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

function M.days_in_month(year, month)
  if month == 2 and M.is_leap(year) then
    return 29
  end
  return DAYS[month]
end

function M.parse_iso(value)
  if type(value) ~= "string" then
    return nil
  end
  local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if year == nil then
    return nil
  end
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if month < 1 or month > 12 or day < 1 or day > M.days_in_month(year, month) then
    return nil
  end
  return { year = year, month = month, day = day }
end

-- Days since 1970-01-01 for a proleptic Gregorian date. Howard Hinnant's
-- civil-from-days algorithm is used in reverse; it is exact for all years.
function M.days_from_civil(year, month, day)
  local y = year
  if month <= 2 then
    y = y - 1
  end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = month + (month > 2 and -3 or 9)
  local doy = math.floor((153 * mp + 2) / 5) + day - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

function M.civil_from_days(days)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local day = doy - math.floor((153 * mp + 2) / 5) + 1
  local month = mp + (mp < 10 and 3 or -9)
  if month <= 2 then
    y = y + 1
  end
  return y, month, day
end

function M.weekday(value)
  local parsed = type(value) == "table" and value or M.parse_iso(value)
  if parsed == nil then
    return nil
  end
  -- 1970-01-01 was a Thursday. Return 1 = Monday … 7 = Sunday.
  local days = M.days_from_civil(parsed.year, parsed.month, parsed.day)
  local zero_based = (days + 3) % 7 -- 0 = Monday
  return zero_based + 1
end

function M.noon_epoch(value)
  local parsed = type(value) == "table" and value or M.parse_iso(value)
  if parsed == nil then
    return nil
  end
  return M.days_from_civil(parsed.year, parsed.month, parsed.day) * 86400 + 12 * 3600
end

function M.add_days(value, count)
  local parsed = type(value) == "table" and value or M.parse_iso(value)
  if parsed == nil then
    return nil
  end
  local days = M.days_from_civil(parsed.year, parsed.month, parsed.day) + (tonumber(count) or 0)
  local y, m, d = M.civil_from_days(days)
  return string.format("%04d-%02d-%02d", y, m, d)
end

return M
