-- Curl command and output parser tests.

local mock = dofile("tests/support/mock.luau")
mock.new({})

local curl = require("./lib/curlcommand.luau")

local spec = {
  providerId = "minimax",
  account = "a3f09c1d2b4e",
  boundary = "aiu0123456789abcdef01234567",
  auth = { header = "Authorization", prefix = "Bearer " },
  requests = {
    { id = "usage", url = "https://api.minimax.io/v1/token_plan/remains", headers = { "Accept: application/json" } },
  },
}

local command = curl.buildCheckCommand(spec)
assert(command:find("secret-tool lookup", 1, true), "lookup missing")
assert(command:find("gdbus call", 1, true), "locked guard missing")
assert(command:find("--max-filesize 1048576", 1, true), "size cap missing")
assert(command:find("--max-redirs 0", 1, true), "redirect cap missing")
assert(command:find("--proto '=https'", 1, true), "https-only missing")
assert(command:find("-H @-", 1, true), "curl stdin header missing")
assert(not command:find("sk-", 1, true), "command must not contain a key")

local function block(id, body, status, retry, curlCode)
  return spec.boundary .. " begin " .. id .. "\n" .. body .. "\n" .. spec.boundary
    .. " end " .. status .. " " .. (retry or "") .. "\n\n" .. spec.boundary .. " curl " .. (curlCode or 0) .. "\n"
end

local result = curl.parseCheckOutput({
  exitCode = 0,
  stdout = block("usage", '{"ok":true}', 200),
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)

assert(result.ok, "parse failed")
assert(result.replies[1].kind == "response", "reply kind")
assert(result.replies[1].status == 200, "status")
assert(result.replies[1].body == '{"ok":true}', "body")
assert(result.replies[1].header("Retry-After") == nil, "no retry-after")

local limited = curl.parseCheckOutput({
  exitCode = 0,
  stdout = block("usage", "{}", 429, "120"),
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(limited.ok and limited.replies[1].header("Retry-After") == "120", "retry-after not parsed")

local locked = curl.parseCheckOutput({
  exitCode = 0,
  stdout = spec.boundary .. " lookup locked\n",
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(not locked.ok and locked.error.reason == "wallet_locked", "locked wallet not detected")

local missingTool = curl.parseCheckOutput({
  exitCode = 0,
  stdout = spec.boundary .. " lookup 127\n",
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(not missingTool.ok and missingTool.error.reason == "tool_missing", "missing tool not detected")

local timedOut = curl.parseCheckOutput({ timedOut = true, stdout = "" }, spec.requests, spec.boundary)
assert(not timedOut.ok and timedOut.error.reason == "request_timeout", "timeout not detected")

local curlTimeout = curl.parseCheckOutput({
  exitCode = 0,
  stdout = block("usage", "", 0, "", 28),
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(curlTimeout.ok and curlTimeout.replies[1].kind == "timeout", "curl timeout not parsed")

local tooLarge = curl.parseCheckOutput({
  exitCode = 0,
  stdout = block("usage", "", 0, "", 63),
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(tooLarge.ok and tooLarge.replies[1].kind == "too_large", "too-large not parsed")

local incomplete = curl.parseCheckOutput({
  exitCode = 0,
  stdout = spec.boundary .. " begin usage\npartial",
  stderr = "",
  timedOut = false,
}, spec.requests, spec.boundary)
assert(incomplete.ok and incomplete.replies[1].kind == "incomplete", "incomplete not parsed")

print("CURL TEST OK")
