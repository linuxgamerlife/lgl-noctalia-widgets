-- Secret Service access through secret-tool. Keys live only in the Secret
-- Service; this module never writes them to a file or plugin setting.

local shell = require("./shell.luau")

local M = {}

M.SECRET_SERVICE_NAME = "org.freedesktop.secrets"
M.SECRET_SERVICE_PATH = "/org/freedesktop/secrets"
M.SEARCH_ITEMS_METHOD = "org.freedesktop.Secret.Service.SearchItems"
M.WALLET_FOLDER = "ai-usage"

M.ERROR = {
  NOT_RUNNING = "not_running",
  NO_ANSWER = "no_answer",
  LOCKED = "locked",
  WRITE_FAILED = "write_failed",
  REMOVE_FAILED = "remove_failed",
  FAILED = "failed",
  INVALID_KEY = "invalid_key",
}

local ENTRY_TYPE = "plaintext"
local KEY_PATTERN = "^[!-~]+$"
local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.entryName(providerId, accountId)
  return providerId .. "." .. accountId
end

function M.isValidKey(key)
  return type(key) == "string" and #key >= 1 and #key <= 4096 and key:match(KEY_PATTERN) ~= nil
end

local function attributes(providerId, account)
  return "server " .. shell.quote(M.WALLET_FOLDER)
    .. " user " .. shell.quote(M.entryName(providerId, account))
    .. " type " .. shell.quote(ENTRY_TYPE)
end

local function attributeDictionary(providerId, account)
  return "\"{\'server\': \'" .. M.WALLET_FOLDER .. "\', \'user\': \'"
    .. M.entryName(providerId, account) .. "\', \'type\': \'" .. ENTRY_TYPE .. "\'}\""
end

function M.buildLookupPart(providerId, account)
  return "secret-tool lookup " .. attributes(providerId, account)
end

function M.buildSearchPart(providerId, account)
  return "gdbus call --session --dest " .. M.SECRET_SERVICE_NAME
    .. " --object-path " .. M.SECRET_SERVICE_PATH
    .. " --method " .. M.SEARCH_ITEMS_METHOD
    .. " " .. attributeDictionary(providerId, account)
end

local function encodeBase64(text)
  local out = {}
  local index = 1
  while index <= #text do
    local a = text:byte(index)
    local b = text:byte(index + 1)
    local c = text:byte(index + 2)
    local chunk = a * 65536 + (b or 0) * 256 + (c or 0)
    table.insert(out, BASE64_ALPHABET:sub(math.floor(chunk / 262144) % 64 + 1, math.floor(chunk / 262144) % 64 + 1))
    table.insert(out, BASE64_ALPHABET:sub(math.floor(chunk / 4096) % 64 + 1, math.floor(chunk / 4096) % 64 + 1))
    if b ~= nil then
      table.insert(out, BASE64_ALPHABET:sub(math.floor(chunk / 64) % 64 + 1, math.floor(chunk / 64) % 64 + 1))
    else
      table.insert(out, "=")
    end
    if c ~= nil then
      table.insert(out, BASE64_ALPHABET:sub(chunk % 64 + 1, chunk % 64 + 1))
    else
      table.insert(out, "=")
    end
    index = index + 3
  end
  return table.concat(out)
end

M.encodeBase64 = encodeBase64

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end

-- Read the key for one account. The key is returned to the caller only for the
-- duration of one check; it is never written anywhere.
function M.lookup(providerId, accountId, callback)
  if not noctalia.commandExists("secret-tool") then
    callback({ ok = false, code = M.ERROR.NOT_RUNNING })
    return
  end
  noctalia.runAsync({
    "secret-tool", "lookup",
    "server", M.WALLET_FOLDER,
    "user", M.entryName(providerId, accountId),
    "type", ENTRY_TYPE,
  }, function(result)
    if result.timedOut then
      callback({ ok = false, code = M.ERROR.NO_ANSWER })
      return
    end
    if result.exitCode ~= 0 then
      callback({ ok = false, code = M.ERROR.LOCKED })
      return
    end
    local key = trim(result.stdout)
    if not M.isValidKey(key) then
      callback({ ok = false, code = M.ERROR.INVALID_KEY })
      return
    end
    callback({ ok = true, key = key })
  end, 10000)
end

-- Replace the stored key. secret-tool reads the secret from stdin; the key is
-- base64-encoded so quoting can never break the command. This is the one place
-- the port differs from the KDE version, which saves through the KWallet D-Bus
-- API without the key entering a command line.
function M.store(providerId, accountId, key, callback)
  if not M.isValidKey(key) then
    callback({ ok = false, code = M.ERROR.INVALID_KEY })
    return
  end
  if not noctalia.commandExists("secret-tool") then
    callback({ ok = false, code = M.ERROR.NOT_RUNNING })
    return
  end
  local label = "AI Usage: " .. providerId .. " " .. accountId
  local command = "timeout 10 secret-tool clear " .. attributes(providerId, accountId)
    .. " >/dev/null 2>&1; printf %s " .. shell.quote(encodeBase64(key))
    .. " | base64 -d | timeout 10 secret-tool store --label " .. shell.quote(label)
    .. " " .. attributes(providerId, accountId)
  noctalia.runAsync(command, function(result)
    if result.timedOut then
      callback({ ok = false, code = M.ERROR.NO_ANSWER })
      return
    end
    callback(result.exitCode == 0 and { ok = true } or { ok = false, code = M.ERROR.WRITE_FAILED })
  end, 20000)
end

function M.clear(providerId, accountId, callback)
  if not noctalia.commandExists("secret-tool") then
    if callback then
      callback({ ok = false, code = M.ERROR.NOT_RUNNING })
    end
    return
  end
  noctalia.runAsync({
    "secret-tool", "clear",
    "server", M.WALLET_FOLDER,
    "user", M.entryName(providerId, accountId),
    "type", ENTRY_TYPE,
  }, function(result)
    if callback then
      callback(result.exitCode == 0 and { ok = true } or { ok = false, code = M.ERROR.REMOVE_FAILED })
    end
  end, 10000)
end

return M
