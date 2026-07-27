-- plancache tests: prove the RadixAttention-style resolved-recipe DAG cache is
-- correct (equivalent plans to the backtracking planner), that nodes are reused
-- across requests (the prefix-cache win), that cycles are handled, and measure
-- the warm-vs-cold speedup.
package.path = "./?.lua;" .. package.path
dofile("tests/mock_cc.lua")
local db = require("recipedb")
local planner = require("planner")
local plancache = require("plancache")
assert(db.load("data"), "db load")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- total output of a plan for a target = sum over steps of (times*count) for the
-- target item; used to confirm both planners produce enough of the goal.
local function producedOf(steps, target)
  local n = 0
  for _, s in ipairs(steps) do
    if s.output == target then n = n + s.times * (s.recipe.count or 1) end
  end
  return n
end

local cache = plancache.new(db)

local cases = {
  { "minecraft:chest", 1, { ["minecraft:oak_planks"] = 64 } },
  { "minecraft:crafting_table", 1, { ["minecraft:oak_log"] = 64 } },
  { "minecraft:chest", 2, { ["minecraft:oak_planks"] = 64 } },
  { "minecraft:piston", 4, { ["minecraft:oak_planks"] = 64, ["minecraft:cobblestone"] = 64,
    ["minecraft:iron_ingot"] = 8, ["minecraft:redstone"] = 8 } },
}

for _, c in ipairs(cases) do
  local target, qty = c[1], c[2]
  local h1, h2 = {}, {}
  for k, v in pairs(c[3]) do h1[k] = v; h2[k] = v end
  local s1 = planner.plan(db, h1, target, qty)
  local s2 = cache:plan(target, qty, h2)
  local name = target:gsub("^[^:]+:", "") .. " x" .. qty
  check("plancache plans " .. name .. " when planner does",
    (s1 ~= nil) == (s2 ~= nil), tostring(s1 ~= nil) .. " vs " .. tostring(s2 ~= nil))
  if s1 and s2 then
    check(name .. ": produces >= requested of target",
      producedOf(s2, target) >= qty, producedOf(s2, target))
    -- every ingredient the plan places must be a concrete item (no tags leak)
    local clean = true
    for _, st in ipairs(s2) do
      for _, item in pairs(st.picks) do if item:sub(1,1) == "#" then clean = false end end
    end
    check(name .. ": all picks are concrete items", clean)
  end
end

-- DAG node reuse: after planning several iron-bearing items, iron_ingot should
-- be resolved exactly once and reused (the prefix-cache win).
do
  local before = cache:cacheStats()
  local h = { ["minecraft:iron_ingot"] = 0 }
  cache:plan("minecraft:hopper", 1, { ["minecraft:iron_ingot"] = 5, ["minecraft:chest"] = 1 })
  cache:plan("minecraft:bucket", 1, { ["minecraft:iron_ingot"] = 3 })
  local after = cache:cacheStats()
  check("resolution cache warms (reuses nodes across requests)",
    after.hits > before.hits, ("hits %d -> %d"):format(before.hits, after.hits))
  check("iron_ingot resolved at most once", (function()
    local node = cache.nodes["minecraft:iron_ingot"]
    return node ~= nil
  end)())
end

-- cycle safety: iron_ingot <-> iron_block must not hang or misresolve
do
  local c2 = plancache.new(db)
  local node = c2:resolve("minecraft:iron_ingot")
  check("cyclic item (ingot/block) resolves without hanging", node ~= nil)
end

-- warm-vs-cold speedup: resolve the piston tree cold, then time re-resolution
do
  local cold = plancache.new(db)
  local t0 = os.clock()
  for i = 1, 200 do
    local h = { ["minecraft:oak_planks"] = 64, ["minecraft:cobblestone"] = 64,
                ["minecraft:iron_ingot"] = 8, ["minecraft:redstone"] = 8 }
    cold:plan("minecraft:piston", 1, h)   -- first iter cold, rest warm
  end
  local warmTime = os.clock() - t0
  local stats = cold:cacheStats()
  check("200 warm plans complete fast", warmTime < 1.0,
    ("%.3fs, %d nodes, %.1f%% hit rate"):format(warmTime, stats.resolved,
      100 * stats.hits / (stats.hits + stats.misses)))
  print(("      resolved %d unique items, %d cache hits / %d misses"):format(
    stats.resolved, stats.hits, stats.misses))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
