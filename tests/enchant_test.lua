-- headless enchantfit test: shelf-ring geometry (exact enchanting-table
-- scan positions, clear inner air ring, door gap), floor coverage, and
-- a movement sim with partial-shelf tolerance.
package.path = "./?.lua;" .. package.path
_TEST = true
local M = require("enchantfit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local FLOOR = "minecraft:deepslate_tiles"
local plan = M.genPlan(FLOOR)
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local targets = {}
for _, s in ipairs(plan) do
  targets[key(s.stand[1], s.stand[2] - 1, s.stand[3])] = s
end

-- table centered, shelves at radius exactly 2, inner ring untouched
check("table at center", targets[key(3, 0, 4)] and targets[key(3, 0, 4)].block == "minecraft:enchanting_table")
local badShelf, shelfCount, innerViolation = nil, 0, nil
for k, s in pairs(targets) do
  if s.kind == "shelf" then
    shelfCount = shelfCount + 1
    local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local dx, dz = math.abs(x - 3), math.abs(z - 4)
    if math.max(dx, dz) ~= 2 then badShelf = k end
    if y ~= 0 and y ~= 1 then badShelf = k end
  end
end
for dx = -1, 1 do
  for dz = -1, 1 do
    if not (dx == 0 and dz == 0) then
      for y = 0, 1 do
        if targets[key(3 + dx, y, 4 + dz)] then innerViolation = key(3 + dx, y, 4 + dz) end
      end
    end
  end
end
check("shelves on the scan ring only", badShelf == nil, badShelf)
check("30 shelf slots (32 minus door gap)", shelfCount == 30, shelfCount)
check("inner air ring kept clear", innerViolation == nil, innerViolation)
check("door gap at mid-south", targets[key(3, 0, 2)] == nil and targets[key(3, 1, 2)] == nil)

local floorCount = 0
for _, s in ipairs(plan) do
  if s.block == FLOOR then floorCount = floorCount + 1 end
end
check("floor is 7x7", floorCount == 49, floorCount)

-- ------------------------------------------------------------ simulation
local function newMock(inv)
  local m = { x = 0, y = 0, z = 0, f = 0, world = {}, inv = inv, sel = 1 }
  for x = -1, 7 do
    for z = -1, 8 do m.world[key(x, -2, z)] = "ground" end
  end
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k) return m.world[k] ~= nil end
  m.ops = {
    forward = function()
      local k = key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])
      if solid(k) then return false end
      m.x, m.z = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
      return true
    end,
    up = function()
      if solid(key(m.x, m.y + 1, m.z)) then return false end
      m.y = m.y + 1
      return true
    end,
    down = function()
      if solid(key(m.x, m.y - 1, m.z)) then return false end
      m.y = m.y - 1
      return true
    end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detectDown = function() return solid(key(m.x, m.y - 1, m.z)) end,
    placeDown = function()
      local d = m.inv[m.sel]
      if not d or d.count <= 0 then return false end
      local tk = key(m.x, m.y - 1, m.z)
      if m.world[tk] then return false end
      m.world[tk] = d.name
      d.count = d.count - 1
      if d.count <= 0 then m.inv[m.sel] = nil end
      return true
    end,
    getItemDetail = function(slot) return m.inv[slot] end,
    select = function(slot) m.sel = slot return true end,
  }
  return m
end

local m = newMock({
  { name = FLOOR, count = 64 },
  { name = "minecraft:enchanting_table", count = 1 },
  { name = "apothic_enchanting:hellshelf", count = 20 },
  { name = "apothic_enchanting:seashelf", count = 10 },
  { name = "minecraft:glowstone", count = 4 },
})
local ok, placed, skipped = M.run(m.ops, { floorBlock = FLOOR })
check("sim: build completes", ok == true, tostring(placed))
check("sim: full shelf ring placed", skipped == 0, skipped)
check("sim: table placed", m.world[key(3, 0, 4)] == "minecraft:enchanting_table")
check("sim: parks at start", m.x == 0 and m.y == 0 and m.z == 0 and m.f == 0,
  ("at %d,%d,%d"):format(m.x, m.y, m.z))
local shelves = 0
for _, v in pairs(m.world) do
  if M.isShelf(v) then shelves = shelves + 1 end
end
check("sim: 30 shelves in the world", shelves == 30, shelves)

-- shelf shortage: build completes, gaps reported
local m2 = newMock({
  { name = FLOOR, count = 64 },
  { name = "minecraft:enchanting_table", count = 1 },
  { name = "apothic_enchanting:hellshelf", count = 12 },
})
local ok2, _, skipped2 = M.run(m2.ops, { floorBlock = FLOOR })
check("sim: shelf shortage tolerated", ok2 == true and skipped2 == 18,
  tostring(ok2) .. "/" .. tostring(skipped2))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
