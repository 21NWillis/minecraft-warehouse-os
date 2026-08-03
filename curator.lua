-- curator: the fleet's quality-control officer. Stands on the BUFFER barrel
-- (where the casino pipes dump), pulls everything, and rules on each item:
--   KEEP  -> the bridge barrel behind it (chained into the warehouse grid)
--   TRASH -> the trash can in front of it (gone forever)
--
-- Policy (edit freely - policy as code is the whole point):
--   * stackable items:   KEEP (storage is effectively infinite for them)
--   * unstackable items: TRASH, unless the id matches KEEP_UNSTACKABLE
--     (Apotheosis gems feed the sword program; enchanted books feed the
--      future disenchanter; plain diamond armor is peasant gear - out)
--
-- Station (warehousefit builds the barrels): curator turtle ON the buffer
-- barrel at warehouse-local (5,1,1), FACING AWAY from the barrel wall.
-- Operator places one Trash Can (trashcans mod) in the block it faces.
local KEEP_UNSTACKABLE = { "gem", "enchanted_book" }
local SWEEP_SECONDS = 5

local function keepable(d)
  if (d.maxCount or 1) > 1 then return true end
  for _, pat in ipairs(KEEP_UNSTACKABLE) do
    if d.name:find(pat, 1, true) then return true end
  end
  return false
end

-- facing: 0 = trash can (as placed), 2 = keep barrel (behind)
local facing = 0
local function face(target)
  while facing ~= target do
    turtle.turnLeft()
    turtle.turnLeft()
    facing = (facing + 2) % 4
  end
end

print("curator on duty: stackables + gems + books live, junk dies")
local kept, trashed = 0, 0
while true do
  -- pull a batch from the buffer below
  while turtle.suckDown() do
    local full = true
    for slot = 1, 16 do
      if turtle.getItemCount(slot) == 0 then full = false break end
    end
    if full then break end
  end

  -- two passes to minimize spinning: trash first, then keeps
  local stuck = false
  for pass = 1, 2 do
    local wantKeep = pass == 2
    face(wantKeep and 2 or 0)
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot, true)
      if d and keepable(d) == wantKeep then
        turtle.select(slot)
        if turtle.drop() then
          if wantKeep then kept = kept + d.count else trashed = trashed + d.count end
        else
          stuck = true
        end
      end
    end
  end
  face(0)
  if stuck then
    print("!! a destination is full or missing - holding cargo, will retry")
  end
  if kept + trashed > 0 and (kept + trashed) % 64 < 8 then
    print(("kept %d / trashed %d"):format(kept, trashed))
  end
  sleep(SWEEP_SECONDS)
end
