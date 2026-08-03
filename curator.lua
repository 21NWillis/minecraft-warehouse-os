-- curator: the fleet's quality-control officer. Stands on the BUFFER barrel
-- (where the casino pipes dump), pulls everything, and rules on each item:
--   KEEP  -> a network barrel (auto-detected: behind or left of the turtle)
--   TRASH -> the trash can in front of it (gone forever)
--
-- Policy (edit freely - policy as code is the whole point):
--   * enchanted books: keep if ANY enchant is level >= BOOK_MIN_LEVEL or
--     matches BOOK_KEEP_ENCHANTS; trash the level-1 dross. (Apotheosis makes
--     identical books stack in this pack, so keepers consolidate nicely.)
--   * other stackables: KEEP (storage is effectively infinite for them)
--   * unstackables: TRASH unless the id matches KEEP_UNSTACKABLE
--     (Apoth gems feed the sword program; plain diamond armor is out)
--
-- Setup: turtle ON the buffer barrel FACING THE TRASH CAN, with a network
-- barrel directly behind it or to its left. Run: curator
local KEEP_UNSTACKABLE = { "gem" }
local BOOK_MIN_LEVEL = 3
local BOOK_KEEP_ENCHANTS = { "mending", "infinity", "silk_touch" }
local SWEEP_SECONDS = 5

local function bookWorthy(d)
  local ench = d.enchantments or d.storedEnchantments
  if not ench then return true end          -- can't read it: keep, don't gamble
  for _, e in ipairs(ench) do
    if (e.level or 0) >= BOOK_MIN_LEVEL then return true end
    local nm = (e.name or ""):lower()
    for _, want in ipairs(BOOK_KEEP_ENCHANTS) do
      if nm:find(want, 1, true) then return true end
    end
  end
  return false
end

local function keepable(d)
  if d.name:find("enchanted_book", 1, true) then return bookWorthy(d) end
  if (d.maxCount or 1) > 1 then return true end
  for _, pat in ipairs(KEEP_UNSTACKABLE) do
    if d.name:find(pat, 1, true) then return true end
  end
  return false
end

-- facing: 0 = trash can (as placed); minimal-turn facing control
local facing = 0
local function face(target)
  local diff = (target - facing) % 4
  if diff == 1 then turtle.turnRight()
  elseif diff == 3 then turtle.turnLeft()
  elseif diff == 2 then turtle.turnRight() turtle.turnRight() end
  facing = target
end

-- find the keep target: behind (2), else left (3). A storage CONTROLLER is
-- the best target (it routes deposits network-wide, merging into existing
-- stacks); a plain barrel also works but holds only its own capacity.
local KEEP_FACE = nil
for _, cand in ipairs({ 2, 3 }) do
  face(cand)
  local ok, d = turtle.inspect()
  if ok and d.name and (d.name:find("controller") or d.name:find("barrel")) then
    KEEP_FACE = cand
    if d.name:find("controller") then break end   -- controller wins outright
  end
end
face(0)
if not KEEP_FACE then
  print("no keep barrel/controller behind or left of me - build the bridge first")
  return
end
print(("curator on duty (keep side: %s)"):format(KEEP_FACE == 2 and "behind" or "left"))
print("policy: stackables + gems + good books live, junk and weak books die")

-- verdict cache: detailed item lookups are server roundtrips; most volume is
-- the same few dozen ids, so remember rulings by name. Books are always
-- re-examined (their enchants differ per book).
local verdictCache = {}
local function verdict(slot)
  local basic = turtle.getItemDetail(slot)
  if not basic then return nil end
  if basic.name:find("enchanted_book", 1, true) then
    local d = turtle.getItemDetail(slot, true)
    return keepable(d), d.count
  end
  local cached = verdictCache[basic.name]
  if cached == nil then
    local d = turtle.getItemDetail(slot, true)
    cached = keepable(d)
    verdictCache[basic.name] = cached
  end
  return cached, basic.count
end

local kept, trashed = 0, 0
while true do
  local sucked = false
  while turtle.suckDown() do
    sucked = true
    local full = true
    for slot = 1, 16 do
      if turtle.getItemCount(slot) == 0 then full = false break end
    end
    if full then break end
  end

  local stuck = false
  for pass = 1, 2 do
    local wantKeep = pass == 2
    face(wantKeep and KEEP_FACE or 0)
    for slot = 1, 16 do
      local keep, count = verdict(slot)
      if keep ~= nil and keep == wantKeep then
        turtle.select(slot)
        if turtle.drop() then
          if wantKeep then kept = kept + count else trashed = trashed + count end
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
  -- adaptive pace: keep working while there's a backlog, rest when idle
  sleep(sucked and 0.5 or SWEEP_SECONDS)
end
