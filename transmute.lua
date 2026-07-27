-- transmute: Equivalent Exchange in one script. Computes value from emc.txt
-- (the fixpoint solve in tools/emc.py) and lets you convert surplus into
-- anything of equal-or-less value.
--
-- Conservation-honest (unlike ProjectE, which conjures matter from nothing -
-- the cheat we won't do): `burn` VOIDS real items into a Trash Can and banks
-- their EMC; `make` spends banked EMC on items that exist in stock. Total value
-- in the world only ever decreases. It still beats the magic mod's UX: any
-- surplus becomes any needed item, by intrinsic value, one command.
--
-- commands: worth | value <q> | burn <q> [n] | make <q> [n] | balance
-- setup: computer wired to the storage controller, a Trash Can on the network
--        (burn target), and a delivery chest/ender chest (make output).
local BAL_FILE = "transmute_bal.txt"

local function find(matches)
  if type(matches) == "string" then matches = { matches } end
  for _, m in ipairs(matches) do
    for _, n in ipairs(peripheral.getNames()) do
      if n:find(m, 1, true) then return n end
    end
  end
end

local controllerName = find("controller")
if not controllerName then error("no storage controller on the network") end
local controller = peripheral.wrap(controllerName)
local trashName = find({ "trash", "void", "burn" })
local deliveryName = find({ "enderstorage", "minecraft:chest", "minecraft:barrel" })

local emc = require("emcload").load()
if not next(emc) then error("no EMC data (need data/emc.txt on disk or an update base url to stream)") end

local function balance()
  local f = fs.open(BAL_FILE, "r")
  if not f then return 0 end
  local v = tonumber(f.readAll()) or 0
  f.close()
  return v
end
local function setBalance(v)
  local f = fs.open(BAL_FILE, "w"); f.write(tostring(v)); f.close()
end

local function pretty(id) return (id:gsub("^[^:]+:", ""):gsub("_", " ")) end

local function index()
  local byItem = {}
  for slot, item in pairs(controller.list()) do
    byItem[item.name] = byItem[item.name] or { count = 0, slots = {} }
    byItem[item.name].count = byItem[item.name].count + item.count
    byItem[item.name].slots[#byItem[item.name].slots + 1] = { slot = slot, count = item.count }
  end
  return byItem
end

local function match(byItem, query)
  query = query:lower()
  local best
  for id in pairs(byItem) do
    if id:lower():find(query, 1, true) then
      if not best or #id < #best then best = id end
    end
  end
  return best
end

local args = { ... }
local cmd = args[1]

if cmd == "worth" then
  local total, priced, unpriced = 0, 0, 0
  for _, item in pairs(controller.list()) do
    local v = emc[item.name]
    if v then total = total + v * item.count; priced = priced + 1 else unpriced = unpriced + 1 end
  end
  print(("your storage is worth %.0f EMC"):format(total))
  print(("(%d priced item-stacks, %d unpriced)"):format(priced, unpriced))
  print(("banked balance: %.0f EMC"):format(balance()))

elseif cmd == "value" and args[2] then
  local byItem = index()
  local id = match(byItem, table.concat(args, " ", 2)) or table.concat(args, " ", 2)
  local v = emc[id]
  print(v and (pretty(id) .. " = " .. v .. " EMC each") or ("no EMC value for " .. id))

elseif cmd == "balance" then
  print(("banked: %.0f EMC"):format(balance()))

elseif cmd == "burn" and args[2] then
  if not trashName then print("no Trash Can on the network (burn needs one to void items)") return end
  local count = tonumber(args[#args]); if count then table.remove(args) else count = 64 end
  local byItem = index()
  local id = match(byItem, table.concat(args, " ", 2))
  if not id then print("not in stock") return end
  local v = emc[id]; if not v then print("no EMC value for " .. pretty(id)) return end
  local want, moved = math.min(count, byItem[id].count), 0
  for _, s in ipairs(byItem[id].slots) do
    if moved >= want then break end
    moved = moved + controller.pushItems(trashName, s.slot, want - moved)
  end
  local credit = moved * v
  setBalance(balance() + credit)
  print(("burned %d x %s -> +%.0f EMC (balance %.0f)"):format(moved, pretty(id), credit, balance()))

elseif cmd == "make" and args[2] then
  if not deliveryName then print("no delivery chest on the network") return end
  local count = tonumber(args[#args]); if count then table.remove(args) else count = 1 end
  local byItem = index()
  local id = match(byItem, table.concat(args, " ", 2))
  if not id then print("not in stock (conservation-honest: only items that exist)") return end
  local v = emc[id]; if not v then print("no EMC value for " .. pretty(id)) return end
  local cost = v * count
  if balance() < cost then
    print(("need %.0f EMC, have %.0f (burn more surplus)"):format(cost, balance()))
    return
  end
  local want, moved = math.min(count, byItem[id].count), 0
  for _, s in ipairs(byItem[id].slots) do
    if moved >= want then break end
    moved = moved + controller.pushItems(deliveryName, s.slot, want - moved)
  end
  setBalance(balance() - moved * v)
  print(("made %d x %s for %.0f EMC (balance %.0f)"):format(moved, pretty(id), moved * v, balance()))

else
  print("transmute worth | value <q> | burn <q> [n] | make <q> [n] | balance")
end
