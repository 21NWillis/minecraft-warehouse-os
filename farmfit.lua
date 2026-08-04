-- farmfit: builds one Mystical Agriculture HYPERSCALE farm pod - the
-- repeatable unit of the resource-generation program.
--
-- Pod anatomy (11x11 self-contained floating platform, safe over void):
--   * base slab 11x11 (purple concrete, campus palette)
--   * 9x9 essence farmland bed inset, center cell = water (hydration -
--     every bed cell is within vanilla's 4-block range)
--   * IF Plant Sower + Plant Gatherer ON THE SOUTH RIM facing the bed
--   * NO moving parts, NO turtle couriers: gatherer output leaves via
--     pipez ultimate straight into the ME system (operator hookup)
--   * growth goes DOWN: accelerator pillars hang under each crop column
--     later (stackable, any tier, range measured from under the
--     farmland) - the pod's underside is deliberately left open
--
-- SETUP: park the turtle at BED level facing +z (go-forward test =
-- campus north); the pod fills 11x11 starting ONE BLOCK AHEAD of it
-- (turtle's own column stays clear - it parks there between builds),
-- extending rightward/forward, base one block below. Load the bill
-- (farmfit bill). Pods tile on a 12-block grid (1-block air gap):
-- finish one, move the turtle 12 right (or forward), run again.
--
-- After the build (operator pass):
--   1. Range Addon (tier 4+) into BOTH sower and gatherer; aim/offset
--      their work areas over the 9x9 bed (colored face toward bed)
--   2. lock the sower's filter to ONE seed type - one pod, one resource
--   3. universal cable to both machines; pipez ultimate on the
--      gatherer's back (rim side) -> ME interface / storage
--   4. drop the seed stock in the sower. Walk away forever.
--
-- Crash/restock recovery: farmfit.state resumes at the exact step;
-- re-place the turtle at its start corner first. A FINISHED pod
-- refuses a fresh rerun (its own slab blocks the base-laying stands);
-- that refusal is normal - move on to the next pod site.
local FARMLAND = "mysticalagriculture:inferium_farmland"
local B = {
  BASE = "minecraft:purple_concrete",
  FARMLAND = FARMLAND,
  SOWER = "industrialforegoing:plant_sower",
  GATHERER = "industrialforegoing:plant_gatherer",
  BUCKET = "minecraft:water_bucket",
}

-- The plan is generated, not hand-written: 121 base cells, rim walkway,
-- 80 farmland, 2 machines on the south rim, water dead last.
-- Frame: turtle start = (0,0,0) = pod SW corner at bed level, +z north.
local function genPlan()
  local plan = {}
  -- pod occupies z 1..11 (one block ahead of the turtle's parking column)
  -- base slab at y=-1: hover at bed level, placeDown
  for z = 1, 11 do
    for x = 0, 10 do
      plan[#plan + 1] = { stand = { x, 0, z }, dir = "down", block = B.BASE }
    end
  end
  -- rim walkway at y0 (edges), skipping the two machine cells
  for z = 1, 11 do
    for x = 0, 10 do
      local rim = (x == 0 or x == 10 or z == 1 or z == 11)
      local machine = (z == 1) and (x == 4 or x == 5)
      if rim and not machine then
        plan[#plan + 1] = { stand = { x, 1, z }, dir = "down", block = B.BASE }
      end
    end
  end
  -- machines on the south rim: gatherer at x4, sower at x5 (operator
  -- aims their areas; placement orientation is wrench-fixable)
  plan[#plan + 1] = { stand = { 4, 1, 1 }, dir = "down", block = B.GATHERER }
  plan[#plan + 1] = { stand = { 5, 1, 1 }, dir = "down", block = B.SOWER }
  -- 9x9 essence farmland bed, center (5,0,6) left open for water
  for z = 2, 10 do
    for x = 1, 9 do
      if not (x == 5 and z == 6) then
        plan[#plan + 1] = { stand = { x, 1, z }, dir = "down", block = B.FARMLAND }
      end
    end
  end
  -- water last (the turtle never has to swim)
  plan[#plan + 1] = { stand = { 5, 1, 6 }, dir = "down", block = B.BUCKET, water = true }
  return plan
end

local PLAN = genPlan()
local CRUISE = 2

local function bill()
  local mats = {}
  for _, p in ipairs(PLAN) do mats[p.block] = (mats[p.block] or 0) + 1 end
  return mats
end

local function targetCell(p)
  return p.stand[1], p.stand[2] - 1, p.stand[3]
end

local function run(t, report, startStep)
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

  local function face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then t.turnLeft(); pose.f = (pose.f + 3) % 4
      else t.turnRight(); pose.f = (pose.f + 1) % 4 end
    end
  end
  local function vmove(up)
    local ok = up and t.up() or t.down()
    if ok then pose.y = pose.y + (up and 1 or -1) end
    return ok
  end
  local function fwd()
    if not t.forward() then return false end
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  local function goTo(x, y, z)
    while pose.y < CRUISE do if not vmove(true) then return false end end
    while pose.x ~= x do
      face(pose.x < x and 1 or 3)
      if not fwd() then return false end
    end
    while pose.z ~= z do
      face(pose.z < z and 0 or 2)
      if not fwd() then return false end
    end
    while pose.y > y do if not vmove(false) then return false end end
    return true
  end
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then t.select(slot) return true end
    end
    return false
  end

  local placed = 0
  for i = startStep or 1, #PLAN do
    local p = PLAN[i]
    local s = p.stand
    if not goTo(s[1], s[2], s[3]) then
      return false, "blocked reaching stand for step " .. i .. " (" .. p.block .. ")"
    end
    if not t.detectDown() then
      if not ensure(p.block) then return false, "out of " .. p.block end
      if not t.placeDown() and not p.water then
        return false, "cannot place " .. p.block .. " at step " .. i
      end
      placed = placed + 1
    end
    if report then report(i, #PLAN) end
  end

  goTo(0, CRUISE, 0)
  while pose.y > 0 do if not vmove(false) then break end end
  face(0)
  return true, placed
end

local M = { run = run, PLAN = PLAN, bill = bill, targetCell = targetCell,
  BLOCKS = B, CRUISE = CRUISE }
if _TEST then return M end

-- ==================================================================== program
local args = { ... }
if args[1] == "bill" then
  print("farmfit bill - PER POD (operator adds: 2x Range Addon tier 4+,")
  print("cable, pipez ultimate, seeds; later: 81x growth accelerator/layer):")
  for block, n in pairs(bill()) do
    print(("  %3d x %s"):format(n, block))
  end
  print("  ~40 coal fuel")
  print("pods tile on a 12-block grid (1 air gap between pods)")
  return
end

print("farmfit: one 11x11 MA farm pod (bed + rim + sower/gatherer)")
local STATE = "farmfit.state"
local startStep = 1
if fs.exists(STATE) then
  local h = fs.open(STATE, "r")
  startStep = tonumber(h.readAll()) or 1
  h.close()
  print(("resuming at step %d/%d"):format(startStep, #PLAN))
end
local ok, res = run(turtle, function(i, n)
  local h = fs.open(STATE, "w")
  h.write(tostring(i + 1))
  h.close()
  if i % 25 == 0 or i == n then print(("step %d/%d"):format(i, n)) end
end, startStep)
if ok then
  if fs.exists(STATE) then fs.delete(STATE) end
  print(("pod built (%d new blocks)."):format(res))
  print("YOUR pass: range addons + aim areas, lock sower filter to ONE")
  print("seed, cable both machines, pipez ultimate: gatherer -> ME.")
  print("Next pod: move me 12 blocks right or forward, rerun farmfit.")
else
  printError("stopped: " .. tostring(res))
  printError("restock, re-place me at the start corner, rerun to resume")
end
