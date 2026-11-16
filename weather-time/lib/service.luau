-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Headless weather/time service.
--
-- Owns the location file, the last-good cache, the HTTP client and the scene
-- assets. Publishes one plain "weather_time" table; the card, bar and panel
-- never touch the network or the filesystem.

local cache = require("./cache.luau")
local config = require("./config.luau")
local forecast = require("./forecast.luau")
local location = require("./location.luau")
local privacy = require("./privacy.luau")
local scene = require("./scene.luau")
local scheduler = require("./scheduler.luau")
local wmo = require("./wmo.luau")
local openmeteo = require("../providers/openmeteo.luau")

local M = {}

local STATE_KEY = "weather_time"
local LOCATION_REV_KEY = "weather_time_location_rev"
local REFRESH_SEQ_KEY = "weather_time_refresh_seq"
local UPDATE_INTERVAL_MS = 30000
local HEARTBEAT_SECONDS = 60
local INFLIGHT_TIMEOUT_SECONDS = 45
local MAX_FORECAST_DAYS = 7

local settings = nil
local current_location = nil
local weather = nil
local last_error = nil
local scene_info = nil
local scene_variant = nil
local next_fetch_at = 0
local failures = 0
local inflight = false
local inflight_at = 0
local serial = 0
local seq = 0
local started = false
local last_publish_at = 0
local last_location_rev = nil
local last_refresh_seq = nil

local function log(message)
  if type(noctalia.log) == "function" then
    noctalia.log("[weather-time] " .. tostring(message))
  end
end

local function now()
  return os.time()
end

local function load_settings()
  settings = config.service()
end

local function read_location_file()
  local raw, err = cache.read_location()
  if raw == nil then
    if err ~= "missing" then
      log("location file unavailable: " .. tostring(err))
    end
    return nil
  end
  local record, validate_err = location.validate(raw)
  if record == nil then
    log("ignoring invalid location file: " .. tostring(validate_err))
    return nil
  end
  return record
end

local function read_weather_file()
  local raw, err = cache.read_weather()
  if raw == nil then
    if err ~= "missing" then
      log("weather cache unavailable: " .. tostring(err))
    end
    return nil
  end
  return forecast.from_cache(raw)
end

local function choose_scene_variant()
  if settings.scene == "off" then
    return nil
  end
  local category = "clear"
  if settings.scene ~= "auto" then
    category = settings.scene
  elseif weather ~= nil and type(weather.current) == "table" then
    category = wmo.scene_category(weather.current.code)
  end
  local is_day = nil
  if settings.scene_theme == "day" then
    is_day = true
  elseif settings.scene_theme == "night" then
    is_day = false
  elseif weather ~= nil and type(weather.current) == "table" then
    is_day = weather.current.is_day == true
  else
    -- Without weather, use the local clock rather than the theme: a moon at
    -- 15:00 looks wrong even in a dark shell theme.
    local hour = tonumber(os.date("%H")) or 12
    is_day = hour >= 7 and hour < 19
  end
  return scene.variant(category, is_day)
end

local function ensure_scene()
  local variant = choose_scene_variant()
  if variant == nil then
    scene_info = nil
    scene_variant = nil
    return
  end
  if scene_info ~= nil and scene_variant == variant
    and type(scene_info.image) == "string" and scene_info.image ~= ""
  then
    return
  end
  local dir, err = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then
    log("scene disabled: " .. tostring(err or "no plugin data directory"))
    scene_info = nil
    scene_variant = nil
    return
  end
  local image, write_err = scene.write(dir, variant)
  if image == nil then
    log("scene disabled: " .. tostring(write_err))
    scene_info = nil
    scene_variant = nil
    return
  end
  scene_variant = variant
  scene_info = {
    variant = variant,
    image = image,
  }
end

local function public_payload()
  local payload = {
    ts = now(),
    seq = seq,
    units = { temperature = "c", wind = "kmh", precipitation = "mm" },
    location = current_location and location.public(current_location) or nil,
    provider = "open-meteo",
    stale = false,
    error = last_error,
    scene = scene_info,
    refresh_minutes = settings and settings.refresh_minutes or 15,
    next_refresh_at = next_fetch_at,
  }
  if weather ~= nil then
    local public = privacy.weather(weather, current_location)
    if public ~= nil then
      payload.location = public.location or payload.location
      payload.timezone = public.timezone
      payload.timezone_abbreviation = public.timezone_abbreviation
      payload.utc_offset_seconds = public.utc_offset_seconds
      payload.current = public.current
      payload.today = public.today
      payload.forecast = public.forecast
      payload.fetched_at = public.fetched_at
      payload.stale = last_error ~= nil
        or scheduler.is_stale(now(), public.fetched_at, settings.refresh_minutes)
    end
  end
  privacy.assert_public(payload)
  return payload
