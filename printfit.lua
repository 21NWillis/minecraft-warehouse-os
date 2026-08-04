-- printfit: builds the ENTIRE Item Printer plant - 10 bays (9 resources
-- + sandbox), self-kitting from a placed backpack, self-watering from a
-- station basin, and it PLANTS THE SEEDS. Design: planning/item_printer.md
--
-- SITING (chosen): warehouse ROOF, southeast corner, row marching EAST
-- over the void. Pods self-float (own base slab).
--
-- RITUAL:
--   1. Fill the backpack per the manifest. Place it on the roof at the
--      row origin. Park the turtle DIRECTLY IN FRONT of it so that
--      `go forward` moves AWAY from the backpack, along the open row
--      direction (east). Backpack is at the turtle's BACK.
--   2. printfit            (or: printfit <baseBlockId> to override the
--      slab material, default minecraft:cobbled_deepslate)
--   3. The turtle: builds a water basin beside the station (needs the
--      2 water buckets in the backpack full ONCE), then per bay:
--      restocks from the backpack, refuels from backpack coal, flies
--      out, builds, plants, returns. All 10 bays, one command.
--
-- Per-bay operator pass (after ALL bays, one walk down the row):
--   supremium hoe INTO each pylon, watering can INTO each item user
--   (+ facing toward the bed, low delay), stack upgrade INTO each
--   chest, pipez ultimate on each chest -> trunk west to the drawers.
--
-- FARMLAND TIER GUESSES: the table below matches farmland tier to seed
-- tier from typical MA tiering - VERIFY EACH SEED'S TIER IN JEI. A
-- wrong guess just stops that bay with "missing <farmland>"; edit the
-- table line and rerun (state resumes). Netherite is set to imperium
-- deliberately (matching would cost supremium; forfeits only +10% seed).
--
-- Crash/restock recovery: printfit.state stores {bay, step}; re-place
-- the turtle at the station start pose and rerun to resume. A finished
-- plant refuses a fresh rerun at bay 1 (its slab is already there).
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

-- plant frame: turtle start = (0,0,0) at roof level, +z = row (east),
-- backpack behind at z=-1. Basin at x2..5 z0..3. Bay k pod = x0..10,
-- z = 4+(k-1)*12 .. +10. Cruise altitude y3 clears chests/lilypads.
local CRUISE = 2   -- nothing is ever built above y1
local BAY_Z = function(k) return 4 + (k - 1) * 12 end

-- water cells inside a bay's 9x9 bed (bed local 1..9 in both axes):
-- center hosts the waterlogged pylon, quadrant waters host lilypads
local WATERS = { { 5, 5 }, { 3, 3 }, { 3, 7 }, { 7, 3 }, { 7, 7 } }

-- one bay's build steps, in order, as {stand={x,y,z}, block=, water=,
-- into_water=} - all placeDown. Frame is PLANT-local (z offset applied).
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
  -- base slab y-1 (11x11)
  for z = 0, 10 do
    for x = 0, 10 do S(x, 0, z, base) end
  end
  -- rim ring y0, minus the item user's cell (south rim, x5)
  for z = 0, 10 do
    for x = 0, 10 do
      local rim = (x == 0 or x == 10 or z == 0 or z == 10)
      if rim and not (z == 0 and x == 5) then S(x, 1, z, base) end
    end
  end
  S(5, 1, 0, ITEMS.USER)   -- item user on the south rim, serves row 1
  -- bed y0: farmland everywhere except the 5 water cells
  for z = 1, 9 do
    for x = 1, 9 do
      if not isWater[x .. "," .. z] then S(x, 1, z, bay.farmland) end
    end
  end
  -- water cells (buckets), then pylon INTO the center water (waterlogs),
  -- lilypads ONTO the quadrant waters (they occupy y1, need y0 water)
  for _, w in ipairs(WATERS) do S(w[1], 1, w[2], ITEMS.BUCKET, { water = true }) end
  S(5, 1, 5, ITEMS.PYLON, { into_water = true })
  for i = 2, 5 do S(WATERS[i][1], 2, WATERS[i][2], ITEMS.LILYPAD, { on_water = true }) end
  S(5, 2, 5, ITEMS.CHEST)  -- output chest directly above the pylon
  -- planting pass: seed onto every farmland cell (sandbox stays bare)
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

