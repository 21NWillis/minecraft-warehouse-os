-- headless survey test: drive surveylogic against a mock voxel world and
-- prove the field guarantees before a turtle ever flies a wing:
--   full coverage of reachable air, naming of every adjacent solid,
--   routing around obstacles (including 3D detours), enclosed pockets
--   reported as unknown, entity handling, the fuel governor, and the
--   non-destruction doctrine (the mock provides NO dig functions - any
--   attempt to dig crashes the test).
package.path = "./?.lua;" .. package.path
local s = require("surveylogic")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local DIRS = s.DIRS
local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- mock turtle: solid blocks come from `world` (key -> name), entities from
-- `entities` (key -> hits left). Moves cost 1 fuel and fail against both;
-- detect/inspect see only blocks (entities are invisible, like CC).
local function newMock(world, opts)
  opts = opts or {}
  local m = {
    x = 0, y = 0, z = 0, f = 0,
    world = world, entities = opts.entities or {},
    fuel = opts.fuel or 100000, refuels = opts.refuels or 0,
    moves = 0, attacks = 0, minFuelSeen = math.huge,
  }
  local function move(dx, dy, dz)
    if m.fuel <= 0 then return false end
    local k = key(m.x + dx, m.y + dy, m.z + dz)
    if m.world[k] then return false end
    if (m.entities[k] or 0) > 0 then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    m.fuel = m.fuel - 1
    m.moves = m.moves + 1
    if m.fuel < m.minFuelSeen then m.minFuelSeen = m.fuel end
    return true
  end
  local function attackAt(dx, dy, dz)
    local k = key(m.x + dx, m.y + dy, m.z + dz)
    m.attacks = m.attacks + 1
    if (m.entities[k] or 0) > 0 then
      m.entities[k] = m.entities[k] - 1
      return true
    end
    return false
  end
  local function inspectAt(dx, dy, dz)
    local b = m.world[key(m.x + dx, m.y + dy, m.z + dz)]
    if b then return true, { name = b } end
    return false
  end
  local function ahead() return DIRS[m.f][1], 0, DIRS[m.f][2] end
  m.ops = {
    forward = function() return move(ahead()) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detect = function() local dx, dy, dz = ahead() return m.world[key(m.x + dx, m.y + dy, m.z + dz)] ~= nil end,
    detectUp = function() return m.world[key(m.x, m.y + 1, m.z)] ~= nil end,
    detectDown = function() return m.world[key(m.x, m.y - 1, m.z)] ~= nil end,
    inspect = function() return inspectAt(ahead()) end,
    inspectUp = function() return inspectAt(0, 1, 0) end,
    inspectDown = function() return inspectAt(0, -1, 0) end,
    attack = function() return attackAt(ahead()) end,
    attackUp = function() return attackAt(0, 1, 0) end,
    attackDown = function() return attackAt(0, -1, 0) end,
    getFuelLevel = function() return m.fuel end,
    tryRefuel = function()
      if m.refuels > 0 then m.refuels = m.refuels - 1; m.fuel = m.fuel + 80; return true end
      return false
    end,
    -- deliberately NO dig/digUp/digDown: calling one crashes the test
  }
  return m
end

local function atHome(m)
  return m.x == 0 and m.y == 0 and m.z == 0 and m.f == 0
end

-- ------------------------------------------------------------ empty volume
local m = newMock({})
local st = s.scan(m.ops, { w = 3, l = 3, h = 2 })
check("empty: completes", st.stopped == "done", st.stopped)
check("empty: all cells visited", st.visited == 18, st.visited)
check("empty: nothing solid/blocked/unknown",
  st.solids == 0 and st.blocked == 0 and st.unknown == 0,
  st.solids .. "/" .. st.blocked .. "/" .. st.unknown)
check("empty: parks at start pose", atHome(m),
  ("at %d,%d,%d f%d"):format(m.x, m.y, m.z, m.f))

-- ------------------------------------------------------- solids get named
local world = {}
world[key(1, 0, 1)] = "minecraft:iron_block"
world[key(2, 0, 2)] = "mekanism:basic_energy_cube"
m = newMock(world)
st = s.scan(m.ops, { w = 4, l = 4, h = 1 })
check("solids: completes", st.stopped == "done", st.stopped)
check("solids: all air visited", st.visited == 14, st.visited)
check("solids: both recorded", st.solids == 2, st.solids)
check("solids: names captured",
  st.cells[key(1, 0, 1)].name == "minecraft:iron_block"
  and st.cells[key(2, 0, 2)].name == "mekanism:basic_energy_cube")
check("solids: nothing unknown", st.unknown == 0, st.unknown)

-- ------------------------------------------------- detour around a wall
-- wall across x=2 with a single door at z=4: everything beyond is only
-- reachable through the door
world = {}
for z = 0, 3 do world[key(2, 0, z)] = "minecraft:stone_bricks" end
m = newMock(world)
st = s.scan(m.ops, { w = 5, l = 5, h = 1 })
check("wall: completes", st.stopped == "done", st.stopped)
check("wall: far side reached through door", st.visited == 21, st.visited)
check("wall: far corner classified air",
  st.cells[key(4, 0, 0)] and st.cells[key(4, 0, 0)].state == "air")
