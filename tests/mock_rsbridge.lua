-- mock_rsbridge: headless stand-in for the Advanced Peripherals
-- rs_bridge peripheral (AP 0.7.62b vs Refined Storage 2.0.9), for
-- craftd v2 tests. Models the LANDMINES from the field research
-- (planning/atm10_translation.md) on purpose:
--   * craftItem returns a job OBJECT immediately (async preview calc),
--     never a success boolean; missing items surface later.
--   * getItems clamps craftable-but-zero-stored counts to 1 (the
--     client-crash workaround in AP's RSApi) - stock policy must not
--     presence-check by count.
--   * rs_crafting events are queued and pulled via :pullEvent().
--
-- Test controls: :advance(n) progresses running jobs n ticks;
-- :setStored(name, n) edits the warehouse.

local M = {}
M.__index = M

-- opts = {
--   stored    = { ["minecraft:iron_ingot"] = 640, ... },
--   craftable = { ["minecraft:piston"] = { ticks=3, missing=nil }, ... }
--             -- missing = {name=..., n=...} makes the job fail calc
-- }
function M.new(opts)
  local self = setmetatable({}, M)
  self.stored = {}
  for k, v in pairs(opts and opts.stored or {}) do self.stored[k] = v end
  self.craftable = opts and opts.craftable or {}
  self.jobs = {}          -- id -> job state
  self.nextId = 1
  self.events = {}        -- queued rs_crafting events {error=, id=, msg=}
  return self
end

function M:setStored(name, n) self.stored[name] = n end

local function push(self, isError, id, msg)
  self.events[#self.events + 1] = { error = isError, id = id, msg = msg }
end

-- === the peripheral surface (subset craftd v2 uses) ===

function M:getItems()
  local out = {}
  for name, n in pairs(self.stored) do
    if n > 0 then out[#out + 1] = { name = name, count = n } end
  end
  -- the count=1 clamp: craftable items with 0 stored still appear
  for name in pairs(self.craftable) do
    if (self.stored[name] or 0) == 0 then
      out[#out + 1] = { name = name, count = 1, craftableClamp = true }
    end
  end
  return out
end

function M:getCraftableItems()
  local out = {}
  for name in pairs(self.craftable) do out[#out + 1] = { name = name } end
  return out
end

function M:isCraftable(filter)
  return self.craftable[filter.name] ~= nil
end

function M:craftItem(filter)
  local spec = self.craftable[filter.name]
  if not spec then return nil, "no pattern for " .. tostring(filter.name) end
  local id = self.nextId
  self.nextId = self.nextId + 1
  local job = {
    id = id, name = filter.name, count = filter.count or 1,
    ticksLeft = spec.ticks or 1, missing = spec.missing,
    done = false, canceled = false, calcDone = false,
  }
  self.jobs[id] = job
  push(self, false, id, "CALCULATION_STARTED")
  -- job OBJECT, matching AP's CraftingJob shape
  local api = {}
  function api.getId() return id end
  function api.isDone() return job.done end
  function api.isCanceled() return job.canceled end
  function api.getMissingItems()
    if job.missing then return { job.missing } end
    return {}
  end
  function api.cancel()
    if not job.done then job.canceled = true; push(self, false, id, "JOB_CANCELED") end
  end
  return api
end

function M:isCrafting(filter)
  for _, j in pairs(self.jobs) do
    if j.name == filter.name and not j.done and not j.canceled and j.calcDone then
      return true
    end
  end
  return false
end

function M:getCraftingTasks()
  local out = {}
  for id, j in pairs(self.jobs) do
    if not j.done and not j.canceled then
      out[#out + 1] = { id = id, name = j.name }
    end
  end
  return out
end

function M:exportItem(filter, _dir)
  local n = math.min(self.stored[filter.name] or 0, filter.count or 64)
  self.stored[filter.name] = (self.stored[filter.name] or 0) - n
  return n
end

-- === test controls ===

function M:advance(n)
  for _ = 1, (n or 1) do
    for id, j in pairs(self.jobs) do
      if not j.done and not j.canceled then
        if not j.calcDone then
          j.calcDone = true
          if j.missing then
            j.canceled = true
            push(self, true, id, "MISSING_ITEMS")
          end
        elseif j.ticksLeft > 0 then
          j.ticksLeft = j.ticksLeft - 1
          if j.ticksLeft == 0 then
            j.done = true
            self.stored[j.name] = (self.stored[j.name] or 0) + j.count
            push(self, false, id, "JOB_DONE")
          end
        end
      end
    end
  end
end

-- pull next rs_crafting event, or nil (mirrors os.pullEvent payload
-- order: event, error, id, message)
function M:pullEvent()
  local e = table.remove(self.events, 1)
  if not e then return nil end
  return "rs_crafting", e.error, e.id, e.msg
end

return M
