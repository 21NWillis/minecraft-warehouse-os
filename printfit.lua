-- printfit v3: datum-launched, shardable, SOLAR-SAFE Item Printer.
-- Design: planning/item_printer.md
--
-- THE CORP LAUNCH CONVENTION: turtle ON THE GOLD DATUM facing campus
-- north, a stack of coal loaded by hand, FEEDER (stocked backpack or
-- omega chest) placed DIRECTLY BEHIND THE DATUM on the pad deck.
-- That's the whole ritual, for every shard.
--
-- SITE: the plant floats at y14, ENTIRELY EAST of the warehouse - no
-- column overhangs the roof, because Mekanism solars need an
-- unobstructed sky column (elevation does NOT help; overhang at any
-- height blocks them). Pods: 11x11, bay k at x = 30+(k-1)*12, spanning
-- z -5..5. Slab y13, rim/bed y14, crops y15.
--
-- ACCESS (built by shard 1 after its bays): ladder tower on the
-- warehouse roof's NORTHEAST corner (x28, z4) up to y14, bridge onto
-- bay 1's rim, and catwalk blocks linking every pod's south rim.
-- If your roof gear lives at the NE corner too, say so - the tower
-- position is two constants.
--
-- USAGE:
--   printfit                     one turtle, all 10 bays + access
--   printfit <shard> <of> [base] up to 4 shards; shard 1 also builds
--                                the access tower + catwalk
--   printfit <base>              single turtle, custom slab block
-- Launch shards a minute apart. Each has its own feeder dock face and
-- its own cruise altitude - no shared cells, no shared airspace.
--
-- Operator pass (after all shards): climb the tower, walk the catwalk:
-- hoe -> pylon, watering can -> item user (aim + delay), omega
-- upgrade -> chest, pipez ultimate chest -> collector CHEST (never a
-- controller). FARMLAND TIER GUESSES in the table: verify in JEI;
-- wrong guess = clean "missing" stop, fix + rerun.
-- Crash recovery: printfit.state {bay, step}; re-place on the datum,
-- rerun with the same shard args.
local MA = "mysticalagriculture:"
local BAYS = {
  { key = "inferium", seed = MA .. "inferium_seeds", farmland = MA .. "supremium_farmland" },
  { key = "iron", seed = MA .. "iron_seeds", farmland = MA .. "prudentium_farmland" },
  { key = "gold", seed = MA .. "gold_seeds", farmland = MA .. "tertium_farmland" },
  { key = "redstone", seed = MA .. "redstone_seeds", farmland = MA .. "prudentium_farmland" },
  { key = "osmium", seed = MA .. "osmium_seeds", farmland = MA .. "tertium_farmland" },
  { key = "diamond", seed = MA .. "diamond_seeds", farmland = MA .. "imperium_farmland" },
  { key = "obsidian", seed = MA .. "obsidian_seeds", farmland = MA .. "tertium_farmland" },
  { key = "uranium", seed = MA .. "uranium_seeds", farmland = MA .. "imperium_farmland" },
  { key = "netherite", seed = MA .. "netherite_seeds", farmland = MA .. "imperium_farmland" },
  { key = "sandbox", seed = nil, farmland = MA .. "inferium_farmland" },
}

local ITEMS = {
  PYLON = "pylons:harvester_pylon",
  USER = "cyclic:user",
  CHEST = "sophisticatedstorage:chest",
  LILYPAD = "reliquary:fertile_lily_pad",
  BUCKET = "minecraft:water_bucket",
  EMPTY_BUCKET = "minecraft:bucket",
  COAL = "minecraft:coal",
  LADDER = "minecraft:ladder",
}

-- datum-frame geometry
local FEEDER = { 0, 0, -1 }        -- directly behind the datum
local X0, Z0, SLAB_Y = 30, -5, 13  -- bay k slab: x X0+(k-1)*12, z Z0..Z0+10
local TOWER = { x = 28, z = 4 }    -- ladder tower, roof NE corner
local ROOF_TOP = 8

-- feeder docks, one per shard: distinct cells around the backpack.
-- Shard 1 = top (suckDown). The datum cell itself stays free so more
-- shards can always launch.
local DOCKS = {
  { at = { 0, 1, -1 }, vertical = true },
  { at = { 0, 0, -2 }, face = 0 },
  { at = { 1, 0, -1 }, face = 3 },
  { at = { -1, 0, -1 }, face = 1 },
}

local BAY_X = function(k) return X0 + (k - 1) * 12 end

