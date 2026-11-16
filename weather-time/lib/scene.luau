-- SPDX-License-Identifier: MIT
-- Copyright (C) 2026 LinuxGamerLife

-- Procedural full-bleed weather scenes rendered as small SVG files.
--
-- Noctalia's declarative UI has no z-index, so the card overlays its real text
-- on these images with a negative flex gap. The SVG contains only scenery:
-- sky, stars, sun/moon, clouds, rain/snow, lightning and grass. Text stays real
-- UI text for scaling, selection and accessibility.

local M = {}

M.WIDTH = 800
M.HEIGHT = 460

local COLORS = {
  clear_day = { top = "#1b4a6e", mid = "#3a7ba4", bottom = "#15334c", star = "#eaf5ff", ground = "#031018" },
  clear_night = { top = "#06111f", mid = "#0c2942", bottom = "#04101c", star = "#dfeeff", ground = "#010409" },
  cloudy_day = { top = "#26333f", mid = "#4d6474", bottom = "#1a2631", star = "#e8f1f7", ground = "#041017" },
  cloudy_night = { top = "#0b111a", mid = "#1d2a38", bottom = "#080d14", star = "#d9e7f3", ground = "#01050a" },
  rain_day = { top = "#14212d", mid = "#2c4659", bottom = "#0d1720", star = "#bcd6e8", ground = "#020b10" },
  rain_night = { top = "#080f17", mid = "#162a3a", bottom = "#050b11", star = "#aac8dd", ground = "#010407" },
  snow_day = { top = "#1d3042", mid = "#3d5d76", bottom = "#16283a", star = "#f0f8ff", ground = "#07131c" },
  snow_night = { top = "#0a1420", mid = "#1e354a", bottom = "#08121c", star = "#e8f4ff", ground = "#02080e" },
  thunder_day = { top = "#0c111b", mid = "#1e2a3d", bottom = "#070b12", star = "#dfeaff", ground = "#010307" },
  thunder_night = { top = "#050810", mid = "#111a2a", bottom = "#03060b", star = "#d5e4ff", ground = "#000205" },
  fog_day = { top = "#2b3741", mid = "#5a6b74", bottom = "#1c272e", star = "#eef5f8", ground = "#071117" },
  fog_night = { top = "#0d141b", mid = "#26323b", bottom = "#080d12", star = "#dbe8ef", ground = "#020609" },
}

local function hash(value)
  local result = 2166136261
  for index = 1, #value do
    result = (result * 16777619) % 4294967296
    result = (result + value:byte(index)) % 4294967296
  end
  return result
end

local function rng(seed)
  local state = seed % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
  return function()
    state = (state * 48271) % 2147483647
    return state / 2147483647
  end
end

local function f(value)
  return string.format("%.2f", value)
end

local function palette(variant)
  return COLORS[variant] or COLORS.clear_night
end

local function defs(colors)
  return table.concat({
    "<defs>",
    '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">',
    '<stop offset="0%" stop-color="', colors.top, '"/>',
    '<stop offset="52%" stop-color="', colors.mid, '"/>',
    '<stop offset="100%" stop-color="', colors.bottom, '"/>',
    "</linearGradient>",
    '<linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">',
    '<stop offset="0%" stop-color="#000000" stop-opacity="0"/>',
    '<stop offset="48%" stop-color="#000000" stop-opacity="0.08"/>',
    '<stop offset="100%" stop-color="#000000" stop-opacity="0.62"/>',
    "</linearGradient>",
    '<radialGradient id="vignette" cx="50%" cy="45%" r="75%">',
    '<stop offset="55%" stop-color="#000000" stop-opacity="0"/>',
    '<stop offset="100%" stop-color="#000000" stop-opacity="0.34"/>',
    "</radialGradient>",
    '<filter id="soft" x="-40%" y="-40%" width="180%" height="180%">',
    '<feGaussianBlur stdDeviation="7"/>',
    "</filter>",
    "</defs>",
  })
end

local function stars(colors, variant)
  local night = variant:match("_night") ~= nil
  local count = night and 110 or 0
  local random = rng(hash(variant))
  local out = {}
  for index = 1, count do
    local x = random() * M.WIDTH
    local y = random() * M.HEIGHT * 0.62
    local radius = 0.35 + random() * 1.25
    local twinkle = 0.45 + random() * 0.5
    out[#out + 1] = string.format(
      '<circle cx="%s" cy="%s" r="%s" fill="%s" opacity="%s"/>',
      f(x), f(y), f(radius), colors.star, f(twinkle)
    )
  end
  return table.concat(out)
