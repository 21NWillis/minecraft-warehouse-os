-- pipefit v2: TOP-MOUNTED pipe network. The turtle lays a pipez lattice one
-- block above the channels - every pipe touches its strainer's TOP face -
-- plus a header along the south lip and a trunk that runs at ground level
-- around the pad, in through the warehouse DOOR, across the floor, to the
-- side of input barrel #1. No digging, no under-deck flying, and you wrench
-- the strainer connections standing comfortably on the walkways.
--
-- Run standing ON the gold datum, facing campus-north (go-forward test!),
-- AFTER the warehouse hall exists. Load:
--   ~220x pipez:item_pipe   (~4 stacks)
--   ~24 coal
-- YOUR one job after: pipez-wrench each pipe->strainer connection (the
-- vertical one under each lattice pipe) to Extract. Only cells that hold
-- strainers need it - do it bay-by-bay. Trunk/barrel connections need no
-- clicks (insertion is default).
-- Rerun-safe: cells already piped are skipped.
local campus = require("campus")

local PIPE = "pipez:item_pipe"

local function run(t, report)
  local casino = campus.site("casino")
  local warehouse = campus.site("warehouse")
  local ca, wa = casino.at, warehouse.at
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
    local cruise = (pose.y == y) and y or math.max(y, 3)
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

  -- pipe cells in DATUM coords as {x, y, z}, in laying order
  local cells = {}
  for c = 0, 3 do                                   -- lattice over every channel cell (y=1)
    for _, lx in ipairs({ 1 + c * 3, 2 + c * 3 }) do
      for lz = 1, 19 do
        cells[#cells + 1] = { ca[1] + lx, 1, ca[3] + lz }
      end
    end
  end
  for lx = 11, 0, -1 do                             -- header on top of the south lip (y=1)
    cells[#cells + 1] = { ca[1] + lx, 1, ca[3] }
  end
  -- step-down pair off the deck edge: LOWER first, else the hover cell for
  -- the lower pipe would be the upper pipe we just placed
  cells[#cells + 1] = { ca[1] - 1, 0, ca[3] }
  cells[#cells + 1] = { ca[1] - 1, 1, ca[3] }
  cells[#cells + 1] = { ca[1] - 2, 0, ca[3] }       -- west to the bypass lane (x = -9)
  for z = ca[3] + 1, wa[3] + 6 do                   -- north along x=-9, past the pad's west rim
    cells[#cells + 1] = { ca[1] - 2, 0, z }
  end
  cells[#cells + 1] = { wa[1] + 18, 0, wa[3] + 6 }  -- through the warehouse doorway (x=-10)
  for lx = 17, 2, -1 do                             -- across the hall floor to the barrel wall
    cells[#cells + 1] = { wa[1] + lx, 0, wa[3] + 6 }
  end
  for lz = 5, 1, -1 do                              -- along the wall to input barrel #1
    cells[#cells + 1] = { wa[1] + 2, 0, wa[3] + lz }
  end
  -- final cell (wa+2, 0, wa+1) is side-adjacent to the lower input barrel

  local placed = 0
  for i, cell in ipairs(cells) do
    -- hover directly above the target cell and place down into it
    if not goTo(cell[1], cell[2] + 1, cell[3]) then
      return false, ("blocked over the route at %d,%d,%d"):format(cell[1], cell[2], cell[3])
    end
    local occ, below = t.inspectDown()
    if occ and below and below.name == PIPE then
      -- already piped (rerun) - skip
    elseif occ then
      return false, ("unexpected block at %d,%d,%d: %s")
        :format(cell[1], cell[2], cell[3], below and below.name or "?")
    else
      if not ensure(PIPE) then
        return false, ("out of pipes at %d/%d - load more and rerun"):format(i, #cells)
      end
      if not t.placeDown() then
        return false, ("cannot place pipe at %d,%d,%d"):format(cell[1], cell[2], cell[3])
      end
      placed = placed + 1
    end
    if report then report(i, #cells) end
  end

  -- home: rise out of the hall through the doorway, back to the datum
  if not goTo(wa[1] + 2, 1, wa[3] + 6) then return false, "blocked leaving the barrel wall" end
  if not goTo(wa[1] + 18, 1, wa[3] + 6) then return false, "blocked reaching the doorway" end
  if not goTo(wa[1] + 20, 1, wa[3] + 6) then return false, "blocked exiting the door" end
  goTo(0, 3, 0)
  goTo(0, 0, 0)
  face(0)
  return true, placed, #cells
end

local M = { run = run }
if _TEST then return M end

-- ==================================================================== program
print("pipefit v2: top lattice + header + door trunk to the warehouse")
local ok, placed, total = run(turtle, function(i, n)
  if i % 16 == 0 or i == n then print(("pipe %d/%d"):format(i, n)) end
end)
if ok then
  print(("done: %d pipes placed (%d cells). Back on the datum."):format(placed, total))
  print("YOUR job: pipez-wrench each lattice pipe's DOWN connection (to its")
  print("strainer) to Extract - from the walkways, only over stocked cells.")
else
  printError("stopped: " .. tostring(placed))
  printError("fix and rerun - piped cells are skipped automatically")
end
