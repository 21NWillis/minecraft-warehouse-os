-- quarrylogic: pure navigation/decision core for the JAMD resource quarry
-- fleet (osmium first - the Mekanism bootstrap needs ~2 stacks; band is
-- y -32..+32 with the peak at y0 per config/Mekanism/world.toml).
-- Transport-agnostic like builder: `ops` is the real turtle API in-game or a
-- mock world in tests, so every guarantee here is proven headless first.
--
-- Mining model: the turtle clears a w-by-l slab at its own level in a
-- serpentine sweep, and at every cell inspects up and down, taking any ORE
-- it sees - one pass effectively harvests a 3-tall slice. `layers` stacks
-- passes 3 blocks apart (descending at the home column, one reusable shaft).
--
-- Guarantees (proven in tests/quarry_test.lua):
--   * every slab cell is visited and cleared, every ore above/below taken
--   * the fuel governor returns the turtle HOME before fuel strands it
--   * a full inventory dumps junk in place, keepers at the home chest, and
--     the sweep resumes at the exact cell it left
--   * the run always ends parked at the start pose (chest corner, original
--     facing) so `quarry resume` needs no field surveying
local q = {}

-- facings as (dx, dz); index 0..3 clockwise from +z - the builder frame:
-- f=0 is the direction the turtle faces at launch (the `go forward` test)
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
q.DIRS = DIRS

-- items worth hauling home. Substring match on the id; everything else is
-- junk flung into the dug corridor (JAMD litter beats wasted slots).
q.DEFAULT_KEEP = {
  "osmium", "redstone", "diamond", "coal", "iron", "gold", "copper",
  "lapis", "emerald", "uranium", "fluorite", "tin", "lead", "silver",
  "zinc", "nickel", "quartz", "glowstone", "ancient_debris", "raw_",
}

function q.isOre(name)
  if not name then return false end
  return name:find("_ore", 1, true) ~= nil
    or name:find("ancient_debris", 1, true) ~= nil
end

function q.isKeeper(name, keep)
  if not name then return false end
  for _, pat in ipairs(keep or q.DEFAULT_KEEP) do
    if name:find(pat, 1, true) then return true end
  end
  return false
end