end

local function celestial(colors, variant)
  -- Only clear scenes get a sun/moon; clouds and precipitation keep the sky
  -- clean so the glyph and temperature stay the focus.
  if not variant:match("clear") then
    return ""
  end
  local day = variant:match("_day") ~= nil
  local x, y = 655, 92
  if day then
    return table.concat({
      '<circle cx="', f(x), '" cy="', f(y), '" r="58" fill="#ffe7a8" opacity="0.07"/>',
      '<circle cx="', f(x), '" cy="', f(y), '" r="42" fill="#ffe7a8" opacity="0.12"/>',
      '<circle cx="', f(x), '" cy="', f(y), '" r="27" fill="#ffe9b8" opacity="0.92"/>',
    })
  end
  return table.concat({
    '<circle cx="', f(x), '" cy="', f(y), '" r="54" fill="#dfeaff" opacity="0.06"/>',
    '<circle cx="', f(x), '" cy="', f(y), '" r="38" fill="#e8f1ff" opacity="0.10"/>',
    '<circle cx="', f(x), '" cy="', f(y), '" r="25" fill="#f1f6ff" opacity="0.95"/>',
    '<circle cx="', f(x - 8), '" cy="', f(y - 6), '" r="5" fill="#c8d6e8" opacity="0.35"/>',
    '<circle cx="', f(x + 7), '" cy="', f(y + 8), '" r="3.5" fill="#c8d6e8" opacity="0.28"/>',
  })
end

local function clouds(colors, variant)
  local rainy = variant:match("rain") or variant:match("thunder") or variant:match("cloudy")
    or variant:match("fog") or variant:match("snow")
  if not rainy then
    return ""
  end
  local random = rng(hash(variant) + 33)
  local out = { '<g filter="url(#soft)">' }
  local count = variant:match("fog") and 3 or 4
  for index = 1, count do
    local x = random() * M.WIDTH
    local base_y = 42 + random() * 100
    local thunder = variant:match("thunder") ~= nil
    local rain = variant:match("rain") ~= nil
    local foggy = variant:match("fog") ~= nil
    local opacity = thunder and 0.62 or (rain and 0.58 or (foggy and 0.10 or 0.13))
    local fill = (thunder or rain) and "#09111a" or "#dfe9f2"
    for part = 1, 5 do
      local cx = x + (part - 3) * 34
      local cy = base_y + math.sin(part * 1.8 + index) * 8
      local radius = 30 + (part % 3) * 12
      out[#out + 1] = string.format(
        '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" opacity="%s"/>',
        f(cx), f(cy), f(radius), f(radius * 0.55), fill, f(opacity)
      )
    end
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end

local function rain()
  local random = rng(hash("rain"))
  local out = { '<g stroke="#a9cfe8" stroke-linecap="round">' }
  for index = 1, 64 do
    local x = random() * M.WIDTH
    local y = random() * M.HEIGHT
    local length = 12 + random() * 20
    local opacity = 0.18 + random() * 0.42
    out[#out + 1] = string.format(
      '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke-width="1.1" opacity="%s"/>',
      f(x), f(y), f(x - 4), f(y + length), f(opacity)
    )
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end

local function snow()
  local random = rng(hash("snow"))
  local out = { '<g fill="#eaf6ff">' }
  for index = 1, 54 do
    local x = random() * M.WIDTH
    local y = random() * M.HEIGHT
    local radius = 1 + random() * 2.3
    local opacity = 0.35 + random() * 0.55
    out[#out + 1] = string.format(
      '<circle cx="%s" cy="%s" r="%s" opacity="%s"/>',
      f(x), f(y), f(radius), f(opacity)
    )
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end

local function lightning()
  return table.concat({
    '<g stroke="#eef6ff" fill="none" stroke-linecap="round" stroke-linejoin="round">',
    '<polyline points="590,55 572,128 595,128 556,212 612,122 586,122 620,55" stroke-width="7" opacity="0.12"/>',
    '<polyline points="590,55 572,128 595,128 556,212 612,122 586,122 620,55" stroke-width="2.4" opacity="0.95"/>',
    "</g>",
  })
end

