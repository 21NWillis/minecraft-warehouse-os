-- printfit v2: DATUM-LAUNCHED, SHARDABLE Item Printer plant builder.
-- Design: planning/item_printer.md
--
-- THE CORP LAUNCH CONVENTION (all future fitters follow this): every
-- turtle starts ON THE GOLD DATUM facing campus north (+z, go-forward
-- test), with a stack of coal loaded by hand. Programs fly themselves
-- to their site. One ritual, any turtle, any job.
--
-- FEEDER: place the item source (backpack or omega chest, stocked per
-- the manifest) ON THE WAREHOUSE ROOF at its SOUTHEAST corner column -
-- datum-frame (x=27, z=-5), sitting on the roof. The plant row builds
-- EAST from there, pods floating past the roof edge.
--
-- USAGE:
--   printfit                     one turtle builds all 10 bays
--   printfit <shard> <of> [base] sharded: turtle <shard> of <of> builds
--                                bays shard, shard+of, ... (of <= 4)
--   printfit <base>              single turtle, custom slab block
-- Launch shards ~a minute apart. Each shard docks at its OWN face of
-- the feeder and cruises at its own altitude - no shared airspace.
--
-- Per-bay operator pass (after all shards finish - one walk east):
--   supremium hoe -> pylon, watering can -> item user (aim + delay),
--   omega upgrade -> chest, pipez ultimate chest -> collector chest
--   (POINT AT THE CHEST BLOCK, never a controller).
--
-- FARMLAND TIER GUESSES below: verify each seed's tier in JEI; a wrong
-- guess stops that bay with "missing <farmland>" - fix table, rerun.
-- Crash recovery: printfit.state per turtle stores {bay, step};
-- re-place the turtle on the datum and rerun with the SAME shard args.
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
}

-- datum-frame flight plan
local CORRIDOR_Y = 15
local FEEDER = { x = 27, z = -5 }   -- roof SE corner column

-- plant-local frame: feeder = (0,0,-1), local +z = datum EAST (+x),
-- local +x = datum SOUTH (-z), local y0 = roof-standing level.
-- Docks: each shard kits at its own face of the feeder; landing columns
-- are disjoint so shards never contest a cell.
local DOCKS = {
  { at = { 0, 1, -1 }, vertical = true, col = { x = 27, z = -5 } },  -- top
  { at = { 0, 0, 0 }, face = 2, col = { x = 28, z = -5 } },          -- east
  { at = { 0, 0, -2 }, face = 0, col = { x = 26, z = -5 } },         -- west
  { at = { 1, 0, -1 }, face = 3, col = { x = 27, z = -6 } },         -- south
}

local BAY_Z = function(k) return 4 + (k - 1) * 12 end

-- water cells inside a bay's 9x9 bed: center hosts the waterlogged
-- pylon, quadrant waters host lilypads
local WATERS = { { 5, 5 }, { 3, 3 }, { 3, 7 }, { 7, 3 }, { 7, 7 } }

