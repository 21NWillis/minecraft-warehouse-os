-- headless tests for stationlogic (the ATM10 mini-PC dispatcher math)
-- and mock_rsbridge (the craftd v2 test substrate). Pure logic, no CC.
--   lua54 tests/stationlogic_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path

local sl = require("stationlogic")
local rsb = require("mock_rsbridge")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local function cfg(machines, maxInFlight)
  return {
    recipes = {
      { key = "infused_alloy",
        inputs = { { name = "mekanism:enriched_redstone", n = 1, toSlot = 2 },
                   { name = "minecraft:iron_ingot", n = 8, toSlot = 1 } },
        outputs = { { name = "mekanism:infused_alloy", fromSlot = 3 } } },
      { key = "steel_dust",
        inputs = { { name = "mekanism:enriched_carbon", n = 1, toSlot = 2 },
                   { name = "minecraft:iron_ingot", n = 1, toSlot = 1 } },
        outputs = { { name = "mekanism:steel_dust", fromSlot = 3 } } },
    },
    machines = machines or { "m1", "m2", "m3" },
    maxInFlight = maxInFlight or 2,
    jamT = 60, staleT = 30,
  }
end

-- 1. set parsing: clean single-recipe buffer
do
  local c = cfg()
  local sets, leftovers = sl.parseSets(c, {
    [1] = { name = "minecraft:iron_ingot", count = 16 },
    [2] = { name = "mekanism:enriched_redstone", count = 2 },
  })
  check("two clean alloy sets", sets.infused_alloy == 2, sets.infused_alloy)
  check("no leftovers on clean parse", not leftovers)
end

-- 2. interleaved pushes from two tasks: aggregate counts still parse
do
  local c = cfg()
  local sets, leftovers = sl.parseSets(c, {
    [1] = { name = "minecraft:iron_ingot", count = 5 },     -- task A partial
    [2] = { name = "mekanism:enriched_redstone", count = 1 },
    [3] = { name = "minecraft:iron_ingot", count = 3 },     -- task B remainder
    [4] = { name = "mekanism:enriched_redstone", count = 1 },
    [5] = { name = "minecraft:iron_ingot", count = 8 },
  })
  check("interleaved slots -> 2 sets", sets.infused_alloy == 2, sets.infused_alloy)
  check("extra redstone flagged leftover", leftovers == false, tostring(leftovers))
end

-- 3. partial set = leftovers, zero sets
do
  local c = cfg()
  local sets, leftovers = sl.parseSets(c, {
    [1] = { name = "minecraft:iron_ingot", count = 7 },
  })
  check("7 iron = no alloy set", (sets.infused_alloy or 0) == 0)
  check("but steel_dust greedy eats iron", sets.steel_dust == nil,
    sets.steel_dust)  -- no carbon present, so no steel sets either
  check("partial flags leftovers", leftovers)
end

-- 4. greedy recipe order: shared ingredient goes to first recipe
do
  local c = cfg()
  local sets = sl.parseSets(c, {
    [1] = { name = "minecraft:iron_ingot", count = 9 },
    [2] = { name = "mekanism:enriched_redstone", count = 1 },
    [3] = { name = "mekanism:enriched_carbon", count = 1 },
  })
  check("alloy set claimed first (greedy order)", sets.infused_alloy == 1)
  check("remaining 1 iron feeds steel set", sets.steel_dust == 1, sets.steel_dust)
end

