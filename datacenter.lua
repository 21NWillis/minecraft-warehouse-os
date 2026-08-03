-- datacenter: builds the whole Paperclip void campus from ONE reference block.
--
-- The datum is the void portal block (javd:portal_block). Place the build
-- turtle ON TOP of the portal facing your chosen campus-north (+z) and run:
--
--   datacenter map            campus layout + coordinates
--   datacenter list           phases + built status
--   datacenter bill <phase>   material checklist + fuel + setup notes
--   datacenter bill all       the whole shopping list
--   datacenter build <phase>  fly to the site, build it, fly home
--
-- Every structure is an offset from that datum, so the entire base is
-- reproducible anywhere from a single block. Builds assume empty void at the
-- site (that's the point of the void dimension). The turtle starts AND ends
-- on the portal, so you can chain phases: restock, rerun, repeat.
local builder = require("builder")
local M = require("campus")   -- the site plan lives in campus.lua (shared)

if _TEST then return M end

-- ==================================================================== program
local args = { ... }
local cmd = args[1]

local STATE = ".datacenter_built"

local function builtSet()
  local out = {}
  if fs.exists(STATE) then
    local f = fs.open(STATE, "r")
    for line in (f.readAll() or ""):gmatch("[^\r\n]+") do out[line] = true end
    f.close()
  end
  return out
end

local function markBuilt(key)
  local f = fs.open(STATE, "a")
  f.write(key .. "\n")
  f.close()
end

local function printBill(site)
  local s = site.gen()
  local plan = s:plan()
  local mats = s:materials()
  print(("== %s (%s)  %dx%dx%d at %d,%d,%d"):format(site.name, site.key,
    s.w, s.h, s.d, site.at[1], site.at[2], site.at[3]))
  local total = 0
  for block, n in pairs(mats) do
    print(("   %4d x %s (%d stacks)"):format(n, block, math.ceil(n / 64)))
    total = total + n
  end
  print(("   %d blocks, ~%d fuel"):format(total, M.estimateFuel(site, s, #plan)))
  for _, note in ipairs(site.after or {}) do print("   > " .. note) end
end

if cmd == "map" then
  print("campus map (datum = portal, +z = campus north):")
  print("")
  print("               +z")
  print("     [NOC 9x9]      [BAYS 13x9]")
  print(" [WAREHOUSE 19x13] [PAD 17x17] [POWER 17x17]")
  print("          [CASINO 13x21]")
  print("               -z")
  print("")
  for _, site in ipairs(M.SITES) do
    local b = M.bounds(site)
    print(("  %-9s x %d..%d  z %d..%d"):format(site.key, b.x1, b.x2, b.z1, b.z2))
  end

elseif cmd == "list" then
  local done = builtSet()
  for i, site in ipairs(M.SITES) do
    print(("%d. [%s] %-9s %s"):format(i, done[site.key] and "x" or " ",
      site.key, site.name))
  end
  print("build order = list order; `datacenter bill <phase>` for the checklist")

elseif cmd == "bill" then
  local which = args[2]
  if which == "all" then
    for _, site in ipairs(M.SITES) do printBill(site) end
  elseif M.site(which) then
    printBill(M.site(which))
  else
    print("usage: datacenter bill <phase|all>; phases via `datacenter list`")
  end

elseif cmd == "build" then
  local site = M.site(args[2] or "")
  if not site then print("usage: datacenter build <phase>") return end
  local s = site.gen()
  local plan = s:plan()
  local need = M.estimateFuel(site, s, #plan)

  -- fuel first: top up from anything combustible on board
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < need then
    for slot = 1, 16 do
      turtle.select(slot)
      if turtle.refuel(0) then
        while turtle.getFuelLevel() < need and turtle.refuel(1) do end
      end
    end
    turtle.select(1)
    if turtle.getFuelLevel() < need then
      print(("not enough fuel: %d < %d needed"):format(turtle.getFuelLevel(), need))
      return
    end
  end

  -- datum-frame pose, mirrored off the same physical moves the builder makes
  local DIRS = builder._internal.DIRS
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local ops = builder.turtleOps({ track = function(name)
    if name == "up" then pose.y = pose.y + 1
    elseif name == "down" then pose.y = pose.y - 1
    elseif name == "forward" then
      pose.x = pose.x + DIRS[pose.f][1]
      pose.z = pose.z + DIRS[pose.f][2]
    elseif name == "turnLeft" then pose.f = (pose.f - 1) % 4
    elseif name == "turnRight" then pose.f = (pose.f + 1) % 4 end
  end })

  local function face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then ops.turnLeft() else ops.turnRight() end
    end
  end
  local function goTo(tx, ty, tz)   -- vertical-first; void = nothing to dig
    while pose.y < ty do if not ops.up() then return false end end
    while pose.y > ty do if not ops.down() then return false end end
    if tx > pose.x then face(1) elseif tx < pose.x then face(3) end
    while pose.x ~= tx do if not ops.forward() then return false end end
    if tz > pose.z then face(0) elseif tz < pose.z then face(2) end
    while pose.z ~= tz do if not ops.forward() then return false end end
    return true
  end

  local resuming = args[3] == "resume"
  local function progressCb(done, total)
    if done % 32 == 0 or done == total then
      local _, y = term.getCursorPos()
      term.setCursorPos(1, y)
      term.clearLine()
      term.write(("building %d/%d"):format(done, total))
    end
  end

  print(("%s: %d blocks; flying out..."):format(site.name, s:count()))
  local placed, err
  if resuming then
    -- fly to the corridor over the site; builder.resume self-locates the
    -- first missing block from there (datum pose -> builder frame is a shift)
    if not (goTo(pose.x, M.CORRIDOR_Y, pose.z)
        and goTo(site.at[1], M.CORRIDOR_Y, site.at[3])) then
      print("travel blocked - is something built in the corridor?")
      return
    end
    placed, err = builder.resume(plan, ops, progressCb,
      { x = 0, y = M.CORRIDOR_Y - site.at[2], z = 0, f = pose.f })
  else
    -- out: rise to the corridor, over, drop to the builder's start hover cell
    if not (goTo(pose.x, M.CORRIDOR_Y, pose.z)
        and goTo(site.at[1], M.CORRIDOR_Y, site.at[3])
        and goTo(site.at[1], site.at[2] + 1, site.at[3])) then
      print("travel blocked - is something built in the corridor?")
      return
    end
    face(0)
    placed, err = builder.run(plan, ops, progressCb)
  end
  print("")

  -- home: rise to the corridor from wherever the builder left us, fly back
  goTo(pose.x, M.CORRIDOR_Y, pose.z)
  goTo(0, M.CORRIDOR_Y, 0)
  goTo(0, 0, 0)
  face(0)

  if err then
    print(("stopped at %d/%d: %s"):format(placed, #plan, err))
    print("restock, then: datacenter build " .. site.key .. " resume")
  else
    markBuilt(site.key)
    print(("%s complete: %d blocks placed; back at the portal"):format(site.name, placed))
  end

else
  print("datacenter map|list|bill <phase|all>|build <phase> [resume]")
  print("place the turtle ON the void portal facing campus-north first")
end
