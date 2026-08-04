-- headless printfit v3 test: datum-frame plant east of the warehouse,
-- feeder behind the datum, solar-safety (no roof-column overhang),
-- access tower + catwalk, kit protocol, 2-shard partition, resume.
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

local worstSlots = 0
for k = 1, 10 do
  local slots = 0
  for name, want in pairs(M.bayBOM(k, BASE)) do
    slots = slots + math.ceil(want / ((name == I.BUCKET) and 1 or 64))
  end
  if slots > worstSlots then worstSlots = slots end
end
check("bay: BOM fits 16 slots", worstSlots <= 16, worstSlots)

-- SOLAR SAFETY (static): no bay step touches a warehouse roof column
-- (x 10..28, z -6..6); only the access tower may, at its two columns
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

local dockCells, dupDock = {}, nil
for _, d in ipairs(M.DOCKS) do
  local ck = table.concat(d.at, ",")
  if dockCells[ck] then dupDock = ck end
  dockCells[ck] = true
end
check("docks: cells disjoint", dupDock == nil, dupDock)

-- ------------------------------------------------------------ mock rig
local function isFarmland(n) return n:find("_farmland", 1, true) ~= nil end
local function isSeed(n) return n:find("_seeds", 1, true) ~= nil end

local function newWorld(pack)
  local world = {}
  for x = -8, 8 do
    for z = -8, 8 do world[key(x, -1, z)] = "pad" end
  end
  for x = 10, 28 do
    for z = -6, 6 do world[key(x, 8, z)] = "roof" end
  end
  world[key(27, 9, -5)] = "solar_gen"    -- the power stuff is here
  world[key(0, 0, -1)] = "feeder"        -- right behind the datum
  return { world = world, pack = pack, placed = {} }
end

