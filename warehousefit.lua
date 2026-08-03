-- warehousefit: the turtle installs the entire Storage Core v1 inside the
-- warehouse hall - barrel wall, storage controller, computer, wired-modem
-- link, disk drive, and it even inserts the provisioning floppy, so the
-- warehouse computer self-installs PaperclipOS the first time you power it.
--
-- Run standing ON the gold datum, facing campus-north, AFTER
-- `datacenter build warehouse`. Load:
--   14x sophisticatedstorage:barrel     (12 storage + 2 input)
--   1x sophisticatedstorage:controller
--   1x computercraft:computer_normal
--   1x computercraft:wired_modem_full
--   1x computercraft:disk_drive
--   1x floppy disk ALREADY carrying provision as its startup (copy from the
--      tower's provisioning drive: it's the same disk item, contents travel)
--   ~16 coal
-- Afterwards YOUR one job: right-click the computer to power it on. It disk
-- boots, installs, and is ready for `doctor` / `warehouse`.
-- Rerun-safe: occupied spots are skipped.
local campus = require("campus")
local flight = require("flight")

local BARREL = "sophisticatedstorage:barrel"
local CONTROLLER = "sophisticatedstorage:controller"
local COMPUTER = "computercraft:computer_normal"
local MODEM = "computercraft:wired_modem_full"
local DRIVE = "computercraft:disk_drive"
local FLOPPY = "computercraft:disk"

-- placements in warehouse-LOCAL coords, all in the x=1 plane along the west
-- wall, placed from the aisle at x=2 facing west (so fronts face the room).
-- Chain contiguity: input barrels(z1) - barrels(z2..7) - controller(z8) -
-- modem(z9) - computer(z10); drive above the computer.
-- NOTE: the hall's DOORWAY sits behind local z5..7 on this wall, so those
-- columns carry a BARREL LINTEL at y3 only - you walk under it, and it
-- bridges the storage chain over the door to the controller column.
local PLAN = {
  { 1, 1, 1, BARREL, "input" }, { 1, 2, 1, BARREL, "input" },
  { 1, 3, 1, BARREL },
}
for z = 2, 4 do
  PLAN[#PLAN + 1] = { 1, 1, z, BARREL }
  PLAN[#PLAN + 1] = { 1, 2, z, BARREL }
end
for z = 5, 7 do                        -- lintel over the doorway
  PLAN[#PLAN + 1] = { 1, 3, z, BARREL }
end
PLAN[#PLAN + 1] = { 1, 3, 8, BARREL }  -- riser: lintel down to the controller
PLAN[#PLAN + 1] = { 1, 2, 8, BARREL }
PLAN[#PLAN + 1] = { 1, 1, 8, CONTROLLER }
PLAN[#PLAN + 1] = { 1, 1, 9, MODEM }
PLAN[#PLAN + 1] = { 1, 1, 10, COMPUTER }
PLAN[#PLAN + 1] = { 1, 2, 10, DRIVE }

local function run(t, report)
  local site = campus.site("warehouse")
  local at = site.at
  local s = site.gen()
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
  local function goTo(x, y, z)   -- rise-first / descend-last, same altitude ok
    local cruise = (pose.y == y) and y or math.max(y, pose.y)
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

  local okf, ferr = flight.verifyFrame(t)
  if not okf then return false, ferr end

  -- route: cruise at datum y2 to outside the door (-x side, facing the pad),
  -- enter through the doorway (local 0, y2, z6), then work the aisle
  local doorOut = { D(-2, 2, 6) }      -- two out from the door, local y2
  local doorIn = { D(2, 2, 6) }        -- just inside
  if not goTo(pose.x, 2, pose.z) then return false, "blocked rising off the datum" end
  if not goTo(doorOut[1], 2, doorOut[3]) then return false, "blocked reaching the warehouse door" end
  if not goTo(doorIn[1], 2, doorIn[3]) then return false, "blocked entering the doorway" end

  local placed = 0
  for i, p in ipairs(PLAN) do
    -- stand in the aisle (local x=2) beside the target, at its height, facing west
    local ax, ay, az = D(2, p[2], p[3])
    if not goTo(ax, ay, az) then return false, "blocked reaching aisle spot " .. i end
    face(3)
    local occ = t.inspect()
    if not occ then
      if not ensure(p[4]) then return false, "out of " .. p[4] end
      if not t.place() then return false, "cannot place " .. p[4] .. " at spot " .. i end
      placed = placed + 1
    end
    if report then report(i, #PLAN) end
  end

  -- the floppy: face the drive (top of the computer stack) and drop it in
  local ax, ay, az = D(2, 2, 10)
  if not goTo(ax, ay, az) then return false, "blocked reaching the drive" end
  face(3)
  if ensure(FLOPPY) then
    t.drop(1)
  end

  -- home: back out the door, up, and return to the datum
  if not goTo(doorIn[1], 2, doorIn[3]) then return false, "blocked leaving the aisle" end
  if not goTo(doorOut[1], 2, doorOut[3]) then return false, "blocked exiting the door" end
  if not goTo(0, 2, 0) then return false, "blocked flying home" end
  goTo(0, 0, 0)
  face(0)
  return true, placed
end

local M = { run = run, PLAN = PLAN }
if _TEST then return M end

-- ==================================================================== program
print("warehousefit: barrel wall + controller + computer + network + floppy")
local ok, res = run(turtle, function(i, n)
  if i % 4 == 0 or i == n then print(("placing %d/%d"):format(i, n)) end
end)
if ok then
  print(("storage core installed (%d new blocks). Back on the datum."):format(res))
  print("YOUR one job: right-click the warehouse computer to power it on.")
  print("It will disk-boot, self-install, and be ready for `doctor`.")
else
  printError("stopped: " .. tostring(res))
  printError("fix and rerun - finished placements are skipped")
end
