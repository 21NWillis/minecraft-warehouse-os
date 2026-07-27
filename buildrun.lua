-- buildrun: turtle program that builds a generated schematic from its own
-- inventory. Place the turtle at the build origin (bottom-front-left corner),
-- facing into the build (+z), with materials + fuel loaded, then e.g.:
--   buildrun box 16 10 16 minecraft:stone
--   buildrun floor 9 9 minecraft:oak_planks
--   buildrun cylinder 5 8 minecraft:glass
--   buildrun tower 12 8 12 minecraft:stone   (hollow box + floor + roof)
-- It flies bottom-up placing blocks downward, and beams progress over starlink
-- if an ender/wireless modem is attached.
local schematic = require("schematic")
local builder = require("builder")

local args = { ... }
local shape = args[1]

local function usage()
  print("buildrun <shape> <dims...> <block>")
  print("  box W H D block      hollow walls only")
  print("  tower W H D block     walls + floor + roof")
  print("  floor W D block")
  print("  solid W H D block")
  print("  cylinder R H block")
  print("  evilhq W H [wall glow spire]   Paperclip Corp HQ")
end

local s, block
if shape == "box" or shape == "solid" or shape == "tower" then
  local w, h, d = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
  block = args[5]
  if not (w and h and d and block) then usage() return end
  if shape == "solid" then s = schematic.solid(w, h, d, block)
  elseif shape == "tower" then s = schematic.hollowBox(w, h, d, block, { floor = true, roof = true })
  else s = schematic.hollowBox(w, h, d, block, { floor = true }) end
elseif shape == "floor" then
  local w, d = tonumber(args[2]), tonumber(args[3])
  block = args[4]
  if not (w and d and block) then usage() return end
  s = schematic.floor(w, d, block)
elseif shape == "cylinder" then
  local r, h = tonumber(args[2]), tonumber(args[3])
  block = args[4]
  if not (r and h and block) then usage() return end
  s = schematic.cylinder(r, h, block)
elseif shape == "evilhq" then
  local w, h = tonumber(args[2]), tonumber(args[3])
  if not (w and h) then usage() return end
  -- palette optional: buildrun evilhq 9 20 [wall glow spire]
  s = schematic.evilTower(w, h, { wall = args[4], glow = args[5], spire = args[6] })
else
  usage() return
end

local plan = s:plan()
local mats = s:materials()
print(("plan: %d blocks, %d placements"):format(s:count(), #plan))
for b, n in pairs(mats) do print(("  need %d x %s"):format(n, b)) end

-- fuel: turtles burn 1 fuel per move. estimate generously and refuel from any
-- fuel item in the inventory before starting.
local estMoves = #plan * 3 + s.h * 4
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < estMoves then
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then turtle.refuel() end
  end
  print(("fuel: %s (est need %d)"):format(tostring(turtle.getFuelLevel()), estMoves))
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < estMoves then
    print("WARNING: may run out of fuel mid-build")
  end
end

-- optional starlink progress beacon
local net
do
  local ok, starlink = pcall(require, "starlink")
  if ok then
    net = starlink.new("builder-" .. os.getComputerID(), "builder")
  end
end

-- turtle ops. ensure() selects a slot holding the needed block (turtles hold
-- one build material per slot; we scan on demand and cache the current pick).
local ops = {
  up = turtle.up, down = turtle.down, forward = turtle.forward,
  turnLeft = turtle.turnLeft, turnRight = turtle.turnRight,
  ensure = function(want)
    local cur = turtle.getItemDetail()
    if cur and cur.name == want then return true end
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and d.name == want then turtle.select(slot); return true end
    end
    return false
  end,
  placeDown = function() return turtle.placeDown() end,
}

-- network-refill via a carried ender chest (reserve a slot for one, stocked
-- from the warehouse). When the builder runs dry it flies home-high and calls
-- this: deploy the chest above, pull build materials, reclaim it. Pose-neutral
-- (place/suck/dig up don't move the turtle), so the builder's tracking holds.
local ENDER_CHEST = "enderstorage:ender_chest"
ops.dock = function(want)
  local chestSlot
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name == ENDER_CHEST then chestSlot = slot break end
  end
  if not chestSlot then return end          -- no chest carried; builder will fail
  turtle.select(chestSlot)
  if not turtle.placeUp() then return end
  for slot = 1, 16 do
    if slot ~= chestSlot then
      turtle.select(slot)
      turtle.suckUp(64)                       -- pull stacks of build materials
    end
  end
  turtle.select(chestSlot)
  turtle.digUp()                              -- reclaim the ender chest
end

local start = os.epoch and os.epoch("utc") or 0
local placed, err = builder.run(plan, ops, function(done, total)
  if done % 16 == 0 or done == total then
    term.clearLine()
    local _, y = term.getCursorPos()
    term.setCursorPos(1, y)
    term.write(("building %d/%d"):format(done, total))
    if net then
      net:setTelemetry({ built = done, total = total, alt = nil })
      net:beacon()
    end
  end
end)

print("")
if err then
  print(("stopped at %d/%d: %s"):format(placed, #plan, err))
else
  print(("done: %d blocks placed"):format(placed))
end
