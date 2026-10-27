-- Account scheduler. Port of core/monitor.mjs with callback-based checks.

local http = require("./http.luau")
local scheduler = require("./scheduler.luau")
local units = require("./units.luau")
local accounts = require("./accounts.luau")
local state = require("./state.luau")

local M = {}

local MAX_CONCURRENT_CHECKS = 4
local MIN_MANUAL_REFRESH_MS = accounts.MIN_MANUAL_REFRESH_SECONDS * units.SECOND_MS

local function minIntervalMs(provider)
  return (provider and provider.minIntervalSeconds or 0) * units.SECOND_MS
end

local function sameTarget(first, second)
  for key, value in pairs(first) do
    if key ~= "name" and second[key] ~= value then
      return false
    end
  end
  for key, value in pairs(second) do
    if key ~= "name" and first[key] ~= value then
      return false
    end
  end
  return true
end

function M.create(deps)
  local entries = {}
  local order = {}
  local lastAttemptByKey = {}
  local inFlight = 0
  local refreshMs = accounts.DEFAULT_REFRESH_SECONDS * units.SECOND_MS

  local function notify()
    deps.onChange()
  end

  local function remember(entry)
    if entry.lastAttemptAt ~= nil then
      lastAttemptByKey[entry.key] = entry.lastAttemptAt
    end
  end

  local function entryFor(account, intervalMs)
    local existing = entries[account.id]
    if existing and sameTarget(existing.account, account) then
      return state.withAccount(state.withInterval(existing, intervalMs), account)
    end
    local lastAttemptAt = existing == nil and lastAttemptByKey[account.id] or nil
    local provider = deps.findProvider(account.service)
    return state.createEntry({
      account = account,
      title = provider and provider.title or account.service,
      intervalMs = intervalMs,
      lastAttemptAt = lastAttemptAt,
    })
  end

  local function configure(list, nextRefreshMs)
    refreshMs = nextRefreshMs or refreshMs
    local nextEntries = {}
    local nextOrder = {}
    for _, account in ipairs(list or {}) do
      local provider = deps.findProvider(account.service)
      if provider and not nextEntries[account.id] then
        local intervalMs = math.max(refreshMs, minIntervalMs(provider))
        nextEntries[account.id] = entryFor(account, intervalMs)
        remember(nextEntries[account.id])
        table.insert(nextOrder, account.id)
      end
    end
    entries = nextEntries
    order = nextOrder
    notify()
  end

  local pump = nil

  local function run(key)
    local entry = entries[key]
    if not entry then
      return
    end
    local provider = deps.findProvider(entry.providerId)
    if not provider then
      return
    end
    local account = entry.account
    entries[key] = state.markLoading(entry, deps.now())
    remember(entries[key])
    inFlight = inFlight + 1
    notify()
    local function finish(outcome)
      inFlight = math.max(0, inFlight - 1)
      local current = entries[key]
      if current and sameTarget(current.account, account) then
        local now = deps.now()
        if outcome and outcome.ok then
          entries[key] = state.applySuccess(current, outcome.usage, now)
        else
          entries[key] = state.applyFailure(
            current,
            outcome and outcome.error or http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, http.REASON.INTERNAL),
            now
          )
        end
        remember(entries[key])
      end
      notify()
      pump()
    end
    local ok, started = pcall(deps.check, provider, account, finish)
    if not ok or started == false then
      finish({ ok = false, error = http.failure(http.ERROR_KIND.UNEXPECTED_ANSWER, http.REASON.INTERNAL) })
    end
  end

  pump = function()
    local now = deps.now()
    for _, key in ipairs(order) do
      if inFlight >= MAX_CONCURRENT_CHECKS then
        break
      end
      local entry = entries[key]
      if entry and scheduler.isDue(entry, now) then
        run(key)
      end
    end
  end

  local function tick()
    pump()
  end

  local function refreshNow()
    local now = deps.now()
    for _, key in ipairs(order) do
      local entry = entries[key]
      if not entry.isLoading then
        local floorMs = math.max(MIN_MANUAL_REFRESH_MS, minIntervalMs(deps.findProvider(entry.providerId)))
        entries[key] = state.dueNow(entry, scheduler.manualRefreshAt(entry, now, floorMs))
      end
    end
    notify()
    tick()
  end

  -- Explicit user refresh: ignore the 30 s/manual floor and every backoff.
  -- The provider's own rate limits still protect a service that rejects us.
  local function forceNow()
    local now = deps.now()
    for _, key in ipairs(order) do
      local entry = entries[key]
      if entry and not entry.isLoading then
        entries[key] = state.dueNow(entry, now)
      end
    end
    notify()
    tick()
  end

  local function recheck(id)
    if not entries[id] then
      return
    end
    entries[id] = state.dueNow(entries[id], deps.now())
    notify()
    tick()
  end

  local function snapshot()
    local list = {}
    for _, key in ipairs(order) do
      table.insert(list, entries[key])
    end
    return list
  end

  local function setIntervalMs(value)
    refreshMs = value
    for _, key in ipairs(order) do
      entries[key] = state.withInterval(entries[key], math.max(refreshMs, minIntervalMs(deps.findProvider(entries[key].providerId))))
    end
    notify()
  end

  return {
    configure = configure,
    tick = tick,
    refreshNow = refreshNow,
    forceNow = forceNow,
    recheck = recheck,
    snapshot = snapshot,
    setIntervalMs = setIntervalMs,
    isBusy = function()
      return inFlight > 0
    end,
  }
end

return M
