-- exchange: the Paperclip Exchange - a live stock ticker for your factory.
-- Values every item in storage at its EMC price (from tools/emc.py) and scrolls
-- a market ticker across a monitor: holdings, prices, and movement arrows (how
-- your stock of each changed since the last snapshot). Header shows total
-- portfolio value. Pure CC/Lua, no mod. Monitor + modem-to-controller.
local monitor = peripheral.find("monitor")
if not monitor then error("no monitor attached") end
local controller
for _, n in ipairs(peripheral.getNames()) do
  if n:find("controller", 1, true) then controller = peripheral.wrap(n) break end
end
if not controller then error("no storage controller on the network") end

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

local function pretty(id) return (id:gsub("^[^:]+:", ""):gsub("_", " "):upper()) end
local function fmt(n)
  if n >= 1e9 then return ("%.2fB"):format(n / 1e9) end
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

monitor.setTextScale(0.5)
pcall(monitor.setPaletteColour, colors.black, 0x0a0e12)
pcall(monitor.setPaletteColour, colors.green, 0x51cf66)
pcall(monitor.setPaletteColour, colors.red, 0xff6b6b)
pcall(monitor.setPaletteColour, colors.cyan, 0x4cc9f0)
local w, h = monitor.getSize()

local prev = {}     -- id -> last count (for movement)
local ticker = ""
local movers = {}   -- {id, delta}
local tickerColors = {}   -- parallel to ticker: color per char

local function snapshot()
  local counts, worth = {}, 0
  for _, it in pairs(controller.list()) do
    counts[it.name] = (counts[it.name] or 0) + it.count
    if emc[it.name] then worth = worth + emc[it.name] * it.count end
  end
  -- build ticker segments for the top holdings by value
  local ranked = {}
  for id, c in pairs(counts) do
    ranked[#ranked + 1] = { id = id, count = c, value = (emc[id] or 0) * c, delta = c - (prev[id] or c) }
  end
  table.sort(ranked, function(a, b) return a.value > b.value end)

  local segs, cols = {}, {}
  movers = {}
  for i = 1, math.min(24, #ranked) do
    local r = ranked[i]
    local arrow = r.delta > 0 and " \24" or (r.delta < 0 and " \25" or "")  -- up/down triangles
    local seg = ("%s %s EMC%s   "):format(pretty(r.id):sub(1, 14), fmt(emc[r.id] or 0),
      r.delta ~= 0 and (arrow .. math.abs(r.delta)) or "")
    local col = r.delta > 0 and colors.green or (r.delta < 0 and colors.red or colors.cyan)
    segs[#segs + 1] = seg
    for _ = 1, #seg do cols[#cols + 1] = col end
    if math.abs(r.delta) > 0 then movers[#movers + 1] = r end
  end
  ticker = table.concat(segs)
  tickerColors = cols
  prev = counts
  local types = 0; for _ in pairs(counts) do types = types + 1 end
  return worth, types
end

local worth, types = snapshot()
local offset = 0
local frame = os.startTimer(0.1)
local snap = os.startTimer(6)

local function drawHeader()
  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.cyan); monitor.setTextColor(colors.black)
  monitor.clearLine()
  monitor.write(" PAPERCLIP EXCHANGE ")
  monitor.setCursorPos(1, 2)
  monitor.setBackgroundColor(colors.black); monitor.setTextColor(colors.cyan)
  monitor.clearLine()
  monitor.write((" PORTFOLIO: %s EMC   LISTINGS: %d"):format(fmt(worth), types))
  -- top movers panel
  for i = 1, math.min(#movers, h - 5) do
    local m = movers[i]
    monitor.setCursorPos(1, 3 + i)
    monitor.setTextColor(m.delta > 0 and colors.green or colors.red)
    monitor.clearLine()
    monitor.write(("%s %s  %s%d"):format(m.delta > 0 and "\24" or "\25",
      pretty(m.id):sub(1, 16), m.delta > 0 and "+" or "-", math.abs(m.delta)))
  end
end

local function drawTicker()
  if #ticker == 0 then return end
  local y = h
  monitor.setCursorPos(1, y)
  monitor.setBackgroundColor(colors.black)
  monitor.clearLine()
  for i = 0, w - 1 do
    local idx = ((offset + i) % #ticker) + 1
    monitor.setCursorPos(i + 1, y)
    monitor.setTextColor(tickerColors[idx] or colors.cyan)
    monitor.write(ticker:sub(idx, idx))
  end
end

drawHeader(); drawTicker()
while true do
  local ev, a = os.pullEvent()
  if ev == "timer" and a == frame then
    offset = (offset + 1) % math.max(1, #ticker)
    drawTicker()
    frame = os.startTimer(0.1)
  elseif ev == "timer" and a == snap then
    worth, types = snapshot()
    drawHeader()
    snap = os.startTimer(6)
  elseif ev == "char" or ev == "monitor_touch" then
    break
  end
end
monitor.setBackgroundColor(colors.black); monitor.clear(); monitor.setCursorPos(1, 1)
print("exchange closed")
