-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Local Steam discovery. No network, no account and no Steam API key.
--
-- The Steam client writes every tracked game process to
-- logs/gameprocess_log.txt. Replaying the "adding PID" and "Remove ... from
-- running list" lines gives the AppID; checking /proc/<pid> keeps the answer
-- honest when Steam crashes or never writes the final remove line.

local M = {}

local RUNTIME_APPIDS = {
  [228980] = true, -- Steamworks Common Redistributables
  [1070560] = true, -- Steam Linux Runtime 1.0 (scout)
  [1391110] = true, -- Steam Linux Runtime 2.0 (soldier)
  [1628350] = true, -- Steam Linux Runtime 3.0 (sniper)
  [1493710] = true, -- Proton Experimental
  [2180100] = true, -- Proton Hotfix
  [2348590] = true, -- Proton 9.0
  [2805730] = true, -- Proton 10.0
}

local libraries_cache = {
  root = nil,
  at = 0,
  paths = nil,
}

local games_cache = {}

local function file_exists(path)
  if type(noctalia.fileExists) == "function" then
    return noctalia.fileExists(path) == true
  end
  return type(noctalia.readFile(path)) == "string"
end

local function home()
  if type(noctalia.getenv) == "function" then
    return noctalia.getenv("HOME") or ""
  end
  return ""
end

local function candidates()
  local prefix = home()
  if prefix == "" then
    return {}
  end
  return {
    prefix .. "/.steam/root",
    prefix .. "/.steam/steam",
    prefix .. "/.local/share/Steam",
    prefix .. "/.steam/debian-installation",
    prefix .. "/.var/app/com.valvesoftware.Steam/.local/share/Steam",
    prefix .. "/snap/steam/common/.local/share/Steam",
  }
end

function M.find_root()
  for _, root in ipairs(candidates()) do
    if file_exists(root .. "/steam.pid")
      or file_exists(root .. "/steamapps/libraryfolders.vdf")
      or file_exists(root .. "/logs/gameprocess_log.txt")
    then
      return root
    end
  end
  return nil
end

function M.log_path(root)
  return root .. "/logs/gameprocess_log.txt"
end

function M.shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Keep the expensive scanning in coreutils. Only the last few hundred launch
-- events cross into Luau, which keeps the async callback under its CPU budget
-- even when the Steam log is several megabytes.
function M.detect_args(path, bytes, events)
  local size = math.max(65536, tonumber(bytes) or 524288)
  local count = math.max(100, tonumber(events) or 1000)
  local command = table.concat({
    "tail -c " .. tostring(size) .. " -- " .. M.shell_quote(path),
    "grep -aE " .. M.shell_quote("AppID [0-9]+ adding PID [0-9]+|Remove [0-9]+ from running list"),
    "tail -n " .. tostring(count),
  }, " | ")
  return { "sh", "-c", command }
end

function M.is_game_appid(appid)
  local number = tonumber(appid)
  if number == nil or number < 10 then
    return false
  end
  return RUNTIME_APPIDS[number] ~= true
end

