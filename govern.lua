-- govern: ER2 turbine governor + reactor trim (ATM10 power plant).
-- Holds rotor RPM at the efficiency sweet spot by steering max steam
-- intake; engages coils at speed; fail-closed on overspeed (flow to
-- zero, coils in as brake, reactor scram at the red line). Doctrine:
-- blindness is breach-class - if the turbine stops answering, scram.
--
-- Setup: wired modems (activated) on the reactor Computer Port, the
-- turbine Computer Port, and the computer. Run: govern
-- API surface extracted from ExtremeReactors jar 2026-08-16.

local TARGET_RPM   = 900     -- efficiency bands ~900 and ~1800; 900 wants
                             -- less steam. Edit + rerun to try 1800.
local RPM_TOLERANCE = 15     -- acceptable wobble around target
local OVERSPEED    = 1950    -- brake hard here (destruction at 2000)
local SCRAM_RPM    = 1985    -- reactor off here
local FLOW_STEP    = 15      -- mB/t per correction step
local COIL_ENGAGE  = TARGET_RPM - 60  -- engage coils above this
local LOOP_S       = 1

-- duck-typed discovery: a turbine quacks getRotorSpeed, a reactor
-- quacks setAllControlRodLevels. Names vary; behaviors don't.
local turbine, reactor
for _, n in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(n)
  local m = {}
  for _, name in ipairs(peripheral.getMethods(n) or {}) do m[name] = true end
  if m.getRotorSpeed then turbine = p print("turbine: " .. n) end
  if m.setAllControlRodLevels then reactor = p print("reactor: " .. n) end
end
assert(turbine, "govern: no turbine computer port on the network")
if not reactor then print("govern: no reactor port found - running turbine-only") end

local function call(p, fn, ...)
  if not p or type(p[fn]) ~= "function" then return nil end
  local ok, res = pcall(p[fn], ...)
  if ok then return res end
  return nil
end

-- fail-closed: any telemetry blindness = emergency posture
local function emergency(reason)
  print("!! EMERGENCY: " .. reason)
  call(turbine, "setFluidFlowRateMax", 0)
  call(turbine, "setInductorEngaged", true)   -- coils as brake
  if reactor then call(reactor, "setActive", false) end
  rednet.broadcast({ station = "powerplant", kind = "scram", detail = reason }, "paperclip.power")
end

-- open modems for telemetry broadcasts
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then pcall(rednet.open, n) end
end

call(turbine, "setVentOverflow")   -- excess steam vents, never deadlocks
call(turbine, "setActive", true)
if reactor then call(reactor, "setActive", true) end

local flowMax = call(turbine, "getFluidFlowRateMaxMax") or 2000
local flow = math.min(400, flowMax)   -- gentle start
call(turbine, "setFluidFlowRateMax", flow)
print(("govern up: target %d RPM, flow start %d mB/t, hard max %d"):format(TARGET_RPM, flow, flowMax))

local lastBeat = 0
while true do
  local rpm = call(turbine, "getRotorSpeed")
  if rpm == nil then
    emergency("rotor speed unreadable")
    sleep(5)
  else
    -- overspeed ladder
    if rpm >= SCRAM_RPM then
      emergency(("RPM %d >= scram line"):format(rpm))
      sleep(5)
    elseif rpm >= OVERSPEED then
      print(("brake: %d RPM"):format(rpm))
      call(turbine, "setFluidFlowRateMax", 0)
      call(turbine, "setInductorEngaged", true)
    else
      -- coil state: engaged once near target, stays engaged
      local engaged = call(turbine, "getInductorEngaged")
      if not engaged and rpm >= COIL_ENGAGE then
        call(turbine, "setInductorEngaged", true)
        print(("coils engaged at %d RPM"):format(rpm))
      end
      -- proportional-ish flow steering toward target RPM
      local err = TARGET_RPM - rpm
      if math.abs(err) > RPM_TOLERANCE then
        local step = FLOW_STEP
        if math.abs(err) > 150 then step = FLOW_STEP * 4 end
        if err > 0 then
          flow = math.min(flowMax, flow + step)
        else
          flow = math.max(0, flow - step)
        end
        call(turbine, "setFluidFlowRateMax", flow)
      end
    end

    -- heartbeat + console telemetry every 5s
    local t = os.clock()
    if t - lastBeat >= 5 then
      lastBeat = t
      local fe = call(turbine, "getEnergyProducedLastTick") or 0
      local eff = call(turbine, "getRotorEfficiencyLastTick")
      local line = ("rpm %4d | flow %4d mB/t | %s FE/t%s"):format(
        math.floor(rpm), flow, tostring(math.floor(fe)),
        eff and (" | eff " .. math.floor(eff * 100) .. "%%") or "")
      print(line)
      rednet.broadcast({ station = "powerplant", kind = "telemetry",
        rpm = rpm, flow = flow, fet = fe }, "paperclip.power")
    end
  end
  sleep(LOOP_S)
end
