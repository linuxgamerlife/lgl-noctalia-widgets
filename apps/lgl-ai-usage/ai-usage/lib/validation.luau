-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Identifier validation shared by ids and account fields.

local M = {}

M.LABEL_PATTERN = "^[A-Za-z0-9][A-Za-z0-9_%-]*$"

function M.isValidLabel(value)
  return type(value) == "string" and #value >= 1 and #value <= 32 and value:match(M.LABEL_PATTERN) ~= nil
end

function M.assertValidLabel(value, what)
  if not M.isValidLabel(value) then
    error(what .. " name is not allowed: use 1 to 32 letters, digits, - or _, starting with a letter or digit")
  end
  return value
end

return M
