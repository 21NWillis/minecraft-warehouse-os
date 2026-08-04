-- headless crafthub test: the pure logic craftd/craftcell run on -
-- grid slot mapping, batch math, staging totals, job hand-off, cell
-- arrangement plans and least-loaded dispatch.
--
-- Arrangement plans are never merely inspected for shape: every plan is
-- APPLIED to a simulated turtle inventory with faithful CC semantics -
--   turtle.transferTo(to, n) moves NOTHING when the destination slot
--   already holds a different item (or would overflow a stack), and
--   turtle.select(s); turtle.dropDown() empties the WHOLE slot -
-- and the resulting crafting grid is then asserted, because that is the
-- only thing turtle.craft() actually cares about.
package.path = "./?.lua;" .. package.path
local hub = require("crafthub")
local planner = require("planner")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local MAX_STACK = 64

-- ------------------------------------------------------------- helpers
local function copyInv(inv)
  local out = {}
  for slot, d in pairs(inv) do
    if d then out[slot] = { name = d.name, count = d.count } end
  end
  return out
end

local function listStr(t)
  local parts = {}
  for i, v in ipairs(t) do parts[i] = tostring(v) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function listEq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function invStr(inv)
  local slots = {}
  for slot in pairs(inv) do slots[#slots + 1] = slot end
  table.sort(slots)
  local parts = {}
  for _, s in ipairs(slots) do
    parts[#parts + 1] = ("%d=%dx%s"):format(s, inv[s].count, inv[s].name)
  end
  return "[" .. table.concat(parts, " ") .. "]"
end

-- run the plan exactly the way craftcell.runJob does: all transfers
-- first (in order), then every cleared slot dropped whole.
-- returns the resulting inventory, or nil + why the turtle would balk.
local function applyPlan(inv, transfers, clears)
  local sim = copyInv(inv)
  for i, t in ipairs(transfers) do
    local src = sim[t.from]
    if not src or src.count < t.count then
      return nil, ("transfer #%d: slot %d cannot supply %d (%s)")
        :format(i, t.from, t.count, src and (src.count .. "x" .. src.name) or "empty")
    end
    local dst = sim[t.to]
    if dst and dst.name ~= src.name then
      return nil, ("transfer #%d (%d->%d %dx%s): destination holds %dx%s, transferTo moves nothing")
        :format(i, t.from, t.to, t.count, src.name, dst.count, dst.name)
    end
    if dst and dst.count + t.count > MAX_STACK then
      return nil, ("transfer #%d: slot %d would overflow a stack"):format(i, t.to)
    end
    if dst then dst.count = dst.count + t.count
    else sim[t.to] = { name = src.name, count = t.count } end
    src.count = src.count - t.count
    if src.count <= 0 then sim[t.from] = nil end
  end
  for _, slot in ipairs(clears) do sim[slot] = nil end   -- dropDown is all-or-nothing
  return sim
end

-- a legal layout for turtle.craft(count): every mapped grid slot holds
-- exactly `count` of the right item and EVERY other slot is empty.
local function gridState(sim, grid, count)
  local want = {}
  for g, item in pairs(grid) do want[hub.turtleSlot(g)] = item end
  for slot = 1, 16 do
    local d = sim[slot]
    if d and d.count == 0 then d = nil end
    local expect = want[slot]
    if expect then
      if not d then return ("slot %d empty, wanted %dx%s"):format(slot, count, expect) end
      if d.name ~= expect then
        return ("slot %d holds %s, wanted %s"):format(slot, d.name, expect)
      end
      if d.count ~= count then
        return ("slot %d holds %d of %s, wanted %d"):format(slot, d.count, expect, count)
      end
    elseif d then
      return ("slot %d must be empty for turtle.craft, holds %dx%s")
        :format(slot, d.count, d.name)
    end
  end
  return nil
end

-- plan + apply + assert. nil when the cell would really craft this.
local function arrangeErr(inv, grid, count)
  local transfers, clears = hub.arrangePlan(inv, grid, count)
  if not transfers then return "arrangePlan refused: missing " .. tostring(clears) end
  local sim, why = applyPlan(inv, transfers, clears)
  if not sim then return why .. "  from " .. invStr(inv) end
  local bad = gridState(sim, grid, count)
  if bad then return bad .. "  ended " .. invStr(sim) end
  return nil
end

-- ---------------------------------------------------------- turtleSlot
local EXPECT_SLOTS = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
local mapped, mapOk = {}, true
for g = 1, 9 do
  mapped[g] = hub.turtleSlot(g)
  if mapped[g] ~= EXPECT_SLOTS[g] then mapOk = false end
end
check("turtleSlot: 1..9 -> {1,2,3,5,6,7,9,10,11}", mapOk, listStr(mapped))
check("turtleSlot: row breaks skip 4, 8", hub.turtleSlot(3) == 3 and hub.turtleSlot(4) == 5
  and hub.turtleSlot(6) == 7 and hub.turtleSlot(7) == 9,
  hub.turtleSlot(4) .. "/" .. hub.turtleSlot(7))
local distinct = {}
for _, s in ipairs(EXPECT_SLOTS) do distinct[s] = (distinct[s] or 0) + 1 end
local dupes = 0
for _, n in pairs(distinct) do if n > 1 then dupes = dupes + 1 end end
check("turtleSlot: mapping is injective and inside slots 1..11", dupes == 0
  and hub.turtleSlot(9) == 11, dupes)
check("turtleSlot: off-grid index has no slot", hub.turtleSlot(10) == nil
  and hub.turtleSlot(0) == nil)

-- ---------------------------------------------------------- batchSizes
check("batchSizes: 130 -> {64,64,2}", listEq(hub.batchSizes(130), { 64, 64, 2 }),
  listStr(hub.batchSizes(130)))
check("batchSizes: 64 -> {64}", listEq(hub.batchSizes(64), { 64 }),
  listStr(hub.batchSizes(64)))
check("batchSizes: 1 -> {1}", listEq(hub.batchSizes(1), { 1 }), listStr(hub.batchSizes(1)))
check("batchSizes: 0 -> {}", listEq(hub.batchSizes(0), {}), listStr(hub.batchSizes(0)))
check("batchSizes: custom maxBatch 10/4 -> {4,4,2}",
  listEq(hub.batchSizes(10, 4), { 4, 4, 2 }), listStr(hub.batchSizes(10, 4)))
local conserved = true
for _, n in ipairs({ 1, 7, 63, 64, 65, 130, 999 }) do
  local sum = 0
  for _, b in ipairs(hub.batchSizes(n)) do
    sum = sum + b
    if b < 1 or b > 64 then conserved = false end
  end
  if sum ~= n then conserved = false end
end
check("batchSizes: batches sum to times and never exceed a stack", conserved)

-- --------------------------------------------------------- stageTotals
local pickStep = { output = "x", picks = { [1] = "a", [2] = "b", [3] = "a" } }
local totals = hub.stageTotals(pickStep, 10)
check("stageTotals: repeated pick aggregates (a=20, b=10)",
  totals.a == 20 and totals.b == 10,
  tostring(totals.a) .. "/" .. tostring(totals.b))
local nTotals = 0
for _ in pairs(totals) do nTotals = nTotals + 1 end
check("stageTotals: one entry per distinct item", nTotals == 2, nTotals)
local one = hub.stageTotals(pickStep, 1)
check("stageTotals: scales linearly with batch", one.a == 2 and one.b == 1,
  tostring(one.a) .. "/" .. tostring(one.b))

-- -------------------------------------------------------------- jobFor
local step = { output = "minecraft:chest", times = 5,
  picks = { [1] = "minecraft:oak_planks", [4] = "minecraft:oak_planks" } }
local job = hub.jobFor(step, 3)
check("jobFor: carries output and batch count",
  job.output == "minecraft:chest" and job.count == 3, tostring(job.count))
check("jobFor: grid mirrors picks on the recipe's own slot keys",
  job.grid[1] == "minecraft:oak_planks" and job.grid[4] == "minecraft:oak_planks"
  and job.grid[2] == nil)
check("jobFor: grid is a copy, not the picks table", job.grid ~= step.picks)
job.grid[1] = "minecraft:dirt"
job.grid[9] = "minecraft:dirt"
check("jobFor: mutating a job's grid cannot corrupt the plan",
  step.picks[1] == "minecraft:oak_planks" and step.picks[9] == nil,
  tostring(step.picks[1]))

-- --------------------------------------------------------- arrangePlan
local PLANK, STICK, COAL = "minecraft:oak_planks", "minecraft:stick", "minecraft:coal"

-- (a) every ingredient parked in a non-grid slot: pure gather
local gridA = { [1] = PLANK, [2] = STICK, [3] = PLANK }
local invA = { [13] = { name = PLANK, count = 16 }, [14] = { name = STICK, count = 8 } }
local tA, cA = hub.arrangePlan(invA, gridA, 8)
check("arrange(a): plan returned", tA ~= nil, tostring(cA))
local sizesOk = tA ~= nil
if tA then
  for _, t in ipairs(tA) do if t.count ~= 8 then sizesOk = false end end
end
check("arrange(a): exactly one stack-move per grid slot, count each",
  tA and #tA == 3 and sizesOk, tA and #tA)
check("arrange(a): nothing to clear once sources drain", cA and #cA == 0,
  cA and listStr(cA))
check("arrange(a): applied plan yields a craftable grid",
  arrangeErr(invA, gridA, 8) == nil, arrangeErr(invA, gridA, 8))

-- (b) destination already holds part of what it needs
local gridB = { [1] = PLANK }
local invB = { [1] = { name = PLANK, count = 4 }, [12] = { name = PLANK, count = 20 } }
local tB, cB = hub.arrangePlan(invB, gridB, 10)
check("arrange(b): destination content counted first (only 6 fetched)",
  tB and #tB == 1 and tB[1].count == 6 and tB[1].to == 1,
  tB and #tB == 1 and tB[1].count or (tB and #tB))
check("arrange(b): leftover source stack is cleared", cB and listEq(cB, { 12 }),
  cB and listStr(cB))
check("arrange(b): applied plan yields a craftable grid",
  arrangeErr(invB, gridB, 10) == nil, arrangeErr(invB, gridB, 10))
local tB2 = hub.arrangePlan({ [1] = { name = PLANK, count = 10 } }, gridB, 10)
check("arrange(b): already-correct slot needs no transfer at all",
  tB2 and #tB2 == 0, tB2 and #tB2)

-- (c) surplus stacks and non-grid junk both land on the clears list
local gridC = { [1] = PLANK, [5] = STICK }   -- grid 5 -> turtle slot 6
local invC = {
  [1] = { name = PLANK, count = 4 },
  [6] = { name = STICK, count = 4 },
  [8] = { name = COAL, count = 30 },          -- non-grid junk
  [13] = { name = PLANK, count = 20 },        -- surplus stack
}
local tC, cC = hub.arrangePlan(invC, gridC, 4)
check("arrange(c): surplus + non-grid leftovers listed, sorted",
  cC and listEq(cC, { 8, 13 }), cC and listStr(cC))
check("arrange(c): grid slots holding exactly their share are not cleared",
  tC and #tC == 0, tC and #tC)
check("arrange(c): after transfers+clears only the recipe's slots hold items",
  arrangeErr(invC, gridC, 4) == nil, arrangeErr(invC, gridC, 4))

-- (d) missing ingredient
local tD, missD = hub.arrangePlan({ [13] = { name = PLANK, count = 10 } },
  { [1] = PLANK, [2] = STICK }, 5)
check("arrange(d): absent ingredient -> nil, itemName", tD == nil and missD == STICK,
  tostring(missD))
local tD2, missD2 = hub.arrangePlan({ [13] = { name = PLANK, count = 3 } },
  { [1] = PLANK }, 5)
check("arrange(d): short supply of a present item also refuses",
  tD2 == nil and missD2 == PLANK, tostring(missD2))

-- (e) a full 9-slot grid, two distinct items, staged as two stacks
local gridE = {}
for g = 1, 9 do gridE[g] = (g % 2 == 1) and PLANK or STICK end
local invE = { [1] = { name = PLANK, count = 15 }, [2] = { name = STICK, count = 12 } }
local tE = hub.arrangePlan(invE, gridE, 3)
check("arrange(e): full 3x3 grid planned", tE ~= nil)
check("arrange(e): all nine positions filled, spare slots empty",
  arrangeErr(invE, gridE, 3) == nil, arrangeErr(invE, gridE, 3))

-- --- KNOWN BUG 1 (crafthub.arrangePlan): a grid destination that holds
-- MORE than the batch needs is pushed onto `clears`, and craftcell
-- clears by select+dropDown, which empties the whole slot - taking the
-- ingredients the grid just kept with it. Surplus must be trimmed
-- (partial drop, or moved to a spare slot), never dropped wholesale.
-- The check below states the CORRECT behavior; it fails today.
local invF = { [1] = { name = PLANK, count = 64 } }
check("arrange: surplus inside a grid slot is trimmed, not dumped [BUG 1]",
  arrangeErr(invF, { [1] = PLANK }, 10) == nil,
  arrangeErr(invF, { [1] = PLANK }, 10))

-- --- KNOWN BUG 2 (crafthub.arrangePlan): transfers are emitted in grid
-- order with no regard for destinations that are still occupied by a
-- foreign item. turtle.transferTo refuses such a move, so the grid is
-- silently left wrong and turtle.craft fails. Two ingredients that need
-- to swap slots deadlock: whichever transfer runs first is blocked.
-- The check below states the CORRECT behavior; it fails today.
local invG = { [1] = { name = PLANK, count = 10 }, [2] = { name = STICK, count = 10 } }
check("arrange: swapping two occupied grid slots still works [BUG 2]",
  arrangeErr(invG, { [1] = STICK, [2] = PLANK }, 10) == nil,
  arrangeErr(invG, { [1] = STICK, [2] = PLANK }, 10))

-- same fault on the shape craftd actually produces: the hub stages
-- exact totals, the cell sucks them into slots 1,2,... in chest order,
-- which need not match the recipe's slot order.
local invH = { [1] = { name = PLANK, count = 20 }, [2] = { name = STICK, count = 10 } }
check("arrange: realistic suck order for {planks,planks,stick} [BUG 2]",
  arrangeErr(invH, { [1] = PLANK, [2] = PLANK, [3] = STICK }, 10) == nil,
  arrangeErr(invH, { [1] = PLANK, [2] = PLANK, [3] = STICK }, 10))

-- ------------------------------------------------------------ pickCell
check("pickCell: empty registry -> nil", hub.pickCell({}) == nil)
local busyCells = { a = { id = "a", busy = 2 }, b = { id = "b", busy = 0 },
  c = { id = "c", busy = 5 } }
check("pickCell: least-loaded wins", hub.pickCell(busyCells).id == "b",
  hub.pickCell(busyCells).id)
local tied = { a = { id = "a", busy = 1 }, b = { id = "b", busy = 1 },
  c = { id = "c", busy = 3 } }
local tiePick = hub.pickCell(tied)
check("pickCell: a tie returns some minimally-loaded cell",
  tiePick and tiePick.busy == 1, tiePick and tiePick.busy)
local fresh = { a = { id = "a" }, b = { id = "b", busy = 4 } }
check("pickCell: a freshly registered cell counts as idle",
  hub.pickCell(fresh).id == "a", hub.pickCell(fresh).id)

-- ------------------------------------------------- integration mini-sim
-- the REAL planner against a toy recipe db, then the whole hub pipeline
-- (batchSizes -> stageTotals -> jobFor -> arrangePlan) per batch against
-- an inventory built the way a cell would actually receive it.
local RECIPES = {
  ["minecraft:stick"] = {
    { output = "minecraft:stick", count = 4,
      grid = { [1] = PLANK, [4] = PLANK } },       -- grid slot 4 -> turtle slot 5
  },
  [PLANK] = {
    { output = PLANK, count = 4, grid = { [1] = "minecraft:oak_log" } },
  },
}
local db = {
  recipesFor = function(id)
    local out = {}
    for i, r in ipairs(RECIPES[id] or {}) do out[i] = r end
    return out                                     -- planner sorts in place
  end,
  options = function(ing) return { ing } end,      -- plain ids, no tags
  isCraftable = function(id) return RECIPES[id] ~= nil end,
}

local have = { [PLANK] = 100 }
local steps = planner.plan(db, have, "minecraft:stick", 128)
check("integration: 128 sticks from planks is one step",
  steps and #steps == 1 and steps[1].output == "minecraft:stick",
  steps and #steps)
check("integration: 128 sticks = 32 crafts of 4",
  steps and steps[1].times == 32, steps and steps[1].times)
check("integration: picks land on the recipe's own grid keys",
  steps and steps[1].picks[1] == PLANK and steps[1].picks[4] == PLANK
  and hub.turtleSlot(4) == 5)

-- deeper: only logs in stock, 1000 sticks -> planks step then stick step
have = { ["minecraft:oak_log"] = 200 }
local deep, missing = planner.plan(db, have, "minecraft:stick", 1000)
check("integration: 1000 sticks from logs plans two steps",
  deep and #deep == 2 and deep[1].output == PLANK
  and deep[2].output == "minecraft:stick",
  deep and #deep or (missing and next(missing)))

local function buildInv(t)
  local names, inv, slot = {}, {}, 1
  for item in pairs(t) do names[#names + 1] = item end
  table.sort(names)
  for _, item in ipairs(names) do
    local left = t[item]
    while left > 0 do
      local n = math.min(MAX_STACK, left)
      inv[slot] = { name = item, count = n }
      slot, left = slot + 1, left - n
    end
  end
  return inv, slot - 1
end

if deep then
  local consumed, produced = {}, {}
  local batchErr, stagedErr, fitErr
  for _, s in ipairs(deep) do
    local batches = hub.batchSizes(s.times)
    local sum, perStep = 0, {}
    for _, b in ipairs(batches) do
      sum = sum + b
      local t = hub.stageTotals(s, b)
      local inv, used = buildInv(t)
      if used > 16 then
        fitErr = fitErr or ("%s batch %d needs %d slots"):format(s.output, b, used)
      end
      local j = hub.jobFor(s, b)
      local e = arrangeErr(inv, j.grid, j.count)
      if e then batchErr = batchErr or ("%s batch %d: %s"):format(s.output, b, e) end
      for item, n in pairs(t) do perStep[item] = (perStep[item] or 0) + n end
    end
    if sum ~= s.times then
      stagedErr = stagedErr or ("%s: batches sum %d ~= times %d"):format(s.output, sum, s.times)
    end
    -- the batches together must stage exactly what the whole step eats
    local want = {}
    for _, item in pairs(s.picks) do want[item] = (want[item] or 0) + s.times end
    for item, n in pairs(want) do
      if perStep[item] ~= n then
        stagedErr = stagedErr or ("%s: staged %s %s, step needs %d")
          :format(s.output, item, tostring(perStep[item]), n)
      end
      consumed[item] = (consumed[item] or 0) + n
    end
    for item in pairs(perStep) do
      if not want[item] then stagedErr = stagedErr or ("%s: staged stray %s"):format(s.output, item) end
    end
    produced[s.output] = (produced[s.output] or 0) + s.times * s.recipe.count
  end
  check("integration: every batch of every step is arrangeable",
    batchErr == nil, batchErr)
  check("integration: batches conserve the step's ingredient totals",
    stagedErr == nil, stagedErr)
  check("integration: a batch's staging fits a turtle's 16 slots",
    fitErr == nil, fitErr)
  check("integration: planks crafted == planks consumed (nothing created or lost)",
    produced[PLANK] == consumed[PLANK] and produced[PLANK] == 500,
    tostring(produced[PLANK]) .. "/" .. tostring(consumed[PLANK]))
  check("integration: sticks produced cover the order",
    produced["minecraft:stick"] >= 1000, produced["minecraft:stick"])
  check("integration: logs consumed match the planks step",
    consumed["minecraft:oak_log"] == deep[1].times,
    tostring(consumed["minecraft:oak_log"]))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
