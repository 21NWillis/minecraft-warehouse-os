-- reactor: Mekanism fission reactor controller. The thin in-game shell around
-- reactorlogic.lua (which holds the interlocks + burn ramp, headless-tested).
--
-- Setup: a computer touching a Fission Reactor Logic Adapter (or reaching it
-- via wired modem). Optional: any modem for starlink telemetry. Run `reactor`.
--
-- Safety model: the 2 Hz safety loop is authoritative. Any interlock breach
-- scrams and LATCHES; restarting a latch takes [f]orce. The reactor never
-- auto-starts. [q] scrams on exit (no controller -> no reactor); [Q] detaches
-- hot if you really mean it.
--
-- Method names are bound against getMethods() at startup; anything missing
-- degrades to monitor-only and says so (then run `probe` and we fix names).
local rlogic = require("reactorlogic")

local METHODS = {
  temp     = "getTemperature",
  damage   = "getDamagePercent",
  coolant  = "getCoolantFilledPercentage",
  heated   = "getHeatedCoolantFilledPercentage",
  fuel     = "getFuelFilledPercentage",
  waste    = "getWasteFilledPercentage",
  actual   = "getActualBurnRate",
  maxBurn  = "getMaxBurnRate",
  running  = "getStatus",
  setBurn  = "setBurnRate",
  scram    = "scram",
  activate = "activate",
}
local GETTERS = { "temp", "damage", "coolant", "heated", "fuel", "waste",
                  "actual", "maxBurn", "running" }

-- ---- bind the adapter -------------------------------------------------------
local function findAdapter()
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t and tostring(t):lower():find("fission") then
      return peripheral.wrap(name), name
    end
  end
end

local p, pname = findAdapter()
if not p then
  print("no fission reactor logic adapter found.")
  print("attach one (directly or via wired modem) and rerun.")
  return
end

