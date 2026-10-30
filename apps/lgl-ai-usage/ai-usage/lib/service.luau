-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Headless service: owns the account list, the timer and the curl transport,
-- then publishes a plain snapshot for the card, bar widget and panel.

local accountsModule = require("./accounts.luau")
local check = require("./check.luau")
local curl = require("./curlcommand.luau")
local monitorModule = require("./monitor.luau")
local privacy = require("./privacy.luau")
local registry = require("../providers/init.luau")
local shell = require("./shell.luau")
local store = require("./store.luau")
local units = require("./units.luau")

local M = {}

local HEARTBEAT_SECONDS = 30
local MAX_COMMAND_TIMEOUT_MS = 59000
local MODEL_STATS_INTERVAL_SECONDS = 300
local MODEL_STATS_TIMEOUT_MS = 30000

local refreshSeconds = accountsModule.DEFAULT_REFRESH_SECONDS
local showModelStats = true
local modelStatsLimit = 5
local monitor = nil
local started = false
local lastPublishedAt = 0
local lastAccountsRev = nil
local lastRefreshSeq = nil
local refreshModelStats
local modelStats = {
  at = 0,
  models = {},
  error = nil,
  loading = false,
}

local function log(message)
  noctalia.log("[ai-usage] " .. tostring(message))
end

local function nowMs()
  return os.time() * 1000
end

local function runCommand(command, timeoutMs, callback)
  local bounded = math.min(math.max(tonumber(timeoutMs) or 5000, 50), MAX_COMMAND_TIMEOUT_MS)
  local accepted = noctalia.runAsync(command, function(result)
    callback({
      exitCode = result and result.exitCode or 1,
      stdout = result and result.stdout or "",
      stderr = result and result.stderr or "",
      timedOut = result and result.timedOut == true or false,
    })
  end, bounded)
  if not accepted then
    callback({ exitCode = 1, stdout = "", stderr = "", timedOut = false })
  end
end

local tools = {
  now = nowMs,
  newBoundary = curl.newBoundary,
  runCommand = runCommand,
}

-- The widget VMs never need the raw label, and an email-style label should not
-- cross the state channel. Publish only id, service and the masked display name.
local function publicEntry(entry)
  local localModels = {}
  local localModelsError = nil
  if showModelStats and entry.providerId == "opencodeGo" then
    localModels = modelStats.models
    localModelsError = modelStats.error
  end
  return {
    key = entry.key,
    providerId = entry.providerId,
    title = entry.title,
    account = {
      id = entry.account.id,
      service = entry.account.service,
      name = privacy.displayName(entry.account.name),
    },
    usage = entry.usage,
    error = entry.error,
    local_models = localModels,
    local_models_error = localModelsError,
    lastSuccessAt = entry.lastSuccessAt,
    lastAttemptAt = entry.lastAttemptAt,
    nextAttemptAt = entry.nextAttemptAt,
    consecutiveFailures = entry.consecutiveFailures,
    isLoading = entry.isLoading,
    intervalMs = entry.intervalMs,
  }
end

local function snapshotState()
  local rawEntries = monitor and monitor.snapshot() or {}
  local entries = {}
  for _, entry in ipairs(rawEntries) do
    table.insert(entries, publicEntry(entry))
  end
  local hasAccounts = #entries > 0
  local walletLocked = false
  local toolsMissing = false
  for _, entry in ipairs(entries) do
    if entry.error then
      if entry.error.reason == "wallet_locked"
        or entry.error.reason == "secret_service_unavailable"
        or entry.error.reason == "secret_service_timeout" then
        walletLocked = true
      end
      if entry.error.reason == "tool_missing" then
        toolsMissing = true
      end
    end
  end
  return {
    ts = os.time(),
    refresh_seconds = refreshSeconds,
    accounts = entries,
    has_accounts = hasAccounts,
    wallet_locked = walletLocked,
    tools_missing = toolsMissing,
    running = started,
  }
end

local function publish()
  lastPublishedAt = os.time()
  noctalia.state.set("ai_usage", snapshotState())
end

local function loadAccounts()
  local list = store.load(registry.find)
  return list
end

