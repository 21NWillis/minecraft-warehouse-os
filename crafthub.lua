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
    if d then
      avail[slot] = { name = d.name, count = d.count }
    end
  end
  local transfers = {}
  local gridSlots = {}
  -- satisfy each grid position
  for g, item in pairs(grid) do
    local dest = hub.turtleSlot(g)
    gridSlots[dest] = true
    local need = count
    -- already-correct content in the destination counts first
    local d = avail[dest]
    if d and d.name == item then
      local keep = math.min(d.count, need)
      need = need - keep
      d.count = d.count - keep
      d.keep = (d.keep or 0) + keep
    end
    if need > 0 then
      for slot, s in pairs(avail) do
        if need <= 0 then break end
        if slot ~= dest and s.name == item and s.count > 0 then
          local take = math.min(s.count, need)
          transfers[#transfers + 1] = { from = slot, to = dest, count = take }
          s.count = s.count - take
          need = need - take
        end
      end
    end
    if need > 0 then return nil, item end
  end
  -- everything not part of the finished grid must be cleared
  local clears = {}
  for slot, s in pairs(avail) do
    local residue = s.count
    if residue and residue > 0 then
      clears[#clears + 1] = slot
    elseif not gridSlots[slot] and (s.keep or 0) > 0 then
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
