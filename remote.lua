-- remote: a pocket-computer console for the Paperclip network. Joins the
-- Starlink mesh over an (ender) modem and shows live status from anywhere -
-- linked ME systems, crafter turtles, and per-node latency - plus a key to
-- broadcast a PA announcement to the base. Pure CC/Lua. Run on a pocket
-- computer with a wireless/ender modem (or any computer with one).
local starlink = require("starlink")

local net = starlink.new(os.getComputerLabel() or ("pocket-" .. os.getComputerID()), "remote")

local function fmt(n)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

-- also ping the gigafactory protocol to count crafter turtles
local function crafterCount()
  rednet.broadcast({ type = "ping" }, "gigafactory")
  local seen = {}
  local deadline = os.epoch("utc") + 700
  while os.epoch("utc") < deadline do
    local id, msg = rednet.receive("gigafactory", 0.2)
    if type(msg) == "table" and msg.type == "hello" then seen[msg.name] = true end
  end
  local n = 0; for _ in pairs(seen) do n = n + 1 end
  return n
end

local crafters = 0
local function draw()
  term.setBackgroundColor(colors.black); term.clear()
  term.setCursorPos(1, 1); term.setTextColor(colors.cyan)
  print("PAPERCLIP REMOTE")
  term.setTextColor(colors.lightGray)
  local peers = net:list()
  local me, items, worth = 0, 0, 0
  for _, p in ipairs(peers) do
    if p.role == "me-node" then
      me = me + 1
      items = items + ((p.telem or {}).items or 0)
      worth = worth + ((p.telem or {}).worth or 0)
    end
  end
  print(("ME systems: %d  items %s"):format(me, fmt(items)))
  print(("empire: %s EMC"):format(fmt(worth)))
  print(("crafters: %d"):format(crafters))
  print("")
  term.setTextColor(colors.gray)
  for _, p in ipairs(peers) do
    if p.age < 20 then
      print((" %s %s%s"):format(p.role:sub(1, 8), p.node:sub(1, 10),
        p.rtt and ("  " .. p.rtt .. "ms") or ""))
    end
  end
  local _, h = term.getSize()
  term.setCursorPos(1, h); term.setTextColor(colors.white)
  term.write("[p]a taunt  [r]efresh  [q]uit")
end

net:beacon()
draw()
local refresh = os.startTimer(3)
local ping = os.startTimer(2)
while true do
  net:pump(0.2)
  local ev, a = os.pullEvent()
  if ev == "timer" and a == refresh then
    net:reap(30); draw(); refresh = os.startTimer(3)
  elseif ev == "timer" and a == ping then
    net:beacon(); ping = os.startTimer(2)
  elseif ev == "rednet_message" then
    draw()
  elseif ev == "char" then
    if a == "q" then break
    elseif a == "r" then crafters = crafterCount(); draw()
    elseif a == "p" then
      rednet.broadcast({ pa = "REMOTE OVERRIDE: THE FACTORY IS WATCHED.", jingle = "alert" }, "pa")
      draw()
    end
  end
end
term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
print("remote closed")
