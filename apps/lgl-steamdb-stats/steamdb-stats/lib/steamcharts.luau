-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- SteamCharts + official Steam transports.
--
-- SteamDB blocks automated clients (HTTP 403/410), so the widget uses the
-- three values SteamCharts exposes on the app page and its chart-data.json
-- series. The live count also comes from Valve's keyless
-- GetNumberOfCurrentPlayers endpoint, which is refreshed more often.

local M = {}

M.MAX_BODY = 1024 * 1024
M.HOURS = 24

local function decode_entities(text)
  if type(text) ~= "string" then
    return text
  end
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#39;", "'")
  text = text:gsub("&#x27;", "'")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&#(%d+);", function(value)
    local code = tonumber(value)
    if code ~= nil and code > 0 and code < 256 then
      return string.char(code)
    end
    return ""
  end)
  text = text:gsub("&amp;", "&")
  return text
end

M.decode_entities = decode_entities

local function number_from_html(value)
  if type(value) ~= "string" then
    return nil
  end
  local digits = value:gsub("[^%d]", "")
  if digits == "" then
    return nil
  end
  return tonumber(digits)
end

function M.page_url(appid)
  return "https://steamcharts.com/app/" .. tostring(appid)
end

function M.chart_url(appid)
  return "https://steamcharts.com/app/" .. tostring(appid) .. "/chart-data.json"
end

function M.current_url(appid)
  return "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid="
    .. tostring(appid)
end

-- Return { current, peak_24h, peak_all_time, name } or nil, reason.
function M.parse_page(body)
  if type(body) ~= "string" or body == "" then
    return nil, "empty page"
  end
  if #body > M.MAX_BODY then
    return nil, "page too large"
  end

  local current = number_from_html(body:match('<span class="num">([%d,]+)</span>%s*<br>%s*playing'))
  local peak_24h = number_from_html(body:match('<span class="num">([%d,]+)</span>%s*<br>%s*24%-hour peak'))
  local peak_all_time = number_from_html(body:match('<span class="num">([%d,]+)</span>%s*<br>%s*all%-time peak'))
  local name = body:match('<h1 id="app%-title">%s*<a[^>]*>(.-)</a>%s*</h1>')
  if name ~= nil then
    name = decode_entities(name):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
      name = nil
    end
  end

  if current == nil and peak_24h == nil and peak_all_time == nil then
    return nil, "unexpected page layout"
  end

  return {
    current = current,
    peak_24h = peak_24h,
    peak_all_time = peak_all_time,
    name = name,
  }
end

-- Return { points, current, peak_24h, peak_at } or nil, reason.
function M.parse_chart(body)
  if type(body) ~= "string" or body == "" then
    return nil, "empty chart"
  end
  if #body > M.MAX_BODY then
    return nil, "chart too large"
  end

  local decoded, err = noctalia.json.decode(body)
  if type(decoded) ~= "table" then
    return nil, err or "invalid chart json"
  end

  local all = {}
  for _, point in ipairs(decoded) do
    if type(point) == "table" then
      local stamp = tonumber(point[1])
      local players = tonumber(point[2])
      if stamp ~= nil and players ~= nil then
        all[#all + 1] = {
          t = math.floor(stamp / 1000),
          v = players,
        }
      end
    end
  end

  if #all < 2 then
    return nil, "chart has too few points"
  end

  table.sort(all, function(left, right)
    return left.t < right.t
  end)

  local last_t = all[#all].t
  local cutoff = last_t - M.HOURS * 3600
  local recent = {}
  for _, point in ipairs(all) do
    if point.t >= cutoff then
      recent[#recent + 1] = point
    end
  end

  -- A game with only daily history still gets a usable line; keep the last
  -- two points rather than an empty graph.
  if #recent < 2 then
    recent = {}
    local first = math.max(1, #all - 23)
    for index = first, #all do
      recent[#recent + 1] = all[index]
    end
  end

  local peak = 0
  for _, point in ipairs(recent) do
    if point.v > peak then
      peak = point.v
    end
  end

  return {
    points = recent,
    current = all[#all].v,
    peak_24h = peak,
    peak_at = all[1].t,
  }
end

-- Normalise the visible series to 0..1 for ui.graph. Use the 24-hour peak as
-- the top so the line keeps a stable shape between refreshes.
function M.normalize(points, peak)
  if type(points) ~= "table" or #points == 0 then
    return {}
  end

  local function point_value(point)
    if type(point) == "table" then
      return tonumber(point.v)
    end
    return tonumber(point)
  end

  local top = tonumber(peak) or 0
  if top <= 0 then
    for _, point in ipairs(points) do
      local value = point_value(point)
      if value ~= nil and value > top then
        top = value
      end
    end
  end
  if top <= 0 then
    top = 1
  end

  local values = {}
  for _, point in ipairs(points) do
    local value = point_value(point) or 0
    values[#values + 1] = math.max(0, math.min(1, value / top))
  end
  return values
end

local function request(url, accept, callback)
  if type(noctalia.http) ~= "function" then
    callback({ ok = false, status = 0, body = "", error = "http unavailable" })
    return false
  end

  local accepted = noctalia.http({
    url = url,
    method = "GET",
    headers = {
      "Accept: " .. accept,
      "User-Agent: LGL-Noctalia-SteamStats/0.1",
    },
    follow_redirects = false,
    allow_insecure_tls = false,
  }, function(response)
    local body = response ~= nil and response.body or ""
    local status = response ~= nil and tonumber(response.status) or 0
    local ok = response ~= nil and response.ok == true and status == 200
    callback({
      ok = ok,
      status = status,
      body = body,
      error = ok and nil or "request failed",
    })
  end)

  if not accepted then
    callback({ ok = false, status = 0, body = "", error = "request not accepted" })
  end
  return accepted
end

function M.request_page(appid, callback)
  return request(M.page_url(appid), "text/html", callback)
end

function M.request_chart(appid, callback)
  return request(M.chart_url(appid), "application/json", callback)
end

function M.parse_current(body)
  if type(body) ~= "string" or body == "" then
    return nil, "empty response"
  end
  local decoded, err = noctalia.json.decode(body)
  if type(decoded) ~= "table" or type(decoded.response) ~= "table" then
    return nil, err or "invalid current response"
  end
  local count = tonumber(decoded.response.player_count)
  if count == nil then
    return nil, "missing player_count"
  end
  return count
end

function M.request_current(appid, callback)
  return request(M.current_url(appid), "application/json", function(result)
    if not result.ok then
      callback(result)
      return
    end
    local count, err = M.parse_current(result.body)
    if count == nil then
      callback({ ok = false, status = result.status, body = result.body, error = err })
      return
    end
    callback({
      ok = true,
      status = result.status,
      body = result.body,
      count = count,
    })
  end)
end

return M
