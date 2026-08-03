-- casinofit v3: installs the casino deck with the turtle. Strainers are pure
-- inventories and the COURIER harvests them from above (turtle.suckDown), so
-- there is NO per-strainer plumbing at all. Run standing ON the gold datum,
-- facing campus-north, AFTER `datacenter build casino`. Three passes:
--   1. seal: any leftover hoppers from the old design are dug out and every
--      underlayer hole is sealed with deck material (watertight again)
--   2. water: 2x2 infinite pools at the pool rows, poured from 2 buckets
--      (refills itself from the pools it makes)
--   3. strainers into the flowing water
-- Load: ~2 stacks purple concrete (hole sealing), strainers (as many as you
-- have), 2 FULL water buckets, ~16 coal. Rerun-safe: done cells are skipped;
-- rerun with more strainers anytime to grow the battery.
local campus = require("campus")
local flight = require("flight")

local SEAL = "minecraft:purple_concrete"
local HOPPER = "minecraft:hopper"
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

  local okf, ferr = flight.verifyFrame(t)
  if not okf then return false, ferr end

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

  local placedCount = { sealed = 0, recovered = 0, strainer = 0, source = 0 }
  local skipped = {}

  -- ---- pass 1: cleanup + seal - dig out old hoppers, plug every hole ----
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
    if not goTo(x, y, z) then return false, "blocked reaching a hole" end
    local occ, below = t.inspectDown()
    if occ and below and below.name == HOPPER then
      t.digDown()                                  -- recover the old design
      placedCount.recovered = placedCount.recovered + 1
      occ = false
    end
    if not occ then
      if not ensure(SEAL) then skipped.seal = true break end
      if t.placeDown() then placedCount.sealed = placedCount.sealed + 1 end
    end
    if report then report("sealing", placedCount.sealed, #meta.holes) end
  end
  if skipped.seal then
    return false, "out of " .. SEAL .. " for hole sealing - load ~2 stacks and rerun"
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
      -- skip cells that already hold water (rerun over a half-poured deck)
      local px, py, pz = D({ cell[1], cell[2] + 1, cell[3] })
      if not goTo(px, py, pz) then return false, "blocked reaching a pool cell" end
      local occ, below = t.inspectDown()
      if not (occ and below and below.name:find("water")) then
        if not ensure(WATER_BUCKET) and not refill() then
          return false, "out of water and no infinite pool yet - carry 2 water buckets"
        end
        local ok = hoverPour(cell, WATER_BUCKET)
        if ok == false then return false, "blocked reaching a pool cell" end
        if ok then placedCount.source = placedCount.source + 1 end
      end
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
print("casino fit-out v3: seal holes -> water -> strainers (courier harvests)")
local ok, res, skipped = run(turtle, function(pass, n, total)
  if n % 8 == 0 or n == total then print(("%s %d/%d"):format(pass, n, total)) end
end)
if ok then
  print(("sealed %d holes (recovered %d old hoppers), %d sources, %d strainers")
    :format(res.sealed, res.recovered, res.source, res.strainer))
  for what in pairs(skipped or {}) do
    print("ran out of " .. what .. "s - rerun with more to grow the battery")
  end
  print("back on the datum. run the courier to start harvesting.")
else
  printError("stopped: " .. tostring(res))
  printError("fix and rerun - finished cells are skipped automatically")
end
