-- melink: link every ME/storage system on the server into one market. Each
-- base runs `melink node` (beacons its controller's summary over the Starlink
-- mesh); a central `melink hub` discovers them all and shows a server-wide,
-- EMC-valued rollup. Pure CC/Lua over ender modems - no mod. Paperclip Corp,
-- indexing every faction's storage.
local starlink = require("starlink")

local emc = require("emcload").load()

local function fmt(n)
  if n >= 1e9 then return ("%.2fB"):format(n / 1e9) end
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

local function localController()
  for _, n in ipairs(peripheral.getNames()) do
    if n:find("controller", 1, true) then return peripheral.wrap(n) end
  end
end

local function summarize(c)
  local items, types, worth = 0, 0, 0
  for _, it in pairs(c.list()) do
    items = items + it.count
    types = types + 1
    if emc[it.name] then worth = worth + emc[it.name] * it.count end
  end
  return { items = items, types = types, worth = worth }
end

local mode = ({ ... })[1] or "hub"
local name = os.getComputerLabel() or ("node-" .. os.getComputerID())

if mode == "node" then
  local c = localController()
  if not c then error("no storage controller on this base's network") end
  local net = starlink.new(name, "me-node")
  print("melink node: broadcasting " .. name .. "'s ME summary to the mesh")
  local beat = os.startTimer(0)
  local rescan = os.startTimer(0)
  local summary = { items = 0, types = 0, worth = 0 }
  while true do
    net:pump(0.3)
    local ev, a = os.pullEvent()
    if ev == "timer" and a == rescan then
      summary = summarize(c)
      net:setTelemetry(summary)
      rescan = os.startTimer(10)
    elseif ev == "timer" and a == beat then
      net:beacon()
      beat = os.startTimer(5)
    end
  end

elseif mode == "hub" then
  local net = starlink.new(name, "hub")
  local monitor = peripheral.find("monitor")
  print("melink hub: discovering ME systems on the mesh...")
  net:beacon()
  local refresh = os.startTimer(3)
  local ping = os.startTimer(2)
  local function render()
    local peers = net:list()
    local nodes, items, types, worth, live = 0, 0, 0, 0, 0
    local out = {}
    for _, p in ipairs(peers) do
      if p.role == "me-node" then
        nodes = nodes + 1
        local t = p.telem or {}
        items = items + (t.items or 0)
        types = types + (t.types or 0)
        worth = worth + (t.worth or 0)
        if p.age < 15 then live = live + 1 end
        out[#out + 1] = { node = p.node, t = t, rtt = p.rtt, age = p.age }
      end
    end
    local function line(s) print(s) end
    if monitor then
      monitor.setTextScale(0.5); monitor.setBackgroundColor(colors.black); monitor.clear()
      monitor.setCursorPos(1, 1); monitor.setTextColor(colors.cyan)
      monitor.write(("PAPERCLIP NETWORK  %d/%d systems linked"):format(live, nodes))
      monitor.setCursorPos(1, 2); monitor.setTextColor(colors.yellow)
      monitor.write(("SERVER-WIDE: %s items  %s EMC"):format(fmt(items), fmt(worth)))
      for i, o in ipairs(out) do
        monitor.setCursorPos(1, 3 + i)
        monitor.setTextColor(o.age < 15 and colors.lime or colors.gray)
        monitor.write(("%-14s %6s items  %6s EMC%s"):format(
          o.node:sub(1, 14), fmt(o.t.items or 0), fmt(o.t.worth or 0),
          o.rtt and ("  " .. o.rtt .. "ms") or ""))
      end
    else
      print(("-- %d/%d ME systems linked --"):format(live, nodes))
      print(("SERVER-WIDE: %s items, %s EMC"):format(fmt(items), fmt(worth)))
      for _, o in ipairs(out) do
        print(("  %-14s %s items  %s EMC"):format(o.node, fmt(o.t.items or 0), fmt(o.t.worth or 0)))
      end
    end
  end
  while true do
    net:pump(0.3)
    local ev, a = os.pullEvent()
    if ev == "timer" and a == refresh then net:reap(30); render(); refresh = os.startTimer(3)
    elseif ev == "timer" and a == ping then net:beacon(); ping = os.startTimer(2)
    elseif ev == "char" then break end
  end
else
  print("melink node   - beacon this base's ME summary to the mesh")
  print("melink hub    - aggregate every linked ME system server-wide")
end
