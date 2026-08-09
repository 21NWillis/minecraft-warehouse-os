-- storagelib: THE PULL-ONLY LAW, ENFORCED IN CODE.
--
-- Case Law (QUIRKS.md, the Emerald Famine): the SS storage controller
-- VOIDS automation inserts once item-matching stacks cap. Reads and
-- pulls are fine. Three independent outside audits found live code
-- inserting into the controller anyway (warehouse deposit/unload,
-- machine drain). This module is the fix at the root: insert targets
-- CANNOT name a controller here - not by discipline, by API.
--
-- Pure logic + peripheral calls; no globals beyond peripheral. Callers
-- may inject `wrap` and `names` for testing (house ops-injection style).
local M = {}

-- the one predicate: what counts as a void-risk aggregate view
function M.isController(name)
  return name:find("controller") ~= nil
end

-- discover network inventories. opts: { names=, wrap=, exclude={set} }
-- returns list of { name, p, pullOnly } - pullOnly for controllers.
function M.discover(opts)
  opts = opts or {}
  local names = opts.names or peripheral.getNames()
  local wrap = opts.wrap or peripheral.wrap
  local has = opts.hasType or peripheral.hasType
  local out = {}
  for _, name in ipairs(names) do
    local skip = opts.exclude and opts.exclude[name]
    if not skip and has and has(name, "turtle") then skip = true end
    if not skip and (not has or has(name, "inventory")) then
      local p = wrap(name)
      if p and p.list then
        out[#out + 1] = { name = name, p = p, pullOnly = M.isController(name) }
      end
    end
  end
  return out
end

function M.insertable(stores)
  local out = {}
  for _, s in ipairs(stores) do
    if not s.pullOnly then out[#out + 1] = s end
  end
  return out
end

-- push from src slot to a named destination. REFUSES controllers.
-- pushItems moves at most one stack per call, so loop; every call
-- pcall'd. Returns items moved.
function M.push(srcP, slot, dstName, count)
  if M.isController(dstName) then
    error("storagelib: refusing insert into controller '" .. dstName
      .. "' (pull-only law - the emerald famine)", 2)
  end
  local moved = 0
  while true do
    local want = count and (count - moved) or nil
    if want and want <= 0 then break end
    local ok, n = pcall(srcP.pushItems, dstName, slot, want)
    if not ok or not n or n == 0 then break end
    moved = moved + n
  end
  return moved
end

-- push one slot into the first insertable store with room; falls
-- through full/broken stores. Returns items moved.
function M.pushFirstFit(srcP, slot, stores)
  local moved = 0
  for _, s in ipairs(M.insertable(stores)) do
    moved = moved + M.push(srcP, slot, s.name)
    local okD, d = pcall(srcP.getItemDetail, slot)
    if okD and not d then break end
  end
  return moved
end

-- drain every slot of src into the insertable stores (first-fit).
-- Returns the number of items left aboard (0 = clean). Never touches
-- a controller; never throws on a broken store.
function M.drain(srcP, stores, opts)
  local targets = M.insertable(stores)
  if #targets == 0 then
    local left = 0
    local okL, listing = pcall(srcP.list)
    if okL and listing then
      for _, it in pairs(listing) do left = left + it.count end
    end
    return left, "no insertable storage on the network"
  end
  local okL, listing = pcall(srcP.list)
  if not (okL and listing) then return 0 end
  for slot in pairs(listing) do
    M.pushFirstFit(srcP, slot, stores)
  end
  local left = 0
  local okA, after = pcall(srcP.list)
  if okA and after then
    for _, it in pairs(after) do left = left + it.count end
  end
  return left
end

-- pull every slot of a source inventory INTO the insertable stores by
-- pulling FROM the source via each store (for sources we can't wrap
-- as pushable, e.g. unloading a turtle over wired modem). Uses each
-- store's pullItems. Returns approximate items moved.
function M.pullFrom(stores, srcName, slots)
  local targets = M.insertable(stores)
  local moved = 0
  for _, slot in ipairs(slots) do
    -- try every store: pullItems returns 0 both for "slot empty" and
    -- "this store is full", so falling through to the next store
    -- covers the full-store case at the cost of a few extra calls
    for _, s in ipairs(targets) do
      while true do
        local ok, got = pcall(s.p.pullItems, srcName, slot)
        if not ok or not got or got == 0 then break end
        moved = moved + got
      end
    end
  end
  return moved
end

return M