local function genBay(k, base)
  local z0 = BAY_Z(k)
  local bay = BAYS[k]
  local steps = {}
  local function S(x, y, z, block, extra)
    local s = { stand = { x, y, z0 + z }, block = block }
    if extra then for kk, vv in pairs(extra) do s[kk] = vv end end
    steps[#steps + 1] = s
  end
  local isWater = {}
  for _, w in ipairs(WATERS) do isWater[w[1] .. "," .. w[2]] = true end
  for z = 0, 10 do
    for x = 0, 10 do S(x, 0, z, base) end
  end
  for z = 0, 10 do
    for x = 0, 10 do
      local rim = (x == 0 or x == 10 or z == 0 or z == 10)
      if rim and not (z == 0 and x == 5) then S(x, 1, z, base) end
    end
  end
  S(5, 1, 0, ITEMS.USER)
  for z = 1, 9 do
    for x = 1, 9 do
      if not isWater[x .. "," .. z] then S(x, 1, z, bay.farmland) end
    end
  end
  for _, w in ipairs(WATERS) do S(w[1], 1, w[2], ITEMS.BUCKET, { water = true }) end
  S(5, 1, 5, ITEMS.PYLON, { into_water = true })
  for i = 2, 5 do S(WATERS[i][1], 2, WATERS[i][2], ITEMS.LILYPAD, { on_water = true }) end
  S(5, 2, 5, ITEMS.CHEST)
  if bay.seed then
    for z = 1, 9 do
      for x = 1, 9 do
        if not isWater[x .. "," .. z] then S(x, 2, z, bay.seed, { crop = true }) end
      end
    end
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

local FUEL_MIN = 2000
local KIT_LIMIT = 400

-- pose helpers shared by launch (datum frame) and run (plant frame):
-- both just count the same physical turns/moves
local function navKit(t, pose)
  local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
  local n = {}
  function n.face(target)
    while pose.f ~= target do
      if (target - pose.f) % 4 == 3 then t.turnLeft(); pose.f = (pose.f + 3) % 4
      else t.turnRight(); pose.f = (pose.f + 1) % 4 end
    end
  end
  function n.vmove(up)
    local ok = up and t.up() or t.down()
    if ok then pose.y = pose.y + (up and 1 or -1) end
    return ok
  end
  function n.fwd()
    if not t.forward() then return false end
    pose.x = pose.x + DIRS[pose.f][1]
    pose.z = pose.z + DIRS[pose.f][2]
    return true
  end
  return n
end

-- fly datum -> corridor -> this shard's landing column -> descend onto
-- the roof/feeder. Returns true on success; ends facing datum east.
local function launch(t, shard)
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local n = navKit(t, pose)
  local col = DOCKS[shard].col
  while pose.y < CORRIDOR_Y do
    if not n.vmove(true) then return false, "blocked rising off the datum" end
  end
  n.face(1)
  while pose.x < col.x do
    if not n.fwd() then return false, "blocked in the corridor (east leg)" end
  end
  n.face(col.z < 0 and 2 or 0)
  while pose.z ~= col.z do
    if not n.fwd() then return false, "blocked in the corridor (south leg)" end
  end
  while not t.detectDown() do
    if not n.vmove(false) then return false, "blocked descending to the roof" end
  end
  n.face(1)   -- datum east = plant-local +z
  return true
end

-- opts: base, shard (1..4), of (1..4), pose (plant-local start pose,
-- as landed), resume {bay, step}, onProgress, onBayDone, report
local function run(t, opts)
  local base = opts.base
  local shard, of = opts.shard or 1, opts.of or 1
  local dock = DOCKS[shard]
  local CRUISE = 2 + (shard - 1)   -- private altitude per shard
  local pose = opts.pose or { x = dock.at[1], y = dock.at[2], z = dock.at[3], f = 0 }
  local n = navKit(t, pose)
  local face, vmove, fwd = n.face, n.vmove, n.fwd
  local suckFn = dock.vertical and t.suckDown or t.suck
  local dropFn = dock.vertical and t.dropDown or t.drop

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
    -- return everything this bay doesn't need (incl. empty buckets)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and not keepable(d.name) then t.select(slot); dropFn() end
    end
    -- fuel first, carrying nothing but coal
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
      -- make room BEFORE sucking: strict surplus first, then any stack
      -- from an already-met line (it cycles back through the feeder)
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
      local occupied = t.detectDown()
      if s.into_water or occupied == false then
        if not ensure(s.block) then return false, "out of " .. s.block .. " in " .. phase end
        if not t.placeDown() and not s.water and not s.crop
            and not s.on_water and not s.into_water then
          return false, ("cannot place %s at step %d of %s"):format(s.block, i, phase)
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

  -- return the change: leftover materials go back into the feeder so
  -- other shards (and the treasury) get them; park empty at the dock
  if atDock() then
    for slot = 1, 16 do
      if t.getItemDetail(slot) then t.select(slot); dropFn() end
    end
  end
  return true
end

local M = { run = run, launch = launch, genBay = genBay, bayBOM = bayBOM,
  BAYS = BAYS, ITEMS = ITEMS, WATERS = WATERS, BAY_Z = BAY_Z,
  DOCKS = DOCKS, FEEDER = FEEDER, CORRIDOR_Y = CORRIDOR_Y }
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

-- hand-loaded launch fuel: the feeder is a flight away
for slot = 1, 16 do turtle.select(slot); turtle.refuel(64) end
turtle.select(1)
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 300 then
  print("hand me a stack of coal first (fuel " .. turtle.getFuelLevel() .. ")")
  return
end

print(("printfit shard %d/%d - base %s"):format(shard, of, base))
print("launching from the datum...")
local okL, lerr = launch(turtle, shard)
if not okL then
  printError("launch failed: " .. tostring(lerr))
  return
end

-- verify the feeder is where the convention says
local dock = DOCKS[shard]
local probe = dock.vertical and turtle.suckDown or turtle.suck
local unprobe = dock.vertical and turtle.dropDown or turtle.drop
if dock.face then
  local pose0 = { x = dock.at[1], y = dock.at[2], z = dock.at[3], f = 0 }
  -- landed facing east (local f0); turn to the dock face for the probe
  local diff = (dock.face - 0) % 4
  if diff == 1 then turtle.turnRight() elseif diff == 3 then turtle.turnLeft()
  elseif diff == 2 then turtle.turnRight(); turtle.turnRight() end
end
if not probe() then
  printError("no stocked feeder at my dock - check its placement (roof")
  printError("SE corner column) and rerun from the datum")
  return
end
unprobe()
if dock.face then
  local diff = (0 - dock.face) % 4
  if diff == 1 then turtle.turnRight() elseif diff == 3 then turtle.turnLeft()
  elseif diff == 2 then turtle.turnRight(); turtle.turnRight() end
end

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
  pose = { x = dock.at[1], y = dock.at[2], z = dock.at[3], f = 0 },
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
  print("when all shards report: operator walk east (hoe->pylon,")
  print("can->user, upgrade->chest, pipez -> collector CHEST)")
else
  printError("stopped: " .. tostring(err))
  printError("fix/restock, re-place me on the datum, rerun: printfit "
    .. shard .. " " .. of)
end
