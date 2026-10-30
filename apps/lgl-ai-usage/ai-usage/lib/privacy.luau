-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Privacy helpers for account labels. A label that looks like an email address
-- is masked before it reaches the published state or any rendered surface.

local M = {}

local EMAIL_PATTERN = "^[%w%.%_%+%-]+@[%w%.%-]+%.%a%a+$"

function M.isEmail(value)
  return type(value) == "string" and value:match(EMAIL_PATTERN) ~= nil
end

function M.displayName(value)
  if type(value) ~= "string" then
    return ""
  end
  if not M.isEmail(value) then
    return value
  end
  local first = value:sub(1, 1)
  return (first ~= "" and first or "?") .. "***"
end

return M
