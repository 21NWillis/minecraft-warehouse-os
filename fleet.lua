-- fleet: fault-tolerant work allocator for a turtle mining fleet. Pure logic
-- (no rednet/turtle), so the coordination guarantees are provable headless.
--
-- Guarantees under concurrent miners and miner death:
--   * a work unit is assigned to at most one live miner at a time
--   * every unit is eventually completed (a dead miner's unit is reclaimed
--     after a lease timeout and handed to someone else)
--   * exactly-once completion (a stale miner reporting late can't double-count)
--   * resumable: serialize/restore continues where it left off
--
-- This is a lease-based work queue - the same pattern a distributed job
-- scheduler uses so a crashed worker's task doesn't vanish or run twice.
local fleet = {}
fleet.__index = fleet

-- units: list of opaque work items (e.g. {x=,z=}); id = its index
function fleet.new(units, leaseSeconds)
  local self = setmetatable({
    units = units,
    lease = leaseSeconds or 120,
    state = {},          -- id -> "pending" | "assigned" | "done"
    holder = {},         -- id -> miner
    since = {},          -- id -> assign time
    epoch = {},          -- id -> assignment epoch (stale-completion guard)
    minerOf = {},        -- miner -> id (idempotent assignment)
    seq = 0,
  }, fleet)
  for i = 1, #units do self.state[i] = "pending" end
  return self
end

-- assign a unit to a miner (idempotent: returns the miner's current unit if it
-- already holds one). returns id, unit  or  nil if nothing left to do.
function fleet:assign(miner, now)
  local held = self.minerOf[miner]
  if held and self.state[held] == "assigned" then
    self.since[held] = now                       -- renew lease (heartbeat)
    return held, self.units[held], self.epoch[held]
  end
  for id = 1, #self.units do
    if self.state[id] == "pending" then
      self.seq = self.seq + 1
      self.state[id] = "assigned"
      self.holder[id] = miner
      self.since[id] = now
      self.epoch[id] = self.seq
      self.minerOf[miner] = id
      return id, self.units[id], self.seq
    end
  end
  return nil
end

-- complete a unit. Must present the epoch from assign() so a stale miner whose
-- lease was already reclaimed and reassigned cannot mark someone else's work.
function fleet:complete(miner, id, epoch)
  if self.state[id] == "done" then return true end
  if self.state[id] == "assigned" and self.holder[id] == miner and self.epoch[id] == epoch then
    self.state[id] = "done"
    self.holder[id] = nil
    self.minerOf[miner] = nil
    return true
  end
  return false
end

-- reclaim leases that expired (miner presumed dead): back to pending
function fleet:reap(now)
  for id = 1, #self.units do
    if self.state[id] == "assigned" and (now - (self.since[id] or 0)) > self.lease then
      local m = self.holder[id]
      self.state[id] = "pending"
      self.holder[id] = nil
      if m and self.minerOf[m] == id then self.minerOf[m] = nil end
    end
  end
end

function fleet:progress()
  local done, assigned, pending = 0, 0, 0
  for id = 1, #self.units do
    local s = self.state[id]
    if s == "done" then done = done + 1
    elseif s == "assigned" then assigned = assigned + 1
    else pending = pending + 1 end
  end
  return { done = done, assigned = assigned, pending = pending, total = #self.units }
end

function fleet:allDone()
  return self:progress().done == #self.units
end

-- resume support: just the completion bitmap + seq (leases are transient)
function fleet:serialize()
  local doneBits = {}
  for id = 1, #self.units do doneBits[id] = self.state[id] == "done" and 1 or 0 end
  return textutils.serialize({ done = doneBits, seq = self.seq })
end

function fleet:restore(str)
  local t = textutils.unserialize(str)
  if not t then return end
  self.seq = t.seq or 0
  for id = 1, #self.units do
    if t.done[id] == 1 then self.state[id] = "done" end
  end
end

-- helper: build a column list for a WxD region (1x1 columns), origin-relative
function fleet.columns(w, d)
  local cols = {}
  for x = 0, w - 1 do
    for z = 0, d - 1 do cols[#cols + 1] = { x = x, z = z } end
  end
  return cols
end

return fleet