-- serpentine visit order over a slab: x grows to the turtle's RIGHT
-- (campus handedness), z along its initial facing; adjacent cells only
function q.path(w, l)
  local cells = {}
  for x = 0, w - 1 do
    if x % 2 == 0 then
      for z = 0, l - 1 do cells[#cells + 1] = { x = x, z = z } end
    else
      for z = l - 1, 0, -1 do cells[#cells + 1] = { x = x, z = z } end
    end
  end
  return cells
end

-- moves needed to reach home (0,0,0) if every step lands (digs are free)
function q.distHome(pose)
  return math.abs(pose.x) + math.abs(pose.z) + math.abs(pose.y)
end

local function face(ops, pose, target)
  local diff = (target - pose.f) % 4
  if diff == 1 then ops.turnRight()
  elseif diff == 3 then ops.turnLeft()
  elseif diff == 2 then ops.turnRight(); ops.turnRight() end
  pose.f = target
end

-- attempts per step before declaring the way undiggable (bedrock/claim);
-- generous because a gravel column re-fills the dug cell repeatedly
local DIG_CAP = 40

local function digMove(ops, pose)
  local tries = 0
  while not ops.forward() do
    tries = tries + 1
    if tries > DIG_CAP then return false end
    if ops.detect() then
      if not ops.dig() then return false end
    elseif ops.attack then
      ops.attack()          -- a mob in the way, or gravel still falling
    end
  end
  pose.x = pose.x + DIRS[pose.f][1]
  pose.z = pose.z + DIRS[pose.f][2]
  return true
end

local function vMove(ops, pose, dy)
  local move = dy > 0 and ops.up or ops.down
  local dig = dy > 0 and ops.digUp or ops.digDown
  local detect = dy > 0 and ops.detectUp or ops.detectDown
  local tries = 0
  while not move() do
    tries = tries + 1
    if tries > DIG_CAP then return false end
    if detect() and not dig() then return false end
  end
  pose.y = pose.y + dy
  return true
end

local function goToY(ops, pose, ty)
  while pose.y < ty do if not vMove(ops, pose, 1) then return false end end
  while pose.y > ty do if not vMove(ops, pose, -1) then return false end end
  return true
end

local function goTo(ops, pose, tx, tz)
  if tx > pose.x then face(ops, pose, 1) elseif tx < pose.x then face(ops, pose, 3) end
  while pose.x ~= tx do if not digMove(ops, pose) then return false end end
  if tz > pose.z then face(ops, pose, 0) elseif tz < pose.z then face(ops, pose, 2) end
  while pose.z ~= tz do if not digMove(ops, pose) then return false end end
  return true
end

-- home = start pose: travel at the current level first, then ascend the
-- home-column shaft, so descent and ascent reuse ONE hole
local function goHome(ops, pose)
  if not goTo(ops, pose, 0, 0) then return false end
  if not goToY(ops, pose, 0) then return false end
  face(ops, pose, 0)
  return true
end

-- ops contract, beyond builder's movement set (all -> bool unless noted):
--   dig/digUp/digDown, detect/detectUp/detectDown, inspectUp/inspectDown
--   (-> ok, {name=}), attack (optional), getFuelLevel (-> n|"unlimited"),
--   tryRefuel (consume carried fuel; true if fuel increased), isFull,
--   dropJunk (shed non-keepers in place), dumpHome (parked at home:
--   unload keepers into the chest)
-- opts: w, l, layers (3-tall passes, default 1), margin (fuel safety pad,
--   default 20), resume {layer=,cell=}, onProgress(layer, cell, total)
-- returns a status table; .stopped is "done" | "fuel" | "blocked", .at is
-- the resume point when not done, .pose the final (home) pose
function q.run(ops, opts)
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local cells = q.path(opts.w, opts.l)
  local layers = opts.layers or 1
  local margin = opts.margin or 20
  local st = { cellsDone = 0, ores = 0, dumps = 0, stopped = "done" }

  local function fuelLow()
    local f = ops.getFuelLevel()
    return f ~= "unlimited" and f < q.distHome(pose) + margin
  end
  local function stopReason()
    local f = ops.getFuelLevel()
    if f ~= "unlimited" and f <= 0 then return "OUT OF FUEL" end
    return "blocked"
  end
  local function bail(reason, layer, cell)
    st.stopped = reason
    st.at = { layer = layer, cell = cell }
    goHome(ops, pose)
    if ops.dumpHome then ops.dumpHome() end
    st.pose = pose
    return st
  end
  local function oreGrab(inspect, dig)
    local ok, info = inspect()
    if ok and q.isOre(info.name) and dig() then st.ores = st.ores + 1 end
  end

  local startLayer = (opts.resume and opts.resume.layer) or 1
  local startCell = (opts.resume and opts.resume.cell) or 1
  for layer = startLayer, layers do
    local ty = -(layer - 1) * 3
    local from = (layer == startLayer) and startCell or 1
    for i = from, #cells do
      local c = cells[i]
      -- the governor runs BEFORE committing to the next cell: margin must
      -- cover the trip home from where we'd be standing
      while fuelLow() and ops.tryRefuel() do end
      if fuelLow() then return bail("fuel", layer, i) end
      if not goToY(ops, pose, ty) or not goTo(ops, pose, c.x, c.z) then
        return bail(stopReason(), layer, i)
      end
      st.cellsDone = st.cellsDone + 1
      oreGrab(ops.inspectUp, ops.digUp)
      oreGrab(ops.inspectDown, ops.digDown)
      if ops.isFull() then
        ops.dropJunk()
        if ops.isFull() then
          -- haul keepers home, then return to this exact cell and go on
          if not goHome(ops, pose) then return bail(stopReason(), layer, i) end
          ops.dumpHome()
          st.dumps = st.dumps + 1
          if not goToY(ops, pose, ty) or not goTo(ops, pose, c.x, c.z) then
            return bail(stopReason(), layer, i)
          end
        end
      end
      if opts.onProgress then opts.onProgress(layer, i, #cells) end
    end
  end
  goHome(ops, pose)
  ops.dumpHome()
  st.pose = pose
  return st
end

q._internal = { face = face, digMove = digMove, goTo = goTo, goHome = goHome }
return q
