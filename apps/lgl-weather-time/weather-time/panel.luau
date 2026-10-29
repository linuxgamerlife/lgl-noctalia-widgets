--!nonstrict
-- Setup / status panel for Weather & Time.
--
-- The panel is the only place that writes location.json. It searches
-- Open-Meteo geocoding only after an explicit action, validates coordinates,
-- and never reads the forecast cache.

local cache = require("./lib/cache.luau")
local config = require("./lib/config.luau")
local format = require("./lib/format.luau")
local location = require("./lib/location.luau")
local geocode = require("./providers/geocode.luau")

local current = noctalia.state.get("weather_time")

local search_text = ""
local search_results = {}
local search_loading = false
local search_error = nil
local manual_latitude = ""
local manual_longitude = ""
local manual_label = ""
local message = nil
local message_error = false

local render

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function bump_location_rev()
  local value = tonumber(noctalia.state.get("weather_time_location_rev")) or 0
  noctalia.state.set("weather_time_location_rev", value + 1)
end

local function bump_refresh()
  local value = tonumber(noctalia.state.get("weather_time_refresh_seq")) or 0
  noctalia.state.set("weather_time_refresh_seq", value + 1)
end

local function set_message(text, is_error)
  message = text
  message_error = is_error == true
end

local function source_label(source)
  if source == "search" then
    return tr("source.search", "City search")
  elseif source == "noctalia" then
    return tr("source.noctalia", "Imported from Noctalia")
  end
  return tr("source.manual", "Manual")
end

local function error_label(error)
  if type(error) ~= "table" then
    return nil
  end
  local reason = error.reason or "unknown"
  if reason == "http_status" and error.status ~= nil then
    return tr("status.error_http", "Weather service returned HTTP {status}", { status = error.status })
  end
  local labels = {
    offline = tr("status.error_offline", "Offline or unreachable"),
    parse = tr("status.error_parse", "Weather response could not be read"),
    timeout = tr("status.error_timeout", "Weather request timed out"),
    http_status = tr("status.error_http_generic", "Weather service error"),
    request = tr("status.error_request", "Weather request could not start"),
  }
  return labels[reason] or tr("status.error_generic", "Weather unavailable")
end

local function status_line()
  if current == nil then
    return tr("status.waiting", "Waiting for the service")
  end
  if current.location == nil then
    return tr("status.set_location", "Set a location")
  end
  if current.error ~= nil then
    return error_label(current.error) or tr("status.error_generic", "Weather unavailable")
  end
  if current.current == nil then
    return tr("status.loading", "Loading weather…")
  end
  if current.stale == true then
    return tr("status.stale", "Cached weather")
  end
  local age = format.age_text(os.time() - (tonumber(current.fetched_at) or os.time()), tr)
  return tr("status.updated", "Updated {age}", { age = age })
end

local function save_location(record, success_key)
  local written, err = cache.write_location(record)
  if not written then
    set_message(tr("panel.save_failed", "Could not save the location: {error}", { error = tostring(err) }), true)
    return false
  end
  set_message(tr(success_key, "Location saved"), false)
  bump_location_rev()
  bump_refresh()
  return true
end

local function select_result(record)
  search_results = {}
  search_error = nil
  save_location(record, "panel.location_saved")
  render()
end

local function on_search_text(value)
  search_text = value or ""
end

local function on_manual_latitude(value)
  manual_latitude = value or ""
end

local function on_manual_longitude(value)
  manual_longitude = value or ""
end

local function on_manual_label(value)
  manual_label = value or ""
end

local function search()
  local query = search_text
  if query == nil or query:gsub("%s", "") == "" then
    search_error = tr("panel.search_empty", "Type a city name first")
    search_results = {}
    render()
    return
  end
  search_loading = true
  search_error = nil
  search_results = {}
  render()
  geocode.request(query, function(result)
    search_loading = false
    if not result.ok then
      search_error = tr("panel.search_failed", "City search failed")
      search_results = {}
      render()
      return
    end
    search_results = result.results or {}
    if #search_results == 0 then
      search_error = tr("panel.search_no_results", "No matching places")
    end
    render()
  end)
end

local function clear_search()
  search_text = ""
  search_results = {}
  search_error = nil
  message = nil
  render()
end

local function save_manual()
  local latitude = tonumber(manual_latitude)
  local longitude = tonumber(manual_longitude)
  local record = location.new(manual_label, latitude, longitude, "", "manual")
  if record == nil then
    set_message(tr("panel.invalid_coords", "Enter a latitude between -90 and 90 and a longitude between -180 and 180"), true)
    render()
    return
  end
  save_location(record, "panel.location_saved")
  render()
end

local function forget()
  cache.clear()
  set_message(tr("panel.location_forgotten", "Location and cached weather removed"), false)
  bump_location_rev()
  render()
