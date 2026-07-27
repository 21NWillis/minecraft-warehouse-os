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
      return i - 1, "out of material: " .. p.block
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

builder._internal = { moveTo = moveTo, newPose = newPose, DIRS = DIRS }
return builder
