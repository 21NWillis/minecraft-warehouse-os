-- harvest tests: prove the regrowth-aware GeOre fleet scheduler headless.
package.path = "./?.lua;" .. package.path
dofile("tests/mock_cc.lua")
local harvest = require("harvest")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local function garden(n)
  local g = {}
  for i = 1, n do g[i] = { pos = { x = i, y = 0, z = 0 }, item = "geore:iron_cluster" } end
  return g
end

-- simulate M harvesters over T seconds; harvesting is instant in sim. Record
-- each cluster's harvest times to check cooldown + throughput.
local function simulate(nClusters, cooldown, nMiners, T)
  local h = harvest.new(garden(nClusters), cooldown, 30)
  local harvestTimes = {}  -- id -> list of times
  local concurrentBad = 0
  for now = 0, T do
    -- detect double-lease: track who holds what this tick
    local heldBy = {}
    for _, m in ipairs({ table.unpack((function()
      local t = {}; for i = 1, nMiners do t[i] = "m" .. i end; return t
    end)()) }) do
      local id, unit, ep = h:assign(m, now)
      if id then
        if heldBy[id] then concurrentBad = concurrentBad + 1 end
        heldBy[id] = m
        harvestTimes[id] = harvestTimes[id] or {}
        harvestTimes[id][#harvestTimes[id] + 1] = now
        h:complete(m, id, ep, now)
      end
    end
  end
  return h, harvestTimes, concurrentBad
end

-- 1. cooldown respected: no cluster harvested twice within `cooldown`
do
  local _, times = simulate(5, 10, 8, 100)   -- 5 clusters, 10s regrow, 8 miners
  local violations = 0
  for _, ts in pairs(times) do
    for i = 2, #ts do if ts[i] - ts[i - 1] < 10 then violations = violations + 1 end end
  end
  check("no cluster re-harvested before regrowth", violations == 0, violations .. " violations")
end

-- 2. no concurrent double-lease of a cluster
do
  local _, _, bad = simulate(6, 8, 10, 60)
  check("no cluster double-leased in a tick", bad == 0, bad)
end

-- 3. regrowth-bound throughput: plenty of miners -> total ~= clusters*(T/cooldown)
do
  local h, times = simulate(10, 20, 20, 200)   -- 10 clusters, 20s, 20 miners, 200s
  local total = 0
  for _, ts in pairs(times) do total = total + #ts end
  local expected = 10 * (200 / 20)   -- ~100
  check("throughput approaches regrowth bound", math.abs(total - expected) <= 12,
    total .. " vs ~" .. expected)
end

-- 4. miner-bound throughput: too few miners -> fewer than the regrowth ceiling
do
  local _, times = simulate(50, 5, 2, 100)   -- 50 clusters regrow fast, only 2 miners
  local total = 0
  for _, ts in pairs(times) do total = total + #ts end
  local ceiling = 50 * (100 / 5)             -- 1000 if unlimited miners
  check("scarce miners are the bottleneck (not regrowth)", total < ceiling and total > 0,
    total .. " << " .. ceiling)
end

-- 5. dead harvester's lease reclaimed (cluster not lost forever)
do
  local h = harvest.new(garden(1), 10, 5)
  local id, _, ep = h:assign("dead", 0)
  check("cluster leased", id ~= nil)
  h:reap(20)                                   -- lease (5s) long expired
  local id2 = h:assign("live", 21)
  check("reclaimed lease reassignable", id2 == id)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