function M.is_runtime_name(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  return name:match("^Steam Linux Runtime") ~= nil
    or name:match("^Steamworks Common Redistributables") ~= nil
    or name:match("^Proton ") ~= nil
    or name == "Proton Experimental"
    or name == "Proton Hotfix"
end

-- Read the first path from libraryfolders.vdf plus the root library. The file
-- is small; refresh the list at most every five minutes.
function M.library_paths(root)
  local now = os.time()
  if libraries_cache.root == root and libraries_cache.paths ~= nil
    and now - libraries_cache.at < 300
  then
    return libraries_cache.paths
  end

  local seen = {}
  local paths = {}

  local function add(path)
    if type(path) == "string" and path ~= "" and not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end

  add(root)

  local raw = noctalia.readFile(root .. "/steamapps/libraryfolders.vdf")
  if type(raw) == "string" then
    for value in raw:gmatch('"path"%s+"([^"]*)"') do
      add(value:gsub("\\\\", "\\"))
    end
  end

  libraries_cache.root = root
  libraries_cache.at = now
  libraries_cache.paths = paths
  return paths
end

-- Return { name = string, library = string, installdir = string } or nil.
function M.game_info(appid, root)
  local key = tostring(appid)
  local cached = games_cache[key]
  if cached ~= nil then
    return cached
  end

  for _, library in ipairs(M.library_paths(root)) do
    local manifest = library .. "/steamapps/appmanifest_" .. key .. ".acf"
    local raw = noctalia.readFile(manifest)
    if type(raw) == "string" then
      local name = raw:match('"name"%s+"([^"]*)"')
      local installdir = raw:match('"installdir"%s+"([^"]*)"')
      if type(name) == "string" then
        name = name:gsub('\\"', '"'):gsub("\\\\", "\\")
      end
      if type(installdir) == "string" then
        installdir = installdir:gsub('\\"', '"'):gsub("\\\\", "\\")
      end
      local info = {
        name = name,
        library = library,
        installdir = installdir,
      }
      games_cache[key] = info
      return info
    end
  end

  games_cache[key] = false
  return nil
end

function M.game_name(appid, root)
  local info = M.game_info(appid, root)
  return info and info.name or nil
end

local function process_alive(pid)
  local number = tonumber(pid)
  if number == nil then
    return false
  end
  local raw = noctalia.readFile("/proc/" .. tostring(number) .. "/stat")
  if type(raw) ~= "string" then
    return false
  end
  local state = raw:match("%) (%a)")
  if state == nil then
    return false
  end
  return state ~= "Z" and state ~= "X"
end

M.process_alive = process_alive

local function any_alive(pids)
  for pid in pairs(pids) do
    if process_alive(pid) then
      return true
    end
  end
  return false
end

function M.detect(text, root)
  if type(text) ~= "string" or text == "" then
    return nil
  end

  -- Two C-level scans instead of a Luau loop over every line. The log can be
  -- several megabytes and is mostly unrelated connection traffic.
  local starts = {}
  local stopped = {}

  local position = 1
  while position <= #text do
    local first, last, appid, pid = text:find("AppID (%d+) adding PID (%d+)", position)
    if first == nil then
      break
    end
    local number = tonumber(appid)
    local process = tonumber(pid)
    if number ~= nil and process ~= nil then
      local record = starts[number]
      if record == nil then
        record = { position = first, pids = {} }
        starts[number] = record
      end
      record.position = first
      record.pids[#record.pids + 1] = process
      -- Long Proton sessions can track dozens of helper processes. Keep the
      -- most recent PIDs; the launch wrapper is usually among them.
      if #record.pids > 64 then
        table.remove(record.pids, 1)
      end
    end
    position = last + 1
  end

  position = 1
  while position <= #text do
    local first, last, appid = text:find("Remove (%-?%d+) from running list", position)
    if first == nil then
      break
    end
    local number = tonumber(appid)
    if number ~= nil then
      stopped[number] = first
    end
    position = last + 1
  end

  local candidates = {}
  for appid, record in pairs(starts) do
    local stopped_at = stopped[appid]
    if M.is_game_appid(appid)
      and (stopped_at == nil or record.position > stopped_at)
    then
      candidates[#candidates + 1] = {
        appid = appid,
        position = record.position,
        pids = record.pids,
      }
    end
  end

  table.sort(candidates, function(left, right)
    return left.position > right.position
  end)

  for _, candidate in ipairs(candidates) do
    if any_alive(candidate.pids) then
      local name = M.game_name(candidate.appid, root)
      if not M.is_runtime_name(name) then
        return candidate.appid
      end
    end
  end

  return nil
end

function M.header_path(data_dir, appid)
  -- v2: the first release used SteamCharts' 184x69 images, which are
  -- placeholders for some games. The store API header replaces them.
  return data_dir .. "/header_v2_" .. tostring(appid) .. ".jpg"
end

function M.header_exists(data_dir, appid)
  return file_exists(M.header_path(data_dir, appid))
end

-- SteamCharts sometimes serves a small question-mark placeholder instead of a
-- real header. Real 184x69 or 460x215 artwork is much larger; treating tiny
-- files as invalid lets the next detection retry the store API.
function M.header_valid(data_dir, appid)
  local path = M.header_path(data_dir, appid)
  if not file_exists(path) then
    return false
  end
  local raw = noctalia.readFile(path)
  return type(raw) == "string" and #raw >= 6000
end

-- Fallback image source. The card uses fit="contain", so either the 184x69
-- SteamCharts image or the 460x215 store header is shown without cropping.
function M.header_url(appid)
  return "https://steamcharts.com/assets/steam-images/" .. tostring(appid) .. ".jpg"
end

return M
