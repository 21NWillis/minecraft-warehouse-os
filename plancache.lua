-- plancache: a content-addressed cache of resolved production subtrees, shared
-- as a DAG across all crafting requests. The crafting analogue of SGLang's
-- RadixAttention KV-cache prefix sharing.
--
-- The key separation:
--   * RESOLUTION (which recipe to use, verified to bottom out at obtainable
--     materials) is STOCK-INDEPENDENT. It is the expensive part - it needs
--     backtracking over recipe choices and cycle handling. So we compute it
--     ONCE per item, memoize it, and share the node across every request that
--     ever touches that item. Resolving "iron_gear" caches an "iron_ingot"
--     node that every other request needing iron reuses for free.
--   * The QUANTITY/STOCK pass (how many to craft given what's on hand, and
--     which concrete item to pick for a tag slot) is per-request and cheap: a
--     linear walk of the already-resolved DAG.
--
-- Result: planning goes from O(exponential backtracking) to amortized
-- O(unique items touched), and warms up like a prefix cache - the more you
-- craft, the more of the recipe graph is pre-resolved. "Compile the plan once,
-- vary only the launch params."
local plancache = {}
plancache.__index = plancache

-- emc (optional): item -> intrinsic value from tools/emc.py. When supplied,
-- resolution picks the CHEAPEST resolvable recipe (min total ingredient EMC)
-- instead of the first - cost-optimal crafting, cached like everything else.
function plancache.new(db, emc)
  return setmetatable({
    db = db, emc = emc,
    nodes = {},          -- item -> resolved node (the shared DAG / cache)
    resolving = {},      -- item -> true while on the DFS stack (cycle color)
    hits = 0, misses = 0,
  }, plancache)
end

local EMC_DEFAULT = 1000   -- unpriced ingredient: usable but deprioritized

-- does some concrete option of this ingredient token resolve to obtainable?
local function tokenOptions(self, token)
  if token:sub(1, 1) == "#" then
    return self.db.options(token)          -- tag -> concrete list
  elseif token:find(";", 1, true) then
    return self.db.options(token)          -- alternatives
  end
  return { token }
end

-- cheapest EMC among a token's concrete options (tags/alts -> min)
function plancache:tokenEmc(token)
  local best = math.huge
  for _, o in ipairs(tokenOptions(self, token)) do
    local v = (self.emc and self.emc[o]) or EMC_DEFAULT
    if v < best then best = v end
  end
  return best == math.huge and EMC_DEFAULT or best
end

-- intrinsic cost of one craft of a recipe: sum of ingredient EMC over yield
function plancache:recipeCost(recipe)
  local total = 0
  for _, token in pairs(recipe.grid) do
    total = total + self:tokenEmc(token)
  end
  return total / (recipe.count or 1)
end

-- Resolve an item to a cached node (stock-independent). A node is:
--   { raw = bool, resolvable = bool, recipe = { count, grid = {slot->token} } }
-- raw items (no recipe) are resolvable leaves you gather. For craftables we
-- pick the FIRST recipe whose every slot has a resolvable option, so we never
-- cache a recipe that dead-ends. Cycles (ingot<->block) are excluded: an item
-- currently on the resolution stack counts as unresolvable via that path.
function plancache:resolve(item)
  local cached = self.nodes[item]
  if cached then self.hits = self.hits + 1; return cached end
  self.misses = self.misses + 1

  if self.resolving[item] then
    -- on the stack: report unresolvable-via-this-path WITHOUT caching (the
    -- result is context-dependent; a sibling recipe may avoid the cycle)
    return { raw = false, resolvable = false, cyclic = true }
  end

  local recipes = self.db.recipesFor(item)
  if #recipes == 0 then
    local node = { raw = true, resolvable = true }
    self.nodes[item] = node
    return node
  end

  self.resolving[item] = true
  local chosen
  for _, r in ipairs(recipes) do
    local ok = true
    for _, token in pairs(r.grid) do
      local anyResolvable = false
      for _, opt in ipairs(tokenOptions(self, token)) do
        local sub = self:resolve(opt)
        if sub.resolvable then anyResolvable = true; break end
      end
      if not anyResolvable then ok = false; break end
    end
    if ok then
      if not self.emc then chosen = r; break end     -- no cost model: first wins
      -- cost model: keep the cheapest resolvable recipe (min total EMC / yield)
      if not chosen or self:recipeCost(r) < self:recipeCost(chosen) then
        chosen = r
      end
    end
  end
  self.resolving[item] = nil

  local node
  if chosen then
    node = { raw = false, resolvable = true,
             recipe = { count = chosen.count, grid = chosen.grid } }
  else
    node = { raw = false, resolvable = false }
  end
  self.nodes[item] = node    -- memoize the completed resolution (DAG node)
  return node
