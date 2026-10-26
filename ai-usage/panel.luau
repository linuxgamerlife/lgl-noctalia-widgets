--!nonstrict
-- Panel: cards, account management and the add/edit forms. Accounts are kept
-- in pluginDataDir/accounts.json; keys are stored only in the Secret Service.

local accountsModule = require("./lib/accounts.luau")
local check = require("./lib/check.luau")
local curl = require("./lib/curlcommand.luau")
local formatter = require("./lib/formatter.luau")
local privacy = require("./lib/privacy.luau")
local registry = require("./providers/init.luau")
local secrets = require("./lib/secrets.luau")
local store = require("./lib/store.luau")
local view = require("./lib/view.luau")

local modal = "cards" -- cards | settings | add | edit
local editingId = nil
local accounts = store.load(registry.find)
local current = noctalia.state.get("ai_usage")
local message = nil
local busy = false
local pendingDelete = nil
local discovering = false
local discoveries = nil
local form = {
  service = "claude",
  name = "",
  originalName = "",
  key = "",
  fields = {},
  orgNames = {},
}

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function providerTitle(provider)
  return tr("provider." .. provider.id .. ".title", provider.title)
end

local function showMessage(text, tone)
  message = { text = text, tone = tone or "normal" }
end

local function messageColor()
  if message and message.tone == "error" then
    return "error"
  end
  if message and message.tone == "ok" then
    return "primary"
  end
  return "on_surface_variant"
end

local function bumpAccounts()
  local value = tonumber(noctalia.state.get("ai_usage_accounts_rev")) or 0
  noctalia.state.set("ai_usage_accounts_rev", value + 1)
end

local function triggerRefresh()
  local value = tonumber(noctalia.state.get("ai_usage_refresh_seq")) or 0
  noctalia.state.set("ai_usage_refresh_seq", value + 1)
end

local function nowMs()
  return os.time() * 1000
end

local function runCommand(command, timeoutMs, callback)
  local accepted = noctalia.runAsync(command, function(result)
    callback({
      exitCode = result and result.exitCode or 1,
      stdout = result and result.stdout or "",
      stderr = result and result.stderr or "",
      timedOut = result and result.timedOut == true or false,
    })
  end, math.min(math.max(tonumber(timeoutMs) or 5000, 50), 59000))
  if not accepted then
    callback({ exitCode = 1, stdout = "", stderr = "", timedOut = false })
  end
end

local tools = {
  now = nowMs,
  newBoundary = curl.newBoundary,
  runCommand = runCommand,
}

local panelStyle = view.defaultStyle()
panelStyle.card_fill = "surface_variant/0.35"
panelStyle.card_border = "outline/0.2"
panelStyle.card_radius = 12
panelStyle.card_border_width = 1

-- Forward declarations: these are referenced by functions defined earlier in
-- the file, and Lua resolves locals lexically.
local render
local loadDiscovery
local startEdit
local moveAccount
local deleteAccount
local addDiscovered
local discoveryRows

local function walletErrorText(code)
  local keys = {
    not_running = "wallet.not_running",
    no_answer = "wallet.no_answer",
    locked = "wallet.locked",
    write_failed = "wallet.write_failed",
    remove_failed = "wallet.remove_failed",
    failed = "wallet.failed",
    invalid_key = "wallet.invalid_key",
  }
  local key = keys[code] or "wallet.failed"
  return tr(key, "The Secret Service could not save or read the key")
end

local function isStale()
  if type(current) ~= "table" or type(current.ts) ~= "number" then
    return true
  end
  local refresh = tonumber(noctalia.getConfig("refresh_seconds")) or 30
  return os.time() - current.ts > math.max(180, refresh * 3)
end

local function resetForm(serviceId)
  form = {
    service = serviceId or "claude",
    name = "",
    originalName = "",
    key = "",
    fields = {},
    orgNames = {},
  }
end

