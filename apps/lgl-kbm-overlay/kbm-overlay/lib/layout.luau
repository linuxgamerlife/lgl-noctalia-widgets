--!nonstrict

-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Gaming key clusters and key-name helpers shared by the reader, overlay,
-- card and device panel.

local M = {}

local function key(code, label, width)
  return { key = code, label = label or code, w = width or 1 }
end

local FPS = {
  {
    key("KEY_GRAVE", "~"),
    key("KEY_1", "1"),
    key("KEY_2", "2"),
    key("KEY_3", "3"),
    key("KEY_4", "4"),
    key("KEY_5", "5"),
  },
  {
    key("KEY_TAB", "TAB"),
    key("KEY_Q", "Q"),
    key("KEY_W", "W"),
    key("KEY_E", "E"),
    key("KEY_R", "R"),
    key("KEY_T", "T"),
  },
  {
    key("KEY_A", "A"),
    key("KEY_S", "S"),
    key("KEY_D", "D"),
    key("KEY_F", "F"),
    key("KEY_G", "G"),
  },
  {
    key("KEY_LEFTSHIFT", "SHIFT"),
    key("KEY_Z", "Z"),
    key("KEY_X", "X"),
    key("KEY_C", "C"),
    key("KEY_V", "V"),
    key("KEY_B", "B"),
  },
  {
    key("KEY_LEFTCTRL", "CTRL"),
    key("KEY_LEFTALT", "ALT"),
    key("KEY_SPACE", "SPACE", 3),
  },
}

local WASD = {
  {
    key("KEY_1", "1"),
    key("KEY_2", "2"),
    key("KEY_3", "3"),
    key("KEY_4", "4"),
  },
  {
    key("KEY_Q", "Q"),
    key("KEY_W", "W"),
    key("KEY_E", "E"),
    key("KEY_R", "R"),
  },
  {
    key("KEY_A", "A"),
    key("KEY_S", "S"),
    key("KEY_D", "D"),
    key("KEY_F", "F"),
  },
  {
    key("KEY_LEFTSHIFT", "SHIFT"),
    key("KEY_SPACE", "SPACE", 2),
    key("KEY_LEFTCTRL", "CTRL"),
  },
}

local SPECIAL = {
  ["ESC"] = "KEY_ESC",
  ["ESCAPE"] = "KEY_ESC",
  ["~"] = "KEY_GRAVE",
  ["`"] = "KEY_GRAVE",
  ["GRAVE"] = "KEY_GRAVE",
  ["BACKTICK"] = "KEY_GRAVE",
  ["SPACE"] = "KEY_SPACE",
  ["SPACEBAR"] = "KEY_SPACE",
  ["SHIFT"] = "KEY_LEFTSHIFT",
  ["LEFTSHIFT"] = "KEY_LEFTSHIFT",
  ["CTRL"] = "KEY_LEFTCTRL",
  ["CONTROL"] = "KEY_LEFTCTRL",
  ["LEFTCTRL"] = "KEY_LEFTCTRL",
  ["ALT"] = "KEY_LEFTALT",
  ["LEFTALT"] = "KEY_LEFTALT",
  ["ENTER"] = "KEY_ENTER",
  ["RETURN"] = "KEY_ENTER",
  ["TAB"] = "KEY_TAB",
  ["CAPS"] = "KEY_CAPSLOCK",
  ["CAPSLOCK"] = "KEY_CAPSLOCK",
  ["BACKSPACE"] = "KEY_BACKSPACE",
  ["DELETE"] = "KEY_DELETE",
  ["DEL"] = "KEY_DELETE",
  ["UP"] = "KEY_UP",
  ["DOWN"] = "KEY_DOWN",
  ["LEFT"] = "KEY_LEFT",
  ["RIGHT"] = "KEY_RIGHT",
  ["PAGEUP"] = "KEY_PAGEUP",
  ["PAGEDOWN"] = "KEY_PAGEDOWN",
  ["HOME"] = "KEY_HOME",
  ["END"] = "KEY_END",
  ["INSERT"] = "KEY_INSERT",
  ["MOUSE1"] = "BTN_LEFT",
  ["MOUSE2"] = "BTN_RIGHT",
  ["MOUSE3"] = "BTN_MIDDLE",
  ["LMB"] = "BTN_LEFT",
  ["RMB"] = "BTN_RIGHT",
  ["MMB"] = "BTN_MIDDLE",
}

