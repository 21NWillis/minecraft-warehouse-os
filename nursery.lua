-- nursery: a hatchery for new fleet turtles. Drop in a stack of blank
-- turtles and walk away - the nursery places one on the boot spot, turns
-- it on so it boots the provisioning floppy, waits for the newborn to
-- install itself and walk off, then places the next. The manual chore
-- (craft turtle, place turtle, wait, label, fuel, fetch) becomes a stack
-- you load once.
--
-- STATION (build it once, exactly like this - the nursery never moves):
--
--     [ nursery ] --faces--> [ BOOT SPOT ] [ disk drive + floppy ]
--                                 |
--                            [ fuel chest ]      (DIRECTLY BELOW)
--
--   * the nursery FACES the boot spot: one empty air cell, the only cell
--     it ever places into. Confirm facing with the go-forward test, never
--     by looking at the turtle's texture.
--   * a DISK DRIVE sits ADJACENT to the boot spot, holding the floppy
--     whose startup.lua is provision.lua (see provision.lua's header for
--     how to burn one). CC rule: a turtle placed next to a drive with a
--     startup disk boots off that disk - it labels itself, pulls
--     PaperclipOS from GitHub, reboots, and runs its own startup.
--   * a FUEL CHEST sits DIRECTLY BELOW the boot spot, stocked with coal,
--     so a newborn can suckDown() + refuel() without moving a block.
--     Below, not beside: every side cell around the spot belongs to the
--     drive (and to the newborn's exit lane).
--   * the newborn's own script is what MOVES IT OFF the spot when it is
--     finished. The nursery will NEVER place on top of a turtle that
--     stayed put - a stuck newborn stops the run instead.
--
-- RITUAL:
--   1. build the station above; fill the fuel chest with coal
--   2. load the nursery with blank turtles (ANY item id containing
--      "turtle" counts - normal, advanced, mining, crafty) plus a few
--      coal for itself
--   3. nursery           - hatch until the turtle items run out
--      nursery 4         - hatch at most 4
--      nursery 4 600     - ...and give each newborn 600s to clear out
--
-- Out of turtles it stops clean; a newborn that never leaves stops it
-- loud. Rerun-safe either way: restock and run it again.
local DEFAULTS = { timeout = 300, poll = 2 }

local function isTurtleItem(name)
  return name ~= nil and name:find("turtle", 1, true) ~= nil
end

-- first inventory slot holding a placeable turtle item, or nil
local function findTurtleSlot(t)
  for slot = 1, 16 do
    local d = t.getItemDetail(slot)
    if d and isTurtleItem(d.name) then return slot, d end
  end
  return nil
end

-- Boot the freshly placed newborn. A placed turtle IS a peripheral of type
-- "turtle" on the placer's front face, so wrap("front").turnOn() starts it.
-- CAVEAT this exists for: whether a newly placed turtle auto-boots from an
-- adjacent drive varies with version/config, so we do not rely on it - we
-- turn it on by hand. If the wrap comes back empty (or has no turnOn), that
-- is a station problem worth shouting about, but we keep waiting anyway:
-- the disk boot may have already worked and the newborn is on its way out.
local function bootFront(t, log)
  local ok, p = pcall(t.wrap, "front")
  if not ok then p = nil end
  if type(p) ~= "table" or type(p.turnOn) ~= "function" then
    log("nursery: WARNING - nothing turtle-shaped in front after placing.")
    log("nursery: check the boot spot and the disk drive beside it.")
    log("nursery: waiting anyway - the floppy boot may have worked.")
    return false
  end
  local okOn, err = pcall(p.turnOn)
  if not okOn then
    log("nursery: WARNING - turnOn() failed: " .. tostring(err))
    log("nursery: waiting anyway - the floppy boot may have worked.")
    return false
  end
  return true
end

-- run(ops, opts) -> status, hatched, detail
--   ops:  detect, place, select, getItemDetail, wrap, sleep
--   opts: max (hatch cap), timeout (seconds a newborn may squat), poll,
--         log (defaults to print)
--   status: "done"      hit the cap
--           "empty"     out of turtle items (the normal finish)
--           "stuck"     a newborn never left; nothing placed on top of it
--           "placefail" place() refused - spot obstructed or bad item
--           "blocked"   boot spot already occupied before placing
local function run(t, opts)
  opts = opts or {}
  local max = opts.max or math.huge
  local timeout = opts.timeout or DEFAULTS.timeout
  local poll = opts.poll or DEFAULTS.poll
  local log = opts.log or print

  local hatched = 0
  while hatched < max do
    if t.detect() then
      return "blocked", hatched, "boot spot occupied - clear it before rerunning"
    end
    local slot = findTurtleSlot(t)
    if not slot then return "empty", hatched end

    t.select(slot)
    if not t.place() then
      return "placefail", hatched, "place() refused at the boot spot"
    end
    bootFront(t, log)

    -- wait for the newborn to provision itself and walk away
    local waited = 0
    while t.detect() do
      if waited >= timeout then
        return "stuck", hatched,
          ("newborn still on the boot spot after %ds"):format(timeout)
      end
      t.sleep(poll)
      waited = waited + poll
    end

    hatched = hatched + 1
    log(("nursery: %d hatched"):format(hatched))
  end
  return "done", hatched
end

local M = { run = run, isTurtleItem = isTurtleItem, findTurtleSlot = findTurtleSlot,
  bootFront = bootFront, DEFAULTS = DEFAULTS }
if _TEST then return M end

-- ==================================================================== program
local args = { ... }
local max = tonumber(args[1])
local timeout = tonumber(args[2]) or DEFAULTS.timeout
if args[1] and not max then
  print("usage: nursery [count] [timeout-seconds]")
  return
end

for slot = 1, 16 do
  local d = turtle.getItemDetail(slot)
  if d and d.name == "minecraft:coal" then turtle.select(slot); turtle.refuel(16) end
end

local stock = 0
for slot = 1, 16 do
  local d = turtle.getItemDetail(slot)
  if d and isTurtleItem(d.name) then stock = stock + d.count end
end
if stock == 0 then
  print("nursery empty - restock and rerun")
  print("(load blank turtles; I place them on the spot I'm facing)")
  return
end

print(("nursery: %d turtle(s) loaded%s"):format(stock,
  max and (", hatching at most " .. max) or ""))
print("boot spot ahead, drive beside it, fuel chest below it.")

local ops = {
  detect = turtle.detect,
  place = turtle.place,
  select = turtle.select,
  getItemDetail = turtle.getItemDetail,
  wrap = peripheral.wrap,
  sleep = sleep,
}
local status, hatched, detail = run(ops, { max = max, timeout = timeout })

print(("nursery: %d hatched this run"):format(hatched))
if status == "empty" then
  print("nursery empty - restock and rerun")
elseif status == "done" then
  print("count reached - nursery idle")
elseif status == "stuck" then
  printError("stopped: " .. tostring(detail))
  printError("the newborn never left. Check: floppy in the drive, drive")
  printError("adjacent to the boot spot, coal in the chest below it.")
elseif status == "placefail" then
  printError("stopped: " .. tostring(detail))
  printError("is the boot spot a clear air cell I can reach?")
else
  printError("stopped: " .. tostring(detail or status))
end
