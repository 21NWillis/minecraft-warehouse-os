-- headless test for pipefit v2 (top-mounted): brownfield casino with sealed
-- underlayer + strainers waterlogged in, warehouse hall present. Prove the
-- lattice covers every channel cell from above, the trunk runs through the
-- DOORWAY to beside input barrel #1, nothing is ever dug, datum return.
package.path = "./?.lua;" .. package.path
_TEST = true
local campus = require("campus")
local pipefit = require("pipefit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local key = function(x, y, z) return x .. "," .. y .. "," .. z end
local world = {}
local function load(site)
  local s = site.gen()
  for k, block in pairs(s.cells) do
    local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
    world[key(tonumber(x) + site.at[1], tonumber(y) + site.at[2], tonumber(z) + site.at[3])] = block
  end
  return s
end
local casino = campus.site("casino")
local warehouse = campus.site("warehouse")
local cs = load(casino)
load(warehouse)
load(campus.site("pad"))
for _, c in ipairs(cs.meta.holes) do          -- holes sealed by hand
  world[key(casino.at[1] + c[1], casino.at[2] + c[2], casino.at[3] + c[3])] = "minecraft:purple_concrete"
end
for _, c in ipairs(cs.meta.strainers) do      -- strainers waterlogged in
  world[key(casino.at[1] + c[1], casino.at[2] + c[2], casino.at[3] + c[3])] = "ftbstuff:oak_water_strainer"
end
world[key(0, -1, 0)] = "minecraft:gold_block"
-- the input barrels exist (warehousefit ran): local (1, 1..2, 1)
world[key(warehouse.at[1] + 1, warehouse.at[2] + 1, warehouse.at[3] + 1)] = "sophisticatedstorage:barrel"
world[key(warehouse.at[1] + 1, warehouse.at[2] + 2, warehouse.at[3] + 1)] = "sophisticatedstorage:barrel"

local slots = { { name = "pipez:item_pipe", count = 250 } }
local m = { x = 0, y = 0, z = 0, f = 0, sel = 1 }
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
local t = {
  turnLeft = function() m.f = (m.f + 3) % 4 end,
  turnRight = function() m.f = (m.f + 1) % 4 end,
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
  inspectDown = function()
    local b = world[key(m.x, m.y - 1, m.z)]
    if b then return true, { name = b } end
    return false
  end,
  detectDown = function() return world[key(m.x, m.y - 1, m.z)] ~= nil end,
  placeDown = function()
    local it = slots[m.sel]
    local k = key(m.x, m.y - 1, m.z)
    if world[k] or not it or it.count <= 0 then return false end
    it.count = it.count - 1
    world[k] = it.name
    return true
  end,
  -- no dig functions at all: v2 never digs; a dig attempt = crash = FAIL
}

local ok, placed, total = pipefit.run(t)
check("pipefit v2 completes", ok == true, tostring(placed))
check("returns to the datum", m.x == 0 and m.y == 0 and m.z == 0,
  m.x .. "," .. m.y .. "," .. m.z)

local wrong, count = nil, 0
for c = 0, 3 do
  for _, lx in ipairs({ 1 + c * 3, 2 + c * 3 }) do
    for lz = 1, 19 do
      local k = key(casino.at[1] + lx, 1, casino.at[3] + lz)
      if world[k] == "pipez:item_pipe" then count = count + 1
      else wrong = wrong or k end
    end
  end
end
check("lattice covers all 152 channel cells (on TOP)", count == 152 and wrong == nil,
  wrong or count)
check("every lattice pipe sits over a strainer or water cell", (function()
  for c = 0, 3 do
    for _, lx in ipairs({ 1 + c * 3, 2 + c * 3 }) do
      for lz = 1, 19 do
        local below = world[key(casino.at[1] + lx, 0, casino.at[3] + lz)]
        if below ~= "ftbstuff:oak_water_strainer" and below ~= nil then return false end
      end
    end
  end
  return true
end)())
check("trunk ends beside input barrel #1",
  world[key(warehouse.at[1] + 2, 0, warehouse.at[3] + 1)] == "pipez:item_pipe")
check("trunk passes through the doorway",
  world[key(warehouse.at[1], 0, warehouse.at[3] + 6)] == "pipez:item_pipe")

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
