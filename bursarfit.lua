-- bursarfit: builds the Bursar's Office - the XP bottle liquefaction line.
--   chest -> hopper -> Deployer (throws bottles) -> sealed glass orb
--   chamber -> EnderIO XP Vacuum (far wall, orbs -> XP Juice) -> [conduit
--   gap] -> XP Obelisk (one click: whole bank into your XP bar)
-- Deployer is driven by a self-contained water wheel. Time in a Bottle the
-- DEPLOYER for throughput (and the vacuum second if orbs pile up).
--
-- SETUP: place the turtle ON THE FLOOR of a clear flat area, at least
-- 3 wide x 12 deep x 5 tall of clearance AHEAD of it (the `go forward`
-- test direction). The build extends 1 block left/right of the turtle's
-- column and from 3 behind its start to 8 ahead. Floor must be solid
-- (orbs bounce; the chamber uses it). Load the bill (bursarfit bill).
--
-- Crash/restock recovery: progress persists in bursarfit.state, so a
-- rerun resumes at the first unfinished step without revisiting stands
-- that completed construction has sealed. Field ritual: re-place the
-- turtle at its START CORNER (same facing) before rerunning. A fully
-- COMPLETED build refuses re-entry (the chamber is sealed - that's the
-- point of it); demolish by hand to rebuild.
--
-- After the build (operator wrench pass):
--   1. verify the deployer NOZZLE points into the glass chamber and the
--      shaft/wheel axis runs front-to-back; wrench-rotate if not
--   2. hand-place ONE EnderIO fluid conduit in the gap between the
--      vacuum and the obelisk, connect both ends
--   3. pipez ultimate: your bottle chest -> the intake chest up top
--   4. throw ONE bottle in by hand; confirm juice reaches the obelisk
--      and "withdraw" gives levels. THEN open the tap.
--   5. TIAB the deployer. Watch the server, not the fireworks.
local FITTER = {
  DEPLOYER = "create:deployer",
  SHAFT = "create:shaft",
  WHEEL = "create:water_wheel",
  HOPPER = "minecraft:hopper",
  CHEST = "minecraft:chest",
  VACUUM = "enderio:xp_vacuum",
  OBELISK = "enderio:xp_obelisk",
  GLASS = "minecraft:gray_stained_glass",
  FILL = "minecraft:polished_blackstone",
  BUCKET = "minecraft:water_bucket",
}
local B = FITTER