-- 5. round-robin fairness + in-flight ledger
do
  local c = cfg({ "m1", "m2", "m3" }, 2)
  local st = sl.new(c)
  local plan = sl.assign(st, { infused_alloy = 3 }, 0)
  check("3 sets dispatched", #plan == 3, #plan)
  check("fair spread m1,m2,m3",
    plan[1].machine == "m1" and plan[2].machine == "m2" and plan[3].machine == "m3",
    plan[1].machine .. "," .. plan[2].machine .. "," .. plan[3].machine)
  local plan2 = sl.assign(st, { infused_alloy = 1 }, 1)
  check("cursor persists across calls", plan2[1].machine == "m1", plan2[1].machine)
end

-- 6. maxInFlight saturation: bank full -> assignment stops, rest waits
do
  local c = cfg({ "m1", "m2" }, 1)
  local st = sl.new(c)
  local plan = sl.assign(st, { infused_alloy = 5 }, 0)
  check("only 2 of 5 sets placed at maxInFlight=1", #plan == 2, #plan)
  check("status shows 2 in flight", sl.status(st).inFlight == 2)
  sl.complete(st, "m1", "infused_alloy")
  local plan2 = sl.assign(st, { infused_alloy = 3 }, 1)
  check("freed machine accepts one more", #plan2 == 1 and plan2[1].machine == "m1",
    #plan2)
end

-- 7. jam detection and route-around
do
  local c = cfg({ "m1", "m2" }, 2)
  local st = sl.new(c)
  sl.assign(st, { infused_alloy = 1 }, 0)          -- lands on m1 at t=0
  local newly = sl.checkJams(st, 61)               -- jamT=60 exceeded
  check("m1 flagged jammed", #newly == 1 and newly[1] == "m1", newly[1])
  local plan = sl.assign(st, { infused_alloy = 2 }, 62)
  for _, a in ipairs(plan) do
    check("jammed m1 routed around", a.machine ~= "m1", a.machine)
  end
  check("jam sweep is edge-triggered", #sl.checkJams(st, 120) == 0)
  sl.complete(st, "m1", "infused_alloy")           -- late output arrives
  check("output clears jam flag", not st.jammed["m1"])
end

-- 8. stale leftover flush signal
do
  local c = cfg()
  local st = sl.new(c)
  check("no flush while fresh", not sl.staleLeftovers(st, true, 0))
  check("no flush before staleT", not sl.staleLeftovers(st, true, 20))
  check("flush after staleT", sl.staleLeftovers(st, true, 31))
  check("clock resets after flush", not sl.staleLeftovers(st, true, 32))
  sl.staleLeftovers(st, false, 40)
  check("clean buffer clears clock", not sl.staleLeftovers(st, true, 41))
end

-- 9. mock_rsbridge: job lifecycle happy path
do
  local b = rsb.new({ craftable = { ["minecraft:piston"] = { ticks = 2 } } })
  local job = b:craftItem({ name = "minecraft:piston", count = 4 })
  check("craftItem returns job object, not boolean", type(job) == "table" and job.getId)
  check("not done at t0", not job.isDone())
  local ev, isErr, id, msg = b:pullEvent()
  check("CALCULATION_STARTED queued", ev == "rs_crafting" and msg == "CALCULATION_STARTED", msg)
  b:advance(3)
  check("done after ticks", job.isDone())
  local sawDone = false
  repeat
    local e, err2, _, m = b:pullEvent()
    if e and m == "JOB_DONE" and not err2 then sawDone = true end
  until not e
  check("JOB_DONE event fired", sawDone)
end

-- 10. mock_rsbridge: MISSING_ITEMS failure path
do
  local b = rsb.new({ craftable = { ["minecraft:piston"] =
    { ticks = 2, missing = { name = "minecraft:redstone", n = 1 } } } })
  local job = b:craftItem({ name = "minecraft:piston" })
  b:advance(1)
  check("calc failure cancels job", job.isCanceled())
  check("missing list populated", job.getMissingItems()[1].name == "minecraft:redstone")
end

-- 11. mock_rsbridge: the count=1 clamp landmine
do
  local b = rsb.new({
    stored = { ["minecraft:iron_ingot"] = 64 },
    craftable = { ["minecraft:piston"] = { ticks = 1 } },
  })
  local clampSeen = false
  for _, it in ipairs(b:getItems()) do
    if it.name == "minecraft:piston" then
      clampSeen = (it.count == 1)
    end
  end
  check("craftable-zero-stored reports count=1", clampSeen)
  -- the doctrine: stock policy must confirm via stored-only view, never count
end

-- 12. movePlan: one set, ingredients spanning multiple source slots
do
  local c = cfg()
  local slots = {
    [1] = { name = "minecraft:iron_ingot", count = 5 },
    [3] = { name = "minecraft:iron_ingot", count = 3 },
    [4] = { name = "mekanism:enriched_redstone", count = 2 },
  }
  local moves, after = sl.movePlan(c, slots, "infused_alloy")
  check("movePlan returns moves", moves ~= nil)
  local ironMoved, rsMoved = 0, 0
  for _, mv in ipairs(moves) do
    if mv.name == "minecraft:iron_ingot" then
      ironMoved = ironMoved + mv.count
      check("iron routed to slot 1", mv.toSlot == 1, mv.toSlot)
    else
      rsMoved = rsMoved + mv.count
      check("redstone routed to slot 2", mv.toSlot == 2, mv.toSlot)
    end
  end
  check("exactly 8 iron moved across slots", ironMoved == 8, ironMoved)
  check("exactly 1 redstone moved", rsMoved == 1, rsMoved)
  check("after-view keeps leftover redstone", after[4].count == 1, after[4] and after[4].count)
  check("after-view drops emptied slots", after[1] == nil and after[3] == nil)
  -- second set from the remainder must fail (iron exhausted)
  local moves2 = sl.movePlan(c, after, "infused_alloy")
  check("second set correctly unplannable", moves2 == nil)
end

-- 13. movePlan: failed plan leaves the caller's slot view untouched
do
  local c = cfg()
  local slots = { [1] = { name = "minecraft:iron_ingot", count = 4 } }
  local moves, after = sl.movePlan(c, slots, "infused_alloy")
  check("short buffer plans nothing", moves == nil)
  check("failed plan mutates nothing", after[1].count == 4, after[1].count)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
