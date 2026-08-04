-- headless printfit test: whole-plant build against a mock world with a
-- real 16-slot inventory and a backpack item source. Proves: per-bay
-- geometry (waters, hydration, pylon-in-water, lilypads, planting),
-- the kit protocol (suck/reject cycling, fuel-first, slot pressure),
-- bucket refill at the basin, 10-bay completion, and crash resume.
package.path = "./?.lua;" .. package.path
_TEST = true
local M = require("printfit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local I = M.ITEMS
local BASE = "minecraft:cobbled_deepslate"
local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- ------------------------------------------------------------- geometry
local bay1 = M.genBay(1, BASE)
check("bay: step count", #bay1 == 121 + 39 + 1 + 76 + 5 + 1 + 4 + 1 + 76, #bay1)
local sandbox = M.genBay(10, BASE)
local sandboxCrops = 0
for _, s in ipairs(sandbox) do if s.crop then sandboxCrops = sandboxCrops + 1 end end
check("bay: sandbox is unplanted", sandboxCrops == 0, sandboxCrops)
check("bay: farmland tier per bay",
  M.BAYS[1].farmland:find("supremium") ~= nil and M.BAYS[10].farmland:find("inferium") ~= nil)

-- hydration: every bed cell within 4 of one of the 5 water cells
local dry = nil
for z = 1, 9 do
  for x = 1, 9 do
    local near = false
    for _, w in ipairs(M.WATERS) do
      if math.max(math.abs(x - w[1]), math.abs(z - w[2])) <= 4 then near = true end
    end
    if not near then dry = x .. "," .. z end
  end
end
check("bay: every bed cell hydrated", dry == nil, dry)

-- kit feasibility: each bay's BOM fits the 16-slot inventory
local worstSlots = 0
for k = 1, 10 do
  local slots = 0
  for name, want in pairs(M.bayBOM(k, BASE)) do
    local stackSize = (name == I.BUCKET) and 1 or 64
    slots = slots + math.ceil(want / stackSize)
  end
  if slots > worstSlots then worstSlots = slots end
end
check("bay: BOM fits 16 slots", worstSlots <= 16, worstSlots)

-- ------------------------------------------------------------ mock rig
local function isFarmland(n) return n:find("_farmland", 1, true) ~= nil end
local function isSeed(n) return n:find("_seeds", 1, true) ~= nil end

local function newMock(pack, opts)
  opts = opts or {}
  local m = { x = 0, y = 0, z = 0, f = 0, world = {}, inv = {}, sel = 1,
    fuel = opts.fuel or 0, pack = pack, outOfBounds = nil }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k)
    local b = m.world[k]
    return b ~= nil and b ~= "water"
  end
  local function atPack()
    return m.x == 0 and m.y == 0 and m.z == 0 and m.f == 2
  end
  local function move(dx, dy, dz)
    if m.fuel <= 0 then return false end
    local k = key(m.x + dx, m.y + dy, m.z + dz)
    if solid(k) then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    m.fuel = m.fuel - 1
    if m.x < 0 or m.x > 10 or m.z < 0 or m.y < 0 or m.y > M.CRUISE then
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
      local d = m.inv[m.sel]
      if not d then return false end
      local tk = key(m.x, m.y - 1, m.z)
      local below = key(m.x, m.y - 2, m.z)
      local function consume()
        d.count = d.count - 1
        if d.count <= 0 then m.inv[m.sel] = nil end
      end
      if d.name == I.BUCKET then
        if m.world[tk] then return false end
        m.world[tk] = "water"
        m.inv[m.sel] = { name = I.EMPTY_BUCKET, count = 1 }
        return true
      elseif d.name == I.EMPTY_BUCKET then
        if m.world[tk] ~= "water" then return false end
        m.inv[m.sel] = { name = I.BUCKET, count = 1 }
        return true
      elseif d.name == I.LILYPAD then
        if m.world[tk] or m.world[below] ~= "water" then return false end
        m.world[tk] = d.name
        consume()
        return true
      elseif isSeed(d.name) then
        if m.world[tk] or not (m.world[below] and isFarmland(m.world[below])) then return false end
        m.world[tk] = "crop:" .. d.name
        consume()
        return true
      elseif d.name == I.PYLON then
        if solid(tk) then return false end
        m.world[tk] = d.name   -- places into air or waterlogs into a source
        consume()
        return true
      else
        if m.world[tk] then return false end
        m.world[tk] = d.name
        consume()
        return true
      end
    end,
    suck = function()
      if not atPack() then return false end
      if #m.pack == 0 then return false end
      local slot = nil
      for s = 1, 16 do
        if not m.inv[s] then slot = s break end
      end
      if not slot then return false end
      m.inv[slot] = table.remove(m.pack, 1)
      return true
    end,
    drop = function()
      if not atPack() then return false end
      local d = m.inv[m.sel]
      if not d then return false end
      m.pack[#m.pack + 1] = d
      m.inv[m.sel] = nil
      return true
    end,
    getItemDetail = function(slot) return m.inv[slot] end,
    select = function(slot) m.sel = slot return true end,
    getFuelLevel = function() return m.fuel end,
    refuel = function(n)
      local d = m.inv[m.sel]
      if not d or d.name ~= I.COAL then return false end
      local burn = math.min(n or d.count, d.count)
      m.fuel = m.fuel + burn * 80
      d.count = d.count - burn
      if d.count <= 0 then m.inv[m.sel] = nil end
      return true
    end,
  }
  return m
end

-- the backpack manifest, deliberately in awkward order so bay kits must
-- reject and cycle (all farmland tiers arrive before most bays need them)
local function manifest()
  local pack = {}
  local function add(name, count, stacks)
    for _ = 1, stacks do pack[#pack + 1] = { name = name, count = count } end
  end
  add(I.COAL, 64, 8)
  add("mysticalagriculture:supremium_farmland", 64, 2)
  add("mysticalagriculture:prudentium_farmland", 64, 3)
  add("mysticalagriculture:tertium_farmland", 64, 4)
  add("mysticalagriculture:imperium_farmland", 64, 4)
  add("mysticalagriculture:inferium_farmland", 64, 2)
  for _, bay in ipairs(M.BAYS) do
    if bay.seed then add(bay.seed, 64, 2) end
  end
  add(I.PYLON, 10, 1)
  add("cyclic:user", 10, 1)
  add("sophisticatedstorage:chest", 10, 1)
  add(I.LILYPAD, 40, 1)
  add(I.BUCKET, 1, 7)
  add(BASE, 64, 26)
  return pack
end

-- ------------------------------------------------------- full plant sim
local m = newMock(manifest())
local ok, err = M.run(m.ops, { base = BASE })
check("sim: plant completes", ok == true, tostring(err))
check("sim: parks at station pose", m.x == 0 and m.y == 0 and m.z == 0 and m.f == 0,
  ("at %d,%d,%d f%d"):format(m.x, m.y, m.z, m.f))
check("sim: stayed in the row corridor", m.outOfBounds == nil, m.outOfBounds)

-- basin: 2x2 interior has its two placed sources
check("sim: basin water placed",
  m.world[key(3, 0, 1)] == "water" and m.world[key(4, 0, 2)] == "water")

local badBay = nil
for k = 1, 10 do
  local z0 = M.BAY_Z(k)
  local bay = M.BAYS[k]
  if m.world[key(5, 0, z0 + 5)] ~= I.PYLON then badBay = k .. ":pylon" end
  if m.world[key(5, 1, z0 + 5)] ~= "sophisticatedstorage:chest" then badBay = k .. ":chest" end
  if m.world[key(5, 0, z0)] ~= "cyclic:user" then badBay = k .. ":user" end
  local farm, crops, pads = 0, 0, 0
  for z = 1, 9 do
    for x = 1, 9 do
      if m.world[key(x, 0, z0 + z)] == bay.farmland then farm = farm + 1 end
      local up = m.world[key(x, 1, z0 + z)]
      if up and up:find("^crop:") then crops = crops + 1 end
      if up == I.LILYPAD then pads = pads + 1 end
    end
  end
  if farm ~= 76 then badBay = k .. ":farmland=" .. farm end
  if pads ~= 4 then badBay = k .. ":pads=" .. pads end
  local wantCrops = bay.seed and 76 or 0
  if crops ~= wantCrops then badBay = k .. ":crops=" .. crops end
  for i = 2, 5 do
    local w = M.WATERS[i]
    if m.world[key(w[1], 0, z0 + w[2])] ~= "water" then badBay = k .. ":water" end
  end
end
check("sim: all 10 bays correct", badBay == nil, badBay)

-- ------------------------------------------------------- failure modes
local short = {}
for _, s in ipairs(manifest()) do
  if s.name ~= I.PYLON then short[#short + 1] = s end
end
local m2 = newMock(short)
local ok2, err2 = M.run(m2.ops, { base = BASE })
check("sim: missing item reported", ok2 == false and err2:find("missing") ~= nil, tostring(err2))
check("sim: missing item names the culprit", tostring(err2):find("harvester_pylon") ~= nil, err2)

-- --------------------------------------------------------- crash resume
local m3 = newMock(manifest())
local crashed = false
local okP = pcall(function()
  M.run(m3.ops, { base = BASE, onProgress = function(phase, i)
    if phase:find("bay 2") and i == 50 then crashed = true; error("simulated crash") end
  end })
end)
check("sim: crash mid-bay-2 simulated", okP == false and crashed)
m3.x, m3.y, m3.z, m3.f = 0, 0, 0, 0   -- re-place at station ritual
local ok3, err3 = M.run(m3.ops, { base = BASE, resume = { bay = 2, step = 51 } })
check("sim: resume completes", ok3 == true, tostring(err3))
local resumeBad = nil
for k = 1, 10 do
  local z0 = M.BAY_Z(k)
  if m3.world[key(5, 0, z0 + 5)] ~= I.PYLON then resumeBad = k end
end
check("sim: resumed plant has all pylons", resumeBad == nil, resumeBad)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
