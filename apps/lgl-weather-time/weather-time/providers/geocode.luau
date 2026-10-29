-- Open-Meteo geocoding used only by the setup panel, and only after an
-- explicit Search / Import action. No request is made while typing.

local location = require("../lib/location.luau")

local M = {}

M.ENDPOINT = "https://geocoding-api.open-meteo.com/v1/search"
M.MAX_RESULTS = 5
M.MAX_BODY = 512 * 1024

local function text(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

function M.build_url(query)
  local clean = type(query) == "string" and query:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if clean == "" or #clean > 120 then
    return nil
  end
  return M.ENDPOINT
    .. "?name=" .. noctalia.string.urlEncode(clean)
    .. "&count=" .. tostring(M.MAX_RESULTS)
    .. "&language=en&format=json"
end

function M.parse(body)
  if type(body) ~= "string" or body == "" then
    return nil, "empty response"
  end
  if #body > M.MAX_BODY then
    return nil, "response too large"
  end
  local decoded, err = noctalia.json.decode(body)
  if decoded == nil then
    return nil, err or "invalid json"
  end
  local rows = type(decoded) == "table" and decoded.results or nil
  if type(rows) ~= "table" then
    return {}
  end
  local results = {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and location.valid_coords(row.latitude, row.longitude) then
      local label_parts = {}
      local name = text(row.name)
      local admin = text(row.admin1)
      local country = text(row.country)
      if name ~= nil then
        table.insert(label_parts, name)
      end
      if admin ~= nil and admin ~= name then
        table.insert(label_parts, admin)
      end
      if country ~= nil then
        table.insert(label_parts, country)
      end
      local record = location.new(
        table.concat(label_parts, ", "),
        row.latitude,
        row.longitude,
        text(row.timezone) or "",
        "search"
      )
      if record ~= nil then
        record.id = row.id
        record.country = country
        record.admin1 = admin
        results[#results + 1] = record
      end
      if #results >= M.MAX_RESULTS then
        break
      end
    end
  end
  return results
end

-- callback({ ok, status, results, error })
function M.request(query, callback)
  local url = M.build_url(query)
  if url == nil then
    callback({ ok = false, status = 0, results = {}, error = "empty query" })
    return false
  end
  local accepted = noctalia.http({
    url = url,
    method = "GET",
    headers = { "Accept: application/json" },
    follow_redirects = false,
    allow_insecure_tls = false,
  }, function(response)
    if response == nil or response.ok ~= true then
      callback({ ok = false, status = response and tonumber(response.status) or 0, results = {}, error = "network" })
      return
    end
    local status = tonumber(response.status) or 0
    if status ~= 200 then
      callback({ ok = false, status = status, results = {}, error = "http" })
      return
    end
    local results, err = M.parse(response.body or "")
    if results == nil then
      callback({ ok = false, status = status, results = {}, error = err or "parse" })
      return
    end
    callback({ ok = true, status = status, results = results })
  end)
  if not accepted then
    callback({ ok = false, status = 0, results = {}, error = "request not accepted" })
  end
  return accepted
end

return M
