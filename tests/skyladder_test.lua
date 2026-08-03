-- headless test for skyladder: flat-ground mock; assert the full scaffold
-- column, the datum block, and the final pose on top of it.
package.path = "./?.lua;" .. package.path
_TEST = true
local sky = require("skyladder")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local key = function(x, y, z) return x .. "," .. y .. "," .. z end
local world = {}
for x = -3, 3 do
  for z = -12, 3 do world[key(x, -1, z)] = "minecraft:grass_block" end
end
-- the tower's front-left corner column (the launch anchor sits on top of it)
for y = 0, 7 do world[key(0, y, 0)] = "minecraft:polished_blackstone" end

local slots = {
  { name = "minecraft:scaffolding", count = 199 },
  { name = "minecraft:gold_block", count = 1 },
}
local m = { x = 0, y = 8, z = 0, f = 0, sel = 1 }   -- on the anchor spot
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
local t = {
  turnLeft = function() m.f = (m.f + 3) % 4 end,
  turnRight = function() m.f = (m.f + 1) % 4 end,
  detectDown = function() return world[key(m.x, m.y - 1, m.z)] ~= nil end,
  up = function()
    if world[key(m.x, m.y + 1, m.z)] then return false end
    m.y = m.y + 1; return true
  end,
  down = function()
    if world[key(m.x, m.y - 1, m.z)] then return false end
    m.y = m.y - 1; return true
  end,
  forward = function()
    local nx, nz = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
    if world[key(nx, m.y, nz)] then return false end
    m.x, m.z = nx, nz; return true
  end,
  select = function(s) m.sel = s end,
  getItemDetail = function(s)
    local it = slots[s or m.sel]
    if it and it.count > 0 then return { name = it.name, count = it.count } end
  end,
  placeDown = function()
    local k = key(m.x, m.y - 1, m.z)
    local it = slots[m.sel]
    if world[k] or not it or it.count <= 0 then return false end
    it.count = it.count - 1
    world[k] = it.name
    return true
  end,
}

local ok, err = sky.run(t)
check("skyladder completes", ok, err)
check("ends standing on the datum", m.x == 0 and m.y == sky.HEIGHT and m.z == 0 and m.f == 0,
  m.x .. "," .. m.y .. "," .. m.z .. " f=" .. m.f)
check("datum gold block placed", world[key(0, sky.HEIGHT - 1, 0)] == "minecraft:gold_block")

local column, gaps = 0, nil
for y = 0, sky.HEIGHT - 2 do
  if world[key(0, y, sky.COL_Z)] == "minecraft:scaffolding" then column = column + 1
  else gaps = gaps or y end
end
check("scaffold column continuous ground to campus level",
  column == sky.HEIGHT - 1 and gaps == nil, (gaps or column))
check("materials exactly consumed", slots[1].count == 0 and slots[2].count == 0,
  slots[1].count .. "/" .. slots[2].count)

-- rerun after partial: wipe the top 50, restock, run again from the ground
for y = 149, sky.HEIGHT - 2 do world[key(0, y, sky.COL_Z)] = nil end
world[key(0, sky.HEIGHT - 1, 0)] = nil
slots[1].count = 60
slots[2].count = 1
m.x, m.y, m.z, m.f = 0, 8, 0, 0
local ok2, err2 = sky.run(t)
check("rerun repairs the column and datum", ok2, err2)
check("column whole again", (function()
  for y = 0, sky.HEIGHT - 2 do
    if world[key(0, y, sky.COL_Z)] ~= "minecraft:scaffolding" then return false end
  end
  return world[key(0, sky.HEIGHT - 1, 0)] == "minecraft:gold_block"
end)())

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
