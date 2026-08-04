-- headless printfit v3 test: datum-frame plant east of the warehouse,
-- feeder behind the datum, solar-safety, access tower, 2-shard
-- partition, resume - and REALISTIC inventory semantics: the mock
-- feeder MERGES returned stacks into existing slots and suck() always
-- takes from the first occupied slot, exactly the behavior that
-- livelocked v3.0's cycling kit. The reject-bin protocol must pass
-- against a feeder whose first slot is one omega-sized coal stack.
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
local sandboxCrops = 0
for _, s in ipairs(M.genBay(10, BASE)) do
  if s.crop then sandboxCrops = sandboxCrops + 1 end
end
check("bay: sandbox is unplanted", sandboxCrops == 0, sandboxCrops)

local dry = nil
for row = 1, 9 do
  for col = 1, 9 do
    local near = false
    for _, w in ipairs(M.WATERS) do
      if math.max(math.abs(col - w[1]), math.abs(row - w[2])) <= 4 then near = true end
    end
    if not near then dry = col .. "," .. row end
  end
end
check("bay: every bed cell hydrated", dry == nil, dry)

local overhang = nil
for k = 1, 10 do
  for _, s in ipairs(M.genBay(k, BASE)) do
    local x, z = s.stand[1], s.stand[3]
    if x >= 10 and x <= 28 and z >= -6 and z <= 6 then overhang = k .. ":" .. x .. "," .. z end
  end
end
check("solar: no bay overhangs the roof", overhang == nil, overhang)
local towerBad = nil
for _, s in ipairs(M.genAccess(BASE)) do
  local x, z = s.stand[1], s.stand[3]
  if x >= 10 and x <= 28 and z >= -6 and z <= 6 then
    if not (z == M.TOWER.z and x >= M.TOWER.x - 2 and x <= M.TOWER.x) then
      towerBad = x .. "," .. z
    end
  end
end
check("solar: access touches only its own columns", towerBad == nil, towerBad)

-- ------------------------------------------------------------ mock rig
-- inventories: slot lists with MERGE-on-insert and first-slot suck,
-- unlimited per-slot capacity (omega semantics - the adversarial case)
local function isFarmland(n) return n:find("_farmland", 1, true) ~= nil end
local function isSeed(n) return n:find("_seeds", 1, true) ~= nil end

local function maxStack(name)
  if name == "minecraft:water_bucket" or name == "minecraft:bucket" then return 1 end
  return 64
end