-- basin steps (station, built once): 4x4 floor, perimeter ring, two
-- diagonal sources -> the 2x2 interior becomes infinite water
local function genBasin(base)
  local steps = {}
  for z = 0, 3 do
    for x = 2, 5 do steps[#steps + 1] = { stand = { x, 0, z }, block = base } end
  end
  for z = 0, 3 do
    for x = 2, 5 do
      if x == 2 or x == 5 or z == 0 or z == 3 then
        steps[#steps + 1] = { stand = { x, 1, z }, block = base }
      end
    end
  end
  steps[#steps + 1] = { stand = { 3, 1, 1 }, block = ITEMS.BUCKET, water = true }
  steps[#steps + 1] = { stand = { 4, 1, 2 }, block = ITEMS.BUCKET, water = true }
  return steps
end

local FUEL_MIN = 2000
local KIT_LIMIT = 400   -- consecutive fruitless sucks before "missing"

local function run(t, opts)
  local base = opts.base
  local report = opts.report
  local pose = { x = 0, y = 0, z = 0, f = 0 }
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
    local n = 0
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then n = n + d.count end
    end
    return n
  end

  -- kit for a BOM at the station: face the backpack, return unneeded
  -- stacks, refuel FIRST (frees the coal slot before the kit fills all
  -- 16), then suck until every line is met - rejects cycle back into
  -- the backpack, and a surplus stack is returned if slots run out
  local function kit(bom)
    if not goTo(0, 0, 0) then return false, "blocked returning to station" end
    face(2)   -- backpack is behind the start pose
    -- full and empty buckets are ONE line (empties refill at the basin)
    local function famName(name)
      if name == ITEMS.EMPTY_BUCKET then return ITEMS.BUCKET end
      return name
    end
    local function famHave(fam)
      if fam == ITEMS.BUCKET then return have(ITEMS.BUCKET) + have(ITEMS.EMPTY_BUCKET) end
      return have(fam)
    end
    local function wantOf(name) return bom[famName(name)] or 0 end
    local function keepable(name) return wantOf(name) > 0 end
    local function deficit()
      local total = 0
      for name, want in pairs(bom) do
        local got = famHave(name)
        if got < want then total = total + (want - got) end
      end
      return total
    end
    local function firstMissing()
      for name, want in pairs(bom) do
        if famHave(name) < want then return name end
      end
    end
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and not keepable(d.name) then t.select(slot); t.drop() end
    end
    local rejects = 0
    while t.getFuelLevel() ~= "unlimited" and t.getFuelLevel() < FUEL_MIN do
      if ensure(ITEMS.COAL) then
        t.refuel(64)
      elseif t.suck() then
        -- fuel phase carries NOTHING but coal - everything else cycles
        -- back and gets re-acquired in the item phase (26 slab stacks
        -- would otherwise fill the inventory before coal surfaces)
        for slot = 1, 16 do
          local d = t.getItemDetail(slot)
          if d and d.name ~= ITEMS.COAL then
            t.select(slot); t.drop()
          end
        end
        rejects = rejects + 1
        if rejects > KIT_LIMIT then return false, "backpack has no coal" end
      else
        return false, "backpack has no coal"
      end
    end
    rejects = 0
    while deficit() > 0 do
      local before = deficit()
      -- make room BEFORE sucking: first return a strictly-surplus stack;
      -- failing that, return a stack from any already-met line (it
      -- cycles back and re-acquires once the scarce line is filled)
      local free = false
      for slot = 1, 16 do
        if not t.getItemDetail(slot) then free = true break end
      end
      if not free then
        local dropped = false
        for slot = 1, 16 do
          local d = t.getItemDetail(slot)
          if d and famHave(famName(d.name)) - d.count >= wantOf(d.name) then
            t.select(slot); t.drop(); dropped = true
            break
          end
        end
        if not dropped then
          for slot = 1, 16 do
            local d = t.getItemDetail(slot)
            if d and famHave(famName(d.name)) >= wantOf(d.name) then
              t.select(slot); t.drop()
              break
            end
          end
        end
      end
      if not t.suck() then
        return false, "backpack is missing " .. (firstMissing() or "?")
      end
      for slot = 1, 16 do
        local d = t.getItemDetail(slot)
        if d and (d.name == ITEMS.COAL or not keepable(d.name)) then
          t.select(slot); t.drop()
        end
      end
      if deficit() < before then rejects = 0 else rejects = rejects + 1 end
      if rejects > KIT_LIMIT then
        return false, "backpack is missing " .. (firstMissing() or "?")
      end
    end
    face(0)
    return true
  end

  -- refill all empty buckets at the basin (scoop the infinite 2x2)
  local function refillBuckets()
    if have(ITEMS.EMPTY_BUCKET) == 0 then return true end
    if not goTo(3, 1, 1) then return false, "blocked reaching the basin" end
    while ensure(ITEMS.EMPTY_BUCKET) do
      if not t.placeDown() then return false, "basin has no water to scoop" end
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

  -- ---- station basin: first run only. Resumes skip it (no state file
  -- is written until bay steps begin, and a crashed basin restart is
  -- idempotent: existing blocks skip, water re-placement is a no-op)
  if not opts.resume then
    local okKit, kerr = kit({ [base] = 28, [ITEMS.BUCKET] = 2 })
    if not okKit then return false, "basin kit: " .. kerr end
    local okB, berr = execute(genBasin(base), "basin", nil)
    if not okB then return false, berr end
  end

  -- ---- bays
  local startBay = opts.resume and opts.resume.bay or 1
  local startStep = opts.resume and opts.resume.step or 1
  for k = startBay, #BAYS do
    local from = (k == startBay) and startStep or 1
    local steps = genBay(k, base)
    if from <= 1 then
      local okKit, kerr = kit(bayBOM(k, base))
      if not okKit then return false, "bay " .. k .. " (" .. BAYS[k].key .. "): " .. kerr end
      local okW, werr = refillBuckets()
      if not okW then return false, werr end
    end
    if report then report(k, BAYS[k].key) end
    local okB, berr = execute(steps, "bay " .. k .. ":" .. BAYS[k].key, from)
    if not okB then
      return false, berr, { bay = k, step = nil }
    end
    if opts.onBayDone then opts.onBayDone(k) end
  end

  goTo(0, CRUISE, 0)
  while pose.y > 0 do if not vmove(false) then break end end
  face(0)
  return true
end

local M = { run = run, genBay = genBay, genBasin = genBasin, bayBOM = bayBOM,
  BAYS = BAYS, ITEMS = ITEMS, WATERS = WATERS, BAY_Z = BAY_Z, CRUISE = CRUISE }
if _TEST then return M end

-- ==================================================================== program
local args = { ... }
local base = args[1] or "minecraft:cobbled_deepslate"

print("printfit: the Item Printer - 10 bays east of the station")
print("base material: " .. base)
local STATE = "printfit.state"
local resume = nil
if fs.exists(STATE) then
  local h = fs.open(STATE, "r")
  resume = textutils.unserialize(h.readAll())
  h.close()
  print(("resuming at bay %d step %d"):format(resume.bay, resume.step))
end

local ok, err = run(turtle, {
  base = base,
  resume = resume,
  report = function(k, key) print(("bay %d/10: %s"):format(k, key)) end,
  onProgress = function(phase, i, n)
    local h = fs.open(STATE, "w")
    local bay = tonumber(phase:match("bay (%d+)")) or 1
    h.write(textutils.serialize({ bay = bay, step = i + 1 }))
    h.close()
    if i % 50 == 0 then print(("  %s: %d/%d"):format(phase, i, n)) end
  end,
  onBayDone = function(k)
    local h = fs.open(STATE, "w")
    h.write(textutils.serialize({ bay = k + 1, step = 1 }))
    h.close()
  end,
})

if ok then
  if fs.exists(STATE) then fs.delete(STATE) end
  print("PLANT COMPLETE: 10 bays, planted and watered.")
  print("Operator walk (east down the row): hoe->pylon, can->user (aim +")
  print("delay), upgrade->chest, pipez ultimate chest->trunk. Then eat.")
else
  printError("stopped: " .. tostring(err))
  printError("fix/restock, re-place me at the station pose, rerun to resume")
end
