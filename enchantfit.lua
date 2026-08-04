-- enchantfit: builds the Apothic Enchanting workshop - a ground-side
-- hands-on room, deliberately NOT on the campus (nothing here wants
-- automation; you stand at the table and read dials).
--
-- Geometry: 7x7 pad, enchanting table dead center, shelf ring on the
-- radius-2 perimeter at table level and +1 (the exact positions the
-- enchanting table scans), the radius-1 ring left AIR (required for
-- shelf power), one door gap mid-south. Up to 30 shelf slots.
--
-- RITUAL (local build - place anywhere on solid ground):
--   1. Park the turtle on the ground at the pad's SOUTH-WEST corner
--      spot, facing the build area (+z, the go-forward test).
--   2. Load: floor blocks (49), 1 enchanting table, up to 30 shelves
--      of ANY mix (anything with "shelf" in the id counts), ~8 coal,
--      optional 4 glowstone (pad corners, mob-proofing).
--   3. enchantfit
-- Runs out of shelves? It skips the rest - hand-place later while
-- TUNING (the whole point: swap shelf types while watching the
-- table's stat readout until the window you need lights up).
-- Rerun-safe: existing blocks are skipped.
local FLOOR_SLOT = 1   -- slot 1 = whatever floor block you chose
local TABLE = "minecraft:enchanting_table"
local GLOW = "minecraft:glowstone"

local function isShelf(name)
  return name:find("shelf", 1, true) ~= nil or name:find("bookshelf", 1, true) ~= nil
end

-- pad local frame: turtle start = (0,0,0) SW corner at ground level,
-- +z forward, +x right. Pad covers x0..6, z1..7 (one ahead, like
-- farmfit - the turtle's own column stays clear). Table at (3,0,4).
local function genPlan(floorBlock)
  local plan = {}
  local function S(x, y, z, kind, block)
    plan[#plan + 1] = { stand = { x, y + 1, z }, kind = kind, block = block }
  end
  for z = 1, 7 do
    for x = 0, 6 do S(x, -1, z, "block", floorBlock) end
  end
  S(3, 0, 4, "block", TABLE)
  -- shelf ring: perimeter of the 5x5 centered on the table (radius 2),
  -- bottom layer then top; door gap at mid-south column (3, z2)
  local ring = {}
  for dx = -2, 2 do
    for dz = -2, 2 do
      if math.abs(dx) == 2 or math.abs(dz) == 2 then
        if not (dx == 0 and dz == -2) then   -- door gap
          ring[#ring + 1] = { 3 + dx, 4 + dz }
        end
      end
    end
  end
  for _, y in ipairs({ 0, 1 }) do
    for _, c in ipairs(ring) do S(c[1], y, c[2], "shelf") end
  end
  -- glowstone pad corners (light; outside the scanned ring)
  for _, c in ipairs({ { 0, 1 }, { 6, 1 }, { 0, 7 }, { 6, 7 } }) do
    S(c[1], 2, c[2], "glow", GLOW)
  end
  return plan
end

local function run(t, opts)
  local plan = genPlan(opts.floorBlock)
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local CRUISE = 3

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
  local function goTo(x, y, z)
    if pose.x == x and pose.y == y and pose.z == z then return true end
    while pose.y < CRUISE do if not vmove(true) then return false end end
    while pose.x ~= x do
      face(pose.x < x and 1 or 3)
      if not t.forward() then return false end
      pose.x = pose.x + DIRS[pose.f][1]
      pose.z = pose.z + DIRS[pose.f][2]
    end
    while pose.z ~= z do
      face(pose.z < z and 0 or 2)
      if not t.forward() then return false end
      pose.x = pose.x + DIRS[pose.f][1]
      pose.z = pose.z + DIRS[pose.f][2]
    end
    while pose.y > y do if not vmove(false) then return false end end
    return true
  end
  local function selectBlock(spec)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d then
        if spec.kind == "shelf" and isShelf(d.name) then t.select(slot) return true end
        if spec.kind ~= "shelf" and d.name == spec.block then t.select(slot) return true end
      end
    end
    return false
  end

  local placed, skippedShelves = 0, 0
  for i, s in ipairs(plan) do
    local st = s.stand
    if not goTo(st[1], st[2], st[3]) then
      return false, "blocked reaching step " .. i
    end
    if not t.detectDown() then
      if selectBlock(s) then
        if t.placeDown() then placed = placed + 1 end
      elseif s.kind == "shelf" then
        skippedShelves = skippedShelves + 1
      elseif s.kind == "glow" then
        -- optional: skip silently
      else
        return false, "out of " .. tostring(s.block)
      end
    end
  end
  goTo(0, CRUISE, 0)
  while pose.y > 0 do if not vmove(false) then break end end
  face(0)
  return true, placed, skippedShelves
end

local M = { run = run, genPlan = genPlan, isShelf = isShelf }
if _TEST then return M end

-- ==================================================================== program
local d1 = turtle.getItemDetail(FLOOR_SLOT)
if not d1 then
  print("put the floor block in slot 1 (plus table, shelves, coal)")
  return
end
for slot = 1, 16 do
  local d = turtle.getItemDetail(slot)
  if d and d.name == "minecraft:coal" then turtle.select(slot); turtle.refuel(64) end
end
turtle.select(1)

print("enchantfit: 7x7 workshop, floor = " .. d1.name)
local ok, placed, skipped = run(turtle, { floorBlock = d1.name })
if ok then
  print(("workshop built (%d blocks)."):format(placed))
  if skipped and skipped > 0 then
    print(("%d shelf slots left empty - fill by hand while tuning"):format(skipped))
  end
  print("TUNE: open the table, watch Eterna/Quanta/Arcana as you swap")
  print("shelves. Infused Breath window: E>=80, A>=60, Q 15..30.")
else
  printError("stopped: " .. tostring(placed))
end