local function newDiscoveries(items)
  local taken = {}
  for _, account in ipairs(accounts) do
    if account.service == form.service then
      table.insert(taken, account)
    end
  end
  local result = {}
  for _, item in ipairs(items or {}) do
    local exists = false
    for _, account in ipairs(taken) do
      local same = true
      for field, value in pairs(item.fields) do
        if account[field] ~= value then
          same = false
          break
        end
      end
      if same then
        exists = true
        break
      end
    end
    if not exists then
      table.insert(result, item)
      if form.orgNames[item.fields.org] == nil then
        form.orgNames[item.fields.org] = ""
      end
    end
  end
  return result
end

function onServiceChange(value)
  local index = tonumber(value)
  if index == nil then
    return
  end
  local provider = registry.ALL[index + 1]
  if provider == nil then
    return
  end
  resetForm(provider.id)
  modal = "add"
  message = nil
  discoveries = nil
  discovering = false
  if provider.discover then
    loadDiscovery(provider)
  else
    render()
  end
end

function onNameChange(value)
  form.name = value or ""
end

function onKeyChange(value)
  form.key = value or ""
end

function onBack()
  if modal == "add" or modal == "edit" then
    modal = #accounts > 0 and "settings" or "cards"
    message = nil
    render()
    return
  end
  if modal == "settings" then
    modal = "cards"
    message = nil
    render()
    return
  end
  panel.close()
end

function onClose()
  panel.close()
end

function onRefresh()
  triggerRefresh()
  showMessage(tr("message.refresh_requested", "Asked the service to check every account now"), "ok")
  render()
end

function onSettings()
  modal = "settings"
  message = nil
  pendingDelete = nil
  render()
end

function onAdd()
  resetForm("claude")
  modal = "add"
  message = nil
  pendingDelete = nil
  discoveries = nil
  local provider = registry.find(form.service)
  if provider and provider.discover then
    loadDiscovery(provider)
  else
    render()
  end
end

function onOpenPluginSettings()
  noctalia.openSettings()
end

function onSave()
  if busy then
    return
  end
  local provider = registry.find(form.service)
  if provider == nil then
    showMessage(tr("form.error.service", "Pick a service"), "error")
    render()
    return
  end
  local typedName = accountsModule.cleanName(form.name)
  local name = typedName
  if name == "" and editingId ~= nil then
    -- The edit form never pre-fills the raw label; an empty field keeps it.
    name = form.originalName
  end
  if not accountsModule.isValidName(name) then
    showMessage(tr("form.error.name", "Type a name of 1 to 100 characters"), "error")
    render()
    return
  end
  local fields = {}
  for _, field in ipairs(provider.fields) do
    local value = form.fields[field.id] or ""
    if not accountsModule.isValidField(value) then
      showMessage(tr("form.error.field", "{label}: use letters, digits and - only, at most 64", { label = field.label }), "error")
      render()
      return
    end
    fields[field.id] = value
  end

  local id = editingId
  if id == nil then
    local ids = {}
    for _, account in ipairs(accounts) do
      table.insert(ids, account.id)
    end
    id = accountsModule.newAccountId(ids)
  end
  local account = accountsModule.makeAccount(provider, id, name, fields)
  if account == nil then
    showMessage(tr("form.error.account", "This account is not valid"), "error")
    render()
    return
  end

  local function persist()
    local list = accountsModule.withAccount(accounts, account)
    local ok, err = store.save(list)
    if not ok then
      busy = false
      showMessage(tr("message.failed", "The accounts file could not be saved: {error}", { error = err }), "error")
      render()
      return
    end
    accounts = list
    bumpAccounts()
    triggerRefresh()
    busy = false
    local action = editingId == nil and "message.added" or "message.saved"
    local fallback = editingId == nil and "Added {name}" or "Saved {name}"
    showMessage(tr(action, fallback, { name = privacy.displayName(account.name) }), "ok")
    modal = #accounts > 0 and "settings" or "cards"
    editingId = nil
    render()
  end

  local key = accountsModule.cleanKey(form.key)
  if provider.needsKey and editingId == nil and key == "" then
    showMessage(tr("form.error.key", "Paste the key"), "error")
    render()
    return
  end
  if provider.needsKey and key ~= "" then
    busy = true
    render()
    secrets.store(provider.id, id, key, function(result)
      if not result.ok then
        busy = false
        showMessage(walletErrorText(result.code), "error")
        render()
        return
      end
      persist()
    end)
    return
  end
  persist()
