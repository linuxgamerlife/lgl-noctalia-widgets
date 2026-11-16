--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Bar shortcut for the device picker. The visual overlay is a desktop widget,
-- not a bar widget.

local config = require("./lib/config.luau")

local cfg = config.bar()
local state = noctalia.state.get("kbm_state")
local error_state = noctalia.state.get("kbm_error")

local function pressed_count()
  if type(state) ~= "table" or type(state.pressed) ~= "table" then
    return 0
  end
  return #state.pressed
end

local function draw()
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {
    ui.glyph({
      key = "bar-glyph",
      name = cfg.glyph,
      size = 14,
      color = pressed_count() > 0 and "primary" or "on_surface",
    }),
  }
  if cfg.show_label and not vertical then
    children[#children + 1] = ui.label({
      key = "bar-label",
      text = cfg.label,
      fontSize = 10,
      fontWeight = "semibold",
      color = "on_surface",
      maxLines = 1,
    })
  end
  if type(error_state) == "table" and error_state.message ~= nil then
    children[#children + 1] = ui.glyph({
      key = "bar-warning",
      name = "alert-triangle",
      size = 12,
      color = "error",
    })
  end
  barWidget.render(container({ key = "bar-root", gap = 5, align = "center" }, children))
end

function onClick()
  if type(noctalia.togglePanel) == "function" then
    noctalia.togglePanel("linuxgamerlife/kbm-overlay:devices")
  end
end

function update()
  draw()
end

noctalia.setUpdateInterval(200)
noctalia.state.watch("kbm_state", function(value)
  state = value
  draw()
end)
noctalia.state.watch("kbm_error", function(value)
  error_state = value
  draw()
end)
draw()
