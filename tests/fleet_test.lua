-- fleet coordination tests: prove the lease-based allocator's distributed
-- guarantees headless, with simulated concurrent + dying miners.
package.path = "./?.lua;" .. package.path
dofile("tests/mock_cc.lua")
local fleet = require("fleet")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- no double-assignment: two miners never hold the same unit concurrently
do
  local f = fleet.new(fleet.columns(4, 4))   -- 16 units
  local a = f:assign("m1", 0)
  local b = f:assign("m2", 0)
  check("distinct miners get distinct units", a ~= b, a .. " vs " .. b)
  check("assign is idempotent per miner", ({ f:assign("m1", 1) })[1] == a)
end

-- full coverage: many miners grinding to completion mine every unit once
do
  local f = fleet.new(fleet.columns(5, 5))   -- 25 units
  local mined = {}
  local t = 0
  local miners = { "m1", "m2", "m3", "m4" }
  while not f:allDone() and t < 1000 do
    t = t + 1
    for _, m in ipairs(miners) do
      local id, unit, ep = f:assign(m, t)
      if id then
        mined[id] = (mined[id] or 0) + 1
        f:complete(m, id, ep)
      end
    end
  end
  check("all 25 units completed", f:allDone(), textutils.serialize(f:progress()))
  local doubles = 0
  for _, c in pairs(mined) do if c > 1 then doubles = doubles + 1 end end
  check("every unit mined exactly once", doubles == 0, doubles .. " double-mined")
end

-- dead miner: unit is reclaimed after lease timeout and finished by another
do
  local f = fleet.new(fleet.columns(2, 1), 10)   -- 2 units, 10s lease
  local id, _, ep = f:assign("dead", 0)          -- 'dead' grabs unit, never returns
  check("unit assigned to dead miner", id ~= nil)
  f:reap(5)                                       -- 5s: lease still valid
  check("not reclaimed before lease expires", f:progress().pending == 1, f:progress().pending)
  f:reap(20)                                      -- 20s: lease expired
  check("reclaimed after lease expires", f:progress().pending == 2)
  -- a live miner picks it up and finishes; the dead miner's late report is void
  local id2, _, ep2 = f:assign("live", 21)
  check("live miner gets the reclaimed unit", id2 == id)
  check("stale completion from dead miner rejected", f:complete("dead", id, ep) == false,
    "dead should not be able to complete")
  check("live miner completes it", f:complete("live", id2, ep2) == true)
end

-- resume: serialize mid-run, restore, and only the unfinished units remain
do
  local f = fleet.new(fleet.columns(3, 3))   -- 9 units
  for i = 1, 4 do local id, _, ep = f:assign("m" .. i, 0); f:complete("m" .. i, id, ep) end
  local saved = f:serialize()
  local g = fleet.new(fleet.columns(3, 3))
  g:restore(saved)
  check("resume preserves completed count", g:progress().done == 4, g:progress().done)
  check("resume leaves the rest pending", g:progress().pending == 5, g:progress().pending)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
