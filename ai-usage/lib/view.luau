-- Shared card rendering for the desktop widget and the panel.

local formatter = require("./formatter.luau")

local M = {}

local GLYPHS = {
  claude = "message-circle",
  chatgpt = "brand-openai",
  openai = "brand-openai",
  anthropic = "letter-a",
  xai = "x",
  opencodeGo = "terminal-2",
  opencodeZen = "terminal-2",
  minimax = "chart-bar",
  requesty = "route",
  huggingFace = "heart-handshake",
  jetbrains = "code",
}

local function append(children, value)
  if value ~= nil then
    table.insert(children, value)
  end
end

function M.severityColor(severity)
  if severity == formatter.SEVERITY.CRITICAL then
    return "error"
  end
  if severity == formatter.SEVERITY.WARNING then
    return "tertiary"
  end
  if severity == formatter.SEVERITY.UNKNOWN then
    return "on_surface_variant"
  end
  return "primary"
end

function M.glyphFor(service)
  return GLYPHS[service] or "sparkles"
end

function M.tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

function M.valueRow(row, opts, key)
  local dense = opts and opts.dense
  local dim = opts and opts.dim
  local color = row.isProblem and "tertiary" or (dim and "on_surface_variant" or "on_surface")
  return ui.row({
    key = key,
    gap = 8,
    align = "top",
    justify = "space_between",
  }, {
    ui.label({
      text = row.label,
      fontSize = dense and 12 or 13,
      color = dim and "on_surface_variant" or "on_surface",
      maxLines = 1,
      flexGrow = 1,
    }),
    ui.label({
      text = row.valueText,
      fontSize = dense and 12 or 13,
      color = color,
      textAlign = "right",
      maxLines = row.isProblem and 3 or 1,
    }),
  })
end

