-- Minimal Noctalia host mock for the LuaJIT tests.
--
-- It installs the sandbox globals (noctalia.*, ui.*, desktopWidget.*), provides
-- a relative `require` loader for lib/, and exposes the rendered tree plus the
-- recorded settings/commands for assertions. No Noctalia session is needed.

local M = {}

local PLUGIN_ROOT = arg[1] or "modern-sysmonitor-plus"
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
    graph = token("graph"),
    progress = token("progress"),
    button = token("button"),
    separator = token("separator"),
    spacer = token("spacer"),
    image = token("image"),
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
  ["meta.name"] = "Modern SysMonitor Plus",
  ["labels.unknown"] = "—",
  ["labels.na"] = "N/A",
  ["labels.usage"] = "Usage",
  ["labels.temp"] = "Temp",
  ["labels.fan"] = "Fan",
  ["labels.network"] = "NETWORK",
  ["labels.download"] = "Download",
  ["labels.upload"] = "Upload",
  ["labels.cpu"] = "CPU",
  ["labels.ram"] = "RAM",
  ["labels.gpu"] = "GPU",
  ["labels.vram"] = "VRAM",
  ["labels.disks"] = "DISKS",
  ["gpu.more"] = "More",
  ["gpu.less"] = "Less",
  ["gpu.junction"] = "Junction:",
  ["gpu.mem_temp"] = "Mem temp:",
  ["gpu.clock"] = "Clock:",
  ["gpu.mem_clock"] = "Mem clock:",
  ["gpu.fan"] = "Fan:",
  ["gpu.power"] = "Power:",
  ["status.waiting"] = "Waiting for system data",
  ["status.unavailable"] = "Sensor data unavailable",
  ["status.no_sections"] = "All sections are hidden",
  ["status.no_gpu"] = "No GPU detected",
  ["units.bps"] = "B/s",
  ["units.kbps"] = "KB/s",
  ["units.mbps"] = "MB/s",
  ["units.gbps"] = "GB/s",
  ["units.gb"] = "GB",
  ["units.tb"] = "TB",
  ["units.rpm"] = "RPM",
  ["units.celsius"] = "°C",
  ["units.mhz"] = "MHz",
  ["units.watts"] = "W",
}

function M.new(options)
  local opts = options or {}
  local context = {
    files = opts.files or {},
    dirs = opts.dirs or {},
    config = opts.config or {},
    state = opts.state or {},
    watchers = {},
    commands = {},
    intervals = {},
    requested = {},
    notifications = {},
    openedSettings = 0,
    now_ms = opts.now_ms or (os.time() * 1000),
    system_stats = opts.system_stats,
    nvidia_smi = opts.nvidia_smi == true,
    df_stdout = opts.df_stdout or "",
    nvidia_stdout = opts.nvidia_stdout or "",
    translations = deep_copy(DEFAULT_TRANSLATIONS),
    colors = opts.colors or {},
    run_async = opts.run_async,
    command_exists = opts.command_exists,
  }

  if opts.translations then
    for key, value in pairs(opts.translations) do
      context.translations[key] = value
    end
  end

  context.advance = function(ms)
    context.now_ms = context.now_ms + (tonumber(ms) or 0)
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

  local function default_run_async(command, callback)
    local stdout = ""
    if command:find("df ", 1, true) then
      stdout = context.df_stdout
    elseif command:find("nvidia-smi", 1, true) then
      stdout = context.nvidia_stdout
    end
    if callback then
      callback({ exitCode = 0, stdout = stdout, stderr = "", timedOut = false })
    end
    return true
  end

  noctalia = {
    getConfig = function(key)
      context.requested[key] = true
      return context.config[key]
    end,
    setUpdateInterval = function(ms)
      if ms ~= nil then
        table.insert(context.intervals, ms)
      end
    end,
    log = function() end,
    tr = tr,
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
      return context.files[path]
    end,
    listDir = function(path)
      return context.dirs[path] or {}
    end,
    fileExists = function(path)
      return context.files[path] ~= nil or context.dirs[path] ~= nil
    end,
    commandExists = function(name)
      if context.command_exists then
        return context.command_exists(name)
      end
      if name == "nvidia-smi" then
        return context.nvidia_smi
      end
      return true
    end,
    runAsync = function(command, callback)
      table.insert(context.commands, command)
      local handler = context.run_async or default_run_async
      local accepted = handler(command, callback, context)
      if accepted == false then
        return false
      end
      return true
    end,
    nowMs = function()
      return context.now_ms
    end,
    systemStats = function()
      if type(context.system_stats) == "function" then
        return context.system_stats()
      end
      return context.system_stats
    end,
    openSettings = function()
      context.openedSettings = context.openedSettings + 1
    end,
    getColor = function(role)
      return context.colors[role]
    end,
    notify = function(title, body)
      table.insert(context.notifications, { title = title, body = body, error = false })
    end,
    notifyError = function(title, body)
      table.insert(context.notifications, { title = title, body = body, error = true })
    end,
  }

  desktopWidget = {
    render = function(tree)
      context.desktop_tree = tree
    end,
    setWantsSecondTicks = function(value)
      context.wantsSecondTicks = value
    end,
    setNeedsFrameTick = function(value)
      context.needsFrameTick = value
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

function M.findAll(tree, key)
  local out = {}
  for _, node in ipairs(M.walk(tree)) do
    if node.props and node.props.key == key then
      out[#out + 1] = node
    end
  end
  return out
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
