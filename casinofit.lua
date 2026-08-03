-- casinofit: installs the casino deck's machinery with the turtle. Run it
-- standing ON the gold datum, facing campus-north, AFTER
-- `datacenter build casino`. Four passes:
--   1. hoppers into the underlayer holes (seals the channel floor)
--   2. collection barrels hung under each hopper, placed from below the deck
--   3. water: 2x2 infinite pools at the pool rows, poured with 2 buckets
--      (refills itself from the pools it makes)
--   4. strainers into the flowing water
-- Load: hoppers + barrels + strainers (as many as you have - it fills slots
-- until it runs out and reports what's left), 2 WATER buckets, ~16 coal.
-- Rerun-safe: occupied slots are skipped, so run it again anytime with more
-- machinery to grow the battery. Layout comes from the schematic itself
-- (schematic.channelPad meta) - the holes in the channel floor ARE the map.
local campus = require("campus")

local HOPPER = "minecraft:hopper"
local BARREL = "minecraft:barrel"
local STRAINER = "ftbstuff:oak_water_strainer"
local WATER_BUCKET = "minecraft:water_bucket"
local BUCKET = "minecraft:bucket"

local function run(t, report)
  local site = campus.site("casino")
  local s = site.gen()
  local meta = s.meta
  local at = site.at
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
  -- travel: same-altitude moves go direct (used for runs along a channel or
  -- under the deck); otherwise cruise at datum y2 (clear above the lip) and
  -- descend at the target column
  local CRUISE = 2
  local function goTo(x, y, z)
    local cruise = (pose.y == y) and y or math.max(y, CRUISE)
    while pose.y < cruise do if not vmove(true) then return false end end
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
  local function riseToCruise()
    while pose.y < CRUISE do
      if not vmove(true) then return false end
    end
    return true
  end
  local function ensure(name)
    for slot = 1, 16 do
      local d = t.getItemDetail(slot)
      if d and d.name == name then t.select(slot) return true end
    end
    return false
  end
  -- datum-frame coords of a casino-local cell
  local function D(c) return at[1] + c[1], at[2] + c[2], at[3] + c[3] end

  -- pre-flight: the first pool primes from TWO simultaneous sources (that's
  -- what makes it infinite) - refuse to fly without both buckets full
  local fullBuckets = 0
  for slot = 1, 16 do
    local d = t.getItemDetail(slot)
    if d and d.name == WATER_BUCKET then fullBuckets = fullBuckets + 1 end
  end
  if fullBuckets < 2 then
    return false, "load TWO FULL water buckets (found " .. fullBuckets ..
      ") - the first pool needs both poured before it can refill itself"
  end

  local placedCount = { hopper = 0, barrel = 0, strainer = 0, source = 0 }
  local skipped = {}

  -- ---- pass 1: hoppers, hovering IN the (dry) channel over each hole ----
  -- runs along each channel column; rises to cruise before switching columns
  -- (walkway tops sit at channel-hover level and would block a direct move)
  if not riseToCruise() then return false, "blocked rising off the datum" end
  local prevX = nil
  for _, cell in ipairs(meta.holes) do
    if prevX and prevX ~= cell[1] then
      if not riseToCruise() then return false, "blocked leaving a channel" end
    end
    prevX = cell[1]
    local x, y, z = D({ cell[1], cell[2] + 1, cell[3] })   -- hover in channel
    if not goTo(x, y, z) then return false, "blocked reaching a hopper hole" end
    local occ = t.inspectDown()
    if not occ then
      if not ensure(HOPPER) then skipped.hopper = true break end
      if t.placeDown() then placedCount.hopper = placedCount.hopper + 1 end
    end
    if report then report("hoppers", placedCount.hopper, #meta.holes) end
  end

  -- ---- pass 2: barrels, flying under the open deck, placing upward ----
  -- stage in and out via a corner OUTSIDE the deck footprint: descend in
  -- open sky, traverse the under-deck plane (clear: barrels sit one above),
  -- and exit the same way before climbing back
  if not skipped.hopper then
    if not riseToCruise() then return false, "blocked leaving the channels" end
    local sx, sz = at[1] - 2, at[3] - 2
    local underY = at[2] - 2
    if not goTo(sx, CRUISE, sz) then return false, "blocked reaching the deck corner" end
    while pose.y > underY do
      if not vmove(false) then return false, "blocked descending beside the deck" end
    end
    for _, cell in ipairs(meta.holes) do
      local x, y, z = D({ cell[1], cell[2] - 2, cell[3] })  -- two below the hole
      if not goTo(x, y, z) then return false, "blocked under the deck" end
      local occ = t.inspectUp()
      if not occ then
        if not ensure(BARREL) then skipped.barrel = true break end
        if t.placeUp() then placedCount.barrel = placedCount.barrel + 1 end
      end
      if report then report("barrels", placedCount.barrel, #meta.holes) end
    end
    if not goTo(sx, underY, sz) then return false, "blocked exiting under the deck" end
    if not riseToCruise() then return false, "blocked climbing beside the deck" end
  end

  -- ---- pass 3: water, hovering one above the lip level ----
  -- pool rows come in 2x2 pairs (pour 2 diagonal, the pool completes itself
  -- and becomes infinite - refill both buckets there) plus a possible tail
  -- pair (pour only). Group meta.sources per channel-pair of columns.
  local groups = {}
  for _, cell in ipairs(meta.sources) do
    local c = math.floor((cell[1] - 1) / 3)          -- channel index
    local gkey = c .. ":" .. (cell[3] - (cell[3] - 1) % 9)  -- pool group start z
    groups[gkey] = groups[gkey] or {}
    local g = groups[gkey]
    g[#g + 1] = cell
  end
  local lastPool = nil
  local function hoverPour(cell, item)
    local x, y, z = D({ cell[1], cell[2] + 1, cell[3] })
    if not goTo(x, y, z) then return false end
    if not ensure(item) then return nil end
    return t.placeDown()
  end
  local function refill()
    if not lastPool then return false end
    for _ = 1, 2 do                                 -- top up every empty bucket
      if not ensure(BUCKET) then break end
      local cell = lastPool[#lastPool]              -- scoop a pool corner
      local x, y, z = D({ cell[1], cell[2] + 1, cell[3] })
      if not goTo(x, y, z) then return false end
      t.placeDown()                                 -- empty bucket over source = scoop
    end
    return ensure(WATER_BUCKET) ~= false
  end
  local orderedGroups = {}
  for _, g in pairs(groups) do orderedGroups[#orderedGroups + 1] = g end
  table.sort(orderedGroups, function(a, b)
    if a[1][1] ~= b[1][1] then return a[1][1] < b[1][1] end
    return a[1][3] < b[1][3]
  end)
  for _, g in ipairs(orderedGroups) do
    -- pour two diagonal-ish cells; a 4-cell group self-completes to 2x2
    local pours = #g >= 4 and { g[1], g[4] } or { g[1], g[2] }
    for _, cell in ipairs(pours) do
      if not ensure(WATER_BUCKET) and not refill() then
        return false, "out of water and no infinite pool yet - carry 2 water buckets"
      end
      local ok = hoverPour(cell, WATER_BUCKET)
      if ok == false then return false, "blocked reaching a pool cell" end
      if ok then placedCount.source = placedCount.source + 1 end
    end
    if #g >= 4 then lastPool = g end
    refill()
  end

  -- ---- pass 4: strainers into the flow ----
  for _, cell in ipairs(meta.strainers) do
    local x, y, z = D({ cell[1], cell[2] + 1, cell[3] })
    if not goTo(x, y, z) then return false, "blocked over a strainer slot" end
    local occ, info = t.inspectDown()
    if not occ or (info and info.name == "minecraft:water") then
      if not ensure(STRAINER) then skipped.strainer = true break end
      if t.placeDown() then placedCount.strainer = placedCount.strainer + 1 end
    end
    if report then report("strainers", placedCount.strainer, #meta.strainers) end
  end

  goTo(0, 2, 0)
  goTo(0, 0, 0)
  face(0)
  return true, placedCount, skipped
end

local M = { run = run }
if _TEST then return M end

-- ==================================================================== program
print("casino fit-out: hoppers -> barrels -> water -> strainers")
local ok, res, skipped = run(turtle, function(pass, n, total)
  if n % 8 == 0 or n == total then print(("%s %d/%d"):format(pass, n, total)) end
end)
if ok then
  print(("installed: %d hoppers, %d barrels, %d sources, %d strainers")
    :format(res.hopper, res.barrel, res.source, res.strainer))
  for what in pairs(skipped or {}) do
    print("ran out of " .. what .. "s - rerun with more to grow the battery")
  end
  print("back on the datum. the casino is live.")
else
  printError("stopped: " .. tostring(res))
  printError("fix and rerun - finished slots are skipped automatically")
end