end

function deleteAccount(id)
  for _, account in ipairs(accounts) do
    if account.id == id then
      local provider = registry.find(account.service)
      local function forget()
        local list = accountsModule.withoutAccount(accounts, id)
        local ok = store.save(list)
        if not ok then
          showMessage(tr("message.failed", "The accounts file could not be saved"), "error")
          render()
          return
        end
        accounts = list
        bumpAccounts()
        busy = false
        pendingDelete = nil
        showMessage(tr("message.deleted", "Deleted {name}", { name = privacy.displayName(account.name) }), "ok")
        modal = #accounts > 0 and "settings" or "cards"
        render()
      end
      if provider and provider.needsKey then
        busy = true
        render()
        secrets.clear(provider.id, id, function(result)
          if not result.ok then
            busy = false
            showMessage(walletErrorText(result.code), "error")
            render()
            return
          end
          forget()
        end)
      else
        forget()
      end
      return
    end
  end
end

function onConfirmDelete(id)
  deleteAccount(id)
end

function onCancelDelete()
  pendingDelete = nil
  render()
end

function startEdit(id)
  local account = nil
  for _, item in ipairs(accounts) do
    if item.id == id then
      account = item
      break
    end
  end
  if account == nil then
    return
  end
  local provider = registry.find(account.service)
  if provider == nil then
    return
  end
  resetForm(provider.id)
  form.name = ""
  form.originalName = account.name
  for _, field in ipairs(provider.fields) do
    form.fields[field.id] = account[field.id]
  end
  editingId = id
  modal = "edit"
  message = nil
  discoveries = nil
  render()
end

function moveAccount(id, step)
  local list = accountsModule.withAccountMoved(accounts, id, step)
  local ok = store.save(list)
  if not ok then
    showMessage(tr("message.failed", "The accounts file could not be saved"), "error")
    render()
    return
  end
  accounts = list
  bumpAccounts()
  showMessage(tr("message.reordered", "Account order saved"), "ok")
  render()
end

