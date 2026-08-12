-- stationlogic: pure logic for the ATM10 mini-PC dispatcher stations
-- (see planning/atm10_station_spec.md). One station = one recipe class,
-- one buffer chest fed by an RS Autocrafter, one machine bank, one
-- importer chest back into RS. This module owns the math only: set
-- parsing, round-robin assignment with an in-flight ledger, jam
-- detection, stale-leftover flushing. station.lua (IO shell) moves items.
--
-- RS may interleave pushes from several concurrent tasks into the
-- buffer, so parsing works on AGGREGATE counts, never slot adjacency.

local M = {}

-- cfg = {
--   recipes = { {key=, inputs={{name=,n=,toSlot=}}, outputs={{name=,fromSlot=}}}, ... },
--   machines = { "periph_name_1", ... },
--   maxInFlight = 2,   -- ingredient sets per machine before it's skipped
--   jamT = 60,         -- seconds in-flight with no output before jam flag
--   staleT = 30,       -- seconds leftovers may sit before flush signal
-- }
function M.new(cfg)
  assert(cfg and cfg.recipes and cfg.machines, "stationlogic.new: bad cfg")
  local st = {
    cfg = cfg,
    inFlight = {},      -- machine -> array of {key=, at=}
    jammed = {},        -- machine -> true
    rr = 1,             -- persistent round-robin cursor
    leftoverSince = nil,
  }
  for _, m in ipairs(cfg.machines) do st.inFlight[m] = {} end
  return st
end

-- aggregate {slot -> {name=,count=}} into {name -> total}
local function totals(slots)
  local t = {}
  for _, item in pairs(slots) do
    t[item.name] = (t[item.name] or 0) + item.count
  end
  return t
end

-- Parse buffer contents into complete ingredient sets per recipe key.
-- Greedy in cfg.recipes order (document recipe order accordingly).
-- Returns: sets = {key -> n}, leftovers = true if any items remain
-- that don't form a complete set of anything.
function M.parseSets(cfg, slots)
  local have = totals(slots)
  local sets = {}
  for _, r in ipairs(cfg.recipes) do
    local n = math.huge
    for _, ing in ipairs(r.inputs) do
      n = math.min(n, math.floor((have[ing.name] or 0) / ing.n))
    end
    if n == math.huge then n = 0 end
    if n > 0 then
      sets[r.key] = n
      for _, ing in ipairs(r.inputs) do
        have[ing.name] = have[ing.name] - ing.n * n
      end
    end
  end
  local leftovers = false
  for _, c in pairs(have) do
    if c > 0 then leftovers = true break end
  end
  return sets, leftovers
end

local function inFlightCount(st, m)
  return #st.inFlight[m]
end

-- Assign available sets to machines. Round-robin from the persistent
-- cursor, skipping jammed machines and machines at maxInFlight.
-- sets = {key -> n} (as from parseSets); now = timestamp.
-- Returns array of {machine=, key=} in dispatch order; the ledger is
-- updated as if the IO shell performs every returned move.
function M.assign(st, sets, now)
  local cfg = st.cfg
  local order = {}
  for _, r in ipairs(cfg.recipes) do
    for _ = 1, (sets[r.key] or 0) do order[#order + 1] = r.key end
  end
  local out = {}
  local nm = #cfg.machines
  for _, key in ipairs(order) do
    local placed = false
    for probe = 0, nm - 1 do
      local idx = ((st.rr - 1 + probe) % nm) + 1
      local m = cfg.machines[idx]
      if not st.jammed[m] and inFlightCount(st, m) < cfg.maxInFlight then
        table.insert(st.inFlight[m], { key = key, at = now })
        out[#out + 1] = { machine = m, key = key }
        st.rr = (idx % nm) + 1   -- next dispatch starts after this machine
        placed = true
        break
      end
    end
    if not placed then break end  -- bank saturated; rest waits in buffer
  end
  return out
end

-- Report a completed output pull from a machine. Pops the OLDEST
-- in-flight entry for that key (FIFO per machine) and clears any jam
-- flag: a machine that produces output is by definition not jammed.
function M.complete(st, machine, key)
  local q = st.inFlight[machine]
  if not q then return false end
  for i, e in ipairs(q) do
    if e.key == key then
      table.remove(q, i)
      st.jammed[machine] = nil
      return true
    end
  end
  return false
end

-- Jam sweep: any machine whose oldest in-flight entry is older than
-- jamT gets flagged. Returns array of NEWLY jammed machine names.
function M.checkJams(st, now)
  local newly = {}
  for m, q in pairs(st.inFlight) do
    if q[1] and (now - q[1].at) > st.cfg.jamT and not st.jammed[m] then
      st.jammed[m] = true
      newly[#newly + 1] = m
    end
  end
  return newly
end

-- Manually clear a jam (operator command / retry policy in the shell).
function M.clearJam(st, machine)
  st.jammed[machine] = nil
end

-- Stale-leftover tracking: call every scan with the parseSets leftover
-- flag. Returns true exactly when leftovers have sat for > staleT and
-- should be flushed to the importer (back to RS for re-planning).
function M.staleLeftovers(st, hasLeftovers, now)
  if not hasLeftovers then
    st.leftoverSince = nil
    return false
  end
  st.leftoverSince = st.leftoverSince or now
  if (now - st.leftoverSince) > st.cfg.staleT then
    st.leftoverSince = nil   -- shell flushes; restart the clock
    return true
  end
  return false
end

-- Slot-level move plan for ONE ingredient set of `key`, given the
-- buffer's current slot map {slot -> {name=,count=}}. Ingredients may
-- span multiple source slots (RS pushes interleave). Returns:
--   moves = { {fromSlot=, toSlot=, count=, name=}, ... }  (nil if the
--           buffer can't supply a full set)
--   after = slot map with the consumed items removed (feed it back in
--           when planning the next set so counts stay honest)
function M.movePlan(cfg, slots, key)
  local recipe
  for _, r in ipairs(cfg.recipes) do
    if r.key == key then recipe = r break end
  end
  if not recipe then return nil, slots end
  -- work on a copy so a failed plan leaves the caller's view untouched
  local after = {}
  for s, it in pairs(slots) do after[s] = { name = it.name, count = it.count } end
  local moves = {}
  for _, ing in ipairs(recipe.inputs) do
    local need = ing.n
    for s, it in pairs(after) do
      if need == 0 then break end
      if it.name == ing.name and it.count > 0 then
        local take = math.min(need, it.count)
        moves[#moves + 1] = { fromSlot = s, toSlot = ing.toSlot, count = take, name = ing.name }
        it.count = it.count - take
        need = need - take
      end
    end
    if need > 0 then return nil, slots end  -- short a full set; no partial moves
  end
  for s, it in pairs(after) do
    if it.count == 0 then after[s] = nil end
  end
  return moves, after
end

-- Heartbeat snapshot for rednet/craftd v2 (paperclip.station protocol).
function M.status(st)
  local flight, jams = 0, {}
  for m, q in pairs(st.inFlight) do flight = flight + #q end
  for m in pairs(st.jammed) do jams[#jams + 1] = m end
  table.sort(jams)
  return { inFlight = flight, jammed = jams, machines = #st.cfg.machines }
end

return M
