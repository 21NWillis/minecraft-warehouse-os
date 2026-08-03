-- headless test for casinofit: mock world preloaded with the REAL casino
-- schematic at its campus offset; run the fit-out and prove every hopper,
-- barrel, water source, and strainer lands where the layout says, with no
-- collisions and a clean return to the datum.
package.path = "./?.lua;" .. package.path
_TEST = true
local campus = require("campus")
local fit = require("casinofit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local site = campus.site("casino")
local s = site.gen()
local at = site.at

check("layout has 112 strainer slots", #s.meta.strainers == 112, #s.meta.strainers)
check("every strainer slot has a hole beneath it", #s.meta.holes == #s.meta.strainers)
check("pool rows present", #s.meta.sources == 40, #s.meta.sources)

local key = function(x, y, z) return x .. "," .. y .. "," .. z end
local world = {}
for k, block in pairs(s.cells) do
  local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
  world[key(tonumber(x) + at[1], tonumber(y) + at[2], tonumber(z) + at[3])] = block
end
-- the pad (travel crosses its airspace) + the gold datum
local pad = campus.site("pad")
local ps = pad.gen()
for k, block in pairs(ps.cells) do
  local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
  world[key(tonumber(x) + pad.at[1], tonumber(y) + pad.at[2], tonumber(z) + pad.at[3])] = block
end
world[key(0, -1, 0)] = "minecraft:gold_block"

local slots = {
  { name = "minecraft:hopper", count = 112 },
  { name = "minecraft:barrel", count = 112 },
  { name = "ftbstuff:oak_water_strainer", count = 112 },
  { name = "minecraft:water_bucket", count = 1 },
  { name = "minecraft:water_bucket", count = 1 },
}
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
  select = function(sl) m.sel = sl end,
  getItemDetail = function(sl)
    local it = slots[sl or m.sel]
    if it and it.count > 0 then return { name = it.name, count = it.count } end
  end,
  inspectDown = function()
    local b = world[key(m.x, m.y - 1, m.z)]
    if b then return true, { name = b } end
    return false
  end,
  inspectUp = function()
    local b = world[key(m.x, m.y + 1, m.z)]
    if b then return true, { name = b } end
    return false
  end,
  placeDown = function()
    local it = slots[m.sel]
    if not it or it.count <= 0 then return false end
    local k = key(m.x, m.y - 1, m.z)
    if it.name == "minecraft:water_bucket" then
      if world[k] then return false end
      world[k] = "minecraft:water"
      it.name = "minecraft:bucket"
      return true
    elseif it.name == "minecraft:bucket" then
      if world[k] == "minecraft:water" then      -- scoop (pool stays: infinite)
        it.name = "minecraft:water_bucket"
        return true
      end
      return false
    else
      if world[k] then return false end
      it.count = it.count - 1
      world[k] = it.name
      return true
    end
  end,
  placeUp = function()
    local it = slots[m.sel]
    local k = key(m.x, m.y + 1, m.z)
    if world[k] or not it or it.count <= 0 then return false end
    it.count = it.count - 1
    world[k] = it.name
    return true
  end,
}

local ok, res, skipped = fit.run(t)
check("casinofit completes", ok == true, tostring(res))
check("returns to the datum", m.x == 0 and m.y == 0 and m.z == 0,
  m.x .. "," .. m.y .. "," .. m.z)
check("nothing ran out", skipped ~= nil and next(skipped) == nil,
  skipped and next(skipped))

local wrong = nil
for _, c in ipairs(s.meta.holes) do
  if world[key(at[1] + c[1], at[2] + c[2], at[3] + c[3])] ~= "minecraft:hopper" then
    wrong = "hopper@" .. c[1] .. "," .. c[3]
  end
  if world[key(at[1] + c[1], at[2] + c[2] - 1, at[3] + c[3])] ~= "minecraft:barrel" then
    wrong = wrong or ("barrel@" .. c[1] .. "," .. c[3])
  end
end
check("all 112 hoppers seated + 112 barrels hung", wrong == nil and
  res.hopper == 112 and res.barrel == 112, wrong or (res.hopper .. "/" .. res.barrel))

wrong = nil
for _, c in ipairs(s.meta.strainers) do
  if world[key(at[1] + c[1], at[2] + c[2], at[3] + c[3])] ~= "ftbstuff:oak_water_strainer" then
    wrong = "strainer@" .. c[1] .. "," .. c[3]
  end
end
check("all 112 strainers installed", wrong == nil and res.strainer == 112,
  wrong or res.strainer)
check("water poured at pool cells (2 per group, self-fill is real-world)",
  res.source == 24, res.source)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