local have = {}
for _, m in ipairs(peripheral.getMethods(pname) or {}) do have[m] = true end
local fns, missing = {}, {}
for key, m in pairs(METHODS) do
  if have[m] then
    fns[key] = function(...) return p[m](...) end
  else
    missing[#missing + 1] = key .. "(" .. m .. ")"
  end
end
local canControl = fns.setBurn and fns.scram and fns.activate and fns.running

-- ---- shared state -----------------------------------------------------------
local state = rlogic.newState()
local ui = { note = #missing > 0 and ("unbound: " .. table.concat(missing, " ")) or "" }
local latest = rlogic.normalize({})

local function read()
  local raw = {}
  for _, key in ipairs(GETTERS) do
    if fns[key] then
      local ok, v = pcall(fns[key])
      if ok then raw[key] = v end
    end
  end
  latest = rlogic.normalize(raw)
  return latest
end

local net
do
  local ok, starlink = pcall(require, "starlink")
  if ok then
    local okNew, n = pcall(starlink.new, "reactor-" .. os.getComputerID(), "reactor")
    if okNew then net = n end
  end
end

-- ---- paint ------------------------------------------------------------------
local function bar(v, w)
  local filled = math.max(0, math.min(w, math.floor((v or 0) * w + 0.5)))
  return string.rep("\127", filled) .. string.rep("\183", w - filled)
end

local function pct(v) return v and ("%3d%%"):format(math.floor(v * 100 + 0.5)) or "  ??" end

local function draw(r)
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("FISSION CONTROL  " .. pname)

  term.setCursorPos(1, 2)
  if state.latched then
    term.setTextColor(colors.red)
    print(("LATCHED: %s"):format(state.cause or "?"))
  elseif r.running then
    term.setTextColor(colors.lime)
    print(("RUNNING  burn %.1f -> target %.1f mB/t"):format(r.actual or 0, state.target))
  else
    term.setTextColor(colors.lightGray)
    print("OFFLINE" .. (canControl and "" or "  (MONITOR-ONLY)"))
  end

  term.setTextColor(colors.white)
  term.setCursorPos(1, 4)
  print(("temp   %6.0f K   (scram > %d K)"):format(r.temp or 0, rlogic.LIMITS.tempMax))
  print(("damage %6.1f %%   (scram > %d %%)"):format(r.damage or 0, rlogic.LIMITS.damageMax))
  print(("burn   %6.1f mB/t (max %s)"):format(r.actual or 0, tostring(r.maxBurn or "?")))
  print("")
  print(("coolant %s %s"):format(bar(r.coolant, 20), pct(r.coolant)))
  print(("heated  %s %s"):format(bar(r.heated, 20), pct(r.heated)))
  print(("fuel    %s %s"):format(bar(r.fuel, 20), pct(r.fuel)))
  print(("waste   %s %s"):format(bar(r.waste, 20), pct(r.waste)))

  term.setCursorPos(1, 13)
  term.setTextColor(colors.yellow)
  print(ui.note:sub(1, W))
  term.setTextColor(colors.lightGray)
  term.write("[s]tart [f]orce [x]scram [+/-] target [q]uit+scram [Q]detach")
end

-- ---- control ----------------------------------------------------------------
local function doScram(cause)
  if fns.scram then pcall(fns.scram) end
  if cause then
    rlogic.operatorScram(state)
    state.cause = cause
  end
end

local function start(force)
  if not canControl then ui.note = "monitor-only: cannot start" return end
  local ok, err = rlogic.canStart(state, read(), force)
  if not ok then ui.note = err return end
  state.latched, state.cause = false, nil
  state.lastSet = 0
  pcall(fns.setBurn, 0)
  local okA, e = pcall(fns.activate)
  if not okA then ui.note = "activate failed: " .. tostring(e) return end
  if state.target == 0 then rlogic.setTarget(state, 1, latest.maxBurn) end
  ui.note = ("started; ramping to %.1f mB/t"):format(state.target)
end

local function safetyLoop()
  local n = 0
  while true do
    local r = read()
    local act = rlogic.step(state, r)
    if act.scram then
      if fns.scram then pcall(fns.scram) end
      ui.note = "SCRAM: " .. act.scram
    elseif act.setBurn and fns.setBurn then
      pcall(fns.setBurn, act.setBurn)
    end
    draw(r)
    n = n + 1
    if net and n % 4 == 0 then
      net:setTelemetry({ temp = r.temp, burn = r.actual, damage = r.damage,
                         waste = r.waste, running = r.running,
                         latched = state.latched })
      net:beacon()
    end
    sleep(0.5)
  end
end

local function keyLoop()
  while true do
    local ev, a = os.pullEvent()
    if ev == "char" then
      if a == "s" then start(false)
      elseif a == "f" then start(true)
      elseif a == "x" then
        doScram("operator scram")
        ui.note = "operator scram"
      elseif a == "+" or a == "=" then
        rlogic.setTarget(state, state.target + 0.5, latest.maxBurn)
        ui.note = ("target %.1f mB/t"):format(state.target)
      elseif a == "-" then
        rlogic.setTarget(state, state.target - 0.5, latest.maxBurn)
        ui.note = ("target %.1f mB/t"):format(state.target)
      elseif a == "q" then
        doScram("controller exit")
        return "scrammed on exit"
      elseif a == "Q" then
        return "DETACHED: reactor left running with NO interlocks"
      end
    elseif ev == "key" then
      if a == keys.up then rlogic.setTarget(state, state.target + 0.5, latest.maxBurn)
      elseif a == keys.down then rlogic.setTarget(state, state.target - 0.5, latest.maxBurn) end
    end
  end
end

draw(read())
local okRun, msg = pcall(function() return select(2, parallel.waitForAny(safetyLoop, keyLoop)) end)
-- GUARANTEED SCRAM ON ABNORMAL EXIT (outside audit, adopted): Ctrl+T,
-- a Lua error, or any surprise ending scrams the core. The ONLY exit
-- that leaves the reactor hot is the deliberate [Q] detach.
local detached = okRun and type(msg) == "string" and msg:find("DETACHED")
if not detached and fns.scram then pcall(fns.scram) end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if detached then
  print(msg)
else
  print("reactor controller stopped - core scrammed on exit")
  if not okRun then print("(exit cause: " .. tostring(msg) .. ")") end
end
