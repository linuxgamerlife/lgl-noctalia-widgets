-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Account validation, ids and ordering. Port of core/accounts.mjs.

local values = require("./values.luau")
local validation = require("./validation.luau")

local M = {}

-- 0 means manual only: the initial start check still runs, but no timer checks.
M.REFRESH_CHOICES_SECONDS = { 0, 30, 60, 300, 900, 1800, 3600 }
M.DEFAULT_REFRESH_SECONDS = 30
M.MIN_MANUAL_REFRESH_SECONDS = 30
M.MAX_ACCOUNT_NAME_LENGTH = 100
M.FIELD_PATTERN = "^[A-Za-z0-9][A-Za-z0-9%-]*$"

local ID_PREFIX = "a"
local ID_DIGITS = 12

function M.refreshSeconds(value)
  local seconds = tonumber(value)
  for _, allowed in ipairs(M.REFRESH_CHOICES_SECONDS) do
    if seconds == allowed then
      return seconds
    end
  end
  return M.DEFAULT_REFRESH_SECONDS
end

function M.cleanKey(value)
  return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function M.cleanName(value)
  return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function hasControlCharacter(text)
  -- Reject C0 controls, DEL and the two Unicode line separators. Bytes in the
  -- 0x80-0x9f range are valid UTF-8 continuation bytes and must stay allowed
  -- for names such as "Łukasz".
  for index = 1, #text do
    local code = text:byte(index)
    if code == nil or code <= 0x1f or code == 0x7f then
      return true
    end
  end
  if text:find("\226\128\168", 1, true) or text:find("\226\128\169", 1, true) then
    return true
  end
  return false
end

function M.isValidName(value)
  local name = M.cleanName(value)
  return #name > 0 and #name <= M.MAX_ACCOUNT_NAME_LENGTH and not hasControlCharacter(name)
end

function M.isValidField(value)
  return type(value) == "string" and #value <= 64 and value:match(M.FIELD_PATTERN) ~= nil
end

function M.newAccountId(existingIds, random)
  local taken = {}
  for _, id in ipairs(existingIds or {}) do
    taken[id] = true
  end
  local generator = random or math.random
  for _ = 1, 10000 do
    local id = ID_PREFIX
    for _ = 1, ID_DIGITS do
      id = id .. string.format("%x", math.floor(generator() * 16))
    end
    if not taken[id] then
      return id
    end
  end
  error("could not generate an account id")
end

function M.makeAccount(provider, id, name, fields)
  local supplied = fields or {}
  if not provider or not validation.isValidLabel(id) or not M.isValidName(name) then
    return nil
  end
  local account = { id = id, service = provider.id, name = M.cleanName(name) }
  for _, field in ipairs(provider.fields) do
    if not M.isValidField(supplied[field.id]) then
      return nil
    end
    account[field.id] = supplied[field.id]
  end
  return account
end

function M.parseAccounts(decoded, findProvider)
  if type(decoded) ~= "table" then
    return {}
  end
  local accounts = {}
  for _, item in ipairs(decoded) do
    local account = nil
    if type(item) == "table" then
      local provider = findProvider(item.service)
      if provider then
        account = M.makeAccount(provider, item.id, item.name, item)
      end
    end
    if account then
      local duplicate = false
      for _, existing in ipairs(accounts) do
        if existing.id == account.id then
          duplicate = true
          break
        end
      end
      if not duplicate then
        table.insert(accounts, account)
      end
    end
  end
  return accounts
end

function M.serializeAccounts(accounts)
  return noctalia.json.encode(accounts or {}) or "[]"
end

function M.withAccount(accounts, account)
  local list = {}
  local replaced = false
  for _, item in ipairs(accounts or {}) do
    if item.id == account.id then
      table.insert(list, account)
      replaced = true
    else
      table.insert(list, item)
    end
  end
  if not replaced then
    table.insert(list, account)
  end
  return list
end

function M.withoutAccount(accounts, id)
  local list = {}
  for _, item in ipairs(accounts or {}) do
    if item.id ~= id then
      table.insert(list, item)
    end
  end
  return list
end

function M.withAccountMoved(accounts, id, step)
  local list = {}
  for _, item in ipairs(accounts or {}) do
    table.insert(list, item)
  end
  local from = nil
  for index, item in ipairs(list) do
    if item.id == id then
      from = index
      break
    end
  end
  if from == nil then
    return list
  end
  local to = from + step
  if to < 1 or to > #list then
    return list
  end
  local moved = table.remove(list, from)
  table.insert(list, to, moved)
  return list
end

function M.findAccount(accounts, id)
  for _, item in ipairs(accounts or {}) do
    if item.id == id then
      return item
    end
  end
  return nil
end

return M
