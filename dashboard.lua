-- dashboard: standalone factory status wall for a monitor.
-- Place a computer with an Advanced Monitor, wire a modem to the storage
-- controller, then run `dashboard`. Renders live stock as pixel bar charts
-- with a top-10 leaderboard and a running clock. Uses CC:Graphics pixel mode
-- if the monitor supports it, else falls back to a text bar chart.
local gfx = require("gfx")

local controller
for _, name in ipairs(peripheral.getNames()) do
  if name:find("controller", 1, true) then
    controller = peripheral.wrap(name)
    break
  end
end
if not controller then error("no storage controller on the network") end

local monitor = peripheral.find("monitor")
if not monitor then error("no monitor found") end
monitor.setTextScale(0.5)

local db
do
  local ok, mod = pcall(require, "recipedb")
  if ok and mod.load("data") then db = mod end
end
local function name(id)
  if db then return db.name(id) end
  local p = id:gsub("^[^:]+:", ""):gsub("_", " ")
  return p:sub(1, 1):upper() .. p:sub(2)
end

local function fmt(n)
  if n >= 1000000 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(n)
end

local function topItems(limit)
  local counts = {}
  for _, item in pairs(controller.list()) do
    counts[item.name] = (counts[item.name] or 0) + item.count
  end
  local sorted = {}
  for id, c in pairs(counts) do sorted[#sorted + 1] = { id = id, count = c } end
  table.sort(sorted, function(a, b) return a.count > b.count end)
  local total, types = 0, 0
  for _, e in pairs(sorted) do total = total + e.count; types = types + 1 end
  while #sorted > limit do sorted[#sorted] = nil end
  return sorted, total, types
end

local PALETTE = { colors.cyan, colors.green, colors.orange, colors.yellow,
                  colors.red, colors.lightBlue, colors.lime, colors.magenta,
                  colors.pink, colors.white }

local function renderPixels(pw, ph)
  local top, total, types = topItems(10)
  gfx.clear(monitor, pw, ph, colors.black)
  gfx.rect(monitor, 0, 0, pw, 12, colors.blue)
  gfx.text(monitor, 3, 3, fmt(total), colors.white)
  gfx.text(monitor, pw - 40, 3, fmt(types), colors.cyan)

  local maxCount = top[1] and top[1].count or 1
  local barsTop = 16
  local baseline = ph - 14
  local barH = baseline - barsTop
  local slotW = math.floor(pw / 10)
  local barW = slotW - 3
  for i, e in ipairs(top) do
    local x = (i - 1) * slotW + 2
    local color = PALETTE[i] or colors.white
    gfx.barUp(monitor, x, baseline, barW, e.count, maxCount, barH, color)
    gfx.text(monitor, x, baseline + 2, fmt(e.count):gsub("%.%d", ""), color)
  end
  gfx.hline(monitor, 0, baseline + 1, pw, colors.gray)
end

local function renderText()
  local top, total, types = topItems(10)
  local w, h = monitor.getSize()
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  monitor.setCursorPos(1, 1)
  monitor.setTextColor(colors.yellow)
  monitor.write(("FACTORY  %s items / %d types"):format(fmt(total), types))
  local maxCount = top[1] and top[1].count or 1
  for i, e in ipairs(top) do
    local y = i + 2
    if y > h then break end
    monitor.setCursorPos(1, y)
    monitor.setTextColor(PALETTE[i] or colors.white)
    local barLen = math.floor((e.count / maxCount) * (w - 16))
    monitor.write(string.rep("\149", barLen))
    monitor.setCursorPos(w - 14, y)
    monitor.write(("%-9s%5s"):format(name(e.id):sub(1, 9), fmt(e.count)))
  end
end

local usePixels = false
local pw, ph = gfx.begin(monitor)
if pw and ph then usePixels = true end

local ok, err = pcall(function()
  while true do
    if usePixels then renderPixels(pw, ph) else renderText() end
    sleep(3)
  end
end)

if usePixels then gfx.finish(monitor) end
if not ok then error(err) end
