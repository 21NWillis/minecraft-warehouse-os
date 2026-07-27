-- starlink_map: ground-station view of the mesh. Shows every node, its role,
-- live round-trip latency, telemetry, and link health. Run on a computer with
-- any modem (ender modem to see orbital / cross-dimension nodes).
local starlink = require("starlink")

local net = starlink.new(os.getComputerLabel() or ("ground-" .. os.getComputerID()), "ground")

local function bar(rtt)
  if not rtt then return "----" end
  if rtt < 100 then return "||||" end
  if rtt < 250 then return "|||." end
  if rtt < 600 then return "||.." end
  return "|..."
end

local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  local w = term.getSize()
  term.write("STARLINK  " .. net.node)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(1, 2)
  term.write(string.rep("-", w))

  local peers = net:list()
  local y = 3
  if #peers == 0 then
    term.setCursorPos(1, y)
    term.setTextColor(colors.gray)
    term.write("no nodes in range - is an ender modem attached?")
  end
  for _, p in ipairs(peers) do
    if y > select(2, term.getSize()) - 1 then break end
    term.setCursorPos(1, y)
    local online = p.age < 12
    term.setTextColor(online and colors.lime or colors.red)
    term.write(bar(p.rtt))
    term.setTextColor(colors.white)
    term.write((" %-12s"):format(p.node:sub(1, 12)))
    term.setTextColor(colors.lightBlue)
    term.write((" %-8s"):format(p.role:sub(1, 8)))
    term.setTextColor(colors.yellow)
    term.write(p.rtt and (" %4dms"):format(p.rtt) or "   --  ")
    -- telemetry: show altitude if present (orbital nodes)
    local t = p.telem or {}
    if t.alt then
      term.setTextColor(t.alt >= 300 and colors.magenta or colors.green)
      term.write((" alt %d%s"):format(math.floor(t.alt), t.alt >= 300 and " ORBIT" or ""))
    end
    y = y + 1
  end

  term.setCursorPos(1, select(2, term.getSize()))
  term.setTextColor(colors.gray)
  term.write("q quits")
end

net:beacon()
local beaconTimer = os.startTimer(3)
local pingTimer = os.startTimer(2)
draw()

while true do
  net:pump(0.3)
  local ev, a = os.pullEvent()
  if ev == "timer" and a == beaconTimer then
    net:beacon(); net:reap(30); beaconTimer = os.startTimer(3); draw()
  elseif ev == "timer" and a == pingTimer then
    net:ping(); pingTimer = os.startTimer(2); draw()
  elseif ev == "char" and a == "q" then
    break
  elseif ev == "rednet_message" then
    draw()
  end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
