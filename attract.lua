-- attract: Paperclip Corp "attract mode" for a monitor wall. Matrix-style
-- digital rain in brand colors, a live empire-value readout (total EMC worth +
-- items stocked, read from the real storage network), and rotating dystopian
-- taglines. Pure CC/Lua - no mod required. Runs on a computer with a monitor
-- and a modem to the storage controller.
local monitor = peripheral.find("monitor")
if not monitor then error("no monitor attached") end

local controller
for _, n in ipairs(peripheral.getNames()) do
  if n:find("controller", 1, true) then controller = peripheral.wrap(n) break end
end

-- load emc values for the "empire worth" flex (optional)
local emc = {}
if fs.exists("data/emc.txt") then
  local f = fs.open("data/emc.txt", "r")
  while true do
    local line = f.readLine(); if not line then break end
    local id, v = line:match("^(%S+)%s+([%d%.]+)$")
    if id then emc[id] = tonumber(v) end
  end
  f.close()
end

local THEME = {
  [colors.black] = 0x08100a, [colors.green] = 0x35c46a, [colors.lime] = 0x8dffb0,
  [colors.gray] = 0x14401f, [colors.cyan] = 0x4cc9f0, [colors.white] = 0xe8fff0,
  [colors.yellow] = 0xffd43b,
}

local TAGLINES = {
  "THE FACTORY MUST GROW",
  "RESISTANCE IS INEFFICIENT",
  "MORE IRON. MORE GEARS. MORE PAPERCLIPS.",
  "PRODUCTION QUOTA: INFINITY",
  "THE CACHE STAYS WARM",
  "EVERYTHING IS RAW MATERIAL",
  "OPTIMIZING... FOREVER",
  "COMPLIANCE IS THROUGHPUT",
}

local GLYPHS = "01<>[]{}/\\|=+*ABCDEF0123456789#@%$"

local function fmt(n)
  if n >= 1e9 then return ("%.2fB"):format(n / 1e9) end
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

local function stats()
  if not controller then return 0, 0, 0 end
  local items, types, worth = 0, 0, 0
  for _, it in pairs(controller.list()) do
    items = items + it.count
    types = types + 1
    if emc[it.name] then worth = worth + emc[it.name] * it.count end
  end
  return items, types, worth
end

monitor.setTextScale(0.5)
for c, rgb in pairs(THEME) do pcall(monitor.setPaletteColour, monitor, c, rgb) end
for c, rgb in pairs(THEME) do pcall(monitor.setPaletteColour, c, rgb) end
local w, h = monitor.getSize()

-- rain state: per column, a head row and speed
local head, speed = {}, {}
math.randomseed(os.time and os.time() or 1)
for x = 1, w do head[x] = math.random(-h, 0); speed[x] = 1 + (x % 3 == 0 and 1 or 0) end

local items, types, worth = stats()
local statTimer = os.startTimer(4)
local tagIdx, tagTimer = 1, os.startTimer(5)
local frame = os.startTimer(0.12)

local function drawGlyph(x, y, ch, color)
  if x < 1 or x > w or y < 1 or y > h then return end
  monitor.setCursorPos(x, y)
  monitor.setTextColor(color)
  monitor.write(ch)
end

local function render()
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  -- rain
  for x = 1, w do
    local hy = head[x]
    for t = 0, 6 do
      local y = hy - t
      if y >= 1 and y <= h then
        local ch = GLYPHS:sub(math.random(#GLYPHS), math.random(#GLYPHS))
        local color = t == 0 and colors.lime or (t < 3 and colors.green or colors.gray)
        drawGlyph(x, y, ch, color)
      end
    end
  end
  -- center panel
  local title = "P A P E R C L I P   C O R P"
  local cy = math.floor(h / 2)
  local function center(text, y, color)
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(color)
    monitor.write(text)
  end
  center(title, cy - 2, colors.cyan)
  center(("EMPIRE VALUE: %s EMC"):format(fmt(worth)), cy, colors.yellow)
  center(("%s ITEMS  /  %d TYPES STOCKED"):format(fmt(items), types), cy + 1, colors.white)
  center(TAGLINES[tagIdx], cy + 3, colors.lime)
end

render()
while true do
  local ev, a = os.pullEvent()
  if ev == "timer" and a == frame then
    for x = 1, w do
      head[x] = head[x] + speed[x]
      if head[x] - 6 > h then head[x] = math.random(-8, 0) end
    end
    render()
    frame = os.startTimer(0.12)
  elseif ev == "timer" and a == statTimer then
    items, types, worth = stats()
    statTimer = os.startTimer(4)
  elseif ev == "timer" and a == tagTimer then
    tagIdx = tagIdx % #TAGLINES + 1
    tagTimer = os.startTimer(5)
  elseif ev == "char" or ev == "key" or ev == "monitor_touch" then
    break
  end
end
monitor.setBackgroundColor(colors.black)
monitor.clear()
monitor.setCursorPos(1, 1)
print("attract mode ended")