check("wall: wall fully named", st.solids == 4, st.solids)

-- ------------------------------------------------- sealed pocket = unknown
world = {}
world[key(1, 0, 2)] = "minecraft:obsidian"
world[key(3, 0, 2)] = "minecraft:obsidian"
world[key(2, 0, 1)] = "minecraft:obsidian"
world[key(2, 0, 3)] = "minecraft:obsidian"
m = newMock(world)
st = s.scan(m.ops, { w = 5, l = 5, h = 1 })
check("pocket: completes", st.stopped == "done", st.stopped)
check("pocket: sealed cell is unknown", st.unknown == 1, st.unknown)
check("pocket: walls named", st.solids == 4, st.solids)
check("pocket: rest visited", st.visited == 20, st.visited)

-- ---------------------------------------------- 3D routing through a slab
-- solid floor slab at y=1 with one hole: y=2 only reachable through it
world = {}
for x = 0, 2 do
  for z = 0, 2 do
    if not (x == 2 and z == 2) then world[key(x, 1, z)] = "minecraft:smooth_stone" end
  end
end
m = newMock(world)
st = s.scan(m.ops, { w = 3, l = 3, h = 3 })
check("slab: completes", st.stopped == "done", st.stopped)
check("slab: top floor reached through hole", st.visited == 19, st.visited)
check("slab: slab named", st.solids == 8, st.solids)
check("slab: top corner classified air",
  st.cells[key(0, 2, 0)] and st.cells[key(0, 2, 0)].state == "air")
check("slab: returns to start pose", atHome(m))

-- ------------------------------------------------------------ fuel governor
m = newMock({}, { fuel = 14 })
st = s.scan(m.ops, { w = 6, l = 6, h = 1, margin = 4 })
check("fuel: stops with reason", st.stopped == "fuel", st.stopped)
check("fuel: parks at home", atHome(m), ("at %d,%d,%d"):format(m.x, m.y, m.z))
check("fuel: never went broke mid-field", m.fuel >= 0 and m.minFuelSeen >= 0,
  m.minFuelSeen)
check("fuel: partial report kept", st.visited > 1 and st.visited < 36, st.visited)

m = newMock({}, { fuel = 14, refuels = 5 })
st = s.scan(m.ops, { w = 6, l = 6, h = 1, margin = 4 })
check("fuel: refuels from cargo and finishes", st.stopped == "done", st.stopped)

-- ------------------------------------------------------------------ entities
-- a mob squatting mid-box dies after 2 hits; scan should finish everything
local entities = {}
entities[key(2, 0, 2)] = 2
m = newMock({}, { entities = entities })
st = s.scan(m.ops, { w = 4, l = 4, h = 1 })
check("mob: completes", st.stopped == "done", st.stopped)
check("mob: all cells visited", st.visited == 16, st.visited)
check("mob: attacks happened", m.attacks >= 2, m.attacks)
check("mob: nothing blocked", st.blocked == 0, st.blocked)

-- an immortal squatter (armor stand, stubborn player) gets written off
entities = {}
entities[key(2, 0, 2)] = math.huge
m = newMock({}, { entities = entities })
st = s.scan(m.ops, { w = 4, l = 4, h = 1 })
check("squatter: completes", st.stopped == "done", st.stopped)
check("squatter: cell written off as blocked", st.blocked == 1, st.blocked)
check("squatter: everything else visited", st.visited == 15, st.visited)
check("squatter: parks at home", atHome(m))

-- ------------------------------------------------------------------ encode
-- synthetic report: 2x2x1 with one solid, one blocked, one unknown
local rep = { w = 2, l = 2, h = 1, stopped = "done", visited = 1, cells = {} }
rep.cells[key(0, 0, 0)] = { state = "air" }
rep.cells[key(1, 0, 0)] = { state = "solid", name = "minecraft:stone" }
rep.cells[key(0, 0, 1)] = { state = "blocked" }
-- (1,0,1) never seen -> unknown
local json = s.encode(rep, "testwing")
check("encode: layer order is z*w+x", json:find('"layers":%[%[0,1,%-2,%-1%]%]') ~= nil, json)
check("encode: palette holds the name", json:find('"palette":%["minecraft:stone"%]') ~= nil)
check("encode: label and dims present",
  json:find('"label":"testwing"') and json:find('"w":2') and json:find('"h":1'))

-- palette dedup: two cells, same block -> one palette entry
rep = { w = 2, l = 1, h = 1, stopped = "done", visited = 0, cells = {} }
rep.cells[key(0, 0, 0)] = { state = "solid", name = "minecraft:stone" }
rep.cells[key(1, 0, 0)] = { state = "solid", name = "minecraft:stone" }
json = s.encode(rep, "dedup")
check("encode: palette deduped", json:find('"palette":%["minecraft:stone"%]') ~= nil
  and json:find('"layers":%[%[1,1%]%]') ~= nil, json)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
