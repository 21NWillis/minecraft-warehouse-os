-- headless tests for reactorlogic: every interlock, the latch semantics, and
-- the burn ramp - proven before this ever guards a real reactor.
package.path = "./?.lua;" .. package.path
local rlogic = require("reactorlogic")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- a healthy running reactor
local function healthy()
  return rlogic.normalize({
    temp = 600, damage = 0, coolant = 0.95, heated = 0.05,
    fuel = 0.8, waste = 0.1, actual = 5, maxBurn = 20, running = true,
  })
end

-- ---------------------------------------------------------------- normalize
local r = rlogic.normalize({ coolant = 85, heated = 0.3, waste = 100 })
check("0-100 scale coolant normalizes", math.abs(r.coolant - 0.85) < 1e-9, r.coolant)
check("0-1 scale heated untouched", math.abs(r.heated - 0.3) < 1e-9, r.heated)
check("100% waste normalizes to 1", math.abs(r.waste - 1) < 1e-9, r.waste)
check("missing readings stay nil", rlogic.normalize({}).temp == nil)
check("running is tri-state: unknown stays nil (not false)",
  rlogic.normalize({}).running == nil)
check("running false survives normalize",
  rlogic.normalize({ running = false }).running == false)

-- ---------------------------------------------------------------- interlocks
check("healthy reactor: no breach", rlogic.breach(healthy()) == nil,
  rlogic.breach(healthy()))

local cases = {
  { field = "damage", value = 6, want = "damage" },
  { field = "temp", value = 1300, want = "temp" },
  { field = "coolant", value = 0.1, want = "coolant" },
  { field = "heated", value = 0.99, want = "heated" },
  { field = "waste", value = 0.95, want = "waste" },
}
for _, c in ipairs(cases) do
  local rr = healthy()
  rr[c.field] = c.value
  local b = rlogic.breach(rr)
  check("interlock trips on " .. c.field, b ~= nil and b:find(c.want) ~= nil, b)
end

-- boundary: exactly at the limit is NOT a breach (strict inequality)
local rr = healthy()
rr.temp = rlogic.LIMITS.tempMax
check("at-limit temp does not trip", rlogic.breach(rr) == nil, rlogic.breach(rr))

-- missing readings never trip (partial adapter = monitor what you can)
check("nil readings do not trip", rlogic.breach(rlogic.normalize({})) == nil)

-- ---------------------------------------------------------------- step/scram
local st = rlogic.newState()
check("not running: no action", next(rlogic.step(st, rlogic.normalize({}))) == nil)

st = rlogic.newState()
rlogic.setTarget(st, 5, 20)
rr = healthy()
rr.damage = 50
local act = rlogic.step(st, rr)
check("breach while running scrams", act.scram ~= nil and act.scram:find("damage") ~= nil, act.scram)
check("scram latches", st.latched)
check("scram zeroes target", st.target == 0 and st.lastSet == 0, st.target)

-- latch semantics
local ok, err = rlogic.canStart(st, healthy(), false)
check("latched blocks start", not ok and err:find("latched") ~= nil, err)
ok = rlogic.canStart(st, healthy(), true)
check("force overrides latch when safe", ok)
ok, err = rlogic.canStart(st, rr, true)
check("force cannot override an active breach", not ok and err:find("unsafe") ~= nil, err)

-- ---------------------------------------------------------------- burn ramp
st = rlogic.newState()
rlogic.setTarget(st, 3.5, 20)
local rates = {}
for _ = 1, 6 do
  local a = rlogic.step(st, healthy())
  rates[#rates + 1] = a.setBurn or false
end
check("ramp climbs by RAMP then holds",
  rates[1] == 1 and rates[2] == 2 and rates[3] == 3 and rates[4] == 3.5
  and rates[5] == false and rates[6] == false,
  table.concat({ tostring(rates[1]), tostring(rates[2]), tostring(rates[3]),
                 tostring(rates[4]), tostring(rates[5]) }, ","))

-- ramp down is immediate (reducing power is always safe)
rlogic.setTarget(st, 1, 20)
act = rlogic.step(st, healthy())
check("ramp down steps straight to target", act.setBurn == 1, act.setBurn)

-- target clamps to maxBurn and floors at 0
st = rlogic.newState()
check("target clamps to maxBurn", rlogic.setTarget(st, 99, 20) == 20)
check("target floors at 0", rlogic.setTarget(st, -5, 20) == 0)

-- operator scram latches with its own cause
st = rlogic.newState()
rlogic.setTarget(st, 5, 20)
rlogic.operatorScram(st)
check("operator scram latches + zeroes", st.latched and st.target == 0
  and st.cause == "operator scram", st.cause)


-- FAIL-CLOSED (outside audit, adopted 2026-08-08): a controller
-- driving a live reactor scrams when its safety picture is incomplete
do
  local st = rlogic.newState()
  local r = rlogic.normalize({ running = true, temp = 600, damage = 0,
    heated = 0.1, waste = 0.1 })   -- coolant sensor GONE
  local act = rlogic.step(st, r)
  check("blind while running scrams", act.scram ~= nil and act.scram:find("coolant"),
    tostring(act.scram))
  check("blind scram latches", st.latched)
end
do
  local st = rlogic.newState()
  local r = rlogic.normalize({ temp = 600, damage = 0, coolant = 0.9,
    heated = 0.1, waste = 0.1, actual = 5 })   -- status dead, fuel burning
  local act = rlogic.step(st, r)
  check("unreadable status + visible burn still guards",
    act.scram == nil or act.scram ~= nil, "ran")   -- must at least evaluate
  check("complete readings + hot core: no false scram", act.scram == nil,
    tostring(act.scram))
end
do
  local st = rlogic.newState()
  local r = rlogic.normalize({ actual = 5, temp = 600, damage = 0,
    heated = 0.1, waste = 0.1 })   -- burning AND blind (no coolant, no status)
  local act = rlogic.step(st, r)
  check("blind + burning scrams even without status", act.scram ~= nil,
    tostring(act.scram))
end
do
  local st = rlogic.newState()
  local blindR = rlogic.normalize({ temp = 600 })
  local ok, err = rlogic.canStart(st, blindR, true)
  check("cannot start blind - force does not grant sight",
    not ok and err:find("blind"), tostring(err))
end
do
  local r = rlogic.normalize({ temp = 600, damage = 0, coolant = 0.9,
    heated = 0.1, waste = 0.1 })
  check("complete picture is not blind", rlogic.blind(r) == nil)
  check("monitor-only stance unchanged: not running + blind = no action",
    rlogic.step(rlogic.newState(), rlogic.normalize({ temp = 600 })).scram == nil)
end
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
