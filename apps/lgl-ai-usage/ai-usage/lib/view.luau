-- Shared HUD-style card rendering for the desktop widget and the panel.

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

local DEFAULTS = {
  text_color = "on_surface",
  muted_text_color = "on_surface_variant",
  divider_color = "outline/0.5",
  divider_width = 1.0,
  bar_height = 5.0,
  track_color = "on_surface/0.14",
  normal_color = "primary",
  warning_color = "tertiary",
  critical_color = "error",
  unknown_color = "on_surface_variant",
  card_fill = nil,
  card_border = nil,
  card_radius = 12,
  card_border_width = 1.0,
  show_reset_times = true,
  show_service_icon = true,
}

function M.defaultStyle()
  local style = {}
  for key, value in pairs(DEFAULTS) do
    style[key] = value
  end
  return style
end

function M.severityColor(severity, style)
  local palette = style or DEFAULTS
  if severity == formatter.SEVERITY.CRITICAL then
    return palette.critical_color
  end
  if severity == formatter.SEVERITY.WARNING then
    return palette.warning_color
  end
  if severity == formatter.SEVERITY.UNKNOWN then
    return palette.unknown_color
  end
  return palette.normal_color
end

function M.glyphFor(service)
  return GLYPHS[service] or "sparkles"
end

function M.tr(key, fallback, subst)
  local text = noctalia.tr(key, subst)
  return (text ~= nil and text ~= key) and text or fallback
end

function M.divider(style, key)
  local palette = style or DEFAULTS
  return ui.separator({
    key = key,
    orientation = "horizontal",
    thickness = palette.divider_width,
    color = palette.divider_color,
  })
end

function M.valueRow(row, opts, key)
  local style = opts and opts.style or DEFAULTS
  local dim = opts and opts.dim
  local color = row.isProblem and style.warning_color or (dim and style.muted_text_color or style.text_color)
  return ui.row({
    key = key,
    gap = 8,
    align = "top",
    justify = "space_between",
  }, {
    ui.label({
      text = row.label,
      fontSize = 13,
      color = dim and style.muted_text_color or style.text_color,
      maxLines = 1,
      flexGrow = 1,
    }),
    ui.label({
      text = row.valueText,
      fontSize = 13,
      fontWeight = "medium",
      color = color,
      textAlign = "right",
      maxLines = row.isProblem and 3 or 1,
    }),
  })
end

function M.bar(item, opts, key)
  local style = opts and opts.style or DEFAULTS
  local children = {
    ui.row({
      key = key .. "-head",
      gap = 8,
      align = "center",
      justify = "space_between",
    }, {
      ui.label({
        text = item.label,
        fontSize = 13,
        color = style.text_color,
        maxLines = 1,
        flexGrow = 1,
      }),
      ui.label({
        text = item.percentText,
        fontSize = 14,
        fontWeight = "semibold",
        color = M.severityColor(item.severity, style),
      }),
    }),
    ui.progress({
      key = key .. "-bar",
      progress = item.fraction,
      fill = M.severityColor(item.severity, style),
      track = style.track_color,
      height = style.bar_height,
      radius = style.bar_height / 2,
    }),
  }
  if style.show_reset_times and item.resetText ~= "" then
    table.insert(children, ui.label({
      key = key .. "-reset",
      text = item.resetText,
      fontSize = 11,
      color = style.muted_text_color,
      maxLines = 2,
    }))
  end
  if item.statusText ~= nil and item.statusText ~= "" then
    table.insert(children, ui.label({
      key = key .. "-status",
      text = item.statusText,
      fontSize = 11,
      color = style.critical_color,
      maxLines = 1,
    }))
  end
  return ui.column({ key = key, gap = 3 }, children)
end

local function modelSummary(model, style)
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
  local style = opts and opts.style or DEFAULTS
  return ui.column({ key = key, gap = 0 }, {
    ui.row({ key = key .. "-head", gap = 8, align = "center", justify = "space_between" }, {
      ui.label({
        key = key .. "-name",
        text = (model.id or "unknown")
          .. (model.variant ~= nil and model.variant ~= "default" and (" · " .. model.variant) or ""),
        fontSize = 13,
        color = style.text_color,
        maxLines = 1,
        flexGrow = 1,
      }),
      ui.label({
        key = key .. "-cost",
        text = formatter.formatMoney(model.cost or 0, "usd"),
        fontSize = 13,
        fontWeight = "medium",
        color = style.text_color,
      }),
    }),
    ui.label({
      key = key .. "-summary",
      text = modelSummary(model, style),
      fontSize = 11,
      color = style.muted_text_color,
      maxLines = 1,
    }),
  })
end

