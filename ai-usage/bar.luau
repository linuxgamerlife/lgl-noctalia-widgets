--!nonstrict

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Łukasz Sarna
-- Copyright (C) 2026 LinuxGamerLife

-- Compact bar widget: the worst current limit, an error count or the account
-- count. Click opens the panel; right-click refreshes.

local formatter = require("./lib/formatter.luau")
local view = require("./lib/view.luau")
local accounts = require("./lib/accounts.luau")

local showPercent = noctalia.getConfig("show_percent")
if showPercent == nil then
  showPercent = true
end
local glyph = noctalia.getConfig("glyph") or "chart-bar"
local mode = noctalia.getConfig("mode") or "worst"
if mode ~= "worst" and mode ~= "errors" and mode ~= "count" then
  mode = "worst"
end
local refreshSeconds = accounts.refreshSeconds(noctalia.getConfig("refresh_seconds"))

local current = noctalia.state.get("ai_usage")

local function tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

local function summary()
  if type(current) ~= "table" or type(current.ts) ~= "number" then
    return nil
  end
  if os.time() - current.ts > math.max(180, refreshSeconds * 3) then
    return nil
  end
  local worst = nil
  local errors = 0
  local count = 0
  for _, entry in ipairs(current.accounts or {}) do
    count = count + 1
    if entry.error then
      errors = errors + 1
    end
    for _, window in ipairs(entry.usage and entry.usage.windows or {}) do
      if type(window.usedPercent) == "number" and (worst == nil or window.usedPercent > worst.percent) then
        worst = { percent = window.usedPercent, severity = formatter.severityFor(window.usedPercent) }
      end
    end
  end
  return { worst = worst, errors = errors, count = count }
end

local function render()
  local info = summary()
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {
    ui.glyph({
      key = "bar-glyph",
      name = glyph,
      size = 14,
      color = info and info.errors > 0 and "error" or "on_surface",
    }),
  }
  if info ~= nil and showPercent then
    if mode == "worst" and info.worst ~= nil then
      table.insert(children, ui.label({
        key = "bar-value",
        text = string.format("%d%%", math.floor(info.worst.percent + 0.5)),
        fontSize = 11,
        fontWeight = "semibold",
        color = view.severityColor(info.worst.severity),
      }))
    elseif mode == "errors" and info.errors > 0 then
      table.insert(children, ui.label({
        key = "bar-value",
        text = tostring(info.errors),
        fontSize = 11,
        fontWeight = "semibold",
        color = "error",
      }))
    elseif mode == "count" then
      table.insert(children, ui.label({
        key = "bar-value",
        text = tostring(info.count),
        fontSize = 11,
        fontWeight = "semibold",
        color = "on_surface",
      }))
    end
  end
  barWidget.render(container({ key = "bar-root", gap = 4, align = "center" }, children))
end

function onClick()
  noctalia.state.set("ai_usage_open_add", false)
  noctalia.togglePanel("lukk17/ai-usage:panel")
end

function onRightClick()
  local value = tonumber(noctalia.state.get("ai_usage_refresh_seq")) or 0
  noctalia.state.set("ai_usage_refresh_seq", value + 1)
  noctalia.notify(tr("app.title", "AI Usage"), tr("ui.refreshing", "Refreshing every account now"))
end

function update()
  render()
end

noctalia.setUpdateInterval(15000)
noctalia.state.watch("ai_usage", function(value)
  current = value
  render()
end)
render()
