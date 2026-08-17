-- reactorlab: ER2 core characterization sweep (ATM10 power plant).
-- Ramps control rods 90% -> 0%, measures steam production, fuel burn,
-- and temperatures at each level, uploads the curve to pastebin, and
-- prints the relay code. The turbine (vent-all) serves as an infinite
-- steam sink so the core shows its true maximum. Measurement first,
-- blueprint second - the turbine that gets built from this data will
-- be sized to the machine it serves.
--
-- Preconditions: reactor in ACTIVE mode (fluid ports installed, water
-- supplied), turbine formed and connected, wired modems on both
-- computer ports + this computer. Run: reactorlab
-- Runtime: ~4 minutes. Ends with reactor deactivated.

local SETTLE_S  = 12   -- seconds to stabilize after each rod change
local SAMPLES   = 5    -- readings averaged per level
local LEVELS    = { 90, 80, 70, 60, 50, 40, 30, 20, 10, 0 }

local turbine, reactor
for _, n in ipairs(peripheral.getNames()) do
  local m = {}
  for _, name in ipairs(peripheral.getMethods(n) or {}) do m[name] = true end
  if m.getRotorSpeed then turbine = peripheral.wrap(n) end
  if m.setAllControlRodLevels then reactor = peripheral.wrap(n) end
end
assert(reactor, "reactorlab: no reactor computer port on the network")

local function call(p, fn, ...)
  if not p or type(p[fn]) ~= "function" then return nil end
  local ok, res = pcall(p[fn], ...)
  if ok then return res end
  return nil
end

if call(reactor, "isActivelyCooled") == false then
  print("reactor is in PASSIVE mode - install the fluid ports first.")
  return
end

local out = {}
local function emit(s) out[#out + 1] = s print(s) end

emit("== reactorlab sweep ==")
emit("rods: " .. tostring(call(reactor, "getNumberOfControlRods")))
if turbine then
  call(turbine, "setActive", true)
  call(turbine, "setVentAll")                     -- infinite sink mode
  -- coils ENGAGED during the sweep: pure drag bonus that bounds rotor
  -- RPM (vent-all still torques the rotor - learned at 2600 RPM).
  -- Overspeed is an efficiency loss, not destruction (no damage code
  -- in the jar; tooltip's "may fail catastrophically" is flavor), but
  -- a bounded rotor is still better instrumentation.
  call(turbine, "setInductorEngaged", true)
  local hard = call(turbine, "getMaxIntakeRateHardLimit")
  call(turbine, "setFluidFlowRateMax", hard or 2000)
  emit(("turbine sink: intake hard limit %s mB/t, blades %s"):format(
    tostring(hard), tostring(call(turbine, "getNumberOfBlades"))))
else
  emit("NO TURBINE FOUND - steam must vent somehow or readings stall!")
end

call(reactor, "setAllControlRodLevels", 100)
call(reactor, "setActive", true)
sleep(3)

emit("level | steam mB/t | fuel mB/t | fuelT C | coolant")
for _, lvl in ipairs(LEVELS) do
  call(reactor, "setAllControlRodLevels", lvl)
  sleep(SETTLE_S)
  local steam, fuel, temp = 0, 0, 0
  for i = 1, SAMPLES do
    steam = steam + (call(reactor, "getHotFluidProducedLastTick") or 0)
    fuel  = fuel  + (call(reactor, "getFuelConsumedLastTick") or 0)
    temp  = temp  + (call(reactor, "getFuelTemperature") or 0)
    sleep(1)
  end
  steam, fuel, temp = steam / SAMPLES, fuel / SAMPLES, temp / SAMPLES
  local coolant = call(reactor, "getCoolantAmount")
  emit(("%5d | %10.1f | %9.3f | %7.0f | %s"):format(
    lvl, steam, fuel, temp, tostring(coolant)))
end

call(reactor, "setAllControlRodLevels", 100)
call(reactor, "setActive", false)
if turbine then call(turbine, "setActive", false) end
emit("sweep done - reactor deactivated, rods 100%")

local f = fs.open("reactorlab_report.txt", "w")
f.write(table.concat(out, "\n"))
f.close()
print("")
print("uploading to pastebin...")
shell.run("pastebin", "put", "reactorlab_report.txt")
print("relay the code to the NOC.")
