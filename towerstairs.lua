-- towerstairs: builds the Paperclip HQ internal staircase with a turtle.
--
-- A walkable block staircase: a switchback from the ground floor up under
-- the shaft mouth (digging the two ceiling blocks it must pass through),
-- then a spiral hugging the shaft wall all 18 levels, arriving through the
-- head-floor opening into the top office. Glowstone steps light the climb.
--
-- Setup: build the ground floor first (buildrun pad 13 9 ...). Then place
-- the turtle ON the floor JUST INSIDE the front door, facing INTO the room,
-- with 21 polished blackstone + 3 glowstone + a little fuel. Run: towerstairs
-- Rerun-safe: existing correct steps are skipped.
--
-- The turtle finishes upstairs in the head office. Take the elevator down.
-- (There is no elevator yet. Jump carefully.)
local TRIM = "minecraft:polished_blackstone"
local GLOW = "minecraft:glowstone"

-- tower-frame step cells, in build/walk order. false = the original roof
-- block already forms this step (kept, not placed).
local PATH = {
  -- switchback lane under the shaft's front-right mouth
  { 9, 1, 3, TRIM }, { 9, 2, 4, TRIM }, { 9, 3, 5, TRIM },
  { 9, 4, 6, TRIM }, { 9, 5, 7, TRIM }, { 8, 6, 7, TRIM },
  { 7, 7, 7, false },
  -- spiral around the 5x5 shaft interior, one rise per step
  { 6, 8, 7, TRIM }, { 5, 9, 7, GLOW },
  { 5, 10, 6, TRIM }, { 5, 11, 5, TRIM }, { 5, 12, 4, TRIM }, { 5, 13, 3, TRIM },
  { 6, 14, 3, TRIM }, { 7, 15, 3, GLOW }, { 8, 16, 3, TRIM }, { 9, 17, 3, TRIM },
  { 9, 18, 4, TRIM }, { 9, 19, 5, TRIM }, { 9, 20, 6, TRIM }, { 9, 21, 7, GLOW },
  { 8, 22, 7, TRIM }, { 7, 23, 7, TRIM }, { 6, 24, 7, TRIM }, { 5, 25, 7, TRIM },
}

-- start pose: on the floor just inside the door, facing +z
local START = { x = 7, y = 1, z = 1, f = 0 }
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function run(t, report)
  local pose = { x = START.x, y = START.y, z = START.z, f = START.f }

  local function face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then
        t.turnLeft()
        pose.f = (pose.f + 3) % 4
      else
        t.turnRight()
        pose.f = (pose.f + 1) % 4
      end
    end
  end
  local function up()
    if t.detectUp() then t.digUp() end
    if not t.up() then return false end
    pose.y = pose.y + 1
    return true
  end
  local function fwd()
    if t.detect() then t.dig() end
    if not t.forward() then return false end
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  -- ascend-first travel; the path only ever rises
  local function goTo(x, y, z)
    while pose.y < y do if not up() then return false end end
    while pose.x ~= x do
      face(pose.x < x and 1 or 3)
      if not fwd() then return false end
    end
    while pose.z ~= z do
      face(pose.z < z and 0 or 2)
      if not fwd() then return false end
    end
    return true
  end
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then
        t.select(slot)
        return true
      end
    end
    return false
  end

  -- placement self-check: turtles face their placer, so a player standing
  -- outside the door produces a perfectly mirrored build OUTSIDE the tower
  -- (ask me how I know). From the correct spot - doorway center, first cell
  -- inside, facing the room - the back wall is exactly 8 ahead and the right
  -- wall exactly 6 to the right. Measure both, fly back, only then build.
  local function span()
    local n = 0
    while n < 12 and not t.detect() and t.forward() do n = n + 1 end
    -- return the way we came
    t.turnLeft(); t.turnLeft()
    for _ = 1, n do
      if not t.forward() then return nil end
    end
    t.turnLeft(); t.turnLeft()
    return n
  end
  local ahead = span()
  if ahead ~= 8 then
    return false, ("placement check failed: back wall should be exactly 8 ahead, measured %s. ")
      :format(tostring(ahead)) ..
      "Stand INSIDE the room facing the door and place me at the doorway center, first cell inside."
  end
  t.turnRight()
  local right = span()
  t.turnLeft()
  if right ~= 6 then
    return false, ("placement check failed: right wall should be exactly 6 to my right, measured %s. ")
      :format(tostring(right)) ..
      "Put me on the doorway's CENTER column, first cell inside."
  end

  for i, p in ipairs(PATH) do
    if not goTo(p[1], p[2] + 1, p[3]) then
      return false, "stuck en route to step " .. i
    end
    if p[4] then
      local occupied, below = t.inspectDown()
      if occupied and below.name ~= p[4] then
        return false, ("step %d blocked by %s"):format(i, below.name)
      end
      if not occupied then
        if not ensure(p[4]) then return false, "out of " .. p[4] end
        if not t.placeDown() then return false, "cannot place step " .. i end
      end
    end
    if report then report(i, #PATH) end
  end

  -- finish standing in the head office
  if not goTo(7, 27, 5) then return false, "stuck exiting the shaft" end
  return true
end

local M = { PATH = PATH, START = START, run = run }
if _TEST then return M end

-- ==================================================================== program
print("building the tower staircase (21 polished blackstone + 3 glowstone)")
local ok, err = run(turtle, function(i, n)
  if i % 5 == 0 or i == n then print(("step %d/%d"):format(i, n)) end
end)
if ok then
  print("staircase done - I'm in the head office. Nice view.")
else
  printError("stopped: " .. tostring(err))
  printError("fix and rerun; existing steps are skipped automatically")
end
