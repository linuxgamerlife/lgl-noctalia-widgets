-- Accounts live in pluginDataDir/accounts.json. No secret ever goes here.
-- Writes are atomic (write a sibling then rename) so a crash cannot leave a
-- half-written account list.

local accounts = require("./accounts.luau")

local M = {}

M.VERSION = 1
M.FILE_NAME = "accounts.json"

function M.path()
  local dir, err = noctalia.pluginDataDir()
  if not dir then
    return nil, err or "plugin data directory is unavailable"
  end
  return dir .. "/" .. M.FILE_NAME
end

function M.load(findProvider)
  local path = M.path()
  if not path or not noctalia.fileExists(path) then
    return {}
  end
  local text, err = noctalia.readFile(path)
  if not text then
    noctalia.log("[ai-usage] could not read accounts: " .. tostring(err))
    return {}
  end
  local decoded = noctalia.json.decode(text)
  if type(decoded) ~= "table" then
    noctalia.log("[ai-usage] accounts.json is not valid JSON; using no accounts")
    return {}
  end
  local list = decoded.accounts
  if type(list) ~= "table" then
    -- Accept the KDE-era bare array as well.
    list = decoded[1] ~= nil and decoded or {}
  end
  return accounts.parseAccounts(list, findProvider)
end

function M.save(list)
  local path, pathError = M.path()
  if not path then
    return false, pathError
  end
  local payload = {
    version = M.VERSION,
    updated_ms = os.time() * 1000,
    accounts = list or {},
  }
  local text = noctalia.json.encode(payload)
  if not text then
    return false, "could not encode accounts"
  end
  local temporary = path .. ".tmp"
  local written, writeError = noctalia.writeFile(temporary, text)
  if not written then
    return false, writeError or "could not write accounts"
  end
  local renamed, renameError = noctalia.renameFile(temporary, path)
  if not renamed then
    noctalia.removeFile(temporary)
    return false, renameError or "could not replace accounts"
  end
  return true
end

return M
