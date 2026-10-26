-- Shell quoting. Only safe printable ASCII is allowed, matching the KDE port.
-- User-visible text never reaches a shell command: account ids, provider ids
-- and field values are validated to [A-Za-z0-9-] first.

local M = {}

local QUOTABLE = "^[%z\32-\38\40-\126]*$"
local HTTPS_URL = "^https://[%z\33-\38\40-\126]+$"

function M.quote(value)
  if type(value) ~= "string" or not value:match(QUOTABLE) then
    error("the value cannot be quoted for the shell")
  end
  return "'" .. value .. "'"
end

function M.quoteUrl(url)
  if type(url) ~= "string" or not url:match(HTTPS_URL) then
    error("only HTTPS URLs without spaces or quotes are allowed")
  end
  return "'" .. url .. "'"
end

return M
