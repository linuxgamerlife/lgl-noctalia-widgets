--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Headless poller for SteamDB Stats.
--
-- It detects the game Steam is running from the client's own process log,
-- resolves the name from the library manifests, and publishes live player
-- counts, 24-hour and all-time peaks, and a normalised 24-hour graph series.
--
-- SteamDB itself refuses automated clients, so the public data comes from
-- SteamCharts plus Valve's keyless GetNumberOfCurrentPlayers endpoint. Every
-- request is cached and rate-limited.

local format = require("./lib/format.luau")
local steam = require("./lib/steam.luau")
local steamcharts = require("./lib/steamcharts.luau")
local cache = require("./lib/cache.luau")

local STATE_KEY = "steam_stats"
local LOG_TAIL_BYTES = 524288
local LOG_TAIL_EVENTS = 200
local REQUEST_TIMEOUT_MS = 45000
local CACHE_WRITE_SECONDS = 120

local detect_interval = 3
local current_refresh = 60
local stats_refresh = 600

local root = nil
local data_dir = nil
local cache_games = {}

local game = nil
local stats = {}
local status = "idle"
local seq = 0
local generation = 0

local detect_pending = false
local detect_pending_at = 0
local detect_run = 0
local detect_at = 0
local root_retry_at = 0

local current_pending = false
local current_pending_at = 0
local current_run = 0
local current_at = 0
local current_retry_at = 0

local stats_pending = false
local stats_pending_at = 0
local stats_run = 0
local stats_at = 0
local stats_retry_at = 0

local header_pending = {}
local last_cache_write = 0

local function log(message)
  if type(noctalia.log) == "function" then
    noctalia.log("[steamdb-stats] " .. tostring(message))
  end
end

local function now_ms()
  if type(noctalia.nowMs) == "function" then
    local value = noctalia.nowMs()
    if type(value) == "number" then
      return value
    end
  end
  return os.time() * 1000
end

local function load_settings()
  detect_interval = math.floor(format.clamp(
    tonumber(noctalia.getConfig("detect_interval")) or 3, 2, 15
  ) + 0.5)
  current_refresh = math.floor(format.clamp(
    tonumber(noctalia.getConfig("current_refresh")) or 60, 30, 300
  ) + 0.5)
  stats_refresh = math.floor(format.clamp(
    tonumber(noctalia.getConfig("stats_refresh")) or 600, 300, 3600
  ) + 0.5)
end

local function copy_array(values)
  local copy = {}
  if type(values) ~= "table" then
    return copy
  end
  for index = 1, #values do
    copy[index] = values[index]
  end
  return copy
end

local function publish()
  seq = seq + 1
  noctalia.state.set(STATE_KEY, {
    ts = os.time(),
    seq = seq,
    status = status,
    game = game and {
      appid = game.appid,
      name = game.name,
      header = game.header,
      started_at = game.started_at,
    } or nil,
    stats = {
      current = stats.current,
      peak_24h = stats.peak_24h,
      peak_all_time = stats.peak_all_time,
      peak_at = stats.peak_at,
      history = copy_array(stats.history),
      chart_at = stats.chart_at,
      page_at = stats.page_at,
      updated_at = stats.updated_at,
    },
    source = "SteamCharts + Steam",
  })
end

local function cached_stats(appid)
  local entry = cache_games[tostring(appid)]
  if type(entry) ~= "table" then
    return {}
  end
  return {
    current = tonumber(entry.current),
    peak_24h = tonumber(entry.peak_24h),
    peak_all_time = tonumber(entry.peak_all_time),
    peak_at = tonumber(entry.peak_at),
    history = type(entry.history) == "table" and entry.history or {},
    chart_at = tonumber(entry.chart_at),
    page_at = tonumber(entry.page_at),
    updated_at = tonumber(entry.updated_at),
  }
end

local function persist(force)
  if game == nil then
    return
  end
  local now = os.time()
  if not force and now - last_cache_write < CACHE_WRITE_SECONDS then
    return
  end
  if stats.current == nil and stats.peak_24h == nil and stats.peak_all_time == nil then
    return
  end

  cache_games[tostring(game.appid)] = {
    name = game.name,
    current = stats.current,
    peak_24h = stats.peak_24h,
    peak_all_time = stats.peak_all_time,
    peak_at = stats.peak_at,
    history = stats.history,
    chart_at = stats.chart_at,
    page_at = stats.page_at,
    updated_at = now,
  }
  last_cache_write = now
  cache.write(cache_games)
end

local function is_placeholder_name(name)
  return type(name) ~= "string" or name == "" or name:match("^Steam App ")
end

