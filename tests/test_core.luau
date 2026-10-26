-- Core rules: scheduler, state, formatter, accounts and HTTP classification.

local mock = dofile("tests/support/mock.luau")
mock.new({})

local scheduler = require("./lib/scheduler.luau")
local state = require("./lib/state.luau")
local formatter = require("./lib/formatter.luau")
local accounts = require("./lib/accounts.luau")
local http = require("./lib/http.luau")
local usage = require("./lib/usage.luau")
local values = require("./lib/values.luau")

local now = 1000000000

assert(scheduler.backoffDelayMs(30000, 1) == 30000, "backoff 1")
assert(scheduler.backoffDelayMs(30000, 2) == 60000, "backoff 2")
assert(scheduler.backoffDelayMs(30000, 3) == 120000, "backoff 3")
assert(scheduler.backoffDelayMs(30000, 40) == 3600000, "backoff cap")

local noConnection = http.failure("cannot_connect", "no_connection")
assert(scheduler.nextAttemptAfterFailure(now, 30000, 8, noConnection) == now + 30000, "no-connection retries without backoff")

local limited = http.failure("rate_limited", "http_status", now + 500000)
assert(scheduler.nextAttemptAfterFailure(now, 30000, 1, limited) == now + 500000, "retry-after wins")

local entry = state.createEntry({
  account = { id = "a123", service = "minimax", name = "work" },
  title = "MiniMax",
  intervalMs = 60000,
})
assert(entry.nextAttemptAt == 0, "new entry is due")
local loading = state.markLoading(entry, now)
assert(loading.isLoading and loading.lastAttemptAt == now, "loading state")
local success = state.applySuccess(loading, { windows = {} }, now + 1000)
assert(not success.isLoading and success.nextAttemptAt == now + 61000, "success schedules next")
local failure = state.applyFailure(success, http.failure("cannot_connect", "timeout"), now + 2000)
assert(failure.consecutiveFailures == 1, "failure count")

-- Formatter -----------------------------------------------------------------
assert(formatter.severityFor(10) == "normal", "normal severity")
assert(formatter.severityFor(75) == "warning", "warning severity")
assert(formatter.severityFor(95) == "critical", "critical severity")
assert(formatter.formatPercent(42.6) == "43%", "percent")
assert(formatter.formatMoney(1234.5, "usd") == "$1,234.50", "money")
assert(formatter.formatMoney(-12, "eur") == "-12.00 EUR", "money currency")
assert(formatter.formatCount(1500) == "1.5k", "count k")
assert(formatter.formatCount(2500000) == "2.5M", "count M")
assert(formatter.formatDuration(30000) == "less than a minute", "duration seconds")
assert(formatter.formatDuration(7200000) == "2h", "duration hours")

local active = usage.usageWindow(usage.PERIOD.FIVE_HOUR, "", 50, now + 1000)
local expired = usage.usageWindow(usage.PERIOD.WEEKLY, "", 90, now - 1000)
local split = formatter.splitWindows({ active, expired }, now)
assert(#split.main == 2, "split main")
assert(split.main[1].period == usage.PERIOD.FIVE_HOUR, "split order")
assert(not formatter.isWindowActive(split.main[2], now), "expired window is inactive")

local model = formatter.buildViewModel({
  {
    key = "a1",
    providerId = "minimax",
    title = "MiniMax",
    account = { id = "a1", name = "work" },
    usage = usage.makeUsage({
      windows = { usage.usageWindow(usage.PERIOD.FIVE_HOUR, "", 92, now + 60000) },
      amounts = { usage.usageAmount(usage.LABEL.BALANCE, "", -1.5, nil, false) },
      counts = { usage.usageCount(usage.LABEL.INPUT_TOKENS_THIS_MONTH, 1500) },
    }),
    error = nil,
    isLoading = false,
  },
  {
    key = "a2",
    providerId = "openai",
    title = "OpenAI API",
    account = { id = "a2", name = "team" },
    usage = nil,
    error = http.failure("key_rejected", "http_status", nil, { status = 401 }),
    isLoading = false,
  },
}, now)
assert(#model.sections == 2, "model sections")
assert(model.sections[1].windows[1].severity == "critical", "critical bar")
assert(model.sections[1].mainRows[1].valueText == "-$1.50", "balance row")
assert(model.sections[1].rows[1].valueText == "1.5k", "token row")
assert(model.sections[2].hasError, "error section")
assert(model.hasErrors, "model has errors")
assert(not model.walletLocked, "not wallet locked")

-- Accounts ------------------------------------------------------------------
assert(accounts.isValidName("work account 1"), "name valid")
assert(not accounts.isValidName("  "), "empty name invalid")
assert(not accounts.isValidName("bad\nname"), "control name invalid")
assert(accounts.isValidField("team-123"), "field valid")
assert(not accounts.isValidField("team 123"), "space field invalid")
assert(accounts.isValidField("") == false, "empty field check")

local id = accounts.newAccountId({ "a000000000000" }, function()
  return 0.5
end)
assert(id:match("^a%x+$"), "account id format")
assert(id ~= "a000000000000", "account id collision")

local provider = { id = "xai", fields = { { id = "teamId" } } }
local account = accounts.makeAccount(provider, "a111", "work", { teamId = "team-1" })
assert(account and account.teamId == "team-1", "make account")
assert(accounts.makeAccount(provider, "a111", "work", { teamId = "bad team" }) == nil, "bad field rejected")

local list = { { id = "a1" }, { id = "a2" }, { id = "a3" } }
local moved = accounts.withAccountMoved(list, "a1", 1)
assert(moved[1].id == "a2" and moved[2].id == "a1", "move account")
assert(accounts.withAccountMoved(list, "a1", -1)[1].id == "a1", "move out of range")

-- Values --------------------------------------------------------------------
assert(values.parseIsoTime("2026-10-26T10:00:00Z") == 1793008800000, "iso Z")
assert(values.parseIsoTime("2026-10-26T12:00:00+02:00") == 1793008800000, "iso offset")
assert(values.toFiniteNumber("12.5") == 12.5, "finite number")
assert(values.toFiniteNumber("nope") == nil, "bad number")
assert(http.parseRetryAfter("120", now) == now + 120000, "retry seconds")
assert(http.parseRetryAfter("Wed, 21 Oct 2026 07:28:00 GMT", 0) ~= nil, "retry date")

print("CORE TEST OK")
