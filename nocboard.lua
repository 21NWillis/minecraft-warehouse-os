-- nocboard: the NOC monitor dashboard. Listens for the warehouse's wireless
-- index broadcast (protocol paperclip.wh) and renders holdings priced in EMC
-- on the monitor wall: total portfolio value, top positions, freshness.
--
-- Needs: a wireless modem clicked onto THIS computer, a monitor (the nocfit
-- wall attaches as "top"), and the warehouse running somewhere in wireless
-- range with its own wireless modem. Run: nocboard
local emcload = require("emcload")

local mon = peripheral.find("monitor")
if not mon then
  print("no monitor attached - nocboard needs the monitor wall")
  return
end
local opened = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    pcall(rednet.open, side)
    opened = true
  end
end
if not opened then
  print("no modem attached - click a wireless modem onto this computer")
  return
end

print("loading EMC prices...")
local emc = emcload.load()
print("nocboard live; listening for the warehouse broadcast")

mon.setTextScale(0.5)
local W, H = mon.getSize()
local color = mon.isColor()

local function line(y, text, fg)
  if y > H then return end
  if color then mon.setTextColor(fg or colors.white) end
  mon.setCursorPos(1, y)
  mon.write(text:sub(1, W))
end

local function fmt(n)
  if n >= 1e9 then return ("%.2fB"):format(n / 1e9) end
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

local last, lastAt = nil, 0
while true do
  local id, msg = rednet.receive("paperclip.wh", 10)
  if id and type(msg) == "table" and msg.t == "wh_index" then
    last, lastAt = msg, os.clock()
  end
  mon.setBackgroundColor(colors.black)
  mon.clear()
  line(1, "PAPERCLIP EXCHANGE - THE FLOOR IS OPEN", colors.cyan)
  if not last then
    line(3, "waiting for the warehouse broadcast...", colors.lightGray)
    line(4, "(warehouse computer needs a wireless modem +", colors.gray)
    line(5, " the warehouse program running)", colors.gray)
  else
    local age = os.clock() - lastAt
    local valued = {}
    local portfolio = 0
    for _, it in ipairs(last.items) do
      local v = (emc[it.id] or 0) * it.count
      portfolio = portfolio + v
      valued[#valued + 1] = { id = it.id, count = it.count, value = v }
    end
    table.sort(valued, function(a, b) return a.value > b.value end)
    line(2, ("PORTFOLIO %s EMC   %s items / %s kinds"):format(
      fmt(portfolio), fmt(last.total), tostring(last.distinct)),
      colors.yellow)
    line(3, ("feed: %ds ago%s"):format(math.floor(age),
      age > 30 and "  (STALE)" or ""), age > 30 and colors.red or colors.gray)
    local y = 5
    line(y - 1, ("%-24s %10s %12s"):format("POSITION", "QTY", "VALUE"), colors.lightGray)
    for i = 1, math.min(#valued, H - y) do
      local v = valued[i]
      local shortId = v.id:gsub("^[^:]+:", "")
      line(y, ("%-24s %10s %12s"):format(shortId:sub(1, 24), fmt(v.count), fmt(v.value)),
        i <= 3 and colors.lime or colors.white)
      y = y + 1
    end
  end
end