-- slot indices are STABLE (real inventories leave gaps); zero-count
-- husks persist and may be refilled by same-name merges
local function invPut(inv, name, count)
  if maxStack(name) > 1 then
    for _, s in ipairs(inv) do
      if s.name == name then s.count = s.count + count return end
    end
    inv[#inv + 1] = { name = name, count = count }
  else
    for _ = 1, count do
      inv[#inv + 1] = { name = name, count = 1 }
    end
  end
end

local function invTake(inv)
  for _, s in ipairs(inv) do
    if s.count > 0 then
      local n = math.min(maxStack(s.name), s.count)
      s.count = s.count - n
      return { name = s.name, count = n }
    end
  end
  return nil
end

local function newWorld(feederInv)
  local world = {}
  for x = -8, 8 do
    for z = -8, 8 do world[key(x, -1, z)] = "pad" end
  end
  for x = 10, 28 do
    for z = -6, 6 do world[key(x, 8, z)] = "roof" end
  end
  world[key(27, 9, -5)] = "solar_gen"
  world[key(0, 0, -1)] = "feeder"
  world[key(0, 0, -4)] = "coal_chest"
  return { world = world, invs = { [key(0, 0, -1)] = feederInv,
    [key(0, 0, -4)] = { { name = "minecraft:coal", count = 512 } } },
    placed = {} }
end

local function newTurtle(sh, opts)
  opts = opts or {}
  local m = { x = 0, y = 0, z = 0, f = 0, inv = {}, sel = 1,
    fuel = opts.fuel or 600, sh = sh }
  if opts.hand then
    for i, stack in ipairs(opts.hand) do m.inv[i] = stack end
  end
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k)
    local b = sh.world[k]
    return b ~= nil and b ~= "water"
  end
  local function facedKey()
    return key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])
  end
  local function belowKey() return key(m.x, m.y - 1, m.z) end
  local function aboveKey() return key(m.x, m.y + 1, m.z) end
  local function invAt(k) return sh.invs[k] end
  local function doSuck(k)
    local inv = invAt(k)
    if not inv then return false end
    local stack = invTake(inv)
    if not stack then return false end
    for s = 1, 16 do
      if not m.inv[s] then m.inv[s] = stack return true end
    end
    invPut(inv, stack.name, stack.count)   -- no room: goes back
    return false
  end
  local function doDrop(k)
    local inv = invAt(k)
    if not inv then return false end
    local d = m.inv[m.sel]
    if not d then return false end
    invPut(inv, d.name, d.count)
    m.inv[m.sel] = nil
    return true
  end
  local function move(dx, dy, dz)
    if m.fuel <= 0 then return false end
    if solid(key(m.x + dx, m.y + dy, m.z + dz)) then return false end
    m.x, m.y, m.z = m.x + dx, m.y + dy, m.z + dz
    m.fuel = m.fuel - 1
    return true
  end
  local function placeInto(tk, name)
    sh.world[tk] = name
    sh.placed[tk] = name
    if name == I.BIN or name == I.CHEST then sh.invs[tk] = sh.invs[tk] or {} end
  end
  m.ops = {
    forward = function() return move(DIRS[m.f][1], 0, DIRS[m.f][2]) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detect = function() return solid(facedKey()) end,
    detectDown = function() return solid(belowKey()) end,
    detectUp = function() return solid(aboveKey()) end,
    suck = function() return doSuck(facedKey()) end,
    suckDown = function() return doSuck(belowKey()) end,
    suckUp = function() return doSuck(aboveKey()) end,
    drop = function() return doDrop(facedKey()) end,
    dropDown = function() return doDrop(belowKey()) end,
    dropUp = function() return doDrop(aboveKey()) end,
    place = function()
      local d = m.inv[m.sel]
      if not d then return false end
      local tk = facedKey()
      if sh.world[tk] then return false end
      placeInto(tk, d.name)
      d.count = d.count - 1
      if d.count <= 0 then m.inv[m.sel] = nil end
      return true
    end,
    placeUp = function()
      local d = m.inv[m.sel]
      if not d then return false end
      local tk = aboveKey()
      if sh.world[tk] then return false end
      placeInto(tk, d.name)
      d.count = d.count - 1
      if d.count <= 0 then m.inv[m.sel] = nil end
      return true
    end,
    placeDown = function()
      local d = m.inv[m.sel]
      if not d then return false end
      local tk = belowKey()
      local below = key(m.x, m.y - 2, m.z)
      local function consume()
        d.count = d.count - 1
        if d.count <= 0 then m.inv[m.sel] = nil end
      end
      if d.name == I.BUCKET then
        if sh.world[tk] then return false end
        placeInto(tk, "water")
        m.inv[m.sel] = { name = I.EMPTY_BUCKET, count = 1 }
        return true
      elseif d.name == I.LILYPAD then
        if sh.world[tk] or sh.world[below] ~= "water" then return false end
        placeInto(tk, d.name)
        consume()
        return true
      elseif isSeed(d.name) then
        if sh.world[tk] or not (sh.world[below] and isFarmland(sh.world[below])) then return false end
        placeInto(tk, "crop:" .. d.name)
        consume()
        return true
      elseif d.name == I.PYLON then
        if solid(tk) then return false end
        placeInto(tk, d.name)
        consume()
        return true
      else
        if sh.world[tk] then return false end
        placeInto(tk, d.name)
        consume()
        return true
      end
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
  -- peripheral shim: wrap("front"/"back"/...) resolves relative to the
  -- turtle's CURRENT facing; pushItems targets resolve the same way
  m.wrap = function(side)
    local function sideKey(s)
      if s == "front" then return facedKey() end
      if s == "back" then
        return key(m.x - DIRS[m.f][1], m.y, m.z - DIRS[m.f][2])
      end
      if s == "top" then return key(m.x, m.y + 1, m.z) end
      if s == "bottom" then return belowKey() end
      return nil
    end
    local myKey = sideKey(side)
    local inv = myKey and sh.invs[myKey]
    if not inv then return nil end
    return {
      list = function()
        local out = {}
        for i, s in ipairs(inv) do
          if s.count > 0 then out[i] = { name = s.name, count = s.count } end
        end
        return out
      end,
      pushItems = function(target, slot, limit)
        -- real pushItems moves at most ONE STACK per call
        local tk = sideKey(target)
        local tinv = tk and sh.invs[tk]
        local s = inv[slot]
        if not tinv or not s or s.count <= 0 then return 0 end
        local n = math.min(limit or s.count, s.count, maxStack(s.name))
        invPut(tinv, s.name, n)
        s.count = s.count - n
        return n
      end,
    }
  end
  return m
end

-- the feeder as an omega backpack really looks: mega-stacks, one slot
-- per item type, COAL FIRST (the exact shape that livelocked v3.0)
local function manifest()
  local inv = {}
  local function add(name, count) inv[#inv + 1] = { name = name, count = count } end
  add(BASE, 64 * 28)
  add("mysticalagriculture:supremium_farmland", 76 + 64)
  add("mysticalagriculture:prudentium_farmland", 152 + 64)
  add("mysticalagriculture:tertium_farmland", 228 + 64)
  add("mysticalagriculture:imperium_farmland", 228 + 64)
  add("mysticalagriculture:inferium_farmland", 76 + 64)
  for _, bay in ipairs(M.BAYS) do
    if bay.seed then add(bay.seed, 76) end
  end
  add(I.PYLON, 10)
  add("cyclic:user", 10)
  add("sophisticatedstorage:netherite_chest", 12)
  add(I.LILYPAD, 40)
  add(I.LADDER, 6)
  for _ = 1, 55 do add(I.BUCKET, 1) end
  return inv
end

local HAND = function()
  return { { name = I.COAL, count = 64 }, { name = I.BIN, count = 1 } }
end

local function verifyPlant(world)
  for k = 1, 10 do
    local px = M.BAY_X(k)
    local bay = M.BAYS[k]
    if world[key(px + 5, 14, 0)] ~= I.PYLON then return k .. ":pylon" end
    if world[key(px + 5, 15, 0)] ~= "sophisticatedstorage:netherite_chest" then return k .. ":chest" end
    if world[key(px + 5, 14, M.Z0)] ~= "cyclic:user" then return k .. ":user" end
    local farm, crops, pads = 0, 0, 0
    for row = 1, 9 do
      for col = 1, 9 do
        if world[key(px + row, 14, M.Z0 + col)] == bay.farmland then farm = farm + 1 end
        local up = world[key(px + row, 15, M.Z0 + col)]
        if up and up:find("^crop:") then crops = crops + 1 end
        if up == I.LILYPAD then pads = pads + 1 end
      end
    end
    if farm ~= 76 then return k .. ":farmland=" .. farm end
    if pads ~= 4 then return k .. ":pads=" .. pads end
    if crops ~= (bay.seed and 76 or 0) then return k .. ":crops=" .. crops end
  end
  return nil
end

-- ------------------------------------------------- full plant, 1 turtle
local sh = newWorld(manifest())
local t1 = newTurtle(sh, { hand = HAND() })
local ok, err = M.run(t1.ops, { base = BASE, shard = 1, of = 1, wrap = t1.wrap })
check("sim: plant completes vs merging feeder", ok == true, tostring(err))
check("sim: parks at its dock", t1.x == 0 and t1.y == 0 and t1.z == -2,
  ("at %d,%d,%d"):format(t1.x, t1.y, t1.z))
check("sim: bin chest placed beside dock", sh.world[key(0, 0, -3)] == I.BIN)
check("sim: all 10 bays correct", verifyPlant(sh.world) == nil, verifyPlant(sh.world))

local shadow = nil
for k in pairs(sh.placed) do
  local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
  x, z = tonumber(x), tonumber(z)
  if x >= 10 and x <= 28 and z >= -6 and z <= 6 then
    if not (z == M.TOWER.z and (x == M.TOWER.x or x == M.TOWER.x - 1)) then
      shadow = k
    end
  end
end
check("solar: no placement shades the roof", shadow == nil, shadow)
check("solar: gen untouched", sh.world[key(27, 9, -5)] == "solar_gen")

check("access: pillar tops at rim level", sh.world[key(M.TOWER.x, 14, M.TOWER.z)] == BASE)
local ladders = 0
for y = 9, 14 do
  if sh.world[key(M.TOWER.x - 1, y, M.TOWER.z)] == I.LADDER then ladders = ladders + 1 end
end
check("access: ladder column complete", ladders == 6, ladders)
local links = 0
for k = 1, 9 do
  if sh.world[key(M.BAY_X(k) + 11, 14, M.Z0)] == BASE then links = links + 1 end
end
check("access: catwalk links all gaps", links == 9, links)

-- --------------------------------------------------- 2-shard partition
local sh2 = newWorld(manifest())
local tA = newTurtle(sh2, { hand = HAND() })
local okA, errA = M.run(tA.ops, { base = BASE, shard = 1, of = 2, wrap = tA.wrap })
check("shards: A (odd bays + access) completes", okA == true, tostring(errA))
local tB = newTurtle(sh2, { hand = HAND() })
local okB, errB = M.run(tB.ops, { base = BASE, shard = 2, of = 2, wrap = tB.wrap })
check("shards: B (even bays) completes", okB == true, tostring(errB))
check("shards: union builds the whole plant", verifyPlant(sh2.world) == nil,
  verifyPlant(sh2.world))
check("shards: two bins at two docks",
  sh2.world[key(0, 0, -3)] == I.BIN and sh2.world[key(2, 0, -1)] == I.BIN)

-- ------------------------------------------------------- failure modes
local shortInv = {}
for _, s in ipairs(manifest()) do
  if s.name ~= I.PYLON then shortInv[#shortInv + 1] = s end
end
local sh3 = newWorld(shortInv)
local t3 = newTurtle(sh3, { hand = HAND() })
local ok3, err3 = M.run(t3.ops, { base = BASE, shard = 1, of = 1, wrap = t3.wrap })
check("sim: missing item reported", ok3 == false and err3:find("missing") ~= nil, tostring(err3))
check("sim: missing item names the culprit", tostring(err3):find("harvester_pylon") ~= nil, err3)

-- --------------------------------------------------------- crash resume
local sh4 = newWorld(manifest())
local t4 = newTurtle(sh4, { hand = HAND() })
local crashed = false
local okP = pcall(function()
  M.run(t4.ops, { base = BASE, shard = 1, of = 1, wrap = t4.wrap,
    onProgress = function(phase, i)
      if phase:find("bay 2") and i == 50 then crashed = true; error("simulated crash") end
    end })
end)
check("sim: crash mid-bay-2 simulated", okP == false and crashed)
t4.x, t4.y, t4.z, t4.f = 0, 0, 0, 0
local ok4, err4 = M.run(t4.ops, { base = BASE, shard = 1, of = 1, wrap = t4.wrap,
  resume = { bay = 2, step = 51 } })
check("sim: resume completes", ok4 == true, tostring(err4))
check("sim: resumed plant fully correct", verifyPlant(sh4.world) == nil,
  verifyPlant(sh4.world))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
