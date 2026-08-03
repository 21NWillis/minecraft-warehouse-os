-- headless quarry test: drive quarrylogic against a mock voxel world and
-- prove the field guarantees before a turtle ever digs:
--   coverage, ore harvesting above/below, the fuel governor bringing the
--   turtle home solvent, junk-shedding + haul trips under inventory
--   pressure, multi-layer descent, and mid-sweep resume.
package.path = "./?.lua;" .. package.path
local q = require("quarrylogic")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local DIRS = q.DIRS
local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- mock turtle in a voxel world. Moves cost 1 fuel, digs are free (matches
-- CC). Inventory is item-count based: keepers and junk tracked separately
-- so dropJunk/dumpHome mirror the real wrapper's behavior.
local function newMock(world, opts)
  opts = opts or {}
  local m = {
    x = 0, y = 0, z = 0, f = 0,
    world = world, fuel = opts.fuel or 100000, cap = opts.cap or 100000,
    keepers = 0, junk = 0, dumps = 0, moves = 0, minFuelSeen = math.huge,
    refuels = opts.refuels or 0,
  }
  local function blockAhead()
    return m.world[key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])]
  end
  local function collect(name)
    if q.isKeeper(name) then m.keepers = m.keepers + 1 else m.junk = m.junk + 1 end
  end
  local function move(dx, dy, dz)
    if m.fuel <= 0 then return false end
    if m.world[key(m.x + dx, m.y + dy, m.z + dz)] then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    m.fuel = m.fuel - 1
    m.moves = m.moves + 1
    if m.fuel < m.minFuelSeen then m.minFuelSeen = m.fuel end
    return true
  end
  m.ops = {
    forward = function() return move(DIRS[m.f][1], 0, DIRS[m.f][2]) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    dig = function()
      local k = key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])
      if not m.world[k] then return false end
      collect(m.world[k]); m.world[k] = nil; return true
    end,
    digUp = function()
      local k = key(m.x, m.y + 1, m.z)
      if not m.world[k] then return false end
      collect(m.world[k]); m.world[k] = nil; return true
    end,
    digDown = function()
      local k = key(m.x, m.y - 1, m.z)
      if not m.world[k] then return false end
      collect(m.world[k]); m.world[k] = nil; return true
    end,
    detect = function() return blockAhead() ~= nil end,
    detectUp = function() return m.world[key(m.x, m.y + 1, m.z)] ~= nil end,
    detectDown = function() return m.world[key(m.x, m.y - 1, m.z)] ~= nil end,
    inspectUp = function()
      local b = m.world[key(m.x, m.y + 1, m.z)]
      if b then return true, { name = b } end
      return false
    end,
    inspectDown = function()
      local b = m.world[key(m.x, m.y - 1, m.z)]
      if b then return true, { name = b } end
      return false
    end,
    getFuelLevel = function() return m.fuel end,
    tryRefuel = function()
      if m.refuels > 0 then m.refuels = m.refuels - 1; m.fuel = m.fuel + 80; return true end
      return false
    end,
    isFull = function() return m.keepers + m.junk >= m.cap end,
    dropJunk = function() m.junk = 0 end,
    dumpHome = function() m.dumps = m.dumps + 1; m.keepers = 0; m.junk = 0 end,
  }
  return m
end

-- fill the mining plane of a w x l slab with stone (the start cell stays
-- open - the turtle stands in it)
local function slabWorld(w, l, y)
  local world = {}
  for x = 0, w - 1 do
    for z = 0, l - 1 do
      if not (x == 0 and z == 0 and (y or 0) == 0) then
        world[key(x, y or 0, z)] = "minecraft:stone"
      end
    end
  end
  return world
end

local function slabClear(world, w, l, y)
  for x = 0, w - 1 do
    for z = 0, l - 1 do
      if world[key(x, y, z)] then return key(x, y, z) end
    end
  end
  return nil
end

local function atHome(m)
  return m.x == 0 and m.y == 0 and m.z == 0 and m.f == 0
end

-- ------------------------------------------------------------- unit rulings
check("osmium ore is ore", q.isOre("mekanism:deepslate_osmium_ore"))
check("stone is not ore", not q.isOre("minecraft:stone"))
check("ancient debris is ore", q.isOre("minecraft:ancient_debris"))
check("raw osmium is keeper", q.isKeeper("mekanism:raw_osmium"))
check("cobblestone is junk", not q.isKeeper("minecraft:cobblestone"))
check("deepslate is junk", not q.isKeeper("minecraft:deepslate"))
check("fluorite is keeper", q.isKeeper("mekanism:fluorite_ore"))
check("prosperity shard is keeper", q.isKeeper("mysticalagriculture:prosperity_shard"))
check("inferium essence is keeper", q.isKeeper("mysticalagriculture:inferium_essence"))