end

-- Per-request planning pass: walk the resolved DAG applying current stock.
-- `have` is MUTATED. Returns steps (deps-first), and stats matching planner.lua
-- (served/crafted for the KV-cache hit rate). Concrete tag picks stay
-- stock-aware here (cheap), even though the recipe choice was cached.
function plancache:plan(targetId, targetCount, have)
  local steps = {}
  local missing = {}
  local stats = { served = 0, crafted = 0 }
  local path = {}

  -- can this item be crafted from what's on hand right now? (depth-1 lookahead,
  -- stock-aware - disambiguates which plank type to pick from the logs we hold)
  local function craftableFromStock(item)
    local node = self:resolve(item)
    if node.raw or not node.resolvable then return false end
    for _, token in pairs(node.recipe.grid) do
      local ok = false
      for _, opt in ipairs(tokenOptions(self, token)) do
        if (have[opt] or 0) > 0 then ok = true; break end
      end
      if not ok then return false end
    end
    return true
  end

  -- concrete pick for a tag/alt slot: in-stock > craftable-from-stock >
  -- resolvable > first. Recipe choice is cached; this stays stock-aware.
  local function pick(token)
    local opts = tokenOptions(self, token)
    local fromStock, resolvable
    for _, o in ipairs(opts) do
      if (have[o] or 0) > 0 then return o end
      if not fromStock and craftableFromStock(o) then fromStock = o end
      if not resolvable and self:resolve(o).resolvable then resolvable = o end
    end
    return fromStock or resolvable or opts[1]
  end

  local produce
  produce = function(item, amount)
    local take = math.min(have[item] or 0, amount)
    have[item] = (have[item] or 0) - take
    amount = amount - take
    stats.served = stats.served + take
    if amount <= 0 then return true end

    local node = self:resolve(item)
    if node.raw or not node.resolvable or path[item] then
      missing[item] = (missing[item] or 0) + amount
      return false
    end
    stats.crafted = stats.crafted + amount

    local times = math.ceil(amount / node.recipe.count)
    local picks, depTotals = {}, {}
    for slot, token in pairs(node.recipe.grid) do
      local concrete = pick(token)
      picks[slot] = concrete
      depTotals[concrete] = (depTotals[concrete] or 0) + times
    end
    path[item] = true
    local ok = true
    for dep, qty in pairs(depTotals) do
      if not produce(dep, qty) then ok = false end
    end
    path[item] = nil

    steps[#steps + 1] = { output = item, recipe = { count = node.recipe.count },
                          times = times, picks = picks }
    have[item] = (have[item] or 0) + times * node.recipe.count - amount
    return ok
  end

  local ok = produce(targetId, targetCount)
  stats.resolveHits, stats.resolveMisses = self.hits, self.misses
  if ok then return steps, nil, stats end
  return nil, missing, stats
end

function plancache:cacheStats()
  local n = 0
  for _ in pairs(self.nodes) do n = n + 1 end
  return { resolved = n, hits = self.hits, misses = self.misses }
end

return plancache