-- water cells in bed coords (col=z-ish 1..9, row=x-ish 1..9): center
-- hosts the waterlogged pylon, quadrants host lilypads
local WATERS = { { 5, 5 }, { 3, 3 }, { 3, 7 }, { 7, 3 }, { 7, 7 } }

-- one bay: row axis = +x, pod spans z Z0..Z0+10. Item user sits on the
-- SOUTH rim (z=Z0) where the catwalk runs. All placements placeDown;
-- stand y = target y + 1.
local function genBay(k, base)
  local px = BAY_X(k)
  local bay = BAYS[k]
  local steps = {}
  local function S(x, y, z, block, extra)
    local s = { stand = { x, y + 1, z }, block = block }
    if extra then for kk, vv in pairs(extra) do s[kk] = vv end end
    steps[#steps + 1] = s
  end
  local isWater = {}
  for _, w in ipairs(WATERS) do isWater[w[1] .. "," .. w[2]] = true end
  for dx = 0, 10 do
    for dz = 0, 10 do S(px + dx, SLAB_Y, Z0 + dz, base) end
  end
  for dx = 0, 10 do
    for dz = 0, 10 do
      local rim = (dx == 0 or dx == 10 or dz == 0 or dz == 10)
      if rim and not (dz == 0 and dx == 5) then S(px + dx, SLAB_Y + 1, Z0 + dz, base) end
    end
  end
  S(px + 5, SLAB_Y + 1, Z0, ITEMS.USER)
  for row = 1, 9 do
    for col = 1, 9 do
      if not isWater[col .. "," .. row] then
        S(px + row, SLAB_Y + 1, Z0 + col, bay.farmland)
      end
    end
  end
  for _, w in ipairs(WATERS) do
    S(px + w[2], SLAB_Y + 1, Z0 + w[1], ITEMS.BUCKET, { water = true })
  end
  S(px + 5, SLAB_Y + 1, Z0 + 5, ITEMS.PYLON, { into_water = true })
  for i = 2, 5 do
    local w = WATERS[i]
    S(px + w[2], SLAB_Y + 2, Z0 + w[1], ITEMS.LILYPAD, { on_water = true })
  end
  S(px + 5, SLAB_Y + 2, Z0 + 5, ITEMS.CHEST)
  if bay.seed then
    for row = 1, 9 do
      for col = 1, 9 do
        if not isWater[col .. "," .. row] then
          S(px + row, SLAB_Y + 2, Z0 + col, bay.seed, { crop = true })
        end
      end
    end
  end
  return steps
end

-- access: tower pillar on the roof NE corner, ladders up its west
-- face, a bridge block onto bay 1's rim, catwalk links between pods
local function genAccess(base)
  local steps = {}
  local function S(x, y, z, block, extra)
    local s = { stand = { x, y + 1, z }, block = block }
    if extra then for kk, vv in pairs(extra) do s[kk] = vv end end
    steps[#steps + 1] = s
  end
  for y = ROOF_TOP + 1, SLAB_Y + 1 do
    S(TOWER.x, y, TOWER.z, base)
  end
  -- ladders: placed forward against the pillar's west face
  for y = ROOF_TOP + 1, SLAB_Y + 1 do
    steps[#steps + 1] = { stand = { TOWER.x - 2, y, TOWER.z }, block = ITEMS.LADDER,
      fwd = true, face = 1 }
  end
  S(TOWER.x + 1, SLAB_Y + 1, TOWER.z, base)   -- bridge to bay 1 rim
  for k = 1, 9 do
    S(BAY_X(k) + 11, SLAB_Y + 1, Z0, base)    -- catwalk gap links
  end
  return steps
end

local function bayBOM(k, base)
  local bay = BAYS[k]
  local bom = {
    [base] = 121 + 39,
    [bay.farmland] = 76,
    [ITEMS.PYLON] = 1, [ITEMS.USER] = 1, [ITEMS.CHEST] = 1,
    [ITEMS.LILYPAD] = 4, [ITEMS.BUCKET] = 5,
  }
  if bay.seed then bom[bay.seed] = 76 end
  return bom
end

local function accessBOM(base)
  local n = (SLAB_Y + 1) - (ROOF_TOP + 1) + 1
  return { [base] = n + 1 + 9, [ITEMS.LADDER] = n }
end

-- must cover the worst bay round-trip: ~324 steps at the highest shard
-- cruise plus the flight to bay 10 - measured ~4.5k, floor at 6k
local FUEL_MIN = 6000
local KIT_LIMIT = 400

-- opts: base, shard, of, resume {bay, step}, onProgress, onBayDone,
-- report. Pose starts ON THE DATUM (0,0,0) facing north.
local function run(t, opts)
  local base = opts.base
  local shard, of = opts.shard or 1, opts.of or 1
  local dock = DOCKS[shard]
  local CRUISE = SLAB_Y + 4 + (shard - 1)   -- private altitude per shard
  local pose = opts.pose or { x = 0, y = 0, z = 0, f = 0 }
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

  local function face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then t.turnLeft(); pose.f = (pose.f + 3) % 4
      else t.turnRight(); pose.f = (pose.f + 1) % 4 end
    end
  end
  local function vmove(up)
    local ok = up and t.up() or t.down()
    if ok then pose.y = pose.y + (up and 1 or -1) end
    return ok
  end
  local function fwd()
    if not t.forward() then return false end
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  local function goTo(x, y, z)
    if pose.x == x and pose.y == y and pose.z == z then return true end
    while pose.y < CRUISE do if not vmove(true) then return false end end
    while pose.x ~= x do
      face(pose.x < x and 1 or 3)
      if not fwd() then return false end
    end
    while pose.z ~= z do
      face(pose.z < z and 0 or 2)
      if not fwd() then return false end
    end
    while pose.y > y do if not vmove(false) then return false end end
    return true
  end
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then t.select(slot) return true end
    end
    return false
  end
  local function have(name)
    local total = 0
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then total = total + d.count end
    end
    return total
  end

  local suckFn = dock.vertical and t.suckDown or t.suck
  local dropFn = dock.vertical and t.dropDown or t.drop
  local function atDock()
    if not goTo(dock.at[1], dock.at[2], dock.at[3]) then return false end
    if dock.face then face(dock.face) end
    return true
  end

  local function kit(bom)
    if not atDock() then return false, "blocked returning to the feeder dock" end
    local function wantOf(name) return bom[name] or 0 end
    local function keepable(name) return wantOf(name) > 0 end
    local function deficit()
      local total = 0
      for name, want in pairs(bom) do
        if have(name) < want then total = total + (want - have(name)) end
      end
      return total
    end
    local function firstMissing()
      for name, want in pairs(bom) do
        if have(name) < want then return name end
      end
    end
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and not keepable(d.name) then t.select(slot); dropFn() end
    end
    local rejects = 0
    while t.getFuelLevel() ~= "unlimited" and t.getFuelLevel() < FUEL_MIN do
      if ensure(ITEMS.COAL) then
        t.refuel(64)
      elseif suckFn() then
        for slot = 1, 16 do
          local d = t.getItemDetail(slot)
          if d and d.name ~= ITEMS.COAL then t.select(slot); dropFn() end
        end
        rejects = rejects + 1
        if rejects > KIT_LIMIT then return false, "feeder has no coal" end
      else
        return false, "feeder has no coal"
      end
    end
    rejects = 0
    while deficit() > 0 do
      local before = deficit()
      local free = false
      for slot = 1, 16 do
        if not t.getItemDetail(slot) then free = true break end
      end
      if not free then
        local dropped = false
        for slot = 1, 16 do
          local d = t.getItemDetail(slot)
          if d and have(d.name) - d.count >= wantOf(d.name) then
            t.select(slot); dropFn(); dropped = true
            break
          end
        end
        if not dropped then
          for slot = 1, 16 do
            local d = t.getItemDetail(slot)
            if d and have(d.name) >= wantOf(d.name) then
              t.select(slot); dropFn()
              break
            end
          end
        end
      end
      if not suckFn() then
        return false, "feeder is missing " .. (firstMissing() or "?")
      end
      for slot = 1, 16 do
        local d = t.getItemDetail(slot)
        if d and (d.name == ITEMS.COAL or not keepable(d.name)) then
          t.select(slot); dropFn()
        end
      end
      if deficit() < before then rejects = 0 else rejects = rejects + 1 end
      if rejects > KIT_LIMIT then
        return false, "feeder is missing " .. (firstMissing() or "?")
      end
    end
    return true
  end

  local function execute(steps, phase, startStep)
    for i = startStep or 1, #steps do
      local s = steps[i]
      local st = s.stand
      if not goTo(st[1], st[2], st[3]) then
        return false, ("blocked reaching step %d of %s"):format(i, phase)
      end
      if s.fwd then
        face(s.face)
        if not t.detect() then
          if not ensure(s.block) then return false, "out of " .. s.block .. " in " .. phase end
          t.place()
        end
      else
        local occupied = t.detectDown()
        if s.into_water or occupied == false then
          if not ensure(s.block) then return false, "out of " .. s.block .. " in " .. phase end
          if not t.placeDown() and not s.water and not s.crop
              and not s.on_water and not s.into_water then
            return false, ("cannot place %s at step %d of %s"):format(s.block, i, phase)
          end
        end
      end
      if opts.onProgress then opts.onProgress(phase, i, #steps) end
    end
    return true
  end

  local startBay = opts.resume and opts.resume.bay or shard
  local startStep = opts.resume and opts.resume.step or 1
  local k = startBay
  while k <= #BAYS do
    local from = (k == startBay) and startStep or 1
    local steps = genBay(k, base)
    if from <= 1 then
      local okKit, kerr = kit(bayBOM(k, base))
      if not okKit then return false, "bay " .. k .. " (" .. BAYS[k].key .. "): " .. kerr end
    end
    if opts.report then opts.report(k, BAYS[k].key) end
    local okB, berr = execute(steps, "bay " .. k .. ":" .. BAYS[k].key, from)
    if not okB then return false, berr end
    if opts.onBayDone then opts.onBayDone(k) end
    k = k + of
  end

  -- shard 1 builds the human access after its bays (tower cells never
  -- overlap any pod, so other shards can still be mid-build; on resume
  -- this re-runs harmlessly - existing blocks skip, change returns)
  if shard == 1 then
    local okKit, kerr = kit(accessBOM(base))
    if not okKit then return false, "access: " .. kerr end
    local okA, aerr = execute(genAccess(base), "access", 1)
    if not okA then return false, aerr end
  end

  -- return the change and park empty at the dock
  if atDock() then
    for slot = 1, 16 do
      if t.getItemDetail(slot) then t.select(slot); dropFn() end
    end
  end
  return true
end

local M = { run = run, genBay = genBay, genAccess = genAccess, bayBOM = bayBOM,
  accessBOM = accessBOM, BAYS = BAYS, ITEMS = ITEMS, WATERS = WATERS,
  BAY_X = BAY_X, DOCKS = DOCKS, X0 = X0, Z0 = Z0, SLAB_Y = SLAB_Y,
  TOWER = TOWER, ROOF_TOP = ROOF_TOP }
if _TEST then return M end

-- ==================================================================== program
local args = { ... }
local shard, of, base = 1, 1, "minecraft:cobbled_deepslate"
if tonumber(args[1]) then
  shard = tonumber(args[1])
  of = tonumber(args[2] or "1")
  base = args[3] or base
elseif args[1] then
  base = args[1]
end
if shard < 1 or shard > 4 or of < 1 or of > 4 or shard > of then
  print("usage: printfit [shard of] [baseBlockId]   (of <= 4)")
  return
end

for slot = 1, 16 do turtle.select(slot); turtle.refuel(64) end
turtle.select(1)
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 300 then
  print("hand me a stack of coal first (fuel " .. turtle.getFuelLevel() .. ")")
  return
end

print(("printfit shard %d/%d - base %s"):format(shard, of, base))
-- (feeder presence is verified by the first kit: a missing/misplaced
-- feeder stops with "feeder is missing ..." before anything is built)

local STATE = "printfit.state"
local resume = nil
if fs.exists(STATE) then
  local h = fs.open(STATE, "r")
  resume = textutils.unserialize(h.readAll())
  h.close()
  print(("resuming at bay %d step %d"):format(resume.bay, resume.step))
end

local ok, err = run(turtle, {
  base = base, shard = shard, of = of, resume = resume,
  report = function(k, key) print(("bay %d: %s"):format(k, key)) end,
  onProgress = function(phase, i, n)
    local h = fs.open(STATE, "w")
    local bay = tonumber(phase:match("bay (%d+)")) or shard
    h.write(textutils.serialize({ bay = bay, step = i + 1 }))
    h.close()
    if i % 50 == 0 then print(("  %s: %d/%d"):format(phase, i, n)) end
  end,
  onBayDone = function(k)
    local h = fs.open(STATE, "w")
    h.write(textutils.serialize({ bay = k + of, step = 1 }))
    h.close()
  end,
})

if ok then
  if fs.exists(STATE) then fs.delete(STATE) end
  print(("shard %d/%d COMPLETE - parked at my feeder dock."):format(shard, of))
  print("when all shards report: climb the roof-NE tower, walk the")
  print("catwalk east: hoe->pylon, can->user, upgrade->chest, pipez")
  print("chest->collector CHEST (never a controller)")
else
  printError("stopped: " .. tostring(err))
  printError("fix/restock, re-place me on the datum, rerun: printfit "
    .. shard .. " " .. of)
end
