-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- HTTP reply classification, shared by the curl transport and the providers.

local units = require("./units.luau")
local values = require("./values.luau")

local M = {}

M.ERROR_KIND = {
  CANNOT_CONNECT = "cannot_connect",
  KEY_REJECTED = "key_rejected",
  RATE_LIMITED = "rate_limited",
  UNEXPECTED_ANSWER = "unexpected_answer",
  NOT_AVAILABLE = "not_available",
  NO_KEY = "no_key",
}

M.REASON = {
  TIMEOUT = "timeout",
  NO_CONNECTION = "no_connection",
  CURL_ERROR = "curl_error",
  REQUEST_TIMEOUT = "request_timeout",
  COMMAND_FAILED = "command_failed",
  INCOMPLETE = "incomplete",
  TOOL_MISSING = "tool_missing",
  ANSWER_TOO_LARGE = "answer_too_large",
  HTTP_STATUS = "http_status",
  SERVICE_ERROR = "service_error",
  PAYMENT_REQUIRED = "payment_required",
  REDIRECT = "redirect",
  SHAPE_CHANGED = "shape_changed",
  SERVICE_CODE = "service_code",
  INTERNAL = "internal",
  NO_KEY = "no_key",
  KEY_FORMAT = "key_format",
  SECRET_SERVICE_TIMEOUT = "secret_service_timeout",
  SECRET_SERVICE_UNAVAILABLE = "secret_service_unavailable",
  WALLET_LOCKED = "wallet_locked",
  TEAM_ORGANIZATION_REQUIRED = "team_organization_required",
  ADMIN_KEY_REQUIRED = "admin_key_required",
  OPENAI_ADMIN_KEY_REQUIRED = "openai_admin_key_required",
  GO_SUBSCRIPTION_REQUIRED = "go_subscription_required",
  ZEN_ALL_PERMISSIONS = "zen_all_permissions",
  BALANCE_EXHAUSTED = "balance_exhausted",
  BALANCE_NEEDS_MANAGE = "balance_needs_manage",
  INSUFFICIENT_BALANCE = "insufficient_balance",
  FILE_READ_FAILED = "file_read_failed",
  FILE_TOO_LARGE = "file_too_large",
  FILE_FORMAT_CHANGED = "file_format_changed",
  CLAUDE_FILE_MISSING = "claude_file_missing",
  CLAUDE_ORG_MISSING = "claude_org_missing",
  CODEX_MISSING = "codex_missing",
  CODEX_NO_LIMITS = "codex_no_limits",
  FIELD_MISSING = "field_missing",
  HF_BILLING_PERMISSION = "hf_billing_permission",
  JETBRAINS_LOG_MISSING = "jetbrains_log_missing",
  JETBRAINS_NO_QUOTA = "jetbrains_no_quota",
}

local MAX_RETRY_AFTER_MS = units.DAY_MS
local DELAY_SECONDS_PATTERN = "^%d+$"
local HTTP_DATE_PATTERN = "^[A-Za-z][A-Za-z][A-Za-z],? "

function M.failure(kind, reason, retryAt, params)
  return {
    kind = kind,
    reason = reason,
    retryAt = retryAt,
    params = params or {},
  }
end

local function parseHttpDate(text)
  -- "Wed, 21 Oct 2026 07:28:00 GMT". os.time() has no UTC parser, so parse the
  -- fields and use the same civil-date conversion the ISO parser uses.
  local day, monthName, year, hour, minute, second =
    text:match("^[A-Za-z]+,? (%d%d?) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d)")
  if day == nil then
    return nil
  end
  local months = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
                   Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
  local month = months[monthName]
  if month == nil then
    return nil
  end
  local parsed = values.parseIsoTime(string.format(
    "%04d-%02d-%02dT%02d:%02d:%02dZ", tonumber(year), month, tonumber(day),
    tonumber(hour), tonumber(minute), tonumber(second)
  ))
  return parsed
