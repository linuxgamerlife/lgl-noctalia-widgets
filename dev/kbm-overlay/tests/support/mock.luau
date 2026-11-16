-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Minimal Noctalia host mock for the Weather & Time tests.
-- Installs noctalia.*, ui.*, desktopWidget.*, barWidget.*, panel.* and a
-- relative module loader. No running shell is required.

local M = {}

local PLUGIN_ROOT = arg[1] or "weather-time"
local module_cache = {}
local current_file = nil

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local function normalize(path)
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then
        table.remove(parts)
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local joined = table.concat(parts, "/")
  if absolute then
    return "/" .. joined
  end
  return joined
end

local function load_file(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err)
  end
  local previous = current_file
  current_file = path
  local ok, value = pcall(chunk)
  current_file = previous
  if not ok then
    error(value)
  end
  return value
end

local function plugin_require(path)
  if type(path) ~= "string" then
    error("require path must be a string")
  end
  if path:sub(1, 2) ~= "./" and path:sub(1, 3) ~= "../" then
    error("require path must be relative")
  end
  if path:sub(-5) ~= ".luau" then
    error("require path must end in .luau")
  end
  local base = current_file and dirname(current_file) or PLUGIN_ROOT
  local full = normalize(base .. "/" .. path)
  if module_cache[full] ~= nil then
    return module_cache[full]
  end
  local value = load_file(full)
  if value == nil then
    error("module did not return a value: " .. full)
  end
  module_cache[full] = value
  return value
end

function M.loadEntry(entry)
  return load_file(PLUGIN_ROOT .. "/" .. entry)
end

local function token(kind)
  return function(props, children)
    return { type = kind, props = props or {}, children = children or {} }
  end
end

local function install_ui()
  ui = {
    column = token("column"),
    row = token("row"),
    box = token("box"),
    label = token("label"),
    glyph = token("glyph"),
    image = token("image"),
    separator = token("separator"),
    spacer = token("spacer"),
    progress = token("progress"),
    button = token("button"),
    graph = token("graph"),
    input = token("input"),
    select = token("select"),
    slider = token("slider"),
    toggle = token("toggle"),
    scroll = token("scroll"),
    markdown = token("markdown"),
  }
end

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, item in pairs(value) do
    out[key] = deep_copy(item)
  end
  return out
end

local DEFAULT_TRANSLATIONS = {
  ["meta.name"] = "Weather & Time",
  ["conditions.clear"] = "Clear",
  ["conditions.mainly_clear"] = "Mainly clear",
  ["conditions.partly_cloudy"] = "Partly cloudy",
  ["conditions.overcast"] = "Overcast",
  ["conditions.fog"] = "Fog",
  ["conditions.drizzle"] = "Drizzle",
  ["conditions.rain"] = "Rain",
  ["conditions.freezing_rain"] = "Freezing rain",
  ["conditions.snow"] = "Snow",
  ["conditions.showers"] = "Showers",
  ["conditions.snow_showers"] = "Snow showers",
  ["conditions.thunderstorm"] = "Thunderstorm",
  ["conditions.thunderstorm_hail"] = "Thunderstorm with hail",
  ["conditions.unknown"] = "Unknown",
  ["labels.local_time"] = "Local time",
  ["labels.feels"] = "Feels",
  ["labels.wind"] = "Wind",
  ["labels.humidity"] = "Humidity",
  ["labels.precipitation"] = "Precip",
  ["labels.no_location"] = "No location",
  ["status.set_location"] = "Set a location",
  ["status.loading"] = "Loading weather…",
  ["status.cached"] = "Cached weather — refresh failed",
  ["status.stale"] = "Cached weather",
  ["status.refreshing"] = "Refreshing weather now",
  ["age.now"] = "just now",
  ["age.minutes"] = "{n} min ago",
  ["age.hours"] = "{n} h ago",
  ["age.days"] = "{n} d ago",
}

local function json_escape(value)
  return value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

