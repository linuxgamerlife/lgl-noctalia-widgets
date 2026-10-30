--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Device picker and permission status. Device selection is written to the
-- plugin data directory because plugin settings are read-only to entries.

local config = require("./lib/config.luau")
local layout = require("./lib/layout.luau")

local devices = noctalia.state.get("kbm_devices") or {}
local status = noctalia.state.get("kbm_status")
local error_state = noctalia.state.get("kbm_error")
local selected = config.read_devices()
local message = nil
local message_error = false

local function tr(key, fallback, subst)
  local value = noctalia.tr(key, subst)
  if value ~= nil and value ~= key then
    return value
  end
  return fallback
end

local function set_message(text, is_error)
  message = text
  message_error = is_error == true
end

local function bump()
  local value = tonumber(noctalia.state.get("kbm_config_rev")) or 0
  noctalia.state.set("kbm_config_rev", value + 1)
end

local function selected_path(kind)
  if kind == "keyboard" then
    return selected.keyboard_path, selected.keyboard
  end
  return selected.mouse_path, selected.mouse
end

local function is_selected(device, kind)
  local path, name = selected_path(kind)
  if path and path ~= "" then
    return path == device.path
  end
  return name ~= nil and name ~= "" and name == device.name
end

local function save_selection(kind, device)
  selected = config.read_devices()
  if kind == "keyboard" then
    selected.keyboard = device.name
    selected.keyboard_path = device.path
    selected.keyboard_vendor = device.vendor
    selected.keyboard_product = device.product
  else
    selected.mouse = device.name
    selected.mouse_path = device.path
    selected.mouse_vendor = device.vendor
    selected.mouse_product = device.product
  end
  local encoded = noctalia.json.encode(selected)
  if encoded == nil then
    set_message(tr("panel.save_failed", "Could not save the device selection: {error}", { error = "JSON encode failed" }), true)
    return false
  end
  local ok, err = noctalia.writeFile(config.devices_path(), encoded)
  if not ok then
    set_message(tr("panel.save_failed", "Could not save the device selection: {error}", { error = tostring(err) }), true)
    return false
  end
  set_message(tr("panel.saved", "Device selection saved. The reader is restarting."), false)
  bump()
  return true
end

local function choose_keyboard(device)
  if save_selection("keyboard", device) then
    render()
  end
end

local function choose_mouse(device)
  if save_selection("mouse", device) then
    render()
  end
end

local function clear_selection()
  selected = {}
  local ok, err = noctalia.writeFile(config.devices_path(), "{}")
  if not ok then
    set_message(tr("panel.save_failed", "Could not save the device selection: {error}", { error = tostring(err) }), true)
  else
    set_message(tr("panel.saved", "Device selection saved. The reader is restarting."), false)
    bump()
  end
  render()
end

local function open_settings()
  if type(noctalia.openSettings) == "function" then
    noctalia.openSettings()
  end
end

local function copy_permission_command()
  local dir = noctalia.pluginDir() or ""
  local path = dir .. "/code/setup-input-permissions.sh"
  if type(noctalia.copyToClipboard) == "function" then
    noctalia.copyToClipboard("bash " .. path, "text/plain")
    set_message(tr("labels.copied", "Copied"), false)
    render()
  end
end

