-- courier: fleet logistics turtle. Loops forever: fly the casino channels,
-- harvest every strainer directly from above (suckDown - they're pure
-- inventories), haul the cargo to the warehouse input barrels, repeat.
-- Pipes are for people who don't have a fleet.
--
-- Setup: a dedicated turtle (label it courier-1) parked ON the gold datum
-- facing campus-north, with a stack of coal in slot 1. Run `courier`.
-- It refuels itself from slot 1 and parks back on the datum between rounds.
-- Stop it with Ctrl+T; it finishes the current leg gracefully on next loop.
local campus = require("campus")

local ROUND_SLEEP = 120     -- seconds between rounds
local FUEL_MIN = 600        -- refuse to launch a round below this

local casino = campus.site("casino")
local warehouse = campus.site("warehouse")
local cs = casino.gen()

local pose = { x = 0, y = 0, z = 0, f = 0 }
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function face(target)
  while pose.f ~= target do
    if (target - pose.f) % 4 == 3 then turtle.turnLeft(); pose.f = (pose.f + 3) % 4
    else turtle.turnRight(); pose.f = (pose.f + 1) % 4 end
  end
end
local function vmove(up)
  local ok = up and turtle.up() or turtle.down()
  if ok then pose.y = pose.y + (up and 1 or -1) end
  return ok
end
local function fwd()
  if not turtle.forward() then return false end
  pose.x = pose.x + DIRS[pose.f][1]
  pose.z = pose.z + DIRS[pose.f][2]
  return true
end
local function goTo(x, y, z)
  local cruise = (pose.y == y) and y or math.max(y, 2)
  while pose.y < cruise do if not vmove(true) then return false end end
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

local function cargoUsed()
  local n = 0
  for slot = 2, 16 do
    if turtle.getItemCount(slot) > 0 then n = n + 1 end
  end
  return n
end

local function round()
  -- refuel from slot 1
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < FUEL_MIN then
    turtle.select(1)
    while turtle.getFuelLevel() < FUEL_MIN * 2 and turtle.refuel(1) do end
    turtle.select(2)
    if turtle.getFuelLevel() < FUEL_MIN then
      print("low fuel and slot 1 is dry - waiting")
      return false
    end
  end

  -- harvest every strainer from above: they're pure inventories, and
  -- turtle.suckDown pulls their catch - no pipes, no hoppers, no config.
  -- MESH GUARD: if a suck yanks the cloth mesh (the strainer's own part)
  -- instead of loot, put it straight back and move to the next one.
  local ca = casino.at
  local hauled = 0
  for _, cell in ipairs(cs.meta.strainers) do
    if cargoUsed() >= 14 then break end       -- hold nearly full, go deliver
    local x, y, z = ca[1] + cell[1], ca[2] + cell[2] + 1, ca[3] + cell[3]
    if goTo(x, y, z) then
      for _ = 1, 27 do
        local before = {}
        for s = 2, 16 do before[s] = turtle.getItemCount(s) end
        if not turtle.suckDown() then break end
        local gotMesh = false
        for s = 2, 16 do
          if turtle.getItemCount(s) > (before[s] or 0) then
            local d = turtle.getItemDetail(s)
            if d and d.name:find("mesh") then
              turtle.select(s)
              turtle.dropDown()
              gotMesh = true
            end
          end
        end
        turtle.select(2)
        if gotMesh then break end     -- only its mesh left; next strainer
        hauled = hauled + 1
      end
    end
  end

  local wa = warehouse.at
  if not goTo(wa[1] + 20, 2, wa[3] + 6) then return false end
  if not goTo(wa[1] + 16, 2, wa[3] + 6) then return false end   -- through the door

  -- dump everything except slot 1 into the input barrels (local x1,z1,y1..2)
  for _, iy in ipairs({ 1, 2 }) do
    if not goTo(wa[1] + 2, wa[2] + iy, wa[3] + 1) then return false end
    face(3)
    for slot = 2, 16 do
      if turtle.getItemCount(slot) > 0 then
        turtle.select(slot)
        turtle.drop()
      end
    end
  end
  turtle.select(2)

  -- home to the datum
  if not goTo(wa[1] + 16, 2, wa[3] + 6) then return false end
  if not goTo(wa[1] + 20, 2, wa[3] + 6) then return false end
  goTo(0, 2, 0)
  goTo(0, 0, 0)
  face(0)
  print(("round done: %d stacks hauled, fuel %s"):format(hauled, tostring(turtle.getFuelLevel())))
  return true
end

print("courier online: casino barrels -> warehouse inputs, every " .. ROUND_SLEEP .. "s")
while true do
  local ok, err = pcall(round)
  if not ok then print("round error: " .. tostring(err)) end
  sleep(ROUND_SLEEP)
end
