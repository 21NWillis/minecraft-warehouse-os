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
-- selected item, refilling from a dock if needed). Optional ops.checkDown
-- (block)->bool makes reruns idempotent. onProgress(done,total) opt.
-- resume_ = { pose=, from= } continues a plan mid-way from a known pose.
-- Returns placed count, error, final pose. On both success and error the
-- turtle parks over the origin column, as low as the built corner allows -
-- a deterministic spot a resume can trust.
function builder.run(plan, ops, onProgress, resume_)
  local pose = resume_ and resume_.pose or newPose()
  local from = resume_ and resume_.from or 1
  local total = #plan
  local maxY = 0
  for _, p in ipairs(plan) do if p.y > maxY then maxY = p.y end end
  local function park()
    -- best-effort: rise clear, fly home over the top, settle at the origin
    -- column (rests on the built corner stack / start marker)
    moveTo(ops, pose, 0, maxY + 2, 0)
    while pose.y > 0 and ops.down() do pose.y = pose.y - 1 end
    return pose
  end
  for i = from, total do
    local p = plan[i]
    -- target hover cell is one above the block we place downward
    if not moveTo(ops, pose, p.x, p.y + 1, p.z) then
      return i - 1, "navigation blocked near " .. p.x .. "," .. p.y .. "," .. p.z, park()
    end
    -- resumable: if this cell already holds the right block (a rerun after
    -- running dry or a reboot), skip it - reruns are idempotent.
    if not (ops.checkDown and ops.checkDown(p.block)) then
      if ops.ensure and not ops.ensure(p.block) then
        -- out of this material: if a dock is configured, fly home, restock,
        -- come back. Lets a 16-slot turtle build far beyond its hold.
        if ops.dock then
          moveTo(ops, pose, 0, maxY + 2, 0)
          ops.dock(p.block)
          if not ops.ensure(p.block) then
            return i - 1, "dock lacks material: " .. p.block, park()
          end
          if not moveTo(ops, pose, p.x, p.y + 1, p.z) then
            return i - 1, "navigation blocked returning to " .. p.x .. "," .. p.y .. "," .. p.z, park()
          end
        else
          return i - 1, "out of material: " .. p.block, park()
        end
      end
      if not ops.placeDown(p.block) then
        return i - 1, "placement failed at " .. p.x .. "," .. p.y .. "," .. p.z, park()
      end
    end
    if onProgress then onProgress(i, total) end
  end
  return total, nil, park()
end

-- Resume a partial build from a KNOWN pose (persisted at park time, or the
-- datum-frame pose a wrapper like datacenter tracks). Placements are always a
-- strict prefix of the plan, so the first missing block is found by binary
-- search with fly-over probes (~12 probes for a 4000-block plan), then the
-- remainder runs normally with checkDown making revisits idempotent.
-- Requires ops.checkDown. Returns like builder.run.
function builder.resume(plan, ops, onProgress, pose)
  if not ops.checkDown then return 0, "resume requires ops.checkDown" end
  local maxY = 0
  for _, p in ipairs(plan) do if p.y > maxY then maxY = p.y end end
  local function lift()
    while pose.y < maxY + 2 do
      if not ops.up() then return false end
      pose.y = pose.y + 1
    end
    return true
  end
  if not lift() then return 0, "cannot reach flight level above the build" end
  local function placedAt(i)
    local p = plan[i]
    if not moveTo(ops, pose, p.x, math.max(pose.y, maxY + 2), p.z) then return nil end
    while pose.y > p.y + 1 do
      if not ops.down() then
        -- blocked above the target: later work exists here, so it's placed
        return lift() and true or nil
      end
      pose.y = pose.y - 1
    end
    local placed = ops.checkDown(p.block)
    if not lift() then return nil end
    return placed
  end
  local lo, hi = 1, #plan + 1        -- find the first unplaced entry
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    local placed = placedAt(mid)
    if placed == nil then return 0, "probe blocked - airspace above the build must be clear" end
    if placed then lo = mid + 1 else hi = mid end
  end
  if lo > #plan then                 -- nothing missing; just park
    moveTo(ops, pose, 0, maxY + 2, 0)
    while pose.y > 0 and ops.down() do pose.y = pose.y - 1 end
    return #plan, nil, pose
  end
  -- align over the first missing block's column, then continue the plan;
  -- run()'s vertical-first descent there is clear (nothing above a prefix end)
  local p = plan[lo]
  if not moveTo(ops, pose, p.x, math.max(pose.y, maxY + 2), p.z) then
    return lo - 1, "cannot reach resume point", pose
  end
  return builder.run(plan, ops, onProgress, { pose = pose, from = lo })
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
    checkDown = function(want)
      local ok, info = turtle.inspectDown()
      return ok and info.name == want
    end,
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
    -- reclaim safely: restocking may have filled EVERY slot (including the
    -- chest's own, via overflow) - digging the chest into a full inventory
    -- drops it on the ground to despawn. Guarantee a home for it first.
    turtle.select(chestSlot)
    if turtle.getItemCount(chestSlot) > 0 then
      turtle.dropUp()                       -- give one stack back to the chest
    end
    if turtle.getItemCount(chestSlot) > 0 then
      -- still jammed: leave the chest mounted rather than lose it
      print("!! inventory jammed; ender chest left placed above home spot")
      return
    end
    turtle.digUp()
    local back = false
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and d.name == ECHEST then back = true break end
    end
    if not back then
      print("!! ender chest not reclaimed - check on/above the home column")
    end
  end
  return ops
end

-- Anchor pose for a pose-free resume: the turtle is physically placed ON TOP
-- of the origin column's highest planned block (for a tower: on the roofline
-- corner where the build started), facing the original build direction.
-- Only valid once the origin column is fully built (i.e. the stop happened
-- after the base topped out) - true for any failure above the first layers.
function builder.anchorPose(plan)
  local top = -1
  for _, p in ipairs(plan) do
    if p.x == 0 and p.z == 0 and p.y > top then top = p.y end
  end
  return { x = 0, y = top + 1, z = 0, f = 0 }
end

builder._internal = { moveTo = moveTo, newPose = newPose, DIRS = DIRS }
return builder