end

function M.parseRetryAfter(value, now)
  if type(value) ~= "string" or value:match("^%s*$") then
    return nil
  end
  local text = value:match("^%s*(.-)%s*$")
  if text:match(DELAY_SECONDS_PATTERN) then
    return now + math.min(tonumber(text) * units.SECOND_MS, MAX_RETRY_AFTER_MS)
  end
  local date = nil
  if text:match(HTTP_DATE_PATTERN) then
    date = parseHttpDate(text)
  end
  if date == nil then
    return nil
  end
  return math.min(math.max(date, now), now + MAX_RETRY_AFTER_MS)
end

local function isResponse(reply)
  return type(reply) == "table" and reply.kind == "response" and type(reply.status) == "number"
end

local function classifyStatus(reply, now)
  local status = reply.status
  if status >= 200 and status < 300 then
    return nil
  end
  if status >= 300 and status < 400 then
    return M.failure(M.ERROR_KIND.UNEXPECTED_ANSWER, M.REASON.REDIRECT, nil, { status = status })
  end
  if status == 401 or status == 403 then
    return M.failure(M.ERROR_KIND.KEY_REJECTED, M.REASON.HTTP_STATUS, nil, { status = status })
  end
  if status == 402 then
    return M.failure(M.ERROR_KIND.NOT_AVAILABLE, M.REASON.PAYMENT_REQUIRED)
  end
  if status == 429 then
    return M.failure(
      M.ERROR_KIND.RATE_LIMITED,
      M.REASON.HTTP_STATUS,
      M.parseRetryAfter(reply.header and reply.header("Retry-After") or nil, now),
      { status = status }
    )
  end
  if status >= 500 then
    return M.failure(
      M.ERROR_KIND.CANNOT_CONNECT,
      M.REASON.SERVICE_ERROR,
      M.parseRetryAfter(reply.header and reply.header("Retry-After") or nil, now),
      { status = status }
    )
  end
  return M.failure(M.ERROR_KIND.UNEXPECTED_ANSWER, M.REASON.HTTP_STATUS, nil, { status = status })
end

local function classifyTransportFailure(reply)
  local kind = reply.kind
  if kind == "timeout" then
    return M.failure(M.ERROR_KIND.CANNOT_CONNECT, M.REASON.TIMEOUT)
  elseif kind == "network" then
    return M.failure(M.ERROR_KIND.CANNOT_CONNECT, M.REASON.NO_CONNECTION)
  elseif kind == "too_large" then
    return M.failure(M.ERROR_KIND.UNEXPECTED_ANSWER, M.REASON.ANSWER_TOO_LARGE)
  elseif kind == "incomplete" then
    return M.failure(M.ERROR_KIND.CANNOT_CONNECT, M.REASON.INCOMPLETE)
  elseif kind == "tool_missing" then
    return M.failure(M.ERROR_KIND.CANNOT_CONNECT, M.REASON.TOOL_MISSING)
  elseif kind == "curl_error" then
    return M.failure(M.ERROR_KIND.CANNOT_CONNECT, M.REASON.CURL_ERROR, nil, { code = reply.code })
  end
  return M.failure(M.ERROR_KIND.UNEXPECTED_ANSWER, M.REASON.INTERNAL)
end

function M.classifyReply(reply, now, override)
  if not reply then
    return M.failure(M.ERROR_KIND.UNEXPECTED_ANSWER, M.REASON.INTERNAL)
  end
  if not isResponse(reply) then
    return classifyTransportFailure(reply)
  end
  local overridden = override and override(reply) or nil
  return overridden or classifyStatus(reply, now)
end

function M.parseJsonBody(reply)
  if not isResponse(reply) or type(reply.body) ~= "string" then
    return { ok = false }
  end
  local decoded, err = noctalia.json.decode(reply.body)
  if decoded == nil then
    return { ok = false, error = err }
  end
  return { ok = true, value = decoded }
end

return M
