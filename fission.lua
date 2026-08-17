-- fission: Mekanism fission reactor operator (ATM10 power plant).
-- Watchdogged ignition and continuous safety governor: temperature,
-- damage, waste, and coolant interlocks with automatic scram.
-- Doctrine: blindness is breach-class; fail closed, always.
--
-- Setup: wired modems (activated) on the Fission Reactor Logic
-- Adapter, a Turbine Valve, and this computer.
-- Run:  fission <burnRate mB/t>     e.g. fission 1
--       fission scram               manual emergency stop
--
-- Safety lines (Mek: damage starts above 1200K):
local TEMP_WARN   = 800    -- K: hold burn, no increases
local TEMP_SCRAM  = 1000   -- K: scram (200K of margin below damage)
local WASTE_SCRAM = 0.90   -- waste tank fraction full
local COOL_SCRAM  = 0.10   -- coolant fraction empty line
local LOOP_S      = 1

local args = { ... }

-- duck-typed discovery: the logic adapter quacks setBurnRate
local reactor, turbine
for _, n in ipairs(peripheral.getNames()) do
  local m = {}
  for _, name in ipairs(peripheral.getMethods(n) or {}) do m[name] = true end
  if m.setBurnRate and m.scram then reactor = peripheral.wrap(n) print("reactor: " .. n) end
  if m.getProductionRate or m.getFlowRate then turbine = peripheral.wrap(n) print("turbine: " .. n) end
end
assert(reactor, "fission: no logic adapter on the network")

local function call(p, fn, ...)
  if not p or type(p[fn]) ~= "function" then return nil end
  local ok, res = pcall(p[fn], ...)
  if ok then return res end
  return nil
end

for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then pcall(rednet.open, n) end
end

local function scram(reason)
  call(reactor, "scram")
  print("!! SCRAM: " .. reason)
  rednet.broadcast({ station = "fission", kind = "scram", detail = reason }, "paperclip.power")
end

if args[1] == "scram" then
  scram("operator command")
  return
end

local burnTarget = tonumber(args[1])
if not burnTarget then
  print("usage: fission <burnRate mB/t> | fission scram")
  return
end

-- preflight: everything readable, tanks sane, then ignite
local temp = call(reactor, "getTemperature")
if temp == nil then
  print("preflight FAIL: temperature unreadable - not igniting blind")
  return
end
local coolant = call(reactor, "getCoolantFilledPercentage")
if coolant ~= nil and coolant < COOL_SCRAM then
  print(("preflight FAIL: coolant at %d%% - prime the water loop first"):format(coolant * 100))
  return
end

call(reactor, "setBurnRate", burnTarget)
local ok = pcall(function() reactor.activate() end)
print(("ignition: burn %.1f mB/t (activate %s)"):format(burnTarget, ok and "ok" or "FAILED - GUI it"))
rednet.broadcast({ station = "fission", kind = "ignition", burn = burnTarget }, "paperclip.power")

local lastBeat = 0
while true do
  local t   = call(reactor, "getTemperature")
  local dmg = call(reactor, "getDamagePercent")
  local wst = call(reactor, "getWasteFilledPercentage")
  local col = call(reactor, "getCoolantFilledPercentage")
  local act = call(reactor, "getStatus")

  if t == nil then
    scram("temperature unreadable (blindness)")
    break
  elseif dmg ~= nil and dmg > 0 then
    scram(("DAMAGE %s%%"):format(tostring(dmg)))
    break
  elseif t >= TEMP_SCRAM then
    scram(("temp %dK >= %dK"):format(math.floor(t), TEMP_SCRAM))
    break
  elseif wst ~= nil and wst >= WASTE_SCRAM then
    scram(("waste %d%% full - barrels!"):format(math.floor(wst * 100)))
    break
  elseif col ~= nil and col <= COOL_SCRAM then
    scram(("coolant %d%% - water loop failed"):format(math.floor(col * 100)))
    break
  end

  if t >= TEMP_WARN then
    print(("warm: %dK (holding, no burn increases)"):format(math.floor(t)))
  end

  local now = os.clock()
  if now - lastBeat >= 5 then
    lastBeat = now
    local prod = call(turbine, "getProductionRate")
    local line = ("%dK | dmg %s%% | waste %d%% | coolant %d%% | %s"):format(
      math.floor(t), tostring(dmg or 0), math.floor((wst or 0) * 100),
      math.floor((col or 0) * 100),
      prod and (tostring(math.floor(prod)) .. " prod") or "turbine n/a")
    print(line)
    rednet.broadcast({ station = "fission", kind = "telemetry",
      temp = t, dmg = dmg, waste = wst, coolant = col, prod = prod,
      active = act }, "paperclip.power")
  end
  sleep(LOOP_S)
end
print("fission: governor exited after scram - reactor is DOWN. Investigate, then rerun.")
