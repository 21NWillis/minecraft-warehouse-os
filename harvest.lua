-- harvest: a recurring, regrowth-aware work allocator for a GeOre harvesting
-- fleet. GeOre budding blocks regrow crystal clusters on a cooldown, so this is
-- resource GENERATION (renewable, no mining, no world damage) rather than a
-- one-shot job. The scheduler is the interesting part: it's a periodic
-- lease-queue - a cluster becomes eligible again only after its regrowth
-- cooldown, and throughput is bounded by regrowth rate, not fleet size, once
-- you have enough turtles.
--
-- Guarantees (proven headless):
--   * a cluster is leased to at most one live harvester at a time
--   * a cluster is never harvested again before its cooldown elapses
--   * a dead harvester's lease is reclaimed (the cluster isn't lost)
--   * steady-state throughput -> garden_size / cooldown (regrowth-bound)
local harvest = {}
harvest.__index = harvest

-- garden: list of clusters, each { pos = {x,y,z}, item = "geore:iron_cluster" }
-- cooldown: seconds a budding block takes to regrow a harvestable cluster
function harvest.new(garden, cooldown, leaseSeconds)
  local self = setmetatable({
    garden = garden,
    cooldown = cooldown or 300,
    lease = leaseSeconds or 60,
    readyAt = {},       -- id -> earliest time harvestable (0 = ready)
    holder = {},        -- id -> miner (nil if free)
    since = {},         -- id -> lease start
    epoch = {},         -- id -> lease epoch (stale-completion guard)
    minerOf = {},       -- miner -> id
    seq = 0,
    harvested = 0,
  }, harvest)
  for i = 1, #garden do self.readyAt[i] = 0 end
  return self
end

local function isReady(self, id, now)
  return not self.holder[id] and (self.readyAt[id] or 0) <= now
end

-- lease a ready cluster to a harvester (idempotent per harvester)
function harvest:assign(miner, now)
  local held = self.minerOf[miner]
  if held and self.holder[held] == miner then
    self.since[held] = now
    return held, self.garden[held], self.epoch[held]
  end
  for id = 1, #self.garden do
    if isReady(self, id, now) then
      self.seq = self.seq + 1
      self.holder[id] = miner
      self.since[id] = now
      self.epoch[id] = self.seq
      self.minerOf[miner] = id
      return id, self.garden[id], self.seq
    end
  end
  return nil
end

-- harvester reports a cluster picked; re-arm its regrowth cooldown
function harvest:complete(miner, id, epoch, now)
  if self.holder[id] == miner and self.epoch[id] == epoch then
    self.readyAt[id] = now + self.cooldown
    self.holder[id] = nil
    self.minerOf[miner] = nil
    self.harvested = self.harvested + 1
    return true
  end
  return false
end

-- reclaim expired leases (dead harvester): free the lease but keep readyAt
function harvest:reap(now)
  for id = 1, #self.garden do
    if self.holder[id] and (now - (self.since[id] or 0)) > self.lease then
      local m = self.holder[id]
      self.holder[id] = nil
      if m and self.minerOf[m] == id then self.minerOf[m] = nil end
    end
  end
end

function harvest:readyCount(now)
  local n = 0
  for id = 1, #self.garden do if isReady(self, id, now) then n = n + 1 end end
  return n
end

function harvest:stats(now)
  local ready, growing, leased = 0, 0, 0
  for id = 1, #self.garden do
    if self.holder[id] then leased = leased + 1
    elseif (self.readyAt[id] or 0) <= now then ready = ready + 1
    else growing = growing + 1 end
  end
  return { total = #self.garden, ready = ready, growing = growing,
           leased = leased, harvested = self.harvested }
end

return harvest
