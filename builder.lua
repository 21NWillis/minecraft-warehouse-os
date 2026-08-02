-- builder: executes a build plan by driving movement/placement primitives.
-- Transport-agnostic: `ops` is the turtle API for real builds, or a mock that
-- updates a virtual world in tests. The SAME navigation runs in both, so the
-- algorithm is proven headless before a turtle ever moves.
--
-- Frame of reference: the turtle starts at the schematic origin corner (0,0,0)
-- at build-height (one above the floor), facing +z. It tracks its own pose and
-- flies over already-placed layers, placing blocks downward.
local builder = {}

-- facings as (dx, dz); index 0..3 turning clockwise from +z
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function newPose()
  return { x = 0, y = 1, z = 0, f = 0 }  -- y=1: hovering above the floor layer
end

local function face(ops, pose, target)
  local diff = (target - pose.f) % 4
  if diff == 1 then ops.turnRight(); pose.f = target
  elseif diff == 3 then ops.turnLeft(); pose.f = target
  elseif diff == 2 then ops.turnRight(); ops.turnRight(); pose.f = target end
end

local function stepForward(ops, pose)
  if ops.forward() then
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  return false
end

local function moveTo(ops, pose, tx, ty, tz)
  -- vertical first: we fly above placed work, so up/down is always clear
  while pose.y < ty do if ops.up() then pose.y = pose.y + 1 else return false end end
  while pose.y > ty do if ops.down() then pose.y = pose.y - 1 else return false end end
  -- x axis
  if tx > pose.x then face(ops, pose, 1) elseif tx < pose.x then face(ops, pose, 3) end
  while pose.x ~= tx do if not stepForward(ops, pose) then return false end end
  -- z axis
  if tz > pose.z then face(ops, pose, 0) elseif tz < pose.z then face(ops, pose, 2) end
  while pose.z ~= tz do if not stepForward(ops, pose) then return false end end
  return true
end

-- run a plan. ops must provide: up/down/forward/turnLeft/turnRight ->bool,
-- placeDown(block)->bool, and ensure(block)->bool (make the named block the
-- selected item, refilling from a dock if needed). onProgress(done,total) opt.
-- Returns placed count, error.
function builder.run(plan, ops, onProgress)
  local pose = newPose()
  local total = #plan
  local maxY = 0
  for _, p in ipairs(plan) do if p.y > maxY then maxY = p.y end end
  for i, p in ipairs(plan) do
    if ops.ensure and not ops.ensure(p.block) then
      -- out of this material: if a dock is configured, fly home, restock, and
      -- resume. Lets a 16-slot turtle build structures far larger than its hold.
      if ops.dock then
        moveTo(ops, pose, 0, maxY + 2, 0)
        ops.dock(p.block)
        if not ops.ensure(p.block) then
          return i - 1, "dock lacks material: " .. p.block
        end
      else
        return i - 1, "out of material: " .. p.block
      end
    end
    -- target hover cell is one above the block we place downward
    if not moveTo(ops, pose, p.x, p.y + 1, p.z) then
      return i - 1, "navigation blocked near " .. p.x .. "," .. p.y .. "," .. p.z
    end
    if not ops.placeDown(p.block) then
      return i - 1, "placement failed at " .. p.x .. "," .. p.y .. "," .. p.z
    end
    if onProgress then onProgress(i, total) end
  end
  -- return home: rise clear above the whole structure first, then travel back
  -- over the top (never routing through the blocks we just placed)
  moveTo(ops, pose, 0, maxY + 2, 0)
  return total, nil
end

-- standard in-game ops for builder.run: real turtle moves, slot-scan ensure,
-- and ender-chest network refill (deploy overhead, pull stacks, reclaim).
-- Only touches the turtle API when actually called, so requiring this stays
-- headless-safe. opts.enderChest overrides the refill chest id. opts.track
-- (fn(opName)) is called after every successful move/turn - lets a caller
-- mirror the turtle's pose in a second frame (datacenter's datum frame).
function builder.turtleOps(opts)
  opts = opts or {}
  local ECHEST = opts.enderChest or "enderstorage:ender_chest"
  local track = opts.track
  local function tracked(name, fn)
    return function()
      local ok = fn()
      if ok and track then track(name) end
      return ok
    end
  end
  local ops = {
    up = tracked("up", turtle.up),
    down = tracked("down", turtle.down),
    forward = tracked("forward", turtle.forward),
    turnLeft = tracked("turnLeft", function() turtle.turnLeft() return true end),
    turnRight = tracked("turnRight", function() turtle.turnRight() return true end),
    placeDown = function() return turtle.placeDown() end,
    ensure = function(want)
      local cur = turtle.getItemDetail()
      if cur and cur.name == want then return true end
      for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and d.name == want then turtle.select(slot); return true end
      end
      return false
    end,
  }
  -- network refill via a carried ender chest: deploy overhead, pull stacks,
  -- reclaim. Pose-neutral (placeUp/suckUp/digUp don't move the turtle).
  ops.dock = function()
    local chestSlot
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and d.name == ECHEST then chestSlot = slot break end
    end
    if not chestSlot then return end        -- no chest carried; builder will fail
    turtle.select(chestSlot)
    if not turtle.placeUp() then return end
    for slot = 1, 16 do
      if slot ~= chestSlot then
        turtle.select(slot)
        turtle.suckUp(64)
      end
    end
    turtle.select(chestSlot)
    turtle.digUp()
  end
  return ops
end

builder._internal = { moveTo = moveTo, newPose = newPose, DIRS = DIRS }
return builder