local function fog()
  local out = { '<g fill="#dbe6ec">' }
  for index = 1, 5 do
    local y = 130 + index * 44
    local opacity = 0.05 + (index % 2) * 0.025
    out[#out + 1] = string.format(
      '<rect x="-40" y="%s" width="880" height="28" rx="14" opacity="%s"/>',
      f(y), f(opacity)
    )
  end
  out[#out + 1] = "</g>"
  return table.concat(out)
end

local function grass(colors)
  local random = rng(hash(colors.ground) + 17)
  local out = {
    '<rect x="0" y="', f(M.HEIGHT - 26), '" width="', f(M.WIDTH), '" height="26" fill="', colors.ground, '"/>',
  }
  -- Back layer: taller, slightly lighter blades.
  for layer = 1, 2 do
    local count = layer == 1 and 86 or 122
    local fill = layer == 1 and colors.ground or "#000000"
    local base_y = M.HEIGHT - 20 + layer * 2
    for index = 1, count do
      local x = (index / count) * M.WIDTH + (random() - 0.5) * 10
      local height = (layer == 1 and 26 or 16) + random() * (layer == 1 and 36 or 28)
      local width = 3 + random() * 6
      local lean = (random() - 0.5) * 8
      out[#out + 1] = string.format(
        '<path d="M %s %s Q %s %s %s %s Q %s %s %s %s Z" fill="%s" opacity="%s"/>',
        f(x - width / 2), f(base_y),
        f(x + lean), f(base_y - height * 0.55),
        f(x + lean * 0.4), f(base_y - height),
        f(x + lean * 0.7), f(base_y - height * 0.45),
        f(x + width / 2), f(base_y),
        fill, layer == 1 and "0.85" or "0.95"
      )
    end
  end
  return table.concat(out)
end

function M.variant(category, is_day)
  local safe = category or "clear"
  if safe ~= "clear" and safe ~= "cloudy" and safe ~= "rain"
    and safe ~= "snow" and safe ~= "thunder" and safe ~= "fog"
  then
    safe = "cloudy"
  end
  return safe .. (is_day and "_day" or "_night")
end

function M.svg(variant)
  local colors = palette(variant)
  local parts = {
    '<svg xmlns="http://www.w3.org/2000/svg" width="', tostring(M.WIDTH), '" height="', tostring(M.HEIGHT),
    '" viewBox="0 0 ', tostring(M.WIDTH), ' ', tostring(M.HEIGHT), '">',
    defs(colors),
    '<rect width="', tostring(M.WIDTH), '" height="', tostring(M.HEIGHT), '" fill="url(#sky)"/>',
    stars(colors, variant),
    celestial(colors, variant),
    clouds(colors, variant),
  }
  if variant:match("rain") then
    parts[#parts + 1] = rain()
  elseif variant:match("snow") then
    parts[#parts + 1] = snow()
  elseif variant:match("thunder") then
    parts[#parts + 1] = rain()
    parts[#parts + 1] = lightning()
  elseif variant:match("fog") then
    parts[#parts + 1] = fog()
  end
  parts[#parts + 1] = grass(colors)
  parts[#parts + 1] = '<rect width="'
  parts[#parts + 1] = tostring(M.WIDTH)
  parts[#parts + 1] = '" height="'
  parts[#parts + 1] = tostring(M.HEIGHT)
  parts[#parts + 1] = '" fill="url(#shade)"/>'
  parts[#parts + 1] = '<rect width="'
  parts[#parts + 1] = tostring(M.WIDTH)
  parts[#parts + 1] = '" height="'
  parts[#parts + 1] = tostring(M.HEIGHT)
  parts[#parts + 1] = '" fill="url(#vignette)"/>'
  parts[#parts + 1] = "</svg>"
  return table.concat(parts)
end

-- Write the static image for one variant into pluginDataDir()/scenes/<variant>/.
-- The image is rewritten when the variant is selected again, so generator or art
-- changes are picked up without a separate cache-version bump.
function M.write(dir, variant)
  if type(dir) ~= "string" or dir == "" then
    return nil, "no data directory"
  end
  local folder = dir .. "/scenes/" .. variant
  local ok, err = noctalia.mkdirAll(folder)
  if ok == false then
    return nil, err or "mkdir failed"
  end
  local path = folder .. "/scene.svg"
  local written, write_err = noctalia.writeFile(path, M.svg(variant))
  if written == false then
    return nil, write_err or "write failed"
  end
  -- Remove frames written by older animated versions when this variant is
  -- regenerated.
  for index = 0, 5 do
    noctalia.removeFile(folder .. "/frame-" .. tostring(index) .. ".svg")
  end
  return path
end

return M