-- Local frame: turtle start = (0,0,0), +z = its facing, x = its right,
-- y up. Floor is y=-1 (existing). Machine line runs along x=1.
-- Ordered so every stand cell is still air when the turtle gets there:
-- far end first, kinetics before their containment, water dead last.
-- dir "fwd" = face `face` then place(); dir "down" = hover, placeDown().
local PLAN = {
  -- far end: obelisk, then the vacuum wall (conduit gap stays at z6)
  { stand = { 1, 1, 7 }, dir = "down", block = B.OBELISK },
  { stand = { 1, 0, 4 }, dir = "fwd", face = 0, block = B.VACUUM },    -- into z5
  { stand = { 0, 1, 5 }, dir = "down", block = B.GLASS },              -- vacuum corners
  { stand = { 2, 1, 5 }, dir = "down", block = B.GLASS },
  -- kinetic line (axis z): wheel from behind, shaft from front, deployer
  -- from inside the future chamber - all before walls close those stands
  { stand = { 1, 0, -2 }, dir = "fwd", face = 0, block = B.WHEEL },    -- into z-1
  { stand = { 1, 0, 1 }, dir = "fwd", face = 2, block = B.SHAFT },     -- into z0
  { stand = { 1, 0, 2 }, dir = "fwd", face = 2, block = B.DEPLOYER },  -- into z1
  -- hopper before the roof glass above it blocks the stand
  { stand = { 1, 1, 2 }, dir = "fwd", face = 2, block = B.HOPPER },    -- into (1,1,1)
  { stand = { 1, 3, 1 }, dir = "down", block = B.CHEST },              -- intake (1,2,1)
  -- orb chamber: interior (1,0,2..4) - side glass at y0, roof at y1
  { stand = { 0, 1, 1 }, dir = "down", block = B.GLASS },
  { stand = { 2, 1, 1 }, dir = "down", block = B.GLASS },
  { stand = { 0, 1, 2 }, dir = "down", block = B.GLASS },
  { stand = { 2, 1, 2 }, dir = "down", block = B.GLASS },
  { stand = { 0, 1, 3 }, dir = "down", block = B.GLASS },
  { stand = { 2, 1, 3 }, dir = "down", block = B.GLASS },
  { stand = { 0, 1, 4 }, dir = "down", block = B.GLASS },
  { stand = { 2, 1, 4 }, dir = "down", block = B.GLASS },
  { stand = { 1, 2, 2 }, dir = "down", block = B.GLASS },              -- roof y1
  { stand = { 1, 2, 3 }, dir = "down", block = B.GLASS },
  { stand = { 1, 2, 4 }, dir = "down", block = B.GLASS },
  { stand = { 1, 2, 5 }, dir = "down", block = B.GLASS },              -- over vacuum
  -- water containment pocket around (1,1,-2) source and (1,1,-1) flow
  { stand = { 1, 1, -2 }, dir = "down", block = B.FILL },              -- floor (1,0,-2)
  { stand = { 0, 2, -1 }, dir = "down", block = B.FILL },
  { stand = { 2, 2, -1 }, dir = "down", block = B.FILL },
  { stand = { 0, 2, -2 }, dir = "down", block = B.FILL },
  { stand = { 2, 2, -2 }, dir = "down", block = B.FILL },
  { stand = { 1, 2, -3 }, dir = "down", block = B.FILL },
  { stand = { 1, 2, 0 }, dir = "down", block = B.FILL },               -- (1,1,0) above shaft
  -- water LAST: source at (1,1,-2) flows into (1,1,-1) across the wheel
  { stand = { 1, 2, -2 }, dir = "down", block = B.BUCKET, water = true },
}

local CRUISE = 4   -- travel altitude: above every placement and stand

local function bill()
  local mats = {}
  for _, p in ipairs(PLAN) do mats[p.block] = (mats[p.block] or 0) + 1 end
  return mats
end

local function targetCell(p)
  local s = p.stand
  if p.dir == "down" then return s[1], s[2] - 1, s[3] end
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  return s[1] + DIRS[p.face][1], s[2], s[3] + DIRS[p.face][2]
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
  -- rise to cruise, travel, drop onto the stand: stands are always open
  -- columns from cruise height at the time they're used (test-proven)
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
    local occupied
    if p.dir == "down" then occupied = t.detectDown()
    else face(p.face); occupied = t.detect() end
    if not occupied then
      if not ensure(p.block) then return false, "out of " .. p.block end
      local ok = (p.dir == "down") and t.placeDown() or t.place()
      if not ok and not p.water then
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
  BLOCKS = FITTER, CRUISE = CRUISE }
if _TEST then return M end

-- ==================================================================== program
local args = { ... }
if args[1] == "bill" then
  print("bursarfit bill (plus: 1 EnderIO fluid conduit, hand-placed):")
  for block, n in pairs(bill()) do
    print(("  %2d x %s"):format(n, block))
  end
  print("  ~10 coal fuel")
  return
end

print("bursarfit: deployer -> orb chamber -> XP vacuum -> obelisk")
local STATE = "bursarfit.state"
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
  if i % 5 == 0 or i == n then print(("step %d/%d"):format(i, n)) end
end, startStep)
if ok then
  if fs.exists(STATE) then fs.delete(STATE) end
  print(("Bursar's Office built (%d new blocks)."):format(res))
  print("YOUR wrench pass:")
  print(" 1. deployer nozzle -> chamber; shaft/wheel axis front-to-back")
  print(" 2. one fluid conduit in the gap behind the vacuum -> obelisk")
  print(" 3. pipez: bottle chest -> intake chest (top)")
  print(" 4. test ONE bottle; then TIAB the deployer")
else
  printError("stopped: " .. tostring(res))
  printError("fix and rerun - finished placements are skipped")
end