local function parse_header_image(body, appid)
  if type(body) ~= "string" or body == "" then
    return nil
  end
  local decoded = noctalia.json.decode(body)
  if type(decoded) ~= "table" then
    return nil
  end
  local entry = decoded[tostring(appid)]
  if type(entry) ~= "table" or entry.success ~= true or type(entry.data) ~= "table" then
    return nil
  end
  local url = entry.data.header_image
  if type(url) ~= "string" or not url:match("^https://") then
    return nil
  end
  return url
end

local function download_header(appid, url, token, fallback)
  local id = tostring(appid)
  local path = steam.header_path(data_dir, appid)

  local accepted = noctalia.runAsync({
    "curl",
    "--disable",
    "--silent",
    "--show-error",
    "--fail",
    "--location",
    "--max-time",
    "20",
    "--output",
    path,
    url,
  }, function(result)
    if token ~= generation then
      header_pending[id] = false
      return
    end
    if result and result.exitCode == 0 and steam.header_valid(data_dir, appid) then
      header_pending[id] = false
      game.header = path
      publish()
      return
    end

    noctalia.removeFile(path)
    if fallback ~= nil and fallback ~= url then
      download_header(appid, fallback, token, nil)
    else
      header_pending[id] = false
    end
  end)

  if not accepted then
    if fallback ~= nil and fallback ~= url then
      download_header(appid, fallback, token, nil)
    else
      header_pending[id] = false
    end
  end
end

local function ensure_header(appid, token)
  if data_dir == nil or game == nil then
    return
  end
  if steam.header_valid(data_dir, appid) then
    game.header = steam.header_path(data_dir, appid)
    publish()
    return
  end
  if steam.header_exists(data_dir, appid) then
    noctalia.removeFile(steam.header_path(data_dir, appid))
  end

  local id = tostring(appid)
  if header_pending[id] then
    return
  end
  header_pending[id] = true

  local fallback = steam.header_url(appid)
  local store = "https://store.steampowered.com/api/appdetails?appids="
    .. tostring(appid) .. "&filters=basic"

  if type(noctalia.http) ~= "function" then
    download_header(appid, fallback, token, nil)
    return
  end

  local accepted = noctalia.http({
    url = store,
    method = "GET",
    headers = { "Accept: application/json" },
    follow_redirects = false,
    allow_insecure_tls = false,
  }, function(response)
    if token ~= generation then
      header_pending[id] = false
      return
    end

    local url = fallback
    if response ~= nil and response.ok == true and tonumber(response.status) == 200 then
      local parsed = parse_header_image(response.body or "", appid)
      if parsed ~= nil then
        url = parsed
      end
    end

    local retry = url ~= fallback and fallback or nil
    download_header(appid, url, token, retry)
  end)

  if not accepted then
    download_header(appid, fallback, token, nil)
  end
end

local on_game_changed

local function request_detect()
  if detect_pending or root == nil then
    return false
  end

  detect_pending = true
  detect_pending_at = now_ms()
  detect_run = detect_run + 1
  local run = detect_run

  local accepted = noctalia.runAsync(
    steam.detect_args(steam.log_path(root), LOG_TAIL_BYTES, LOG_TAIL_EVENTS),
    function(result)
      if run ~= detect_run then
        return
      end
      detect_pending = false
      if result == nil or result.exitCode ~= 0 then
        return
      end
      local appid = steam.detect(result.stdout or "", root)
      local current_appid = game and game.appid or nil
      if appid ~= current_appid then
        on_game_changed(appid)
      end
    end
  )

  if not accepted then
    detect_pending = false
  end
  return accepted
end

local function request_current(force)
  if game == nil or current_pending then
    return false
  end

  local now = now_ms()
  if not force and (now < current_retry_at or now - current_at < current_refresh * 1000) then
    return false
  end

  current_pending = true
  current_pending_at = now
  current_at = now
  current_run = current_run + 1
  local run = current_run
  local token = generation
  local appid = game.appid

  local accepted = steamcharts.request_current(appid, function(result)
    if run ~= current_run or token ~= generation then
      return
    end
    current_pending = false

    if result.ok and result.count ~= nil then
      stats.current = result.count
      stats.current_at = os.time()
      current_retry_at = 0
      if status == "loading" or status == "error" then
        status = "ok"
      end
      persist()
    else
      current_retry_at = now_ms() + 30000
      if stats.current == nil then
        status = "partial"
      end
    end
    publish()
  end)

  if not accepted then
    current_pending = false
  end
  return accepted
end

local function finish_stats(page_ok, chart_ok)
  stats_pending = false
  stats.updated_at = os.time()

  if stats.peak_all_time ~= nil and stats.peak_24h ~= nil then
    status = "ok"
  elseif chart_ok and (stats.peak_24h ~= nil or stats.current ~= nil) then
    status = "partial"
  elseif page_ok and (stats.peak_all_time ~= nil or stats.current ~= nil) then
    status = "partial"
  else
    status = "error"
  end

  if status == "error" then
    stats_retry_at = now_ms() + 120000
  else
    stats_retry_at = 0
  end

  persist(true)
  publish()