local function json_encode(value)
  local kind = type(value)
  if kind == "nil" then
    return "null"
  elseif kind == "boolean" then
    return value and "true" or "false"
  elseif kind == "number" then
    return tostring(value)
  elseif kind == "string" then
    return '"' .. json_escape(value) .. '"'
  elseif kind == "table" then
    local is_array = #value > 0
    local parts = {}
    if is_array then
      for _, item in ipairs(value) do
        parts[#parts + 1] = json_encode(item)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      parts[#parts + 1] = json_encode(tostring(key)) .. ":" .. json_encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode " .. kind)
end

local function json_decode(text)
  if type(text) ~= "string" then
    return nil, "not a string"
  end
  local position = 1
  local function skip()
    while position <= #text and text:sub(position, position):match("%s") do
      position = position + 1
    end
  end
  local parse_value
  local function parse_string()
    position = position + 1
    local out = {}
    while position <= #text do
      local char = text:sub(position, position)
      if char == '"' then
        position = position + 1
        return table.concat(out)
      elseif char == "\\" then
        local next_char = text:sub(position + 1, position + 1)
        local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\" }
        out[#out + 1] = map[next_char] or next_char
        position = position + 2
      else
        out[#out + 1] = char
        position = position + 1
      end
    end
    error("unterminated string")
  end
  parse_value = function()
    skip()
    local char = text:sub(position, position)
    if char == "{" then
      position = position + 1
      local out = {}
      skip()
      if text:sub(position, position) == "}" then
        position = position + 1
        return out
      end
      while true do
        skip()
        local key = parse_string()
        skip()
        assert(text:sub(position, position) == ":", "expected colon")
        position = position + 1
        out[key] = parse_value()
        skip()
        local sep = text:sub(position, position)
        position = position + 1
        if sep == "}" then
          return out
        end
        assert(sep == ",", "expected comma")
      end
    elseif char == "[" then
      position = position + 1
      local out = {}
      skip()
      if text:sub(position, position) == "]" then
        position = position + 1
        return out
      end
      while true do
        out[#out + 1] = parse_value()
        skip()
        local sep = text:sub(position, position)
        position = position + 1
        if sep == "]" then
          return out
        end
        assert(sep == ",", "expected comma")
      end
    elseif char == '"' then
      return parse_string()
    elseif text:sub(position, position + 3) == "true" then
      position = position + 4
      return true
    elseif text:sub(position, position + 4) == "false" then
      position = position + 5
      return false
    elseif text:sub(position, position + 3) == "null" then
      position = position + 4
      return nil
    else
      local start = position
      while position <= #text and text:sub(position, position):match("[%d%+%-%.eE]") do
        position = position + 1
      end
      local number = tonumber(text:sub(start, position - 1))
      if number == nil then
        error("invalid json at " .. tostring(start))
      end
      return number
    end
  end
  local ok, value = pcall(parse_value)
  if not ok then
    return nil, value
  end
  return value
end

function M.new(options)
  local opts = options or {}
  local context = {
    config = opts.config or {},
    settings = opts.settings or {},
    state = opts.state or {},
    files = opts.files or {},
    dirs = opts.dirs or {},
    data_dir = opts.data_dir or "/data",
    translations = deep_copy(DEFAULT_TRANSLATIONS),
    watchers = {},
    commands = {},
    streams = {},
    intervals = {},
    requested = {},
    logs = {},
    notifications = {},
    http_requests = {},
    http_responses = opts.http_responses or {},
    http_handler = opts.http_handler,
    commands_available = opts.commands_available or { python3 = true },
    clipboard = nil,
    env = opts.env or {},
    outputs = opts.outputs or {},
    format_time = opts.format_time,
    time_format = opts.time_format or "%H:%M",
    date_format = opts.date_format or "%A, %B %d",
    dark = opts.dark ~= false,
    now_ms = opts.now_ms or 1761744000000,
    valid_timezones = opts.valid_timezones or { ["Europe/London"] = true, ["Europe/Berlin"] = true },
  }
  if opts.translations then
    for key, value in pairs(opts.translations) do
      context.translations[key] = value
    end
  end

  install_ui()
  _G.require = plugin_require

  local function tr(key, subst)
    local template = context.translations[key] or key
    if subst then
      template = template:gsub("{([%w_]+)}", function(name)
        local value = subst[name]
        return value == nil and ("{" .. name .. "}") or tostring(value)
      end)
    end
    return template
  end

  local function ensure_dir(path)
    context.dirs[path] = context.dirs[path] or {}
  end

  noctalia = {
    getConfig = function(key)
      context.requested[key] = true
      return context.config[key]
    end,
    getSetting = function(path)
      context.requested[path] = true
      return context.settings[path]
    end,
    setUpdateInterval = function(ms)
      table.insert(context.intervals, ms)
    end,
    log = function(message)
      table.insert(context.logs, tostring(message))
    end,
    tr = tr,
    trp = function(key, count, subst)
      local values = subst or {}
      values.count = count
      return tr(key, values)
    end,
    json = {
      encode = function(value)
        return json_encode(value)
      end,
      decode = function(value)
        if type(value) == "table" then
          return value
        end
        return json_decode(value)
      end,
    },
    string = {
      trim = function(value)
        return (value:gsub("^%s+", ""):gsub("%s+$", ""))
      end,
      urlEncode = function(value)
        return (value:gsub("([^%w%-%._~])", function(char)
          return string.format("%%%02X", string.byte(char))
        end))
      end,
      urlDecode = function(value)
        return value
      end,
    },
    state = {
      get = function(key)
        return deep_copy(context.state[key])
      end,
      set = function(key, value)
        context.state[key] = deep_copy(value)
        for _, callback in ipairs(context.watchers[key] or {}) do
          callback(deep_copy(value))
        end
      end,
      watch = function(key, callback)
        context.watchers[key] = context.watchers[key] or {}
        table.insert(context.watchers[key], callback)
      end,
    },
    readFile = function(path)
      local value = context.files[path]
      if type(value) == "table" then
        return json_encode(value)
      end
      return value
    end,
    writeFile = function(path, contents)
      ensure_dir(dirname(path))
      context.files[path] = contents
      return true
    end,
    renameFile = function(from, to)
      if context.files[from] == nil then
        return false, "missing"
      end
      context.files[to] = context.files[from]
      context.files[from] = nil
      return true
    end,
    removeFile = function(path)
      context.files[path] = nil
      return true
    end,
    fileExists = function(path)
      if context.files[path] ~= nil or context.dirs[path] ~= nil then
        return true
      end
      local handle = io.open(path, "r")
      if handle then
        handle:close()
        return true
      end
      return false
    end,
    mkdirAll = function(path)
      ensure_dir(path)
      return true
    end,
    pluginDataDir = function()
      ensure_dir(context.data_dir)
      return context.data_dir
    end,
    pluginDir = function()
      return PLUGIN_ROOT
    end,
    runAsync = function(command, callback)
      table.insert(context.commands, command)
      if callback then
        callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
      end
      return true
    end,
    runStream = function(command, callback)
      table.insert(context.streams, command)
      context.stream_callback = callback
      return true
    end,
    commandExists = function(name)
      return context.commands_available == nil or context.commands_available[name] == true
    end,
    copyToClipboard = function(text, mime)
      context.clipboard = { text = text, mime = mime }
      return true
    end,
    nowMs = function()
      return context.now_ms
    end,
    outputs = function()
      return deep_copy(context.outputs)
    end,
    formatTime = function(pattern, timestamp, timezone)
      if context.format_time then
        return context.format_time(pattern, timestamp, timezone)
      end
      return os.date(pattern, timestamp or os.time())
    end,
    timeFormat = function()
      return context.time_format
    end,
    dateFormat = function()
      return context.date_format
    end,
    isValidTimezone = function(name)
      return name == "" or context.valid_timezones[name] == true
    end,
    isDarkMode = function()
      return context.dark
    end,
    http = function(request, callback)
      table.insert(context.http_requests, deep_copy(request))
      local response = nil
      if context.http_handler then
        response = context.http_handler(request, context)
      elseif #context.http_responses > 0 then
        response = table.remove(context.http_responses, 1)
      end
      if response == nil then
        response = { ok = false, status = 0, body = "" }
      end
      if type(response) == "table" and type(response.body) == "table" then
        response = deep_copy(response)
        response.body = json_encode(response.body)
      end
      if type(response) == "function" then
        response(callback, context)
      else
        callback(response)
      end
      return true
    end,
    togglePanel = function(id)
      context.toggled_panel = id
    end,
    openSettings = function()
      context.opened_settings = (context.opened_settings or 0) + 1
    end,
    notify = function(title, body)
      table.insert(context.notifications, { title = title, body = body })
    end,
    notifyError = function(title, body)
      table.insert(context.notifications, { title = title, body = body, error = true })
    end,
    getenv = function(name)
      return context.env[name]
    end,
  }

  desktopWidget = {
    render = function(tree)
      context.desktop_tree = tree
    end,
    setWantsSecondTicks = function(value)
      context.wants_second_ticks = value
    end,
    setNeedsFrameTick = function(value)
      context.needs_frame_tick = value
    end,
  }

  barWidget = {
    render = function(tree)
      context.bar_tree = tree
    end,
    isVertical = function()
      return context.vertical == true
    end,
  }

  panel = {
    render = function(tree)
      context.panel_tree = tree
    end,
    close = function()
      context.panel_closed = true
    end,
    setWantsSecondTicks = function(value)
      context.panel_seconds = value
    end,
    setNeedsFrameTick = function(value)
      context.panel_frame_tick = value
    end,
  }

  return context
end

function M.walk(tree, out)
  out = out or {}
  if type(tree) ~= "table" then
    return out
  end
  table.insert(out, tree)
  for _, child in ipairs(tree.children or {}) do
    M.walk(child, out)
  end
  return out
end

function M.find(tree, key)
  for _, node in ipairs(M.walk(tree)) do
    if node.props and node.props.key == key then
      return node
    end
  end
  return nil
end

function M.findText(tree, text)
  for _, node in ipairs(M.walk(tree)) do
    if node.props and node.props.text == text then
      return node
    end
  end
  return nil
end

function M.count(tree, kind)
  local count = 0
  for _, node in ipairs(M.walk(tree)) do
    if node.type == kind then
      count = count + 1
    end
  end
  return count
end

return M
