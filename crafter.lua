-- crafter: turtle agent for the gigafactory
-- setup: place a CRAFTY turtle adjacent to a full-block wired modem on the
-- network, then on the turtle:
--   wget https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/crafter.lua startup.lua
--   reboot
local PROTO = "gigafactory"

local modemSide, localName
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "modem" then
    local m = peripheral.wrap(side)
    if m.getNameLocal then
      modemSide = side
      localName = m.getNameLocal()
      break
    end
  end
end
if not localName then
  error("no wired modem found - place me against a full-block wired modem and right-click it")
end
rednet.open(modemSide)
print("crafter online as " .. localName)

local function hello()
  rednet.broadcast({ type = "hello", name = localName }, PROTO)
end

hello()
local lastHello = os.clock()
local HEARTBEAT = 5   -- keep the warehouse roster fresh without spamming
while true do
  if os.clock() - lastHello > HEARTBEAT then
    hello()
    lastHello = os.clock()
  end
  local senderId, msg = rednet.receive(PROTO, HEARTBEAT)
  if senderId and type(msg) == "table" then
    if msg.type == "ping" then
      hello()
    elseif msg.type == "craft" then
      local ok, err = turtle.craft(msg.times or 1)
      rednet.send(senderId, { type = "done", ok = ok or false, err = err, name = localName }, PROTO)
    end
  end
end
