-- skyladder: bootstraps the sky campus commute from the cornerstone.
--
-- One run does both jobs:
--   1. builds a climbable scaffolding column from the ground up to campus
--      level, one block outside the future pad's rim (hold jump inside
--      scaffolding to climb, sneak to descend, hop up onto the pad rim)
--   2. places the GOLD DATUM BLOCK at stand height 200 and finishes
--      standing on it, facing campus-north - ready for `datacenter build pad`
--
-- Setup: place the turtle ON TOP of the tower's front-left base-roof corner
-- (the anchor spot - the ground cornerstone cell is inside the tower wall
-- now), facing into the building, loaded with:
--   ~200 scaffolding, 1 gold block, ~10 coal (refuel first if low)
-- Rerun-safe: if it runs out of scaffolding partway, add more and rerun -
-- it flies over the top and lands on the existing column to continue.
local SCAFF = "minecraft:scaffolding"
local GOLD = "minecraft:gold_block"
local HEIGHT = 200      -- datum stand height above ground/cornerstone level
local START_Y = 8       -- the anchor spot: on top of the base-roof corner
local COL_Z = -9        -- scaffold column: one block outside the pad rim

local function run(t)
  local pose = { x = 0, y = START_Y, z = 0, f = 0 }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then t.turnLeft(); pose.f = (pose.f + 3) % 4
      else t.turnRight(); pose.f = (pose.f + 1) % 4 end
    end
  end
  local function up()
    if not t.up() then return false end
    pose.y = pose.y + 1
    return true
  end
  local function down()
    if not t.down() then return false end
    pose.y = pose.y - 1
    return true
  end
  local function fwd()
    if not t.forward() then return false end
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then t.select(slot) return true end
    end
    return false
  end

  -- 1. climb the corner column to just under campus level (always clear:
  -- nothing of the tower or a finished datum occupies this column below 199),
  -- then fly out over the scaffold column position
  while pose.y < HEIGHT - 2 do
    if not up() then return false, "blocked climbing above the anchor at height " .. pose.y end
  end
  face(2)
  for _ = 1, -COL_Z do
    if not fwd() then return false, "blocked flying out over the column spot" end
  end

  -- 2. drop to the ground (or the top of an existing column on a rerun)
  while not t.detectDown() do
    if pose.y < -10 then return false, "no ground found below the column spot" end
    if not down() then return false, "blocked descending to the ground" end
  end
  print(("column base at height %d; building to %d..."):format(pose.y, HEIGHT - 1))

  -- 3. the column: rise and fill the cell behind us with scaffolding
  while pose.y < HEIGHT - 1 do
    if not up() then return false, "blocked at height " .. pose.y end
    if not t.detectDown() then
      if not ensure(SCAFF) then
        return false, ("out of scaffolding at height %d - add more and rerun"):format(pose.y)
      end
      if not t.placeDown() then
        return false, "cannot place scaffolding at height " .. pose.y
      end
    end
    if pose.y % 25 == 0 then print("height " .. pose.y) end
  end

  -- 4. over to the datum cell and place the gold block
  if not up() then return false, "blocked topping out" end
  face(0)
  for _ = 1, -COL_Z do
    if not fwd() then return false, "blocked flying to the datum cell" end
  end
  if t.detectDown() then
    print("datum already placed; standing on it")
  else
    if not ensure(GOLD) then return false, "no gold block aboard for the datum" end
    if not t.placeDown() then return false, "cannot place the datum block" end
  end
  face(0)
  return true
end

local M = { run = run, HEIGHT = HEIGHT, COL_Z = COL_Z }
if _TEST then return M end

-- ==================================================================== program
print("skyladder: scaffolding column + gold datum, from the cornerstone")
local ok, err = run(turtle)
if ok then
  print("done. I'm standing on the datum, facing campus-north.")
  print("next: datacenter build pad")
  print("(you: climb inside the scaffolding - hold jump up, sneak down)")
else
  printError("stopped: " .. tostring(err))
end