end

local function publish()
  seq = seq + 1
  last_publish_at = now()
  local payload = public_payload()
  payload.seq = seq
  noctalia.state.set(STATE_KEY, payload)
end

local function fail(reason, status)
  failures = failures + 1
  last_error = privacy.error(reason, status)
  next_fetch_at = scheduler.next_after_failure(now(), settings.refresh_minutes, failures)
  log("fetch failed: " .. tostring(reason) .. (status and (" (" .. tostring(status) .. ")") or ""))
  publish()
end

local fetch

local function on_response(token, result)
  if not started or token ~= serial then
    return
  end
  inflight = false
  if result == nil then
    fail("offline")
    return
  end
  if result.ok ~= true then
    fail(result.error or "offline", result.status)
    return
  end
  local status = tonumber(result.status) or 0
  if status ~= 200 then
    fail("http_status", status)
    return
  end
  local payload, parse_err = openmeteo.parse(result.body or "")
  if payload == nil then
    log("parse failed: " .. tostring(parse_err))
    fail("parse")
    return
  end
  local model, normalize_err = forecast.normalize(payload, { days = MAX_FORECAST_DAYS + 1, now = now() })
  if model == nil then
    log("normalize failed: " .. tostring(normalize_err))
    fail("parse")
    return
  end
  weather = model
  last_error = nil
  failures = 0
  next_fetch_at = scheduler.next_after_success(now(), settings.refresh_minutes)
  local cache_value = privacy.cache(weather, current_location)
  if cache_value ~= nil then
    local ok, write_err = cache.write_weather(cache_value)
    if not ok then
      log("cache write failed: " .. tostring(write_err))
    end
  end
  ensure_scene()
  publish()
end

fetch = function()
  if not started or inflight or current_location == nil then
    return false
  end
  inflight = true
  inflight_at = now()
  serial = serial + 1
  local token = serial
  local accepted = openmeteo.request(current_location, MAX_FORECAST_DAYS, function(result)
    on_response(token, result)
  end)
  if not accepted and inflight then
    inflight = false
    fail("request")
  end
  return accepted
end

local function reload_location()
  current_location = read_location_file()
  weather = nil
  cache.remove_weather()
  last_error = nil
  failures = 0
  next_fetch_at = 0
  scene_variant = nil
  scene_info = nil
  ensure_scene()
  publish()
  if current_location ~= nil then
    fetch()
  end
end

function M.start()
  if started then
    return
  end
  started = true
  load_settings()
  last_location_rev = noctalia.state.get(LOCATION_REV_KEY)
  last_refresh_seq = noctalia.state.get(REFRESH_SEQ_KEY)
  current_location = read_location_file()
  weather = current_location ~= nil and read_weather_file() or nil
  if weather ~= nil then
    next_fetch_at = scheduler.next_after_success(
      tonumber(weather.fetched_at) or 0,
      settings.refresh_minutes
    )
  end
  ensure_scene()
  publish()
  noctalia.setUpdateInterval(UPDATE_INTERVAL_MS)
  noctalia.state.watch(LOCATION_REV_KEY, function(value)
    if value ~= last_location_rev then
      last_location_rev = value
      log("location changed; reloading")
      reload_location()
    end
  end)
  noctalia.state.watch(REFRESH_SEQ_KEY, function(value)
    if value ~= last_refresh_seq then
      last_refresh_seq = value
      next_fetch_at = 0
      fetch()
    end
  end)
  if current_location ~= nil and scheduler.is_due(now(), next_fetch_at) then
    fetch()
  end
end

function M.update()
  if not started then
    return
  end
  if inflight and now() - inflight_at > INFLIGHT_TIMEOUT_SECONDS then
    inflight = false
    serial = serial + 1
    fail("timeout")
  end
  if current_location ~= nil and not inflight and scheduler.is_due(now(), next_fetch_at) then
    fetch()
  end
  if now() - last_publish_at >= HEARTBEAT_SECONDS then
    publish()
  end
end

function M.configChanged()
  if not started then
    return
  end
  load_settings()
  ensure_scene()
  publish()
  if current_location ~= nil and weather == nil and not inflight then
    next_fetch_at = 0
    fetch()
  end
end

function M.ipc(event)
  if event == "refresh" and started then
    next_fetch_at = 0
    fetch()
  elseif event == "reload" and started then
    reload_location()
  end
end

function M.stop()
  started = false
end

-- Exposed for tests.
M._test = {
  state_key = STATE_KEY,
  location_rev_key = LOCATION_REV_KEY,
  refresh_seq_key = REFRESH_SEQ_KEY,
}

return M
