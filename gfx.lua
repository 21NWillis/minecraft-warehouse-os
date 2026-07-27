-- gfx: thin helpers over the CC:Graphics pixel API (CraftOS-PC compatible).
-- Works on any target (monitor or term) that reports setGraphicsMode.
-- Falls back gracefully: gfx.available(t) tells you if pixel mode is usable.
local gfx = {}

local HEX = "0123456789abcdef"
local function hexOf(color)
  -- palette color (a power of two) -> single hex digit index
  local n = 0
  local c = color
  while c > 1 do c = c / 2; n = n + 1 end
  return HEX:sub(n + 1, n + 1)
end

function gfx.available(t)
  return type(t.setGraphicsMode) == "function"
end

-- enter pixel mode; returns pixel width, height (or nil if unavailable)
function gfx.begin(t)
  if not gfx.available(t) then return nil end
  local ok = pcall(t.setGraphicsMode, 1)
  if not ok then return nil end
  local w, h = t.getSize(1)
  return w, h
end

function gfx.finish(t)
  pcall(t.setGraphicsMode, 0)
end

-- filled rectangle via one drawPixels batch per rect (fast)
function gfx.rect(t, x, y, w, h, color)
  if w <= 0 or h <= 0 then return end
  local row = string.rep(hexOf(color), w)
  local rows = {}
  for i = 1, h do rows[i] = row end
  pcall(t.drawPixels, x, y, rows)
end

function gfx.clear(t, w, h, color)
  gfx.rect(t, 0, 0, w, h, color or colors.black)
end

function gfx.hline(t, x, y, w, color)
  gfx.rect(t, x, y, w, 1, color)
end

function gfx.vline(t, x, y, h, color)
  gfx.rect(t, x, y, 1, h, color)
end

-- vertical bar growing upward from a baseline, for charts
function gfx.barUp(t, x, baselineY, w, value, maxValue, height, color)
  local frac = maxValue > 0 and math.min(1, value / maxValue) or 0
  local h = math.floor(frac * height + 0.5)
  if h > 0 then gfx.rect(t, x, baselineY - h, w, h, color) end
  return h
end

-- tiny 3x5 pixel digits for labels in graphics mode (0-9, no font available)
local DIGITS = {
  ["0"] = { "111", "101", "101", "101", "111" },
  ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" },
  ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" },
  ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" },
  ["7"] = { "111", "001", "010", "010", "010" },
  ["8"] = { "111", "101", "111", "101", "111" },
  ["9"] = { "111", "101", "111", "001", "111" },
  ["k"] = { "101", "110", "100", "110", "101" },
  ["M"] = { "101", "111", "111", "101", "101" },
  ["."] = { "000", "000", "000", "000", "010" },
  [" "] = { "000", "000", "000", "000", "000" },
}

function gfx.text(t, x, y, str, color)
  local cx = x
  for i = 1, #str do
    local glyph = DIGITS[str:sub(i, i)]
    if glyph then
      for row = 1, 5 do
        local bits = glyph[row]
        for col = 1, 3 do
          if bits:sub(col, col) == "1" then
            pcall(t.setPixel, cx + col - 1, y + row - 1, color)
          end
        end
      end
    end
    cx = cx + 4
  end
end

return gfx