function addDiscovered()
  if busy then
    return
  end
  local provider = registry.find(form.service)
  if provider == nil or not provider.discover then
    return
  end
  local chosen = {}
  for _, item in ipairs(discoveries or {}) do
    local name = form.orgNames[item.fields.org] or ""
    if accountsModule.cleanName(name) ~= "" then
      if not accountsModule.isValidName(name) then
        showMessage(tr("form.error.name", "Type a name or email of 1 to 100 characters"), "error")
        render()
        return
      end
      table.insert(chosen, { item = item, name = name })
    end
  end
  if #chosen == 0 then
    showMessage(tr("form.discovery_names", "Type a name or email for at least one organization"), "error")
    render()
    return
  end
  local list = accounts
  local ids = {}
  for _, account in ipairs(list) do
    table.insert(ids, account.id)
  end
  for _, entry in ipairs(chosen) do
    local id = accountsModule.newAccountId(ids)
    table.insert(ids, id)
    local account = accountsModule.makeAccount(provider, id, entry.name, entry.item.fields)
    if account ~= nil then
      list = accountsModule.withAccount(list, account)
    end
  end
  local ok = store.save(list)
  if not ok then
    showMessage(tr("message.failed", "The accounts file could not be saved"), "error")
    render()
    return
  end
  accounts = list
  bumpAccounts()
  triggerRefresh()
  showMessage(tr("message.added_many", "Added {n} accounts", { n = #chosen }), "ok")
  modal = "settings"
  render()
end

local function panelHeader(title, opts)
  local options = opts or {}
  local left = {}
  if options.back then
    table.insert(left, ui.button({ key = "header-back", glyph = "arrow-left", glyphSize = 16, variant = "ghost", controlSize = "sm", onClick = "onBack" }))
  end
  table.insert(left, ui.glyph({ key = "header-glyph", name = "chart-bar", size = 20, color = "primary" }))
  table.insert(left, ui.label({
    key = "header-title",
    text = title,
    fontSize = 18,
    fontWeight = "semibold",
    color = "on_surface",
    flexGrow = 1,
    maxLines = 1,
  }))
  local right = {}
  if options.refresh then
    table.insert(right, ui.button({
      key = "header-refresh",
      text = tr("ui.refresh", "Refresh"),
      glyph = "refresh",
      glyphSize = 16,
      variant = "ghost",
      controlSize = "sm",
      onClick = "onRefresh",
    }))
  end
  if options.settings then
    table.insert(right, ui.button({ key = "header-settings", glyph = "settings", glyphSize = 16, variant = "ghost", controlSize = "sm", onClick = "onSettings" }))
  end
  table.insert(right, ui.button({ key = "header-close", glyph = "x", glyphSize = 16, variant = "ghost", controlSize = "sm", onClick = "onClose" }))
  return ui.row({
    key = "panel-header",
    gap = 6,
    align = "center",
    justify = "space_between",
  }, {
    ui.row({ key = "panel-header-left", gap = 4, align = "center", flexGrow = 1 }, left),
    ui.row({ key = "panel-header-right", gap = 2, align = "center" }, right),
  })
end

local function messageNode(key)
  if message == nil then
    return nil
  end
  return ui.label({
    key = key or "message",
    text = message.text,
    fontSize = 11,
    color = messageColor(),
    maxLines = 4,
  })
end

local function renderCards()
  local children = {
    panelHeader(tr("app.title", "AI Usage"), { refresh = true, settings = true }),
  }
  if isStale() then
    table.insert(children, view.waitingCard("onRefresh", { style = panelStyle }))
  else
    local model = formatter.buildViewModel(current.accounts or {}, nowMs())
    local cards = {}
    if not model.hasAccounts then
      table.insert(cards, view.emptyCard("onAdd", { style = panelStyle }))
    else
      for _, section in ipairs(model.sections) do
        table.insert(cards, view.card(section, { show_details = true, style = panelStyle }))
      end
    end
    if model.walletLocked then
      table.insert(cards, ui.label({
        key = "wallet-hint",
        text = tr("wallet.hint", "The keyring is locked or unavailable. Unlock it with your keyring app, then refresh."),
        fontSize = 11,
        color = "tertiary",
        maxLines = 3,
      }))
    end
    if current.tools_missing then
      table.insert(cards, ui.label({
        key = "tools-hint",
        text = tr("tools.hint", "curl, secret-tool or timeout is missing. Install curl, libsecret and coreutils."),
        fontSize = 11,
        color = "tertiary",
        maxLines = 3,
      }))
    end
    table.insert(cards, ui.row({ key = "cards-actions", gap = 8, align = "center" }, {
      ui.button({ key = "cards-add", text = tr("ui.add_account", "Add account"), glyph = "plus", variant = "primary", onClick = "onAdd" }),
      ui.button({ key = "cards-refresh", text = tr("ui.refresh_now", "Refresh now"), glyph = "refresh", variant = "outline", onClick = "onRefresh" }),
      ui.button({ key = "cards-manage", text = tr("ui.manage_accounts", "Manage accounts"), glyph = "settings", variant = "outline", onClick = "onSettings" }),
    }))
    table.insert(children, ui.scroll({ key = "cards-scroll", flexGrow = 1, gap = 8 }, cards))
  end
  local node = messageNode("cards-message")
  if node then
    table.insert(children, node)
  end
  panel.render(ui.column({ key = "panel-cards", padding = 14, gap = 10 }, children))
end

local function renderSettings()
  local refresh = accountsModule.refreshSeconds(noctalia.getConfig("refresh_seconds"))
  local refreshText
  if refresh <= 0 then
    refreshText = tr("refresh.manual", "Manual only — use Refresh now")
  else
    refreshText = tr("refresh.every", "Refresh every {value}", { value = formatter.refreshChoiceText(refresh) })
  end
  local children = {
    panelHeader(tr("accounts.title", "Accounts"), { back = true }),
    ui.column({ key = "settings-refresh", gap = 4 }, {
      ui.label({
        key = "settings-refresh-label",
        text = refreshText,
        fontSize = 12,
        color = "on_surface",
      }),
      ui.row({ key = "settings-refresh-actions", gap = 8, align = "center" }, {
        ui.button({
          key = "settings-refresh-now",
          text = tr("ui.refresh_now", "Refresh now"),
          glyph = "refresh",
          variant = "outline",
          onClick = "onRefresh",
        }),
        ui.button({
          key = "settings-open",
          text = tr("ui.open_plugin_settings", "Open plugin settings"),
          glyph = "settings",
          variant = "outline",
          onClick = "onOpenPluginSettings",
        }),
      }),
    }),
  }
  local rows = {}
  for index, account in ipairs(accounts) do
    local provider = registry.find(account.service)
    local rowChildren = {
      ui.row({ key = "account-head-" .. account.id, gap = 8, align = "center" }, {
        ui.column({ key = "account-titles-" .. account.id, gap = 0, flexGrow = 1 }, {
          ui.label({
            key = "account-title-" .. account.id,
            text = provider and providerTitle(provider) or account.service,
            fontSize = 13,
            fontWeight = "semibold",
            color = "on_surface",
            maxLines = 1,
          }),
          ui.label({
            key = "account-name-" .. account.id,
            text = privacy.displayName(account.name),
            fontSize = 11,
            color = "on_surface_variant",
            maxLines = 1,
          }),
        }),
        ui.row({ key = "account-actions-" .. account.id, gap = 0, align = "center" }, {
          ui.button({
            key = "account-up-" .. account.id,
            glyph = "chevron-up",
            variant = "ghost",
            enabled = index > 1,
            onClick = function() moveAccount(account.id, -1) end,
          }),
          ui.button({
            key = "account-down-" .. account.id,
            glyph = "chevron-down",
            variant = "ghost",
            enabled = index < #accounts,
            onClick = function() moveAccount(account.id, 1) end,
          }),
          ui.button({
            key = "account-edit-" .. account.id,
            glyph = "pencil",
            variant = "ghost",
            onClick = function() startEdit(account.id) end,
          }),
          ui.button({
            key = "account-delete-" .. account.id,
            glyph = "trash",
            variant = "ghost",
            onClick = function()
              pendingDelete = account.id
              render()
            end,
          }),
        }),
      }),
    }
    if pendingDelete == account.id then
      table.insert(rowChildren, ui.row({ key = "account-confirm-" .. account.id, gap = 8, align = "center" }, {
        ui.label({
          key = "account-confirm-label-" .. account.id,
          text = tr("delete.confirm", "Delete this account and its stored key?"),
          fontSize = 11,
          color = "error",
          flexGrow = 1,
        }),
        ui.button({
          key = "account-confirm-yes-" .. account.id,
          text = tr("ui.delete", "Delete"),
          variant = "destructive",
          onClick = function() onConfirmDelete(account.id) end,
        }),
        ui.button({
          key = "account-confirm-no-" .. account.id,
          text = tr("ui.cancel", "Cancel"),
          variant = "outline",
          onClick = "onCancelDelete",
        }),
      }))
    end
    table.insert(rows, ui.column({
      key = "account-" .. account.id,
      gap = 6,
      padding = 10,
      fill = "surface_variant/0.35",
      radius = 10,
      border = "outline/0.18",
      borderWidth = 1,
    }, rowChildren))
  end
  table.insert(rows, ui.button({
    key = "settings-add",
    text = tr("ui.add_account", "Add account"),
    glyph = "plus",
    variant = "primary",
    onClick = "onAdd",
  }))
  table.insert(children, ui.scroll({ key = "settings-scroll", flexGrow = 1, gap = 8 }, rows))
  local status = isStale()
    and tr("status.service_waiting", "Waiting for the service to publish data")
    or tr("status.last_update", "Last update {time}", { time = os.date("%H:%M", current.ts) })
  table.insert(children, ui.label({ key = "settings-status", text = status, fontSize = 10, color = "on_surface_variant" }))
  local node = messageNode("settings-message")
  if node then
    table.insert(children, node)
  end
  panel.render(ui.column({ key = "panel-settings", padding = 14, gap = 10 }, children))
end

function discoveryRows(provider)
  local rows = {}
  if discovering then
    table.insert(rows, ui.label({
      key = "discovery-reading",
      text = tr("discovery.claude_reading", "Reading the Claude desktop app file"),
      fontSize = 11,
      color = "on_surface_variant",
    }))
    return rows
  end
  if discoveries == nil then
    return rows
  end
  if #discoveries == 0 then
    table.insert(rows, ui.label({
      key = "discovery-none",
      text = tr("discovery.claude_none_new", "No new accounts found in the Claude desktop app file"),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 3,
    }))
    return rows
  end
  for _, item in ipairs(discoveries) do
    local org = item.fields.org
    table.insert(rows, ui.column({ key = "discovery-" .. org, gap = 4 }, {
      ui.column({ key = "discovery-info-" .. org, gap = 0 }, {
        ui.label({ key = "discovery-org-" .. org, text = org, fontSize = 12, fontWeight = "semibold", color = "on_surface" }),
        ui.label({
          key = "discovery-usage-" .. org,
          text = formatter.summaryText(item.usage or {}),
          fontSize = 10,
          color = "on_surface_variant",
        }),
      }),
      ui.input({
        key = "discovery-name-" .. org,
        value = form.orgNames[org] or "",
        placeholder = tr("form.name_placeholder", "Name (email addresses are masked)"),
        controlSize = "sm",
        onChange = function(value)
          form.orgNames[org] = value or ""
        end,
      }),
    }))
  end
  table.insert(rows, ui.button({
    key = "discovery-add",
    text = tr("form.add_selected", "Add the named organizations"),
    glyph = "plus",
    variant = "primary",
    enabled = not busy,
    onClick = "onAddDiscovered",
  }))
  return rows
end

local function renderForm()
  local provider = registry.find(form.service)
  if provider == nil then
    modal = "cards"
    renderCards()
    return
  end
  local title = modal == "edit" and tr("edit.title", "Edit account") or tr("add.title", "Add account")
  local children = { panelHeader(title, { back = true }) }
  local body = {}

  if modal == "add" then
    local titles = {}
    local selected = 0
    for index, item in ipairs(registry.ALL) do
      table.insert(titles, providerTitle(item))
      if item.id == form.service then
        selected = index - 1
      end
    end
    table.insert(body, ui.column({ key = "form-service-group", gap = 4 }, {
      ui.label({ key = "form-service-label", text = tr("form.service", "Service"), fontSize = 11, color = "on_surface_variant" }),
      ui.select({
        key = "form-service",
        options = titles,
        selectedIndex = selected,
        onChange = "onServiceChange",
      }),
    }))
  else
    table.insert(body, ui.label({
      key = "form-edit-service",
      text = providerTitle(provider),
      fontSize = 13,
      fontWeight = "semibold",
      color = "primary",
    }))
  end

  local nameChildren = {
    ui.label({
      key = "form-name-label",
      text = tr("form.name", "Account label"),
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }
  if modal == "edit" and form.originalName ~= "" then
    table.insert(nameChildren, ui.label({
      key = "form-current-name",
      text = tr("form.current_label", "Current label: {name}", { name = privacy.displayName(form.originalName) }),
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 2,
    }))
  end
  table.insert(nameChildren, ui.input({
    key = "form-name-" .. form.service .. "-" .. tostring(editingId),
    value = form.name,
    placeholder = modal == "edit"
      and tr("form.name_keep", "Leave empty to keep the current label")
      or tr("form.name_placeholder", "Name (email addresses are masked)"),
    onChange = "onNameChange",
    onSubmit = "onSave",
  }))
  table.insert(body, ui.column({ key = "form-name-group", gap = 4 }, nameChildren))

  if provider.needsKey then
    table.insert(body, ui.column({ key = "form-key-group", gap = 4 }, {
      ui.label({ key = "form-key-label", text = tr("form.key", "Key"), fontSize = 11, color = "on_surface_variant" }),
      ui.input({
        key = "form-key-" .. form.service .. "-" .. tostring(editingId),
        value = "",
        placeholder = modal == "edit" and tr("form.key_keep", "Leave empty to keep the saved key") or tr("form.key_paste", "Paste the key"),
        password = true,
        onChange = "onKeyChange",
        onSubmit = "onSave",
      }),
      provider.keyHelp ~= "" and ui.label({
        key = "form-key-help",
        text = tr("provider." .. provider.id .. ".key_help", provider.keyHelp),
        fontSize = 10,
        color = "on_surface_variant",
        maxLines = 3,
      }) or nil,
    }))
  end

  for _, field in ipairs(provider.fields) do
    if field.typed then
      table.insert(body, ui.column({ key = "form-field-group-" .. field.id, gap = 4 }, {
        ui.label({
          key = "form-field-label-" .. field.id,
          text = field.label,
          fontSize = 11,
          color = "on_surface_variant",
        }),
        ui.input({
          key = "form-field-" .. field.id .. "-" .. form.service,
          value = form.fields[field.id] or "",
          placeholder = field.label,
          controlSize = "sm",
          onChange = function(value)
            form.fields[field.id] = value or ""
          end,
        }),
      }))
    end
  end

  if provider.discover then
    table.insert(body, ui.column({ key = "form-discovery", gap = 6 }, discoveryRows(provider)))
  end

  local node = messageNode("form-message")
  if node then
    table.insert(body, node)
  end

  local actions = {}
  if provider.discover and modal == "add" then
    table.insert(actions, ui.button({
      key = "form-discovered-add",
      text = tr("form.add_selected", "Add the named organizations"),
      variant = "primary",
      enabled = not busy,
      onClick = "onAddDiscovered",
    }))
  end
  table.insert(actions, ui.button({
    key = "form-save",
    text = modal == "edit" and tr("ui.save", "Save") or tr("ui.add", "Add"),
    variant = "primary",
    enabled = not busy,
    onClick = "onSave",
  }))
  table.insert(actions, ui.button({
    key = "form-cancel",
    text = tr("ui.cancel", "Cancel"),
    variant = "outline",
    onClick = "onBack",
  }))
  table.insert(body, ui.row({ key = "form-actions", gap = 8, align = "center" }, actions))
  if busy then
    table.insert(body, ui.label({
      key = "form-busy",
      text = tr("form.saving", "Saving to the Secret Service..."),
      fontSize = 10,
      color = "on_surface_variant",
    }))
  end

  table.insert(children, ui.scroll({ key = "form-scroll", flexGrow = 1, gap = 10 }, body))
  panel.render(ui.column({ key = "panel-form", padding = 14, gap = 10 }, children))
end

function render()
  if modal == "settings" then
    renderSettings()
  elseif modal == "add" or modal == "edit" then
    renderForm()
  else
    renderCards()
  end
end

function onAddDiscovered()
  addDiscovered()
end

loadDiscovery = function(provider)
  discovering = true
  discoveries = nil
  busy = false
  render()
  check.discoverAccounts(provider, tools, function(result)
    discovering = false
    if not result.ok then
      showMessage(formatter.describeError(result.error), "error")
      render()
      return
    end
    discoveries = newDiscoveries(result.items)
    render()
  end)
end

function onOpen(context)
  accounts = store.load(registry.find)
  current = noctalia.state.get("ai_usage")
  pendingDelete = nil
  message = nil
  busy = false
  local openAdd = noctalia.state.get("ai_usage_open_add")
  noctalia.state.set("ai_usage_open_add", false)
  if openAdd then
    onAdd()
    return
  end
  modal = "cards"
  render()
end

noctalia.state.watch("ai_usage", function(value)
  current = value
  if modal == "cards" then
    render()
  end
end)

noctalia.state.watch("ai_usage_accounts_rev", function()
  accounts = store.load(registry.find)
  if modal ~= "add" and modal ~= "edit" then
    render()
  end
end)
