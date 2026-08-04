-- headless farmfit test: pod layout invariants (bed size, hydration
-- coverage, rim integrity, machine placement, open underside for
-- growth-accelerator pillars) plus the full movement simulation.
package.path = "./?.lua;" .. package.path
_TEST = true
local M = require("farmfit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local B = M.BLOCKS
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local targets = {}
local dup = nil
for _, p in ipairs(M.PLAN) do
  local x, y, z = M.targetCell(p)
  local k = key(x, y, z)
  if targets[k] then dup = k end
  targets[k] = (p.block == B.BUCKET) and "water" or p.block
end
check("no duplicate placements", dup == nil, dup)

local total = 0
for _, n in pairs(M.bill()) do total = total + n end
check("bill accounts for every step", total == #M.PLAN, total .. "/" .. #M.PLAN)

-- base slab: full 11x11 at y=-1
local baseMissing = nil
for z = 1, 11 do
  for x = 0, 10 do
    if targets[key(x, -1, z)] ~= B.BASE then baseMissing = key(x, -1, z) end
  end
end
check("base slab complete (safe over void)", baseMissing == nil, baseMissing)

-- bed: 80 farmland + center water at y0, all inside the rim
local farmland, badBed = 0, nil
for z = 2, 10 do
  for x = 1, 9 do
    local got = targets[key(x, 0, z)]
    if x == 5 and z == 6 then
      if got ~= "water" then badBed = "center is " .. tostring(got) end
    elseif got == B.FARMLAND then farmland = farmland + 1
    else badBed = key(x, 0, z) .. "=" .. tostring(got) end
  end
end
check("bed is 80 farmland + center water", farmland == 80 and badBed == nil, badBed)

-- hydration: vanilla waters farmland within 4 blocks horizontally
local dry = nil
for z = 2, 10 do
  for x = 1, 9 do
    if math.max(math.abs(x - 5), math.abs(z - 6)) > 4 then dry = key(x, 0, z) end
  end
end
check("every bed cell within water range", dry == nil, dry)

-- rim: y0 border fully solid (walkway or machine) - water can't escape
local gap = nil
for z = 1, 11 do
  for x = 0, 10 do
    if (x == 0 or x == 10 or z == 1 or z == 11) and not targets[key(x, 0, z)] then
      gap = key(x, 0, z)
    end
  end
end
check("rim complete (walkway + machines)", gap == nil, gap)
check("machines on south rim", targets[key(4, 0, 1)] == B.GATHERER
  and targets[key(5, 0, 1)] == B.SOWER)

-- machines adjacent to the bed they serve
check("machines touch the bed row", targets[key(4, 0, 2)] == B.FARMLAND
  and targets[key(5, 0, 2)] == B.FARMLAND)

-- turtle parking column (z0) stays clear of the build
local parked = nil
for k in pairs(targets) do
  local _, _, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
  if tonumber(z) < 1 then parked = k end
end
check("parking column untouched", parked == nil, parked)

-- underside open: nothing below y=-1 - accelerator pillars bolt on later
local under = nil
for k in pairs(targets) do
  local _, y = k:match("(-?%d+),(-?%d+)")
  if tonumber(y) < -1 then under = k end
end
check("underside open for accelerator pillars", under == nil, under)

-- ------------------------------------------------------------ simulation
local function newMock()
  local world = {}
  local slots, idx = {}, {}
  for blockName in pairs(M.bill()) do
    slots[#slots + 1] = blockName
    idx[blockName] = #slots
  end
  local m = { x = 0, y = 0, z = 0, f = 0, world = world, slots = slots,
    selected = 1, outOfBounds = nil }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k)
    local b = m.world[k]
    return b ~= nil and b ~= "water"
  end
  local function move(dx, dy, dz)
    local k = key(m.x + dx, m.y + dy, m.z + dz)
    if solid(k) then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    if m.x < 0 or m.x > 10 or m.z < 0 or m.z > 11 or m.y < 0 or m.y > 2 then
      m.outOfBounds = ("%d,%d,%d"):format(m.x, m.y, m.z)
    end
    return true
  end
  m.ops = {
    forward = function() return move(DIRS[m.f][1], 0, DIRS[m.f][2]) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detectDown = function() return solid(key(m.x, m.y - 1, m.z)) end,
    placeDown = function()
      local k = key(m.x, m.y - 1, m.z)
      if solid(k) then return false end
      local name = m.slots[m.selected]
      m.world[k] = (name == B.BUCKET) and "water" or name
      return true
    end,
    getItemDetail = function(slot)
      if m.slots[slot] then return { name = m.slots[slot] } end
      return nil
    end,
    select = function(slot) m.selected = slot return true end,
  }
  return m
end

local m = newMock()
local ok, res = M.run(m.ops)
check("sim: build completes", ok == true, tostring(res))
check("sim: every step placed", res == #M.PLAN, res)
check("sim: parks at start pose", m.x == 0 and m.y == 0 and m.z == 0 and m.f == 0,
  ("at %d,%d,%d f%d"):format(m.x, m.y, m.z, m.f))
check("sim: stayed within pod footprint", m.outOfBounds == nil, m.outOfBounds)

local wrong = nil
for k, blockName in pairs(targets) do
  if m.world[k] ~= blockName then wrong = k end
end
check("sim: world matches the plan", wrong == nil, wrong)

-- a finished pod's slab blocks the base-laying stands: fresh rerun must
-- refuse cleanly (crash-resume still works - later stands sit at y1)
local ok2, res2 = M.run(m.ops)
check("sim: finished-pod rerun refuses cleanly", ok2 == false and res2:find("blocked") ~= nil,
  tostring(ok2) .. "/" .. tostring(res2))

-- crash recovery: die mid-build, re-place at corner, resume by step
local m2 = newMock()
local stopAt = 100
local okA = pcall(function()
  M.run(m2.ops, function(i)
    if i >= stopAt then error("simulated crash") end
  end)
end)
check("sim: crash mid-build simulated", okA == false)
m2.x, m2.y, m2.z, m2.f = 0, 0, 0, 0
local okB, resB = M.run(m2.ops, nil, stopAt + 1)
check("sim: resume completes the pod", okB == true, tostring(resB))
local missing = nil
for k, blockName in pairs(targets) do
  if m2.world[k] ~= blockName then missing = k end
end
check("sim: resumed world matches the plan", missing == nil, missing)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
