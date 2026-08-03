-- nocfit: the turtle installs the NOC control room - a 4x2 advanced monitor
-- wall on the back interior wall, an advanced computer beneath it (touching
-- the wall, so the monitors attach as its "top" peripheral), a disk drive
-- beside it, and the provisioning floppy inserted. Power it on and it
-- self-installs; then `monitor top attract` (or exchange) lights the wall.
--
-- Run standing ON the gold datum, facing campus-north (go-forward test!),
-- AFTER `datacenter build noc`. Load:
--   8x Advanced Monitor │ 1x Advanced Computer │ 1x Disk Drive
--   1x provisioned floppy │ ~12 coal
-- YOUR jobs after: right-click the computer once; optionally click a
-- wireless modem onto it by hand (flat modems are a hand job).
-- Rerun-safe: occupied spots are skipped.
local campus = require("campus")

local MONITOR = "computercraft:monitor_advanced"
local COMPUTER = "computercraft:computer_advanced"
local DRIVE = "computercraft:disk_drive"
local FLOPPY = "computercraft:disk"

-- placements in NOC-LOCAL coords (hall is 9x9, door -z, back wall z8);
-- everything sits at z7 against the back wall, placed from the z6 aisle
-- facing +z so fronts look into the room.
local PLAN = {
  { 2, 2, 7, MONITOR }, { 3, 2, 7, MONITOR }, { 4, 2, 7, MONITOR }, { 5, 2, 7, MONITOR },
  { 2, 3, 7, MONITOR }, { 3, 3, 7, MONITOR }, { 4, 3, 7, MONITOR }, { 5, 3, 7, MONITOR },
  { 2, 1, 7, COMPUTER },
  { 1, 1, 7, DRIVE },
}

local function run(t, report)
  local site = campus.site("noc")
  local at = site.at
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
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then t.select(slot) return true end
    end
    return false
  end
  local function D(x, y, z) return at[1] + x, at[2] + y, at[3] + z end

  -- enter through the door (-z face, center column x4, local y2)
  if not goTo(pose.x, 2, pose.z) then return false, "blocked rising off the datum" end
  local dx, dy, dz = D(4, 2, -2)
  if not goTo(dx, dy, dz) then return false, "blocked reaching the NOC door" end
  local ix, iy, iz = D(4, 2, 2)
  if not goTo(ix, iy, iz) then return false, "blocked entering the doorway" end

  local placed = 0
  for i, p in ipairs(PLAN) do
    -- stand in the aisle one short of the wall, at target height, facing +z
    local ax, ay, az = D(p[1], p[2], 6)
    if not goTo(ax, ay, az) then return false, "blocked reaching aisle spot " .. i end
    face(0)
    local occ = t.inspect()
    if not occ then
      if not ensure(p[4]) then return false, "out of " .. p[4] end
      if not t.place() then return false, "cannot place " .. p[4] .. " at spot " .. i end
      placed = placed + 1
    end
    if report then report(i, #PLAN) end
  end

  -- floppy into the drive
  local fx, fy, fz = D(1, 1, 6)
  if not goTo(fx, fy, fz) then return false, "blocked reaching the drive" end
  face(0)
  if ensure(FLOPPY) then t.drop(1) end

  -- home
  if not goTo(ix, iy, iz) then return false, "blocked leaving the aisle" end
  if not goTo(dx, dy, dz) then return false, "blocked exiting the door" end
  goTo(0, 2, 0)
  goTo(0, 0, 0)
  face(0)
  return true, placed
end

local M = { run = run, PLAN = PLAN }
if _TEST then return M end

-- ==================================================================== program
print("nocfit: monitor wall + computer + drive + floppy")
local ok, res = run(turtle, function(i, n)
  if i % 3 == 0 or i == n then print(("placing %d/%d"):format(i, n)) end
end)
if ok then
  print(("NOC installed (%d new blocks). Back on the datum."):format(res))
  print("YOUR jobs: right-click the NOC computer once (self-installs),")
  print("then on it: `monitor top attract` (or exchange) to light the wall.")
  print("Optional: hand-click a wireless modem onto the computer.")
else
  printError("stopped: " .. tostring(res))
  printError("fix and rerun - finished placements are skipped")
end
