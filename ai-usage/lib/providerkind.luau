-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

local M = {
  REMOTE = "remote",
  LOCAL = "local",
}

-- Stored provider ids stay camelCase for accounts.json compatibility, but the
-- translation store requires lowercase, dot-free segments.
local TRANSLATION_KEYS = {
  opencodeGo = "opencode-go",
  opencodeZen = "opencode-zen",
  huggingFace = "hugging-face",
}

function M.translation_key(provider_id)
  if provider_id == nil then
    return ""
  end
  return TRANSLATION_KEYS[provider_id] or tostring(provider_id)
end

return M
