-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Small JSON cache in pluginDataDir(). It keeps the last good values for a
-- handful of games so a restart or a SteamCharts outage does not blank the
-- card. No account data, tokens or browsing history is stored.

local M = {}

local FILE = "cache.json"
local MAX_GAMES = 16

local function data_dir()
  local dir, err = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then
    return nil, err or "plugin data directory unavailable"
  end
  return dir
end

function M.path()
  local dir, err = data_dir()
  if dir == nil then
    return nil, err
  end
  return dir .. "/" .. FILE
end

function M.dir()
  return data_dir()
end

function M.read()
  local path = M.path()
  if path == nil then
    return {}
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" then
    return {}
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" or type(decoded.games) ~= "table" then
    return {}
  end
  return decoded.games
end

local function trim(games)
  local keys = {}
  for key in pairs(games) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(left, right)
    local left_at = tonumber(games[left] and games[left].updated_at) or 0
    local right_at = tonumber(games[right] and games[right].updated_at) or 0
    return left_at > right_at
  end)
  for index = MAX_GAMES + 1, #keys do
    games[keys[index]] = nil
  end
end

function M.write(games)
  if type(games) ~= "table" then
    return false
  end
  trim(games)

  local encoded = noctalia.json.encode({ games = games })
  if type(encoded) ~= "string" then
    return false
  end

  local path = M.path()
  if path == nil then
    return false
  end
  local temporary = path .. ".tmp"
  local ok = noctalia.writeFile(temporary, encoded)
  if not ok then
    noctalia.removeFile(temporary)
    return false
  end
  local renamed = noctalia.renameFile(temporary, path)
  if not renamed then
    noctalia.removeFile(temporary)
    return false
  end
  return true
end

return M