end

local function request_stats(force)
  if game == nil or stats_pending then
    return false
  end

  local now = now_ms()
  if not force and (now < stats_retry_at or now - stats_at < stats_refresh * 1000) then
    return false
  end

  stats_pending = true
  stats_pending_at = now
  stats_at = now
  stats_run = stats_run + 1
  local run = stats_run
  local token = generation
  local appid = game.appid

  local left = 2
  local page_ok = false
  local chart_ok = false

  local function done()
    left = left - 1
    if left == 0 then
      if run ~= stats_run or token ~= generation then
        return
      end
      finish_stats(page_ok, chart_ok)
    end
  end

  steamcharts.request_page(appid, function(result)
    if run ~= stats_run or token ~= generation then
      return
    end

    if result.ok then
      local page = steamcharts.parse_page(result.body)
      if page ~= nil then
        page_ok = true
        stats.page_at = os.time()
        if page.peak_all_time ~= nil then
          stats.peak_all_time = page.peak_all_time
        end
        if page.peak_24h ~= nil then
          stats.peak_24h = page.peak_24h
        end
        if page.current ~= nil then
          stats.current = page.current
        end
        if page.name ~= nil and is_placeholder_name(game.name) then
          game.name = page.name
        end
      end
    end
    done()
  end)

  steamcharts.request_chart(appid, function(result)
    if run ~= stats_run or token ~= generation then
      return
    end

    if result.ok then
      local chart = steamcharts.parse_chart(result.body)
      if chart ~= nil then
        chart_ok = true
        stats.chart_at = os.time()
        stats.peak_at = chart.peak_at or stats.peak_at
        if chart.peak_24h ~= nil then
          stats.peak_24h = chart.peak_24h
        end
        if stats.current == nil and chart.current ~= nil then
          stats.current = chart.current
        end
        stats.history = steamcharts.normalize(chart.points, chart.peak_24h)
      end
    end
    done()
  end)

  return true
end

on_game_changed = function(appid)
  generation = generation + 1
  current_pending = false
  stats_pending = false
  current_at = 0
  current_retry_at = 0
  stats_at = 0
  stats_retry_at = 0
  header_pending = {}

  if appid == nil then
    game = nil
    stats = {}
    status = root == nil and "no_steam" or "idle"
    publish()
    return
  end

  local info = steam.game_info(appid, root)
  local name = info and info.name or ("Steam App " .. tostring(appid))
  local header = nil
  if data_dir ~= nil and steam.header_exists(data_dir, appid) then
    header = steam.header_path(data_dir, appid)
  end

  game = {
    appid = appid,
    name = name,
    header = header,
    started_at = os.time(),
  }
  stats = cached_stats(appid)
  status = "loading"
  if stats.current ~= nil or stats.peak_24h ~= nil then
    status = "ok"
  end

  log("game changed: " .. tostring(appid) .. " " .. tostring(name))
  publish()

  ensure_header(appid, generation)
  request_current(true)
  request_stats(true)
end

function update()
  local now = now_ms()

  if root == nil and now >= root_retry_at then
    root = steam.find_root()
    root_retry_at = now + 15000
    if root ~= nil then
      detect_at = 0
      on_game_changed(nil)
    else
      status = "no_steam"
      publish()
    end
  end

  if root == nil then
    return
  end

  if detect_pending and now - detect_pending_at > REQUEST_TIMEOUT_MS then
    detect_pending = false
    detect_run = detect_run + 1
  end
  if current_pending and now - current_pending_at > REQUEST_TIMEOUT_MS then
    current_pending = false
    current_run = current_run + 1
  end
  if stats_pending and now - stats_pending_at > REQUEST_TIMEOUT_MS then
    stats_pending = false
    stats_run = stats_run + 1
    if stats.current == nil and stats.peak_24h == nil and stats.peak_all_time == nil then
      status = "error"
      publish()
    end
  end

  if now - detect_at >= detect_interval * 1000 then
    detect_at = now
    request_detect()
  end

  if game ~= nil then
    if now - current_at >= current_refresh * 1000 then
      request_current()
    end
    if now - stats_at >= stats_refresh * 1000 then
      request_stats()
    end
  end
end

function onConfigChanged()
  load_settings()
  noctalia.setUpdateInterval(detect_interval * 1000)
  current_at = 0
  stats_at = 0
  request_current(true)
  request_stats(true)
end

load_settings()
root = steam.find_root()
data_dir = cache.dir()
cache_games = cache.read()

if data_dir ~= nil then
  noctalia.runAsync({ "mkdir", "-p", data_dir }, function() end)
end

status = root == nil and "no_steam" or "idle"
publish()

noctalia.setUpdateInterval(detect_interval * 1000)
if root ~= nil then
  request_detect()
end