function M.card(section, opts)
  local style = opts and opts.style or DEFAULTS
  local children = {}

  local head = {}
  if style.show_service_icon then
    local glyphSeverity = section.hasError and section.errorSeverity or formatter.SEVERITY.NORMAL
    table.insert(head, ui.glyph({
      key = "card-glyph-" .. section.key,
      name = M.glyphFor(section.service),
      size = 20,
      color = M.severityColor(glyphSeverity, style),
    }))
  end
  table.insert(head, ui.column({ key = "card-titles-" .. section.key, gap = 0, flexGrow = 1 }, {
    ui.label({
      key = "card-title-" .. section.key,
      text = section.title,
      fontSize = 16,
      fontWeight = "semibold",
      color = style.text_color,
      maxLines = 1,
    }),
    section.account ~= "" and ui.label({
      key = "card-account-" .. section.key,
      text = section.account,
      fontSize = 12,
      color = style.muted_text_color,
      maxLines = 1,
    }) or nil,
  }))
  if section.isLoading then
    table.insert(head, ui.glyph({
      key = "card-loading-" .. section.key,
      name = "loader",
      size = 14,
      color = style.muted_text_color,
    }))
  end
  table.insert(children, ui.row({
    key = "card-head-" .. section.key,
    gap = 10,
    align = "center",
  }, head))

  if section.hasError then
    table.insert(children, ui.label({
      key = "card-error-" .. section.key,
      text = section.errorText,
      fontSize = 12,
      color = section.errorSeverity == formatter.SEVERITY.CRITICAL and style.critical_color or style.warning_color,
      maxLines = 4,
    }))
  end

  for index, row in ipairs(section.mainRows) do
    table.insert(children, M.valueRow(row, { style = style }, "card-main-" .. section.key .. "-" .. index))
  end

  for index, item in ipairs(section.windows) do
    table.insert(children, M.bar(item, { style = style }, "card-window-" .. section.key .. "-" .. index))
  end

  local showDetails = not opts or opts.show_details ~= false
  if showDetails and #section.rows > 0 and (#section.windows > 0 or #section.mainRows > 0) then
    table.insert(children, M.divider(style, "card-separator-" .. section.key))
  end

  if showDetails then
    for index, row in ipairs(section.rows) do
      table.insert(children, M.valueRow(row, { style = style, dim = true }, "card-row-" .. section.key .. "-" .. index))
    end
  end

  local localModels = section.localModels or {}
  local localModelsError = section.localModelsError
  if showDetails and (#localModels > 0 or (localModelsError ~= nil and localModelsError ~= "")) then
    if #section.windows > 0 or #section.mainRows > 0 or #section.rows > 0 then
      table.insert(children, M.divider(style, "models-separator-" .. section.key))
    end
    table.insert(children, ui.label({
      key = "models-heading-" .. section.key,
      text = M.tr("models.heading", "Models on this machine"),
      fontSize = 11,
      fontWeight = "medium",
      color = style.muted_text_color,
    }))
    table.insert(children, ui.label({
      key = "models-note-" .. section.key,
      text = M.tr("models.note", "Local OpenCode data, not official Go quota"),
      fontSize = 10,
      color = style.muted_text_color,
      maxLines = 2,
    }))
    if localModelsError ~= nil and localModelsError ~= "" then
      table.insert(children, ui.label({
        key = "models-error-" .. section.key,
        text = M.tr("models.unavailable", "Local model stats unavailable: {error}", { error = localModelsError }),
        fontSize = 11,
        color = style.warning_color,
        maxLines = 3,
      }))
    else
      for index, model in ipairs(localModels) do
        table.insert(children, M.modelRow(model, { style = style }, "model-" .. section.key .. "-" .. index))
      end
    end
  end

  local container = {
    key = "card-" .. section.key,
    gap = 8,
    padding = style.card_fill ~= nil and 10 or 0,
    radius = style.card_radius,
  }
  if style.card_fill ~= nil then
    container.fill = style.card_fill
  end
  if style.card_border ~= nil then
    container.border = style.card_border
    container.borderWidth = style.card_border_width
  end
  return ui.column(container, children)
end

function M.emptyCard(onAdd, opts)
  local style = opts and opts.style or DEFAULTS
  local children = {
    ui.glyph({ key = "empty-glyph", name = "chart-bar", size = 30, color = style.normal_color }),
    ui.label({
      key = "empty-title",
      text = M.tr("empty.title", "No accounts yet"),
      fontSize = 18,
      fontWeight = "semibold",
      color = style.text_color,
      textAlign = "center",
    }),
    ui.label({
      key = "empty-body",
      text = M.tr("empty.body", "Add a service to start checking limits, spend and balance."),
      fontSize = 13,
      color = style.muted_text_color,
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
  local container = {
    key = "empty-card",
    gap = 10,
    padding = style.card_fill ~= nil and 14 or 0,
    align = "center",
    radius = style.card_radius,
  }
  if style.card_fill ~= nil then
    container.fill = style.card_fill
  end
  if style.card_border ~= nil then
    container.border = style.card_border
    container.borderWidth = style.card_border_width
  end
  return ui.column(container, children)
end

function M.waitingCard(onRefresh, opts)
  local style = opts and opts.style or DEFAULTS
  local children = {
    ui.glyph({ key = "waiting-glyph", name = "hourglass-empty", size = 28, color = style.muted_text_color }),
    ui.label({
      key = "waiting-title",
      text = M.tr("stale.title", "Waiting for the AI Usage service"),
      fontSize = 16,
      fontWeight = "semibold",
      color = style.text_color,
      textAlign = "center",
    }),
    ui.label({
      key = "waiting-body",
      text = M.tr("stale.body", "The poller has not published data yet. Enable the plugin and check its settings."),
      fontSize = 12,
      color = style.muted_text_color,
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
  local container = {
    key = "waiting-card",
    gap = 8,
    padding = style.card_fill ~= nil and 14 or 0,
    align = "center",
    radius = style.card_radius,
  }
  if style.card_fill ~= nil then
    container.fill = style.card_fill
  end
  if style.card_border ~= nil then
    container.border = style.card_border
    container.borderWidth = style.card_border_width
  end
  return ui.column(container, children)
end

return M
