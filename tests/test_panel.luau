-- Panel: cards, account discovery, add/edit/reorder/delete.

local mock = dofile("tests/support/mock.luau")

local DATA_DIR = "/tmp/opencode/ai-usage-data"
local ACCOUNTS_PATH = DATA_DIR .. "/accounts.json"

local history = {
  version = 2,
  samples = {
    { org = "org-a", t = 1760000000000, u = { fh = 40, sd = 10 } },
  },
}

local storedKeys = {}
local clearedKeys = {}

local function runAsync(command, callback)
  if type(command) == "table" then
    if command[1] == "secret-tool" and command[2] == "clear" then
      table.insert(clearedKeys, command[6])
      callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
      return true
    end
    if command[1] == "secret-tool" and command[2] == "lookup" then
      callback({ exitCode = 1, stdout = "", stderr = "", timedOut = false })
      return true
    end
    callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
    return true
  end
  if command:find("plan-usage-history.json", 1, true) then
    local text = mock.jsonEncode(history)
    callback({ exitCode = 0, stdout = "found " .. #text .. "\n" .. text, stderr = "", timedOut = false })
    return true
  end
  if command:find("secret-tool store", 1, true) then
    table.insert(storedKeys, command)
    callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
    return true
  end
  callback({ exitCode = 0, stdout = "", stderr = "", timedOut = false })
  return true
end

local context = mock.new({
  config = { refresh_seconds = "30" },
  files = {},
  runAsync = runAsync,
})

context.state.ai_usage = {
  ts = os.time(),
  refresh_seconds = 30,
  accounts = {},
  has_accounts = false,
}

mock.loadEntry("panel.luau")
onOpen()

local tree = context.panelTree
assert(tree ~= nil, "panel did not render")
assert(mock.find(tree, "empty-card") ~= nil, "empty card missing")
assert(mock.find(tree, "cards-add") ~= nil, "add button missing")

-- Add a Claude account through discovery -------------------------------------
mock.click(mock.find(tree, "cards-add"))
tree = context.panelTree
assert(mock.find(tree, "discovery-org-org-a") ~= nil, "Claude org not discovered")
local nameInput = mock.find(tree, "discovery-name-org-a")
assert(nameInput ~= nil, "discovery name input missing")
mock.change(nameInput, "personal")
mock.click(mock.find(tree, "discovery-add"))

local saved = context.readAccountsFile()
assert(#saved == 1, "Claude account was not saved")
assert(saved[1].service == "claude" and saved[1].org == "org-a", "Claude account fields")
assert(saved[1].name == "personal", "Claude account name")
assert(context.state.ai_usage_accounts_rev == 1, "account revision not bumped")
assert(context.state.ai_usage_refresh_seq == 1, "refresh not requested")

tree = context.panelTree
assert(mock.find(tree, "account-" .. saved[1].id) ~= nil, "settings account row missing")

-- Add a MiniMax account with a key -------------------------------------------
mock.click(mock.find(tree, "settings-add"))
tree = context.panelTree
mock.change(mock.find(tree, "form-service"), 7) -- registry order: minimax
tree = context.panelTree
mock.change(mock.find(tree, "form-name-minimax-nil"), "work")
mock.change(mock.find(tree, "form-key-minimax-nil"), "sk-test-key")
mock.click(mock.find(tree, "form-save"))

saved = context.readAccountsFile()
assert(#saved == 2, "MiniMax account was not saved")
assert(#storedKeys == 1, "key was not stored in the Secret Service")
local minimax = nil
for _, account in ipairs(saved) do
  if account.service == "minimax" then
    minimax = account
  end
end
assert(minimax ~= nil and minimax.name == "work", "MiniMax account missing")
assert(context.files[ACCOUNTS_PATH]:find("sk-test-key", 1, true) == nil, "key must not be written to accounts.json")

-- Edit the MiniMax name, leaving the key empty --------------------------------
tree = context.panelTree
mock.click(mock.find(tree, "account-edit-" .. minimax.id))
tree = context.panelTree
mock.change(mock.find(tree, "form-name-minimax-" .. minimax.id), "work renamed")
mock.click(mock.find(tree, "form-save"))
saved = context.readAccountsFile()
local edited = nil
for _, account in ipairs(saved) do
  if account.id == minimax.id then
    edited = account
  end
end
assert(edited and edited.name == "work renamed", "edit did not save")
assert(#storedKeys == 1, "empty key field should keep the saved key")

-- Reorder: move MiniMax up ---------------------------------------------------
tree = context.panelTree
mock.click(mock.find(tree, "account-up-" .. minimax.id))
saved = context.readAccountsFile()
assert(saved[1].service == "minimax", "reorder did not move the account")

-- Delete the MiniMax account -------------------------------------------------
tree = context.panelTree
mock.click(mock.find(tree, "account-delete-" .. minimax.id))
tree = context.panelTree
mock.click(mock.find(tree, "account-confirm-yes-" .. minimax.id))
saved = context.readAccountsFile()
assert(#saved == 1, "delete did not remove the account")
assert(saved[1].service == "claude", "delete removed the wrong account")
assert(#clearedKeys == 1, "key was not removed from the Secret Service")

-- The plugin-settings button opens the host settings window ------------------
tree = context.panelTree
if mock.find(tree, "settings-open") == nil then
  -- Deleting the last remote account returns to cards; go back to settings.
  mock.click(mock.find(tree, "cards-manage"))
  tree = context.panelTree
end
mock.click(mock.find(tree, "settings-open"))
assert(context.openedSettings == 1, "plugin settings not opened")

print("PANEL TEST OK")