-- serpentine path: right cell count, no diagonal jumps, starts at origin
local cells = q.path(4, 6)
check("path covers w*l cells", #cells == 24, #cells)
check("path starts at origin", cells[1].x == 0 and cells[1].z == 0)
local jumps = nil
for i = 2, #cells do
  local d = math.abs(cells[i].x - cells[i - 1].x) + math.abs(cells[i].z - cells[i - 1].z)
  if d ~= 1 then jumps = i end
end
check("path steps are adjacent", jumps == nil, jumps)

-- ---------------------------------------------------------------- coverage
local m = newMock(slabWorld(4, 6, 0))
local st = q.run(m.ops, { w = 4, l = 6 })
check("coverage: completes", st.stopped == "done", st.stopped)
check("coverage: slab fully cleared", slabClear(m.world, 4, 6, 0) == nil,
  slabClear(m.world, 4, 6, 0))
check("coverage: all cells visited", st.cellsDone == 24, st.cellsDone)
check("coverage: parks at home pose", atHome(m),
  ("at %d,%d,%d f%d"):format(m.x, m.y, m.z, m.f))
check("coverage: final haul dumped", m.dumps >= 1, m.dumps)

-- --------------------------------------------------------------- ore grabs
local world = slabWorld(3, 5, 0)
world[key(1, 1, 2)] = "mekanism:osmium_ore"          -- above a mid cell
world[key(2, -1, 4)] = "mekanism:deepslate_osmium_ore" -- below a far cell
world[key(0, 1, 3)] = "minecraft:dirt"               -- above, NOT ore: stays
m = newMock(world)
st = q.run(m.ops, { w = 3, l = 5 })
check("ores: both osmium blocks taken",
  world[key(1, 1, 2)] == nil and world[key(2, -1, 4)] == nil)
check("ores: counted", st.ores == 2, st.ores)
check("ores: non-ore ceiling untouched", world[key(0, 1, 3)] == "minecraft:dirt",
  tostring(world[key(0, 1, 3)]))

-- ------------------------------------------------------------ fuel governor
m = newMock(slabWorld(6, 6, 0), { fuel = 18 })
st = q.run(m.ops, { w = 6, l = 6, margin = 5 })
check("fuel: stops with reason", st.stopped == "fuel", st.stopped)
check("fuel: parks at home", atHome(m), ("at %d,%d,%d"):format(m.x, m.y, m.z))
check("fuel: never went broke mid-field", m.fuel >= 0 and m.minFuelSeen >= 0,
  m.minFuelSeen)
check("fuel: resume point recorded", st.at and st.at.cell and st.at.cell > 1,
  st.at and st.at.cell)

-- carried fuel gets consumed before giving up
m = newMock(slabWorld(6, 6, 0), { fuel = 18, refuels = 3 })
st = q.run(m.ops, { w = 6, l = 6, margin = 5 })
check("fuel: refuels from cargo and finishes", st.stopped == "done", st.stopped)

-- ------------------------------------------------------ inventory pressure
-- an osmium ceiling over every cell: cargo is all keepers, tiny hold ->
-- haul trips home, then back to the same cell; sweep still completes
world = slabWorld(3, 4, 0)
for x = 0, 2 do
  for z = 0, 3 do world[key(x, 1, z)] = "mekanism:osmium_ore" end
end
m = newMock(world, { cap = 4 })
st = q.run(m.ops, { w = 3, l = 4 })
check("cargo: completes despite tiny hold", st.stopped == "done", st.stopped)
check("cargo: made haul trips", st.dumps >= 2, st.dumps)
check("cargo: every ceiling ore taken", st.ores == 12, st.ores)
check("cargo: slab still fully cleared", slabClear(m.world, 3, 4, 0) == nil)
check("cargo: parks at home", atHome(m))

-- junk-only pressure sheds in place instead of hauling
m = newMock(slabWorld(3, 4, 0), { cap = 3 })
st = q.run(m.ops, { w = 3, l = 4 })
check("junk: completes by shedding", st.stopped == "done", st.stopped)
check("junk: no mid-sweep hauls needed", st.dumps == 0 and m.dumps == 1,
  st.dumps .. "/" .. m.dumps)

-- -------------------------------------------------------------- multilayer
world = slabWorld(3, 3, 0)
for x = 0, 2 do
  for z = 0, 2 do world[key(x, -3, z)] = "minecraft:stone" end
end
world[key(1, -4, 1)] = "mekanism:osmium_ore"   -- under layer 2's plane
m = newMock(world)
st = q.run(m.ops, { w = 3, l = 3, layers = 2 })
check("layers: completes", st.stopped == "done", st.stopped)
check("layers: layer 1 cleared", slabClear(m.world, 3, 3, 0) == nil)
check("layers: layer 2 cleared", slabClear(m.world, 3, 3, -3) == nil)
check("layers: deep ore taken", world[key(1, -4, 1)] == nil)
check("layers: returns to surface home", atHome(m),
  ("at %d,%d,%d"):format(m.x, m.y, m.z))

-- ------------------------------------------------------------------ resume
world = slabWorld(1, 10, 0)
m = newMock(world)
st = q.run(m.ops, { w = 1, l = 10, resume = { layer = 1, cell = 8 } })
check("resume: completes", st.stopped == "done", st.stopped)
check("resume: only remaining cells processed", st.cellsDone == 3, st.cellsDone)
check("resume: parks at home", atHome(m))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
