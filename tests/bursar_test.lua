-- headless bursarfit test: static layout invariants (sealed orb chamber,
-- contained water, kinetic chain, conduit gap) plus a full movement
-- simulation in a mock world proving every stand is reachable, every
-- placement lands, and the turtle parks back at its start pose.
package.path = "./?.lua;" .. package.path
_TEST = true
local M = require("bursarfit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local B = M.BLOCKS
local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- --------------------------------------------------------- layout facts
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

check("conduit gap left open", targets[key(1, 0, 6)] == nil, targets[key(1, 0, 6)])
check("obelisk behind the gap", targets[key(1, 0, 7)] == B.OBELISK)
check("vacuum is the chamber's far wall", targets[key(1, 0, 5)] == B.VACUUM)

-- kinetic chain: wheel -> shaft -> deployer colinear along z at x=1
check("kinetic chain colinear",
  targets[key(1, 0, -1)] == B.WHEEL and targets[key(1, 0, 0)] == B.SHAFT
  and targets[key(1, 0, 1)] == B.DEPLOYER)

-- orb chamber (1,0,2..4): every neighbor is floor (y=-1), a planned
-- block, or another interior cell - orbs must have nowhere to leak
local interior = { [key(1, 0, 2)] = true, [key(1, 0, 3)] = true, [key(1, 0, 4)] = true }
local leak = nil
for ik in pairs(interior) do
  local x, y, z = ik:match("(-?%d+),(-?%d+),(-?%d+)")
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
    local nx, ny, nz = x + d[1], y + d[2], z + d[3]
    local nk = key(nx, ny, nz)
    if ny >= 0 and not interior[nk] and not targets[nk] then leak = nk end
  end
end
check("orb chamber is sealed", leak == nil, leak)
check("chamber interior kept clear",
  not (targets[key(1, 0, 2)] or targets[key(1, 0, 3)] or targets[key(1, 0, 4)]))

-- vacuum reaches every interior cell (7-block radius, actual distance ~3)
local far = 0
for ik in pairs(interior) do
  local x, y, z = ik:match("(-?%d+),(-?%d+),(-?%d+)")
  local d = math.max(math.abs(tonumber(x) - 1), math.abs(tonumber(y) - 0),
    math.abs(tonumber(z) - 5))
  if d > far then far = d end
end
check("vacuum covers the whole chamber", far <= 7, far)

-- water pocket: source (1,1,-2) and flow cell (1,1,-1) fully contained
-- sideways and below (open top is fine - water doesn't climb)
local wet = { [key(1, 1, -2)] = true, [key(1, 1, -1)] = true }
local spill = nil
for wk in pairs(wet) do
  local x, y, z = wk:match("(-?%d+),(-?%d+),(-?%d+)")
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
    local nk = key(x + d[1], y + d[2], z + d[3])
    if not wet[nk] and not targets[nk] then spill = nk end
  end
end
check("water pocket contained", spill == nil, spill)

-- ------------------------------------------------------------ simulation
local function newMock()
  local world = {}
  for x = -2, 4 do
    for z = -5, 10 do world[key(x, -1, z)] = "floor" end
  end
  local slots, idx = {}, {}
  for blockName in pairs(M.bill()) do
    slots[#slots + 1] = blockName
    idx[blockName] = #slots
  end
  local m = { x = 0, y = 0, z = 0, f = 0, world = world, slots = slots,
    selected = 1, moves = 0, outOfBounds = nil }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k)
    local b = m.world[k]
    return b ~= nil and b ~= "water"
  end
  local function trackBounds()
    -- documented clearance: x 0..2 (1 left/right of the column), z -3..8,
    -- y 0..4 (5 tall)
    if m.x < 0 or m.x > 2 or m.z < -3 or m.z > 8 or m.y < 0 or m.y > 4 then
      m.outOfBounds = ("%d,%d,%d"):format(m.x, m.y, m.z)
    end
  end
  local function move(dx, dy, dz)
    local k = key(m.x + dx, m.y + dy, m.z + dz)
    if solid(k) then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    m.moves = m.moves + 1
    trackBounds()
    return true
  end
  local function placeAt(x, y, z)
    local k = key(x, y, z)
    if solid(k) then return false end
    local name = m.slots[m.selected]
    m.world[k] = (name == B.BUCKET) and "water" or name
    return true
  end
  m.ops = {
    forward = function() return move(DIRS[m.f][1], 0, DIRS[m.f][2]) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detect = function() return solid(key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])) end,
    detectDown = function() return solid(key(m.x, m.y - 1, m.z)) end,
    place = function() return placeAt(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2]) end,
    placeDown = function() return placeAt(m.x, m.y - 1, m.z) end,
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
check("sim: stayed within documented clearance", m.outOfBounds == nil, m.outOfBounds)

local wrong = nil
for k, blockName in pairs(targets) do
  if m.world[k] ~= blockName then wrong = k .. " expected " .. blockName .. " got " .. tostring(m.world[k]) end
end
check("sim: world matches the plan", wrong == nil, wrong)

-- a COMPLETED build seals its own chamber: rerun must refuse cleanly
-- (partial-build reruns work because stands seal strictly in plan order)
local ok2, res2 = M.run(m.ops)
check("sim: completed build refuses re-entry", ok2 == false and res2:find("blocked") ~= nil,
  tostring(ok2) .. "/" .. tostring(res2))

-- crash recovery: build stops after step N; resuming at N+1 (as the
-- state file would) finishes the build without revisiting sealed stands
local m2 = newMock()
local stopAt = #M.PLAN - 6
local okA = pcall(function()
  M.run(m2.ops, function(i)
    if i >= stopAt then error("simulated crash") end
  end)
end)
check("sim: crash mid-build simulated", okA == false)
-- field ritual: re-place the turtle at the start corner before rerunning
m2.x, m2.y, m2.z, m2.f = 0, 0, 0, 0
local okB, resB = M.run(m2.ops, nil, stopAt + 1)
check("sim: resume from state completes", okB == true and resB == #M.PLAN - stopAt,
  tostring(okB) .. "/" .. tostring(resB))
local missing = nil
for k, blockName in pairs(targets) do
  if m2.world[k] ~= blockName then missing = k end
end
check("sim: resumed world matches the plan", missing == nil, missing)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
