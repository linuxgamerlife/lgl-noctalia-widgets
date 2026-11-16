-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Persistent, privacy-minimal storage in pluginDataDir().
--
-- weather.json has no coordinates. location.json is the only file with
-- coordinates. The data directory is hardened to 700 and the files are set to
-- 600. Writes go through a temp file and a rename so a crash cannot leave a
-- partially written final file.

local M = {}

local LOCATION_FILE = "location.json"
local WEATHER_FILE = "weather.json"

local function data_dir()
  local dir, err = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then
    return nil, err or "plugin data directory unavailable"
  end
  return dir
end

function M.paths()
  local dir, err = data_dir()
  if dir == nil then
    return nil, err
  end
  return {
    dir = dir,
    location = dir .. "/" .. LOCATION_FILE,
    weather = dir .. "/" .. WEATHER_FILE,
  }
end

local function chmod(path, mode)
  if type(noctalia.runAsync) == "function" then
    local accepted = noctalia.runAsync({ "chmod", mode, path }, function() end)
    if accepted == false then
      noctalia.log("[weather-time] could not queue chmod for " .. path)
    end
  end
end

local function parent_dir(path)
  return path:match("^(.*)/[^/]+$")
end

local function write_json(path, value)
  local encoded, err = noctalia.json.encode(value)
  if encoded == nil then
    return false, err or "encode failed"
  end
  local parent = parent_dir(path)
  if parent ~= nil then
    -- The host's writeFile creates files with the process umask; the 700
    -- directory is the hard boundary for the short temp-file window.
    chmod(parent, "700")
  end
  local temporary = path .. ".tmp"
  local ok, write_err = noctalia.writeFile(temporary, encoded)
  if ok == false then
    return false, write_err or "write failed"
  end
  chmod(temporary, "600")
  local renamed, rename_err = noctalia.renameFile(temporary, path)
  if renamed == false then
    noctalia.removeFile(temporary)
    return false, rename_err or "rename failed"
  end
  chmod(path, "600")
  return true
end

local function read_json(path)
  if type(noctalia.fileExists) == "function" and not noctalia.fileExists(path) then
    return nil, "missing"
  end
  local raw, err = noctalia.readFile(path)
  if type(raw) ~= "string" then
    return nil, err or "read failed"
  end
  local decoded, decode_err = noctalia.json.decode(raw)
  if decoded == nil then
    return nil, decode_err or "decode failed"
  end
  return decoded
end

function M.read_location()
  local paths, err = M.paths()
  if paths == nil then
    return nil, err
  end
  return read_json(paths.location)
end

function M.write_location(record)
  local paths, err = M.paths()
  if paths == nil then
    return false, err
  end
  return write_json(paths.location, record)
end

function M.read_weather()
  local paths, err = M.paths()
  if paths == nil then
    return nil, err
  end
  return read_json(paths.weather)
end

function M.write_weather(value)
  local paths, err = M.paths()
  if paths == nil then
    return false, err
  end
  return write_json(paths.weather, value)
end

function M.clear()
  local paths, err = M.paths()
  if paths == nil then
    return false, err
  end
  noctalia.removeFile(paths.location)
  noctalia.removeFile(paths.weather)
  return true
end

function M.remove_location()
  local paths, err = M.paths()
  if paths == nil then
    return false, err
  end
  noctalia.removeFile(paths.location)
  return true
end

function M.remove_weather()
  local paths, err = M.paths()
  if paths == nil then
    return false, err
  end
  noctalia.removeFile(paths.weather)
  return true
end

return M