local LABELS = {
  KEY_ESC = "ESC",
  KEY_GRAVE = "~",
  KEY_TAB = "TAB",
  KEY_CAPSLOCK = "CAPS",
  KEY_LEFTSHIFT = "SHIFT",
  KEY_LEFTCTRL = "CTRL",
  KEY_LEFTALT = "ALT",
  KEY_SPACE = "SPACE",
  KEY_ENTER = "ENTER",
  KEY_BACKSPACE = "BACK",
  KEY_DELETE = "DEL",
  KEY_UP = "UP",
  KEY_DOWN = "DOWN",
  KEY_LEFT = "LEFT",
  KEY_RIGHT = "RIGHT",
  KEY_PAGEUP = "PGUP",
  KEY_PAGEDOWN = "PGDN",
  KEY_HOME = "HOME",
  KEY_END = "END",
  KEY_INSERT = "INS",
  BTN_LEFT = "LMB",
  BTN_RIGHT = "RMB",
  BTN_MIDDLE = "MMB",
  BTN_SIDE = "MB4",
  BTN_EXTRA = "MB5",
  BTN_FORWARD = "MB6",
  BTN_BACK = "MB7",
  BTN_TASK = "MB8",
  BTN_0 = "B0", BTN_1 = "B1", BTN_2 = "B2", BTN_3 = "B3", BTN_4 = "B4",
  BTN_5 = "B5", BTN_6 = "B6", BTN_7 = "B7", BTN_8 = "B8", BTN_9 = "B9",
}

function M.normalize(input)
  if type(input) ~= "string" then
    return nil
  end
  local value = noctalia.string.trim(input)
  if value == "" then
    return nil
  end
  local upper = string.upper(value)
  if SPECIAL[upper] then
    return SPECIAL[upper]
  end
  if string.match(upper, "^BTN_") or string.match(upper, "^KEY_") then
    return upper
  end
  if string.match(upper, "^F%d%d?$") then
    return "KEY_" .. upper
  end
  if string.match(upper, "^%d$") then
    return "KEY_" .. upper
  end
  if string.match(upper, "^[A-Z]$") then
    return "KEY_" .. upper
  end
  return "KEY_" .. upper
end

function M.label(key_name)
  if LABELS[key_name] then
    return LABELS[key_name]
  end
  if type(key_name) ~= "string" then
    return "?"
  end
  if string.sub(key_name, 1, 4) == "KEY_" then
    return string.sub(key_name, 5)
  end
  if string.sub(key_name, 1, 4) == "BTN_" then
    return "B" .. string.sub(key_name, 5)
  end
  return key_name
end

local function custom_rows(custom_keys)
  local rows = {}
  local row = {}
  for _, raw in ipairs(custom_keys or {}) do
    local name = M.normalize(raw)
    if name ~= nil then
      row[#row + 1] = key(name, M.label(name))
      if #row == 6 then
        rows[#rows + 1] = row
        row = {}
      end
    end
  end
  if #row > 0 then
    rows[#rows + 1] = row
  end
  if #rows == 0 then
    return FPS
  end
  return rows
end

function M.rows(layout, custom_keys)
  if layout == "wasd" then
    return WASD
  elseif layout == "custom" then
    return custom_rows(custom_keys)
  end
  return FPS
end

function M.all_keys(layout, custom_keys)
  local seen = {}
  local out = {}
  for _, row in ipairs(M.rows(layout, custom_keys)) do
    for _, spec in ipairs(row) do
      if not seen[spec.key] then
        seen[spec.key] = true
        out[#out + 1] = spec.key
      end
    end
  end
  return out
end

function M.mouse_side_order()
  -- Draw the front-most thumb button at the top. On a typical mouse
  -- BTN_EXTRA is the forward button and BTN_SIDE is the rear/back button, so
  -- BTN_SIDE must sit below BTN_EXTRA.
  return {
    "BTN_FORWARD", "BTN_EXTRA", "BTN_SIDE", "BTN_BACK", "BTN_TASK",
    "BTN_0", "BTN_1", "BTN_2", "BTN_3", "BTN_4",
    "BTN_5", "BTN_6", "BTN_7", "BTN_8", "BTN_9",
  }
end

function M.mouse_button_order()
  return {
    "BTN_LEFT", "BTN_RIGHT", "BTN_MIDDLE", "BTN_SIDE", "BTN_EXTRA",
    "BTN_FORWARD", "BTN_BACK", "BTN_TASK",
    "BTN_0", "BTN_1", "BTN_2", "BTN_3", "BTN_4",
    "BTN_5", "BTN_6", "BTN_7", "BTN_8", "BTN_9",
  }
end

function M.mouse_button_label(name)
  return M.label(name)
end

return M
