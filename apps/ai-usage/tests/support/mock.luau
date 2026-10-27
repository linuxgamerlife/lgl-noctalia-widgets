-- Minimal Noctalia host mock for LuaJIT tests.

local M = {}

local PLUGIN_ROOT = arg[1] or "ai-usage"
local DATA_DIR = "/tmp/opencode/ai-usage-data"
local TRANSLATIONS = PLUGIN_ROOT .. "/translations/en.json"

-- ── JSON ────────────────────────────────────────────────────────────────────

local function jsonDecode(text)
  local pos = 1

  local function skip()
    while pos <= #text and text:sub(pos, pos):match("%s") do
      pos = pos + 1
    end
  end

  local parseValue

  local function parseString()
    pos = pos + 1
    local out = {}
    while pos <= #text do
      local char = text:sub(pos, pos)
      if char == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif char == "\\" then
        local escape = text:sub(pos + 1, pos + 1)
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if map[escape] then
          table.insert(out, map[escape])
          pos = pos + 2
        elseif escape == "u" then
          local hex = text:sub(pos + 2, pos + 5)
          local code = tonumber(hex, 16) or 63
          if code < 128 then
            table.insert(out, string.char(code))
          else
            table.insert(out, "?")
          end
          pos = pos + 6
        else
          pos = pos + 1
        end
      else
        table.insert(out, char)
        pos = pos + 1
      end
    end
    error("unterminated JSON string")
  end

  local function parseNumber()
    local start = pos
    while pos <= #text and text:sub(pos, pos):match("[-+0-9.eE]") do
      pos = pos + 1
    end
    return tonumber(text:sub(start, pos - 1))
  end

  local function parseArray()
    pos = pos + 1
    local out = {}
    skip()
    if text:sub(pos, pos) == "]" then
      pos = pos + 1
      return out
    end
    while true do
      table.insert(out, parseValue())
      skip()
      local char = text:sub(pos, pos)
      pos = pos + 1
      if char == "]" then
        return out
      elseif char ~= "," then
        error("bad JSON array")
      end
    end
  end

  local function parseObject()
    pos = pos + 1
    local out = {}
    skip()
    if text:sub(pos, pos) == "}" then
      pos = pos + 1
      return out
    end
    while true do
      skip()
      local key = parseString()
      skip()
      if text:sub(pos, pos) ~= ":" then
        error("bad JSON object")
      end
      pos = pos + 1
      out[key] = parseValue()
      skip()
      local char = text:sub(pos, pos)
      pos = pos + 1
      if char == "}" then
        return out
      elseif char ~= "," then
        error("bad JSON object")
      end
    end
  end

  parseValue = function()
    skip()
    local char = text:sub(pos, pos)
    if char == "{" then
      return parseObject()
    elseif char == "[" then
      return parseArray()
    elseif char == '"' then
      return parseString()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end
    return parseNumber()
  end

  local value = parseValue()
  skip()
  if pos <= #text then
    error("trailing JSON data")
  end
  return value
end

