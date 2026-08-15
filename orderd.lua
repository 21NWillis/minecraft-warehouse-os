-- orderd: ME-backed driver for the PaperclipOS order terminal (ATM10).
-- The terminal GUI is dumb glass; this daemon feeds it. Catalog comes
-- from the commune ME network via the AP ME Bridge; orders fulfill
-- from stock into a pickup chest, or dispatch an ME autocraft when a
-- pattern exists. craftd v2's first organ.
--
-- Physical setup (ALL on one wired-modem network, modems activated):
--   computer + ME Bridge (touching the commune ME network)
--   + paperclip terminal (touching an activated wired modem)
--   + a pickup chest (the delivery point)
-- Run: orderd            (optionally: orderd <pickupPeripheralName>)

local CATALOG_PERIOD = 10    -- seconds between catalog refreshes
local CATALOG_MAX    = 500   -- most-stocked N items shown
local POLL           = 1.5   -- order poll period

local function findType(want)
  for _, n in ipairs(peripheral.getNames()) do
    local t = (peripheral.getType(n) or ""):lower():gsub("_", "")
    if t == want then return n, peripheral.wrap(n) end
  end
end

local meName, me = findType("mebridge")
local tName, term_ = findType("paperclipterminal")
assert(me, "orderd: no me_bridge on the wired network")
assert(term_, "orderd: no paperclip_terminal on the wired network")

local pickup = ({ ... })[1]
if not pickup then
  for _, n in ipairs(peripheral.getNames()) do
    if n:find("chest") or n:find("barrel") then pickup = n break end
  end
end
assert(pickup, "orderd: no pickup chest found (pass its peripheral name)")

print("orderd up: bridge=" .. meName .. " terminal=" .. tName)
print("pickup chest: " .. pickup)

local function pretty(displayName, id)
  if type(displayName) == "string" and #displayName > 0 then
    local inner = displayName:match("^%[(.*)%]$")
    return inner or displayName
  end
  return id
end

local jobs = {}      -- in-flight autocrafts: {job=, player=, item=, count=}
local queueLines = {}

local function pushQueue()
  local lines = {}
  for _, j in ipairs(jobs) do
    lines[#lines + 1] = { label = j.count .. "x " .. j.item, status = "crafting for " .. j.player }
  end
  for i = #queueLines, math.max(1, #queueLines - 4), -1 do
    lines[#lines + 1] = queueLines[i]
  end
  pcall(term_.setQueue, lines)
end

local function refreshCatalog()
  local ok, items = pcall(me.getItems)
  if not ok or type(items) ~= "table" then return end
  table.sort(items, function(a, b) return (a.count or 0) > (b.count or 0) end)
  local cat = {}
  for i = 1, math.min(#items, CATALOG_MAX) do
    local it = items[i]
    cat[#cat + 1] = { id = it.name, name = pretty(it.displayName, it.name), stock = it.count or 0 }
  end
  pcall(term_.setCatalog, cat)
end

local function fulfill(o)
  local who = o.player or "?"
  local want = o.count or 1
  local okE, moved = pcall(me.exportItem, { name = o.item, count = want }, pickup)
  moved = (okE and tonumber(moved)) or 0
  if moved > 0 then
    pcall(term_.toast, ("%s: %dx %s -> pickup chest"):format(who, moved, o.item), true)
    queueLines[#queueLines + 1] = { label = moved .. "x " .. o.item, status = "delivered (" .. who .. ")" }
  end
  local short = want - moved
  if short > 0 then
    local okC, craftable = pcall(me.isCraftable, { name = o.item })
    if okC and craftable then
      local okJ, job = pcall(me.craftItem, { name = o.item, count = short })
      if okJ and job then
        jobs[#jobs + 1] = { job = job, player = who, item = o.item, count = short }
        pcall(term_.toast, ("%s: crafting %dx %s"):format(who, short, o.item), true)
      else
        pcall(term_.toast, ("%s: craft dispatch failed for %s"):format(who, o.item), false)
      end
    else
      pcall(term_.toast, ("%s: short %dx %s (no stock, no pattern)"):format(who, short, o.item), false)
      queueLines[#queueLines + 1] = { label = short .. "x " .. o.item, status = "UNFULFILLABLE" }
    end
  end
end

local function checkJobs()
  for i = #jobs, 1, -1 do
    local j = jobs[i]
    local okD, done = pcall(function() return j.job.isDone() end)
    local okC, canc = pcall(function() return j.job.isCanceled() end)
    if okD and done then
      -- deliver the finished craft to the pickup chest too
      local _, moved = pcall(me.exportItem, { name = j.item, count = j.count }, pickup)
      pcall(term_.toast, ("%s: %dx %s crafted -> pickup"):format(j.player, j.count, j.item), true)
      queueLines[#queueLines + 1] = { label = j.count .. "x " .. j.item, status = "crafted (" .. j.player .. ")" }
      table.remove(jobs, i)
    elseif okC and canc then
      pcall(term_.toast, ("%s: craft of %s canceled (missing items?)"):format(j.player, j.item), false)
      queueLines[#queueLines + 1] = { label = j.count .. "x " .. j.item, status = "CANCELED" }
      table.remove(jobs, i)
    end
  end
end

local lastCat = 0
refreshCatalog()
pushQueue()
while true do
  local t = os.clock()
  if t - lastCat >= CATALOG_PERIOD then
    refreshCatalog()
    lastCat = t
  end
  local ok, orders = pcall(term_.getOrders)
  if ok and type(orders) == "table" then
    for _, o in ipairs(orders) do
      if o.item then fulfill(o) end
    end
    if #orders > 0 then pushQueue() end
  end
  local before = #jobs
  checkJobs()
  if #jobs ~= before then pushQueue() end
  sleep(POLL)
end