function M.bar(item, opts, key)
  local dense = opts and opts.dense
  local children = {
    ui.row({
      key = key .. "-head",
      gap = 8,
      align = "center",
      justify = "space_between",
    }, {
      ui.label({
        text = item.label,
        fontSize = dense and 12 or 13,
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
      ui.label({
        text = item.percentText,
        fontSize = dense and 12 or 13,
        fontWeight = "semibold",
        color = M.severityColor(item.severity),
      }),
    }),
    ui.progress({
      key = key .. "-bar",
      progress = item.fraction,
      fill = M.severityColor(item.severity),
      track = "on_surface/0.14",
      height = dense and 4 or 6,
      radius = 3,
    }),
  }
  if item.resetText ~= "" then
    table.insert(children, ui.label({
      key = key .. "-reset",
      text = item.resetText,
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 2,
    }))
  end
  if item.statusText ~= nil and item.statusText ~= "" then
    table.insert(children, ui.label({
      key = key .. "-status",
      text = item.statusText,
      fontSize = 10,
      color = "error",
      maxLines = 1,
    }))
  end
  return ui.column({ key = key, gap = 2 }, children)
end

local function modelSummary(model)
  local parts = {}
  if (model.steps or 0) > 0 then
    table.insert(parts, M.tr("models.steps", "{n} steps", { n = formatter.formatCount(model.steps) }))
  end
  if (model.input or 0) + (model.output or 0) > 0 then
    table.insert(parts, M.tr("models.tokens", "{input} in · {output} out", {
      input = formatter.formatCount(model.input or 0),
      output = formatter.formatCount(model.output or 0),
    }))
  end
  return table.concat(parts, " · ")
end

function M.modelRow(model, opts, key)
  local dense = opts and opts.dense
  return ui.column({ key = key, gap = 0 }, {
    ui.row({ key = key .. "-head", gap = 8, align = "center", justify = "space_between" }, {
      ui.label({
        key = key .. "-name",
        text = (model.id or "unknown")
          .. (model.variant ~= nil and model.variant ~= "default" and (" · " .. model.variant) or ""),
        fontSize = dense and 11 or 12,
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
      ui.label({
        key = key .. "-cost",
        text = formatter.formatMoney(model.cost or 0, "usd"),
        fontSize = dense and 11 or 12,
        fontWeight = "semibold",
        color = "on_surface",
      }),
    }),
    ui.label({
      key = key .. "-summary",
      text = modelSummary(model),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  })
end

function M.card(section, opts)
  local dense = opts and opts.dense
  local gap = dense and 4 or 7
  local padding = dense and 8 or 12
  local titleSize = dense and 13 or 15
  local children = {}

  local head = {
    ui.glyph({
      key = "card-glyph-" .. section.key,
      name = M.glyphFor(section.service),
      size = dense and 14 or 17,
      color = "primary",
    }),
    ui.column({ key = "card-titles-" .. section.key, gap = 0, flexGrow = 1 }, {
      ui.label({
        key = "card-title-" .. section.key,
        text = section.title,
        fontSize = titleSize,
        fontWeight = "semibold",
        color = "on_surface",
        maxLines = 1,
      }),
      section.account ~= "" and ui.label({
        key = "card-account-" .. section.key,
        text = section.account,
        fontSize = dense and 10 or 11,
        color = "on_surface_variant",
        maxLines = 1,
      }) or nil,
    }),
  }
  if section.isLoading then
    table.insert(head, ui.glyph({
      key = "card-loading-" .. section.key,
      name = "loader",
      size = 13,
      color = "on_surface_variant",
    }))
  end
  table.insert(children, ui.row({
    key = "card-head-" .. section.key,
    gap = 8,
    align = "center",
  }, head))

  if section.hasError then
    table.insert(children, ui.label({
      key = "card-error-" .. section.key,
      text = section.errorText,
      fontSize = dense and 11 or 12,
      color = section.errorSeverity == formatter.SEVERITY.CRITICAL and "error" or "tertiary",
      maxLines = 4,
    }))
  end

  for index, row in ipairs(section.mainRows) do
    table.insert(children, M.valueRow(row, opts, "card-main-" .. section.key .. "-" .. index))
  end

  for index, item in ipairs(section.windows) do
    table.insert(children, M.bar(item, opts, "card-window-" .. section.key .. "-" .. index))
  end

  local showDetails = not opts or opts.show_details ~= false
  if showDetails and #section.rows > 0 and (#section.windows > 0 or #section.mainRows > 0) then
    table.insert(children, ui.separator({
      key = "card-separator-" .. section.key,
      thickness = 1,
      color = "outline/0.35",
      spacing = 2,
    }))
  end

  if showDetails then
    for index, row in ipairs(section.rows) do
      table.insert(children, M.valueRow(row, { dense = dense, dim = true }, "card-row-" .. section.key .. "-" .. index))
    end
  end

  local localModels = section.localModels or {}
  local localModelsError = section.localModelsError
  if showDetails and (#localModels > 0 or (localModelsError ~= nil and localModelsError ~= "")) then
    if #section.windows > 0 or #section.mainRows > 0 or #section.rows > 0 then
      table.insert(children, ui.separator({
        key = "models-separator-" .. section.key,
        thickness = 1,
        color = "outline/0.35",
        spacing = 2,
      }))
    end
    table.insert(children, ui.label({
      key = "models-heading-" .. section.key,
      text = M.tr("models.heading", "Models on this machine"),
      fontSize = 10,
      fontWeight = "medium",
      color = "on_surface_variant",
    }))
    table.insert(children, ui.label({
      key = "models-note-" .. section.key,
      text = M.tr("models.note", "Local OpenCode data, not official Go quota"),
      fontSize = 9,
      color = "on_surface_variant",
      maxLines = 2,
    }))
    if localModelsError ~= nil and localModelsError ~= "" then
      table.insert(children, ui.label({
        key = "models-error-" .. section.key,
        text = M.tr("models.unavailable", "Local model stats unavailable: {error}", { error = localModelsError }),
        fontSize = 10,
        color = "tertiary",
        maxLines = 3,
      }))
    else
      for index, model in ipairs(localModels) do
        table.insert(children, M.modelRow(model, opts, "model-" .. section.key .. "-" .. index))
      end
    end
  end

  local cardOpacity = opts and opts.card_opacity
  if cardOpacity == nil then
    cardOpacity = 0.42
  end
  local container = {
    key = "card-" .. section.key,
    gap = gap,
    padding = padding,
    radius = 12,
  }
  if cardOpacity > 0 then
    container.fill = string.format("surface_variant/%.2f", cardOpacity)
    container.border = "outline/0.22"
    container.borderWidth = 1
  end
  return ui.column(container, children)
end

function M.emptyCard(onAdd, opts)
  local children = {
    ui.glyph({ key = "empty-glyph", name = "sparkles", size = 28, color = "primary" }),
    ui.label({
      key = "empty-title",
      text = M.tr("empty.title", "No accounts yet"),
      fontSize = 16,
      fontWeight = "semibold",
      color = "on_surface",
    }),
    ui.label({
      key = "empty-body",
      text = M.tr("empty.body", "Add a service to start checking limits, spend and balance."),
      fontSize = 12,
      color = "on_surface_variant",
      textAlign = "center",
      maxLines = 3,
    }),
  }
  if onAdd then
    table.insert(children, ui.button({
      key = "empty-add",
      text = M.tr("ui.add_account", "Add account"),
      glyph = "plus",
      variant = "primary",
      onClick = onAdd,
    }))
  end
  local opacity = opts and opts.card_opacity
  if opacity == nil then
    opacity = 0.35
  end
  local container = {
    key = "empty-card",
    gap = 10,
    padding = 18,
    align = "center",
    radius = 14,
  }
  if opacity > 0 then
    container.fill = string.format("surface_variant/%.2f", opacity)
    container.border = "outline/0.2"
    container.borderWidth = 1
  end
  return ui.column(container, children)
end

function M.waitingCard(onRefresh, opts)
  local children = {
    ui.glyph({ key = "waiting-glyph", name = "clock-hour-4", size = 24, color = "on_surface_variant" }),
    ui.label({
      key = "waiting-title",
      text = M.tr("stale.title", "Waiting for the AI Usage service"),
      fontSize = 14,
      fontWeight = "semibold",
      color = "on_surface",
      textAlign = "center",
    }),
    ui.label({
      key = "waiting-body",
      text = M.tr("stale.body", "The poller has not published data yet. Enable the plugin and check its settings."),
      fontSize = 11,
      color = "on_surface_variant",
      textAlign = "center",
      maxLines = 4,
    }),
  }
  if onRefresh then
    table.insert(children, ui.button({
      key = "waiting-refresh",
      text = M.tr("ui.refresh_now", "Refresh now"),
      glyph = "refresh",
      variant = "outline",
      onClick = onRefresh,
    }))
  end
  local opacity = opts and opts.card_opacity
  if opacity == nil then
    opacity = 0.35
  end
  local container = {
    key = "waiting-card",
    gap = 8,
    padding = 18,
    align = "center",
    radius = 14,
  }
  if opacity > 0 then
    container.fill = string.format("surface_variant/%.2f", opacity)
    container.border = "outline/0.2"
    container.borderWidth = 1
  end
  return ui.column(container, children)
end

return M
