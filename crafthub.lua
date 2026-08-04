-- crafthub: pure logic for the craftd platform (design: planning/craftd.md).
-- The dispatcher's brain: batch math, staging lists, turtle grid slot
-- mapping, cell arrangement plans, and least-loaded cell assignment.
-- No peripherals, no rednet - everything here is headless-testable.
--
-- Vocabulary:
--   step  = planner step { output, recipe, times, picks = {gridSlot->item} }
--   job   = one dispatched batch { output, grid = picks, count }
--   cell  = { id, busy (jobs in flight), input, output (peripheral names) }
local hub = {}

-- vanilla 3x3 grid slot g (1..9, row-major) -> turtle inventory slot
hub.GRID_SLOTS = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

function hub.turtleSlot(g)
  return hub.GRID_SLOTS[g]
end

-- split `times` crafts into batches a cell can execute in one
-- turtle.craft call (bounded by a stack per grid slot)
function hub.batchSizes(times, maxBatch)
  maxBatch = maxBatch or 64
  local out = {}
  while times > 0 do
    local n = math.min(times, maxBatch)
    out[#out + 1] = n
    times = times - n
  end
  return out
end

-- items the hub must stage into a cell's input chest for one batch:
-- aggregated per item id (vanilla grids consume 1 per slot per craft)
function hub.stageTotals(step, batch)
  local totals = {}
  for _, item in pairs(step.picks) do
    totals[item] = (totals[item] or 0) + batch
  end
  return totals
end

function hub.jobFor(step, batch)
  local grid = {}
  for g, item in pairs(step.picks) do grid[g] = item end
  return { output = step.output, grid = grid, count = batch }
end

-- cell-side arrangement: given the turtle inventory snapshot after
-- sucking its input chest ({slot -> {name, count}}), produce the
-- transfer list that forms the crafting grid, plus the list of slots
-- to clear (turtle.craft demands all non-grid slots empty).
-- Returns transfers = { {from, to, count} }, clears = { slot, ... },
-- or nil, missingItemName.
function hub.arrangePlan(inv, grid, count)
  local avail = {}
  for slot, d in pairs(inv) do
    if d and d.count > 0 then
      avail[slot] = { name = d.name, count = d.count }
    end
  end
  local transfers = {}
  local wantAt = {}   -- destination turtle slot -> required item
  for g, item in pairs(grid) do
    wantAt[hub.turtleSlot(g)] = item
  end
  local function freeSlot()
    for s = 1, 16 do
      if not wantAt[s] and (not avail[s] or avail[s].count == 0) then
        return s
      end
    end
  end
  -- PHASE A - evict: every grid destination is reduced to AT MOST
  -- `count` of exactly its required item; everything else moves to a
  -- scratch slot first. This breaks transfer cycles (a destination is
  -- never blocked by foreign items when phase B fills it) and keeps
  -- surplus out of the grid (clears would otherwise drop it wholesale
  -- from a grid slot - turtle drops empty the WHOLE slot).
  for dest, item in pairs(wantAt) do
    local d = avail[dest]
    if d and d.count > 0 then
      local keep = (d.name == item) and math.min(d.count, count) or 0
      local excess = d.count - keep
      if excess > 0 then
        local scratch = freeSlot()
        if not scratch then return nil, "no scratch slot free" end
        transfers[#transfers + 1] = { from = dest, to = scratch, count = excess }
        avail[scratch] = { name = d.name, count = excess }
        d.count = keep
        if keep > 0 then d.name = item end
      end
    end
  end
  -- PHASE B - fill: satisfy each destination's deficit from non-grid
  -- slots (all surplus lives outside the grid after phase A)
  for dest, item in pairs(wantAt) do
    local d = avail[dest]
    local held = (d and d.name == item) and d.count or 0
    local need = count - held
    if need > 0 then
      for slot, s in pairs(avail) do
        if need <= 0 then break end
        if not wantAt[slot] and s.name == item and s.count > 0 then
          local take = math.min(s.count, need)
          transfers[#transfers + 1] = { from = slot, to = dest, count = take }
          s.count = s.count - take
          need = need - take
          if d then
            d.name, d.count = item, d.count + take
          else
            avail[dest] = { name = item, count = take }
            d = avail[dest]
          end
        end
      end
    end
    if need > 0 then return nil, item end
  end
  -- clears: only non-grid slots ever get dropped
  local clears = {}
  for slot, s in pairs(avail) do
    if not wantAt[slot] and s.count > 0 then
      clears[#clears + 1] = slot
    end
  end
  table.sort(clears)
  return transfers, clears
end

-- least-loaded assignment; nil if no cell registered
function hub.pickCell(cells)
  local best
  for _, c in pairs(cells) do
    if not best or (c.busy or 0) < (best.busy or 0) then best = c end
  end
  return best
end

return hub