local function newTurtle(sh, opts)
  opts = opts or {}
  local m = { x = 0, y = 0, z = 0, f = 0, inv = {}, sel = 1,
    fuel = opts.fuel or 600, sh = sh }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local function solid(k)
    local b = sh.world[k]
    return b ~= nil and b ~= "water"
  end
  local function facedKey()
    return key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])
  end
  local function belowKey() return key(m.x, m.y - 1, m.z) end
  local function isFeeder(k) return sh.world[k] == "feeder" end
  local function packSuck()
    if #sh.pack == 0 then return false end
    for s = 1, 16 do
      if not m.inv[s] then
        m.inv[s] = table.remove(sh.pack, 1)
        return true
      end
    end
    return false
  end
  local function packDrop()
    local d = m.inv[m.sel]
    if not d then return false end
    sh.pack[#sh.pack + 1] = d
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
  end
  m.ops = {
    forward = function() return move(DIRS[m.f][1], 0, DIRS[m.f][2]) end,
    up = function() return move(0, 1, 0) end,
    down = function() return move(0, -1, 0) end,
    turnLeft = function() m.f = (m.f - 1) % 4 return true end,
    turnRight = function() m.f = (m.f + 1) % 4 return true end,
    detect = function() return solid(facedKey()) end,
    detectDown = function() return solid(belowKey()) end,
    suck = function() return isFeeder(facedKey()) and packSuck() or false end,
    suckDown = function() return isFeeder(belowKey()) and packSuck() or false end,
    drop = function() return isFeeder(facedKey()) and packDrop() or false end,
    dropDown = function() return isFeeder(belowKey()) and packDrop() or false end,
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
  return m
end

local function manifest()
  local pack = {}
  local function add(name, count, stacks)
    for _ = 1, stacks do pack[#pack + 1] = { name = name, count = count } end
  end
  add(I.COAL, 64, 8)
  add("mysticalagriculture:supremium_farmland", 64, 3)
  add("mysticalagriculture:prudentium_farmland", 64, 4)
  add("mysticalagriculture:tertium_farmland", 64, 5)
  add("mysticalagriculture:imperium_farmland", 64, 5)
  add("mysticalagriculture:inferium_farmland", 64, 3)
  for _, bay in ipairs(M.BAYS) do
    if bay.seed then add(bay.seed, 76, 1) end
  end
  add(I.PYLON, 10, 1)
  add("cyclic:user", 10, 1)
  add("sophisticatedstorage:chest", 10, 1)
  add(I.LILYPAD, 40, 1)
  add(I.LADDER, 6, 1)
  add(I.BUCKET, 1, 55)
  add(BASE, 64, 28)
  return pack
end

local function verifyPlant(world)
  for k = 1, 10 do
    local px = M.BAY_X(k)
    local bay = M.BAYS[k]
    if world[key(px + 5, 14, 0)] ~= I.PYLON then return k .. ":pylon" end
    if world[key(px + 5, 15, 0)] ~= "sophisticatedstorage:chest" then return k .. ":chest" end
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
local t1 = newTurtle(sh)
local ok, err = M.run(t1.ops, { base = BASE, shard = 1, of = 1 })
check("sim: plant completes", ok == true, tostring(err))
check("sim: parks at its dock", t1.x == 0 and t1.y == 1 and t1.z == -1,
  ("at %d,%d,%d"):format(t1.x, t1.y, t1.z))
local emptyInv = true
for s = 1, 16 do if t1.inv[s] then emptyInv = false end end
check("sim: change returned to feeder", emptyInv)
check("sim: all 10 bays correct", verifyPlant(sh.world) == nil, verifyPlant(sh.world))

-- solar safety (dynamic): nothing placed in a roof column outside the
-- tower's own two columns; the solar gen block is untouched
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

-- access: tower pillar, ladders, bridge, catwalk
check("access: pillar tops at rim level", sh.world[key(M.TOWER.x, 14, M.TOWER.z)] == BASE)
local ladders = 0
for y = 9, 14 do
  if sh.world[key(M.TOWER.x - 1, y, M.TOWER.z)] == I.LADDER then ladders = ladders + 1 end
end
check("access: ladder column complete", ladders == 6, ladders)
check("access: bridge to bay 1", sh.world[key(M.TOWER.x + 1, 14, M.TOWER.z)] == BASE)
local links = 0
for k = 1, 9 do
  if sh.world[key(M.BAY_X(k) + 11, 14, M.Z0)] == BASE then links = links + 1 end
end
check("access: catwalk links all gaps", links == 9, links)

-- --------------------------------------------------- 2-shard partition
local sh2 = newWorld(manifest())
local tA = newTurtle(sh2)
local okA, errA = M.run(tA.ops, { base = BASE, shard = 1, of = 2 })
check("shards: A (odd bays + access) completes", okA == true, tostring(errA))
local tB = newTurtle(sh2)
local okB, errB = M.run(tB.ops, { base = BASE, shard = 2, of = 2 })
check("shards: B (even bays) completes", okB == true, tostring(errB))
check("shards: B parks at its own dock", tB.x == 0 and tB.y == 0 and tB.z == -2,
  ("at %d,%d,%d"):format(tB.x, tB.y, tB.z))
check("shards: union builds the whole plant", verifyPlant(sh2.world) == nil,
  verifyPlant(sh2.world))

-- ------------------------------------------------------- failure modes
local shortPack = {}
for _, s in ipairs(manifest()) do
  if s.name ~= I.PYLON then shortPack[#shortPack + 1] = s end
end
local sh3 = newWorld(shortPack)
local t3 = newTurtle(sh3)
local ok3, err3 = M.run(t3.ops, { base = BASE, shard = 1, of = 1 })
check("sim: missing item reported", ok3 == false and err3:find("missing") ~= nil, tostring(err3))
check("sim: missing item names the culprit", tostring(err3):find("harvester_pylon") ~= nil, err3)

-- --------------------------------------------------------- crash resume
local sh4 = newWorld(manifest())
local t4 = newTurtle(sh4)
local crashed = false
local okP = pcall(function()
  M.run(t4.ops, { base = BASE, shard = 1, of = 1,
    onProgress = function(phase, i)
      if phase:find("bay 2") and i == 50 then crashed = true; error("simulated crash") end
    end })
end)
check("sim: crash mid-bay-2 simulated", okP == false and crashed)
t4.x, t4.y, t4.z, t4.f = 0, 0, 0, 0   -- re-placed on the datum
local ok4, err4 = M.run(t4.ops, { base = BASE, shard = 1, of = 1,
  resume = { bay = 2, step = 51 } })
check("sim: resume completes", ok4 == true, tostring(err4))
check("sim: resumed plant fully correct", verifyPlant(sh4.world) == nil,
  verifyPlant(sh4.world))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
