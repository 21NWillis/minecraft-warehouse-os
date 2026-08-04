-- gunfit: builds a row of Dyson Cube EM Rail Ejectors ("guns").
-- Source-verified mechanics (InnovativeOnlineIndustries/Dyson-Cube-Project):
--   * the ENTIRE gun is ONE controller item - on placement it
--     validates a 3x3x3 volume of PURE AIR (controller bottom-center)
--     and manifests its own structure blocks. No constituents.
--   * power + items feed the controller (bottom-center block).
--   * guns only fire in daytime/clear weather; power ramps ejection.
-- Because turtles ARE blocks, a turtle standing beside the placement
-- spot fails the air validation - so the build happens FROM BELOW:
-- the turtle lays a 3-wide platform with a center pipe trench, then
-- tunnels the trench placing controllers UPWARD (outside every
-- volume) and item pipes behind itself as it retreats.
--
-- RITUAL: place the turtle at the strip's near end, at TRENCH level
-- (one below where the guns will stand), facing down the row (+z,
-- go-forward test). Clearance: 3 wide, 3*N long, 4 tall above the
-- turtle. Load: floor blocks (slot 1 sets the material, ~6 per gun),
-- N x EM Rail Ejector Controller, ~3N+2 pipez item pipes, 1 chest,
-- ~10 coal.  Usage: gunfit <gunCount>
--
-- After (operator): feeder chest at the trench mouth gets a pipez
-- extract upgrade; connect energy to any controller per your flux
-- network; stock sails/beams; daylight does the rest.
local CONTROLLER = "dysoncubeproject:em_railejector_controller"
local PIPE = "pipez:item_pipe"
local CHEST_ITEMS = { "sophisticatedstorage:netherite_chest", "minecraft:chest" }

local tArgs = { ... }
local N = tonumber(tArgs[1] or "")
if not N or N < 1 then
  print("usage: gunfit <gunCount>")
  return
end

local function ensure(name)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name == name then turtle.select(slot) return true end
  end
  return false
end

local function ensureAny(names)
  for _, n in ipairs(names) do
    if ensure(n) then return true end
  end
  return false
end

local floorD = turtle.getItemDetail(1)
if not floorD then
  print("slot 1 must hold the floor block")
  return
end
local FLOOR = floorD.name

for slot = 1, 16 do
  local d = turtle.getItemDetail(slot)
  if d and d.name == "minecraft:coal" then turtle.select(slot); turtle.refuel(64) end
end
turtle.select(1)

-- frame: turtle start = (x=1 center column, y=-1 trench level, z=-1),
-- facing +z. Strip: x0..2, z0..3N-1. Floor at y-1 on side columns,
-- trench (pipes) at y-1 center column, controllers at y0 center of
-- each 3x3 (z = 3k+1), guns' structure self-builds at y0..y2.
print(("gunfit: %d guns, floor=%s"):format(N, FLOOR))

-- pass 1: side floor columns from above (y0), skipping the center
local pose = { x = 0, z = -1 }   -- track loosely; movements are scripted
turtle.up()                      -- to y0
for _, xCol in ipairs({ 0, 2 }) do
  -- move to column start: from center start cell, sidestep
  if xCol == 0 then turtle.turnLeft() else turtle.turnRight() end
  turtle.forward()
  if xCol == 0 then turtle.turnRight() else turtle.turnLeft() end
  turtle.up()                    -- fly at y1 over the column, placeDown
  for z = 0, 3 * N - 1 do
    turtle.forward()
    if not turtle.detectDown() then
      if not ensure(FLOOR) then printError("out of floor blocks") return end
      turtle.placeDown()
    end
  end
  -- return to start of column at y0
  turtle.turnLeft() turtle.turnLeft()
  for z = 0, 3 * N - 1 do turtle.forward() end
  turtle.down()
  -- back to center column
  if xCol == 0 then turtle.turnLeft() else turtle.turnRight() end
  turtle.forward()
  if xCol == 0 then turtle.turnLeft() else turtle.turnRight() end
  turtle.turnLeft() turtle.turnLeft()
  -- now facing +z again at center (1, y0, -1)
end
turtle.down()                    -- back to trench level y-1

-- pass 2: tunnel forward at trench level to the far end, then retreat
-- placing controllers UP (at each 3k+1) and pipes into vacated cells
for z = 0, 3 * N - 1 do
  if turtle.detect() then turtle.dig() end
  if not turtle.forward() then printError("trench blocked at z=" .. z) return end
end
-- turtle now at (1, -1, 3N-1); retreat placing behind
turtle.turnLeft() turtle.turnLeft()   -- face -z (retreat direction = forward now)
for z = 3 * N - 1, 0, -1 do
  if z % 3 == 1 then
    if not ensure(CONTROLLER) then printError("out of controllers") return end
    if not turtle.placeUp() then
      printError(("controller refused at gun %d - is its 3x3x3 clear?"):format(math.floor(z / 3) + 1))
      return
    end
    print(("gun %d placed"):format(math.floor(z / 3) + 1))
  end
  if not turtle.forward() then printError("retreat blocked") return end
  -- pipe into the cell just vacated (behind = the gun side now)
  turtle.turnLeft() turtle.turnLeft()
  if ensure(PIPE) then turtle.place() end
  turtle.turnLeft() turtle.turnLeft()
end
-- at (1,-1,-1) facing -z; place the feeder chest ahead (trench mouth)
if ensureAny(CHEST_ITEMS) then
  turtle.place()
  print("feeder chest set at the trench mouth")
end
turtle.turnLeft() turtle.turnLeft()
print(("DONE: %d guns. Operator: extract upgrade on the feeder chest,"):format(N))
print("energy to any controller, stock sails/beams. Fire at dawn.")
