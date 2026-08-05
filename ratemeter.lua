-- ratemeter: park a turtle (or computer w/ modem) next to any chest and
-- measure items/minute flowing into it. Built for the bay output chests:
-- the printer's dyno.
--
--   ratemeter                 first adjacent inventory, 60s samples
--   ratemeter <name> [secs]   specific peripheral / custom interval
--
-- Shows running total, delta per sample, per-item rates. Ctrl+T stops.
local args = { ... }
local name = args[1]
local interval = tonumber(args[2]) or 60

local inv
if name then
  inv = peripheral.wrap(name)
else
  inv = peripheral.find("inventory")
end
if not inv then
  print("no inventory found - put me next to the chest")
  return
end

local function tally()
  local total, byItem = 0, {}
  for _, item in pairs(inv.list()) do
    total = total + item.count
    byItem[item.name] = (byItem[item.name] or 0) + item.count
  end
  return total, byItem
end

print(("ratemeter: sampling every %ds. Ctrl+T stops."):format(interval))
local prevTotal, prevItems = tally()
print(("t=0  total %d items"):format(prevTotal))
local t = 0
while true do
  sleep(interval)
  t = t + interval
  local total, items = tally()
  local delta = total - prevTotal
  local perMin = delta * 60 / interval
  print(("t=%ds  total %d  (+%d, %.0f/min)"):format(t, total, delta, perMin))
  for id, n in pairs(items) do
    local d = n - (prevItems[id] or 0)
    if d ~= 0 then
      print(("  %+5d  %s"):format(d, id:gsub("^[^:]+:", "")))
    end
  end
  prevTotal, prevItems = total, items
end
