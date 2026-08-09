-- storagelib: the pull-only law, proven against a mock network that
-- reproduces the famine (controller inserts VOID silently).
package.path = "./?.lua;" .. package.path
local S = require("storagelib")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- mock inventory: merge-on-insert, one stack per pushItems call
local function newInv(name, slots)
  local inv = { name = name, slots = slots or {}, cap = 27 }
  inv.list = function()
    local out = {}
    for k, v in pairs(inv.slots) do out[k] = { name = v.name, count = v.count } end
    return out
  end
  inv.getItemDetail = function(slot) return inv.slots[slot] end
  return inv
end

local network = {}
local function connect(inv) network[inv.name] = inv end

local function mockPush(srcInv)
  return function(dstName, slot, count)
    local dst = network[dstName]
    if not dst then error("no such peripheral " .. dstName) end
    local item = srcInv.slots[slot]
    if not item then return 0 end
    local n = math.min(item.count, count or item.count, 64)
    if dst.void then
      -- THE FAMINE: controller accepts and destroys
      item.count = item.count - n
      if item.count <= 0 then srcInv.slots[slot] = nil end
      return n
    end
    local used = 0
    for _ in pairs(dst.slots) do used = used + 1 end
    if used >= dst.cap then return 0 end
    local free = 1
    while dst.slots[free] do free = free + 1 end
    dst.slots[free] = { name = item.name, count = n }
    item.count = item.count - n
    if item.count <= 0 then srcInv.slots[slot] = nil end
    return n
  end
end

-- network: a controller (voids), two chests (one tiny), a broken one
local controller = newInv("sophisticatedstorage:controller_0")
controller.void = true
local chestA = newInv("minecraft:chest_1")
chestA.cap = 2
local chestB = newInv("minecraft:chest_2")
connect(controller); connect(chestA); connect(chestB)

local names = { "sophisticatedstorage:controller_0", "minecraft:chest_1",
  "minecraft:chest_2" }
local stores = S.discover({ names = names,
  wrap = function(n) return network[n] end, hasType = function(_, t) return t == "inventory" end })

check("discover: finds all three", #stores == 3, #stores)
local pullOnlyCount = 0
for _, s in ipairs(stores) do if s.pullOnly then pullOnlyCount = pullOnlyCount + 1 end end
check("discover: controller marked pull-only", pullOnlyCount == 1)
check("insertable: excludes the controller", #S.insertable(stores) == 2)

-- push REFUSES controllers outright
local src = newInv("turtle_5", { [1] = { name = "minecraft:emerald", count = 64 } })
src.pushItems = mockPush(src)
local ok, err = pcall(S.push, src, 1, "sophisticatedstorage:controller_0")
check("push: refuses the controller", not ok and tostring(err):find("famine"),
  tostring(err))
check("push: nothing was voided by the refusal", src.slots[1].count == 64)

-- push to a chest works, loops past the one-stack-per-call limit
src.slots[1].count = 100
local moved = S.push(src, 1, "minecraft:chest_2")
check("push: loops one-stack calls", moved == 100, moved)

-- drain: fills tiny chest, overflows to the big one, never the controller
local cell = newInv("turtle_9", {
  [1] = { name = "minecraft:iron_ingot", count = 64 },
  [2] = { name = "minecraft:diamond", count = 3 },
  [3] = { name = "minecraft:emerald", count = 64 },
})
cell.pushItems = mockPush(cell)
local left = S.drain(cell, stores)
check("drain: everything landed", left == 0, left)
local ctrlCount = 0
for _ in pairs(controller.slots) do ctrlCount = ctrlCount + 1 end
check("drain: controller untouched (famine cannot recur)", ctrlCount == 0)

-- drain with NO insertable storage reports the stranding honestly
local lonelyStores = S.discover({ names = { "sophisticatedstorage:controller_0" },
  wrap = function(n) return network[n] end, hasType = function(_, t) return t == "inventory" end })
local cell2 = newInv("turtle_2", { [1] = { name = "minecraft:stone", count = 5 } })
cell2.pushItems = mockPush(cell2)
local left2, why = S.drain(cell2, lonelyStores)
check("drain: strands honestly without insertables", left2 == 5 and why ~= nil,
  tostring(left2) .. " / " .. tostring(why))

-- pullFrom: unloads a turtle via store.pullItems, controller excluded
local tSlots = { [1] = { name = "minecraft:rail", count = 32 } }
local turtleInv = newInv("turtle_7", tSlots)
for _, s in ipairs(stores) do
  s.p.pullItems = function(srcName, slot)
    if srcName ~= "turtle_7" then return 0 end
    local it = tSlots[slot]
    if not it or s.p.void then return 0 end
    local n = math.min(it.count, 64)
    local free = 1
    while s.p.slots[free] do free = free + 1 end
    local used = 0
    for _ in pairs(s.p.slots) do used = used + 1 end
    if used >= s.p.cap then return 0 end
    s.p.slots[free] = { name = it.name, count = n }
    it.count = it.count - n
    if it.count <= 0 then tSlots[slot] = nil end
    return n
  end
end
local got = S.pullFrom(stores, "turtle_7", { 1, 2, 3 })
check("pullFrom: unloaded the turtle", got == 32, got)
check("pullFrom: controller still empty", (function()
  for _ in pairs(controller.slots) do return false end
  return true
end)())

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