local function reloadAccounts()
  local list = loadAccounts()
  monitor.configure(list, refreshSeconds * units.SECOND_MS)
  if refreshSeconds > 0 then
    monitor.tick()
  end
  if not showModelStats then
    modelStats.models = {}
    modelStats.error = nil
  else
    refreshModelStats(#modelStats.models == 0)
  end
  publish()
end

local function configuredRefreshSeconds()
  return accountsModule.refreshSeconds(noctalia.getConfig("refresh_seconds"))
end

local function configuredShowModelStats()
  local value = noctalia.getConfig("show_model_stats")
  if value == nil then
    return true
  end
  return value == true or value == "true"
end

local function configuredModelStatsLimit()
  local value = tonumber(noctalia.getConfig("model_stats_limit")) or 5
  return math.max(1, math.min(20, value))
end

local function hasOpenCodeGo()
  if monitor == nil then
    return false
  end
  for _, entry in ipairs(monitor.snapshot()) do
    if entry.providerId == "opencodeGo" then
      return true
    end
  end
  return false
end

local function opencodeBinary()
  if noctalia.commandExists("opencode") then
    return "opencode"
  end
  local home = noctalia.getenv("HOME")
  if not home or home == "" then
    return nil
  end
  local candidates = {
    home .. "/.opencode/bin/opencode",
    home .. "/.local/bin/opencode",
  }
  for _, path in ipairs(candidates) do
    if noctalia.fileExists(path) then
      return shell.quote(path)
    end
  end
  return nil
end

local function parseModelStats(stdout)
  local decoded = noctalia.json.decode(stdout)
  if type(decoded) ~= "table" or type(decoded.models) ~= "table" then
    return {}, "opencode stats returned an unexpected format"
  end
  local models = {}
  for _, item in ipairs(decoded.models) do
    local model = type(item) == "table" and item.model or nil
    if type(model) == "table" and model.providerID == "opencode-go" and type(model.id) == "string" then
      local tokens = type(item.tokens) == "table" and item.tokens or {}
      local cache = type(tokens.cache) == "table" and tokens.cache or {}
      table.insert(models, {
        id = model.id,
        variant = type(model.variant) == "string" and model.variant or nil,
        steps = tonumber(item.steps) or 0,
        input = tonumber(tokens.input) or 0,
        output = tonumber(tokens.output) or 0,
        reasoning = tonumber(tokens.reasoning) or 0,
        cache_read = tonumber(cache.read) or 0,
        cost = tonumber(item.cost) or 0,
      })
    end
  end
  table.sort(models, function(first, second)
    if first.cost ~= second.cost then
      return first.cost > second.cost
    end
    return first.steps > second.steps
  end)
  local limited = {}
  for index = 1, math.min(#models, modelStatsLimit) do
    table.insert(limited, models[index])
  end
  return limited, nil
end

refreshModelStats = function(force)
  if not showModelStats or not hasOpenCodeGo() then
    modelStats.models = {}
    modelStats.error = nil
    modelStats.at = os.time()
    return
  end
  if not force and (modelStats.loading or os.time() - modelStats.at < MODEL_STATS_INTERVAL_SECONDS) then
    return
  end
  local binary = opencodeBinary()
  if binary == nil then
    modelStats.models = {}
    modelStats.error = "opencode CLI not installed"
    modelStats.at = os.time()
    publish()
    return
  end
  modelStats.loading = true
  runCommand(binary .. " stats --json --models --limit 10", MODEL_STATS_TIMEOUT_MS, function(result)
    modelStats.loading = false
    modelStats.at = os.time()
    if result.timedOut or result.exitCode ~= 0 then
      modelStats.models = {}
      modelStats.error = "opencode stats failed"
      publish()
      return
    end
    local models, err = parseModelStats(result.stdout)
    modelStats.models = models
    modelStats.error = err
    publish()
  end)
end

function M.start()
  math.randomseed(os.time())
  refreshSeconds = configuredRefreshSeconds()
  showModelStats = configuredShowModelStats()
  modelStatsLimit = configuredModelStatsLimit()
  monitor = monitorModule.create({
    findProvider = registry.find,
    now = nowMs,
    check = function(provider, account, callback)
      check.checkAccount(provider, account, tools, callback)
    end,
    onChange = function()
      if started then
        publish()
      end
    end,
  })
  lastAccountsRev = noctalia.state.get("ai_usage_accounts_rev")
  lastRefreshSeq = noctalia.state.get("ai_usage_refresh_seq")
  monitor.configure(loadAccounts(), refreshSeconds * units.SECOND_MS)
  started = true
  publish()
  noctalia.setUpdateInterval(5000)
  noctalia.state.watch("ai_usage_accounts_rev", function(value)
    if value ~= lastAccountsRev then
      lastAccountsRev = value
      log("account list changed; reloading")
      reloadAccounts()
    end
  end)
  noctalia.state.watch("ai_usage_refresh_seq", function(value)
    if value ~= lastRefreshSeq then
      lastRefreshSeq = value
      monitor.forceNow()
      refreshModelStats(true)
    end
  end)
  monitor.tick()
  refreshModelStats(true)
end

function M.update()
  if not started then
    return
  end
  if refreshSeconds > 0 then
    monitor.tick()
    if showModelStats and os.time() - modelStats.at >= MODEL_STATS_INTERVAL_SECONDS then
      refreshModelStats(false)
    end
  end
  if os.time() - lastPublishedAt >= HEARTBEAT_SECONDS then
    publish()
  end
end

function M.configChanged()
  if not started then
    return
  end
  local nextShowModelStats = configuredShowModelStats()
  if nextShowModelStats ~= showModelStats then
    showModelStats = nextShowModelStats
    modelStats.at = 0
    modelStats.models = {}
    modelStats.error = nil
  end
  refreshSeconds = configuredRefreshSeconds()
  modelStatsLimit = configuredModelStatsLimit()
  monitor.configure(loadAccounts(), refreshSeconds * units.SECOND_MS)
  if refreshSeconds > 0 then
    monitor.refreshNow()
  end
  publish()
  refreshModelStats(true)
end

function M.ipc(event, _payload)
  if event == "refresh" and started then
    monitor.forceNow()
    refreshModelStats(true)
  elseif event == "reload" and started then
    reloadAccounts()
  end
end

function M.stop()
  started = false
end

return M
