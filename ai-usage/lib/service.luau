-- Headless service: owns the account list, the timer and the curl transport,
-- then publishes a plain snapshot for the card, bar widget and panel.

local accountsModule = require("./accounts.luau")
local check = require("./check.luau")
local curl = require("./curlcommand.luau")
local monitorModule = require("./monitor.luau")
local registry = require("../providers/init.luau")
local store = require("./store.luau")
local units = require("./units.luau")

local M = {}

local HEARTBEAT_SECONDS = 30
local MAX_COMMAND_TIMEOUT_MS = 59000

local refreshSeconds = accountsModule.DEFAULT_REFRESH_SECONDS
local monitor = nil
local started = false
local lastPublishedAt = 0
local lastAccountsRev = nil
local lastRefreshSeq = nil

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

local function snapshotState()
  local entries = monitor and monitor.snapshot() or {}
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
  monitor.tick()
  publish()
end

local function configuredRefreshSeconds()
  return accountsModule.refreshSeconds(noctalia.getConfig("refresh_seconds"))
end

function M.start()
  math.randomseed(os.time())
  refreshSeconds = configuredRefreshSeconds()
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
      monitor.refreshNow()
    end
  end)
  monitor.tick()
end

function M.update()
  if not started then
    return
  end
  monitor.tick()
  if os.time() - lastPublishedAt >= HEARTBEAT_SECONDS then
    publish()
  end
end

function M.configChanged()
  if not started then
    return
  end
  refreshSeconds = configuredRefreshSeconds()
  monitor.configure(loadAccounts(), refreshSeconds * units.SECOND_MS)
  monitor.refreshNow()
  publish()
end

function M.ipc(event, _payload)
  if event == "refresh" and started then
    monitor.refreshNow()
  elseif event == "reload" and started then
    reloadAccounts()
  end
end

function M.stop()
  started = false
end

return M