end

local function noctalia_location()
  if type(noctalia.getSetting) ~= "function" then
    return nil
  end
  local value = noctalia.getSetting("location")
  if type(value) ~= "table" then
    return nil
  end
  return value
end

local function noctalia_manual_coords()
  local loc = noctalia_location()
  if loc == nil then
    return nil, "unavailable"
  end
  if loc.auto_locate == true then
    return nil, "auto"
  end
  if location.valid_coords(loc.latitude, loc.longitude) then
    return location.new(loc.address, loc.latitude, loc.longitude, "", "noctalia")
  end
  return nil, "none"
end

local function import_noctalia_coords()
  local record, reason = noctalia_manual_coords()
  if record ~= nil then
    save_location(record, "panel.location_saved")
    render()
    return
  end
  if reason == "auto" then
    set_message(tr("panel.noctalia_auto", "Noctalia is set to auto-locate. Use a manual location here so this widget never reuses IP-derived coordinates."), true)
  else
    set_message(tr("panel.noctalia_missing", "No manual coordinates are set in Noctalia"), true)
  end
  render()
end

local function import_noctalia_address()
  local loc = noctalia_location()
  if loc == nil then
    return
  end
  if loc.auto_locate == true then
    set_message(tr("panel.noctalia_auto", "Noctalia is set to auto-locate. Use a manual location here so this widget never reuses IP-derived coordinates."), true)
    render()
    return
  end
  local address = loc.address
  if type(address) ~= "string" or address == "" then
    set_message(tr("panel.noctalia_address_missing", "No address is set in Noctalia"), true)
    render()
    return
  end
  search_text = address
  search()
end

local function refresh()
  bump_refresh()
  set_message(tr("status.refreshing", "Refreshing weather now"), false)
  render()
end

local function open_settings()
  if type(noctalia.openSettings) == "function" then
    noctalia.openSettings()
  end
end

local function close()
  if type(panel.close) == "function" then
    panel.close()
  end
end