local function jsonEncode(value)
  local kind = type(value)
  if value == nil then
    return "null"
  end
  if kind == "boolean" then
    return value and "true" or "false"
  end
  if kind == "number" then
    if value % 1 == 0 then
      return string.format("%d", value)
    end
    return tostring(value)
  end
  if kind == "string" then
    local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. escaped .. '"'
  end
  if kind == "table" then
    local isArray = #value > 0
    if isArray then
      local parts = {}
      for _, item in ipairs(value) do
        table.insert(parts, jsonEncode(item))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
      if type(key) == "string" then
        table.insert(keys, key)
      end
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
      table.insert(parts, jsonEncode(key) .. ":" .. jsonEncode(value[key]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

M.jsonEncode = jsonEncode
M.jsonDecode = jsonDecode

-- ── Require shim ────────────────────────────────────────────────────────────

local moduleCache = {}
local currentFile = nil

local function normalize(path)
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then
        table.remove(parts)
      end
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return (absolute and "/" or "") .. table.concat(parts, "/")
end

local function dirname(path)
  local dir = path:match("^(.*)/[^/]+$")
  return dir or "."
end

local function loadFile(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err)
  end
  local previous = currentFile
  currentFile = path
  local ok, value = pcall(chunk)
  currentFile = previous
  if not ok then
    error(value)
  end
  return value
end

local function pluginRequire(path)
  if type(path) ~= "string" then
    error("require path must be a string")
  end
  local base = currentFile and dirname(currentFile) or PLUGIN_ROOT
  local full = normalize(base .. "/" .. path)
  if moduleCache[full] ~= nil then
    return moduleCache[full]
  end
  local value = loadFile(full)
  moduleCache[full] = value
  return value
end

function M.loadEntry(entry)
  local path = PLUGIN_ROOT .. "/" .. entry
  currentFile = path
  return loadFile(path)
end

-- ── Translations ────────────────────────────────────────────────────────────

local translations = {}
local function flattenTranslations(node, prefix)
  if type(node) ~= "table" then
    return
  end
  for key, value in pairs(node) do
    local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
    if type(value) == "table" then
      flattenTranslations(value, path)
    elseif type(value) == "string" then
      translations[path] = value
    end
  end
end
do
  local file = io.open(TRANSLATIONS, "r")
  if file then
    flattenTranslations(jsonDecode(file:read("*a")), "")
    file:close()
  end
end

local function tr(key, subst)
  local template = translations[key]
  if template == nil then
    return key
  end
  return (template:gsub("{([%w_]+)}", function(name)
    local value = subst and subst[name]
    return value == nil and ("{" .. name .. "}") or tostring(value)
  end))
end

-- ── UI constructors ─────────────────────────────────────────────────────────

local function node(kind)
  return function(props, children)
    return { type = kind, props = props or {}, children = children or {} }
  end
end

local function installUi()
  ui = {
    column = node("column"),
    row = node("row"),
    box = node("box"),
    label = node("label"),
    glyph = node("glyph"),
    image = node("image"),
    spacer = node("spacer"),
    separator = node("separator"),
    progress = node("progress"),
    button = node("button"),
    scroll = node("scroll"),
    select = node("select"),
    input = node("input"),
    toggle = node("toggle"),
    slider = node("slider"),
    graph = node("graph"),
    markdown = node("markdown"),
  }
end

-- ── Host ────────────────────────────────────────────────────────────────────

function M.new(options)
  local opts = options or {}
  local context = {
    files = opts.files or {},
    state = {},
    watchers = {},
    notifications = {},
    config = opts.config or {},
    commands = {},
    intervals = {},
    panels = {},
    openedSettings = 0,
    filesWritten = {},
    runAsync = opts.runAsync,
    commandExists = opts.commandExists or function()
      return true
    end,
    env = opts.env or {},
  }

  installUi()
  _G.require = pluginRequire

  noctalia = {
    getConfig = function(key)
      return context.config[key]
    end,
    setUpdateInterval = function(ms)
      if ms ~= nil then
        table.insert(context.intervals, ms)
      end
    end,
    log = function(message)
      if opts.verbose then
        print("LOG " .. tostring(message))
      end
    end,
    isDarkMode = function()
      return true
    end,
    getColor = function()
      return nil
    end,
    tr = tr,
    trp = function(key, count, subst)
      return tr(key, subst)
    end,
    json = {
      decode = function(text)
        local ok, value = pcall(jsonDecode, text)
        if not ok then
          return nil, value
        end
        return value
      end,
      encode = function(value)
        local ok, text = pcall(jsonEncode, value)
        return ok and text or nil
      end,
    },
    string = {
      urlEncode = function(text)
        return (tostring(text):gsub("[^%w%-_%.~]", function(char)
          return string.format("%%%02X", string.byte(char))
        end))
      end,
      trim = function(text)
        return (text:gsub("^%s*(.-)%s*$", "%1"))
      end,
    },
    state = {
      get = function(key)
        return context.state[key]
      end,
      set = function(key, value)
        context.state[key] = value
        for _, watcher in ipairs(context.watchers[key] or {}) do
          watcher(value)
        end
      end,
      watch = function(key, callback)
        context.watchers[key] = context.watchers[key] or {}
        table.insert(context.watchers[key], callback)
      end,
    },
    pluginDir = function()
      return PLUGIN_ROOT
    end,
    pluginDataDir = function()
      return DATA_DIR
    end,
    readFile = function(path)
      local value = context.files[path]
      if value == nil then
        return nil, "not found"
      end
      return value
    end,
    writeFile = function(path, content)
      context.files[path] = content
      context.filesWritten[path] = content
      return true
    end,
    removeFile = function(path)
      context.files[path] = nil
      return true
    end,
    renameFile = function(from, to)
      context.files[to] = context.files[from]
      context.files[from] = nil
      return true
    end,
    fileExists = function(path)
      return context.files[path] ~= nil
    end,
    fileInfo = function()
      return { size = 0, mtime = 0, isDir = false }
    end,
    listDir = function()
      return {}
    end,
    mkdirAll = function()
      return true
    end,
    commandExists = function(name)
      return context.commandExists(name)
    end,
    runAsync = function(command, callback, timeout)
      table.insert(context.commands, { command = command, timeout = timeout })
      if context.runAsync then
        local accepted = context.runAsync(command, callback, timeout, context)
        if accepted == false then
          return false
        end
        return true
      end
      if callback then
        callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
      end
      return true
    end,
    notify = function(title, body)
      table.insert(context.notifications, { title = title, body = body, error = false })
    end,
    notifyError = function(title, body)
      table.insert(context.notifications, { title = title, body = body, error = true })
    end,
    getenv = function(name)
      return context.env[name]
    end,
    expandPath = function(path)
      return path
    end,
    togglePanel = function(id)
      table.insert(context.panels, id)
    end,
    openSettings = function()
      context.openedSettings = context.openedSettings + 1
    end,
    copyToClipboard = function()
      return true
    end,
    nowMs = function()
      return os.time() * 1000
    end,
    formatTime = function(pattern)
      return os.date(pattern)
    end,
  }

  desktopWidget = {
    render = function(tree)
      context.desktopTree = tree
    end,
    setWantsSecondTicks = function(value)
      context.wantsSecondTicks = value
    end,
    setNeedsFrameTick = function(value)
      context.needsFrameTick = value
    end,
  }

  barWidget = {
    render = function(tree)
      context.barTree = tree
    end,
    isVertical = function()
      return opts.vertical == true
    end,
    setText = function(text)
      context.barText = text
    end,
    setGlyph = function(glyph)
      context.barGlyph = glyph
    end,
    setImage = function(path)
      context.barImage = path
    end,
  }

  panel = {
    render = function(tree)
      context.panelTree = tree
    end,
    close = function()
      context.panelClosed = true
    end,
    setWantsSecondTicks = function(value)
      context.panelWantsTicks = value
    end,
    setNeedsFrameTick = function(value)
      context.panelNeedsTicks = value
    end,
    openContextMenu = function()
      return true
    end,
  }

  context.readAccountsFile = function()
    local text = context.files[DATA_DIR .. "/accounts.json"]
    if not text then
      return {}
    end
    local value = jsonDecode(text)
    return value.accounts or {}
  end

  return context
end

-- Walk a ui tree.
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
  for _, item in ipairs(M.walk(tree)) do
    if item.props and item.props.key == key then
      return item
    end
  end
  return nil
end

function M.findText(tree, text)
  for _, item in ipairs(M.walk(tree)) do
    if item.props and item.props.text == text then
      return item
    end
  end
  return nil
end

function M.click(item)
  local callback = item and item.props and item.props.onClick
  if type(callback) == "function" then
    return callback()
  end
  if type(callback) == "string" and type(_G[callback]) == "function" then
    return _G[callback]()
  end
  error("no click handler on " .. tostring(item and item.props and item.props.key))
end

function M.change(item, value)
  local callback = item and item.props and item.props.onChange
  if type(callback) == "function" then
    return callback(value)
  end
  if type(callback) == "string" and type(_G[callback]) == "function" then
    return _G[callback](value)
  end
  error("no change handler on " .. tostring(item and item.props and item.props.key))
end

function M.findType(tree, kind)
  local result = {}
  for _, item in ipairs(M.walk(tree)) do
    if item.type == kind then
      table.insert(result, item)
    end
  end
  return result
end

return M