local function section(title, children)
  local nodes = {
    ui.label({
      key = "section-title-" .. title,
      text = title,
      fontSize = 12,
      fontWeight = "bold",
      color = "on_surface",
      maxLines = 1,
    }),
  }
  for _, child in ipairs(children) do
    nodes[#nodes + 1] = child
  end
  return ui.column({ key = "section-" .. title, gap = 8 }, nodes)
end

local function status_text()
  if type(error_state) == "table" and error_state.message ~= nil then
    return error_state.message
  end
  if type(status) == "table" and status.state == "ok" then
    return tr("status.ok", "Input reader running")
  end
  return tr("status.waiting", "Waiting for the input reader")
end

local function device_meta(device)
  local parts = {}
  if device.vendor and device.vendor ~= "" then
    parts[#parts + 1] = device.vendor .. ":" .. (device.product or "")
  end
  parts[#parts + 1] = device.path
  if device.mouse and type(device.buttons) == "table" and #device.buttons > 0 then
    local labels = {}
    for _, name in ipairs(device.buttons) do
      labels[#labels + 1] = layout.mouse_button_label(name)
    end
    parts[#parts + 1] = table.concat(labels, " · ")
  end
  return table.concat(parts, "  ·  ")
end

local function device_row(device, kind)
  local chosen = is_selected(device, kind)
  local readable = device.readable ~= false
  local children = {
    ui.column({ key = "device-text-" .. device.path, gap = 2, flexGrow = 1 }, {
      ui.label({
        key = "device-name-" .. device.path,
        text = device.name or tr("labels.unknown", "Unknown"),
        fontSize = 11,
        fontWeight = "semibold",
        color = readable and "on_surface" or "error",
        maxLines = 1,
      }),
      ui.label({
        key = "device-meta-" .. device.path,
        text = device_meta(device),
        fontSize = 8,
        color = "on_surface_variant",
        maxLines = 2,
      }),
    }),
  }
  if chosen then
    children[#children + 1] = ui.label({
      key = "device-selected-" .. device.path,
      text = tr("labels.selected", "Selected"),
      fontSize = 8,
      fontWeight = "semibold",
      color = "primary",
      maxLines = 1,
    })
  else
    children[#children + 1] = ui.button({
      key = "device-use-" .. device.path,
      text = kind == "keyboard" and tr("panel.select_keyboard", "Use as keyboard") or tr("panel.select_mouse", "Use as mouse"),
      variant = "secondary",
      controlSize = "sm",
      onClick = function()
        if kind == "keyboard" then
          choose_keyboard(device)
        else
          choose_mouse(device)
        end
      end,
    })
  end
  return ui.row({
    key = "device-row-" .. device.path,
    gap = 8,
    padding = 6,
    align = "center",
    fill = chosen and "primary/0.10" or "surface_container/0.25",
    radius = 8,
  }, children)
end

local function list_for(kind)
  local rows = {}
  for _, device in ipairs(devices) do
    if device[kind] then
      rows[#rows + 1] = device_row(device, kind)
    end
  end
  if #rows == 0 then
    rows[#rows + 1] = ui.label({
      key = "no-" .. kind,
      text = kind == "keyboard" and tr("labels.no_keyboard", "No keyboard") or tr("labels.no_mouse", "No mouse"),
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 2,
    })
  end
  return rows
end

local function permission_section()
  local command = "bash " .. (noctalia.pluginDir() or "") .. "/code/setup-input-permissions.sh"
  return section(tr("panel.permission_title", "Input permission"), {
    ui.label({
      key = "permission-body",
      text = tr("panel.permission_body", "Reading a keyboard or mouse requires a one-time udev rule for the selected device. The rule grants read access only to that device for the active user; no root daemon is used."),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 5,
    }),
    ui.label({
      key = "permission-command",
      text = command,
      fontSize = 9,
      color = "on_surface",
      maxLines = 2,
    }),
    ui.row({ key = "permission-actions", gap = 8, align = "center" }, {
      ui.button({
        key = "permission-copy",
        text = tr("labels.copy_command", "Copy command"),
        variant = "secondary",
        controlSize = "sm",
        onClick = copy_permission_command,
      }),
      ui.label({
        key = "permission-hint",
        text = tr("panel.permission_body", "Reading a keyboard or mouse requires a one-time udev rule for the selected device."),
        fontSize = 8,
        color = "on_surface_variant",
        flexGrow = 1,
        maxLines = 3,
      }),
    }),
  })
end

local function selection_text()
  local parts = {}
  if selected.keyboard and selected.keyboard ~= "" then
    parts[#parts + 1] = tr("panel.selected_keyboard", "Keyboard: {name}", { name = selected.keyboard })
  end
  if selected.mouse and selected.mouse ~= "" then
    parts[#parts + 1] = tr("panel.selected_mouse", "Mouse: {name}", { name = selected.mouse })
  end
  if #parts == 0 then
    return tr("panel.auto_selection", "Automatic selection")
  end
  return table.concat(parts, "  ·  ")
end

function render()
  local children = {
    ui.row({ key = "devices-header", gap = 8, align = "center" }, {
      ui.glyph({ key = "devices-glyph", name = "keyboard", size = 20, color = "primary" }),
      ui.label({
        key = "devices-title",
        text = tr("panel.title", "Keyboard & Mouse"),
        fontSize = 16,
        fontWeight = "semibold",
        color = "on_surface",
        flexGrow = 1,
        maxLines = 1,
      }),
      ui.button({
        key = "devices-settings",
        glyph = "settings",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = open_settings,
      }),
      ui.button({
        key = "devices-close",
        glyph = "x",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = function()
          panel.close()
        end,
      }),
    }),
    ui.column({ key = "devices-status", gap = 2 }, {
      ui.label({
        key = "devices-status-line",
        text = status_text(),
        fontSize = 10,
        color = (type(error_state) == "table" and error_state.message) and "error" or "on_surface_variant",
        maxLines = 3,
      }),
      ui.label({
        key = "devices-status-selection",
        text = selection_text(),
        fontSize = 8,
        color = "on_surface_variant",
        maxLines = 2,
      }),
    }),
  }
  if message ~= nil then
    children[#children + 1] = ui.label({
      key = "devices-message",
      text = message,
      fontSize = 9,
      color = message_error and "error" or "primary",
      maxLines = 2,
    })
  end
  children[#children + 1] = section(tr("panel.keyboard_title", "Keyboard"), list_for("keyboard"))
  children[#children + 1] = section(tr("panel.mouse_title", "Mouse"), list_for("mouse"))
  children[#children + 1] = permission_section()
  children[#children + 1] = ui.row({ key = "devices-actions", gap = 8, align = "center" }, {
    ui.button({
      key = "devices-clear",
      text = tr("panel.clear", "Use automatic selection"),
      variant = "ghost",
      controlSize = "sm",
      onClick = clear_selection,
    }),
    ui.button({
      key = "devices-appearance",
      text = tr("panel.open_settings", "Appearance settings"),
      variant = "secondary",
      controlSize = "sm",
      onClick = open_settings,
    }),
  })
  panel.render(ui.scroll({ key = "devices-root", gap = 14, padding = 16, flexGrow = 1 }, children))
end

function onOpen()
  devices = noctalia.state.get("kbm_devices") or {}
  status = noctalia.state.get("kbm_status")
  error_state = noctalia.state.get("kbm_error")
  selected = config.read_devices()
  render()
end

function update()
  render()
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("kbm_devices", function(value)
  devices = value or {}
  render()
end)
noctalia.state.watch("kbm_status", function(value)
  status = value
  render()
end)
noctalia.state.watch("kbm_error", function(value)
  error_state = value
  render()
end)