local function section(title, children)
  local items = {
    ui.label({ key = "section-title-" .. title, text = title, fontSize = 11, fontWeight = "bold", color = "primary", maxLines = 1 }),
  }
  for _, child in ipairs(children) do
    items[#items + 1] = child
  end
  return ui.column({ key = "section-" .. title, gap = 6, padding = 12, radius = 10, fill = "surface_variant/0.35" }, items)
end

local function location_section()
  local children = {}
  if current ~= nil and current.location ~= nil then
    local zone = current.location.timezone
    if zone == nil or zone == "" then
      zone = current.timezone
    end
    if zone == nil or zone == "" then
      zone = tr("labels.local_time", "Local time")
    end
    table.insert(children, ui.label({
      key = "current-label",
      text = current.location.label or "",
      fontSize = 13,
      fontWeight = "semibold",
      color = "on_surface",
      maxLines = 2,
    }))
    table.insert(children, ui.label({
      key = "current-source",
      text = source_label(current.location.source) .. " · " .. zone,
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 1,
    }))
  else
    table.insert(children, ui.label({
      key = "current-none",
      text = tr("panel.no_location", "No location is set. The clock still works."),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 2,
    }))
  end
  table.insert(children, ui.row({ key = "current-actions", gap = 8, align = "center" }, {
    ui.button({
      key = "forget",
      text = tr("panel.forget", "Forget location"),
      variant = "destructive",
      controlSize = "sm",
      onClick = forget,
    }),
    ui.button({
      key = "refresh",
      text = tr("panel.refresh", "Refresh now"),
      variant = "secondary",
      controlSize = "sm",
      onClick = refresh,
    }),
  }))
  return section(tr("panel.location", "Location"), children)
end

local function search_section()
  local children = {
    ui.input({
      key = "search-input",
      value = search_text,
      placeholder = tr("panel.search_placeholder", "City, for example London"),
      fontSize = 13,
      submitOnEnter = true,
      onChange = on_search_text,
      onSubmit = search,
    }),
    ui.row({ key = "search-actions", gap = 8, align = "center" }, {
      ui.button({
        key = "search-button",
        text = search_loading and tr("panel.searching", "Searching…") or tr("panel.search", "Search"),
        variant = "primary",
        controlSize = "sm",
        enabled = not search_loading,
        onClick = search,
      }),
      ui.button({
        key = "close-search",
        text = tr("panel.clear", "Clear"),
        variant = "ghost",
        controlSize = "sm",
        onClick = clear_search,
      }),
    }),
  }
  if search_error ~= nil then
    table.insert(children, ui.label({
      key = "search-error",
      text = search_error,
      fontSize = 10,
      color = "tertiary",
      maxLines = 2,
    }))
  end
  for index, result in ipairs(search_results) do
    table.insert(children, ui.button({
      key = "search-result-" .. tostring(index),
      text = result.label,
      variant = "ghost",
      controlSize = "sm",
      contentAlign = "start",
      onClick = function()
        select_result(result)
      end,
    }))
  end
  return section(tr("panel.search_title", "Search for a place"), children)
end

local function manual_section()
  return section(tr("panel.manual_title", "Manual coordinates"), {
    ui.row({ key = "manual-row", gap = 8, align = "center" }, {
      ui.input({
        key = "manual-lat",
        value = manual_latitude,
        placeholder = tr("panel.latitude", "Latitude"),
        fontSize = 12,
        flexGrow = 1,
        onChange = on_manual_latitude,
      }),
      ui.input({
        key = "manual-lon",
        value = manual_longitude,
        placeholder = tr("panel.longitude", "Longitude"),
        fontSize = 12,
        flexGrow = 1,
        onChange = on_manual_longitude,
      }),
    }),
    ui.input({
      key = "manual-label",
      value = manual_label,
      placeholder = tr("panel.label", "Label (optional)"),
      fontSize = 12,
      onChange = on_manual_label,
    }),
    ui.button({
      key = "manual-save",
      text = tr("panel.save_location", "Save location"),
      variant = "primary",
      controlSize = "sm",
      onClick = save_manual,
    }),
    ui.label({
      key = "manual-hint",
      text = tr("panel.manual_hint", "Coordinates are rounded to two decimal places before they are sent to Open-Meteo."),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 3,
    }),
  })
end

local function noctalia_section()
  if type(noctalia.getSetting) ~= "function" then
    return nil
  end
  return section(tr("panel.noctalia_title", "Import from Noctalia"), {
    ui.label({
      key = "noctalia-note",
      text = tr("panel.noctalia_note", "Only manual coordinates or an address you typed in Noctalia are imported. IP-based auto-locate is never reused."),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 4,
    }),
    ui.row({ key = "noctalia-actions", gap = 8, align = "center" }, {
      ui.button({
        key = "noctalia-coords",
        text = tr("panel.use_noctalia_coords", "Use manual coordinates"),
        variant = "secondary",
        controlSize = "sm",
        onClick = import_noctalia_coords,
      }),
      ui.button({
        key = "noctalia-address",
        text = tr("panel.use_noctalia_address", "Look up address"),
        variant = "ghost",
        controlSize = "sm",
        onClick = import_noctalia_address,
      }),
    }),
  })
end

local function status_section()
  local children = {
    ui.label({
      key = "status-line",
      text = status_line(),
      fontSize = 11,
      color = "on_surface",
      maxLines = 2,
    }),
  }
  if current ~= nil and current.error ~= nil then
    table.insert(children, ui.label({
      key = "status-error",
      text = error_label(current.error) or "",
      fontSize = 10,
      color = "error",
      maxLines = 2,
    }))
  end
  if current ~= nil and current.fetched_at ~= nil then
    local age = format.age_text(os.time() - current.fetched_at, tr)
    table.insert(children, ui.label({
      key = "status-age",
      text = tr("panel.cache_age", "Last successful update: {age}", { age = age }),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 1,
    }))
  end
  table.insert(children, ui.label({
    key = "status-privacy",
    text = tr("panel.privacy", "Only rounded coordinates and your IP are sent to Open-Meteo. No automatic IP lookup, no history, no analytics."),
    fontSize = 9,
    color = "on_surface_variant",
    maxLines = 4,
  }))
  return section(tr("panel.status", "Status and privacy"), children)
end

function render()
  local children = {
    ui.row({ key = "panel-header", gap = 8, align = "center" }, {
      ui.glyph({ key = "panel-glyph", name = "weather-cloud-sun", size = 20, color = "primary" }),
      ui.label({
        key = "panel-title",
        text = tr("meta.name", "Weather & Time"),
        fontSize = 16,
        fontWeight = "semibold",
        color = "on_surface",
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.button({
        key = "panel-settings",
        glyph = "settings",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = open_settings,
      }),
      ui.button({
        key = "panel-close",
        glyph = "x",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = close,
      }),
    }),
    location_section(),
  }
  if message ~= nil then
    table.insert(children, ui.label({
      key = "panel-message",
      text = message,
      fontSize = 10,
      color = message_error and "error" or "primary",
      maxLines = 3,
    }))
  end
  table.insert(children, search_section())
  table.insert(children, manual_section())
  local imported = noctalia_section()
  if imported ~= nil then
    table.insert(children, imported)
  end
  table.insert(children, status_section())
  panel.render(ui.scroll({ key = "panel-root", gap = 12, padding = 16, flexGrow = 1 }, children))
end

function onOpen()
  render()
end

function update()
  render()
end

noctalia.setUpdateInterval(30000)
noctalia.state.watch("weather_time", function(value)
  current = value
  render()
end)
render()
