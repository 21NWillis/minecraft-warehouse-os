-- seed: pull the Paperclip bootstrap payload out of the ME/controller into a
-- single portable inventory (an ender chest), so you can split off cleanly in
-- one trip and rebuild the whole stack elsewhere from cheap raw materials.
--
-- Run on a computer wired to the shared storage controller, with a modem'd
-- ender chest on the network as the delivery target. It reads seed_manifest.txt,
-- pulls what it can, and prints exactly what you got and the bootstrap steps.
local function findPeripheral(matches)
  if type(matches) == "string" then matches = { matches } end
  for _, m in ipairs(matches) do
    for _, name in ipairs(peripheral.getNames()) do
      if name:find(m, 1, true) then return name end
    end
  end
end

local controllerName = findPeripheral("controller")
if not controllerName then error("no storage controller on the network") end
local controller = peripheral.wrap(controllerName)
local deliveryName = findPeripheral({ "enderstorage", "minecraft:chest", "minecraft:barrel" })
if not deliveryName then error("no delivery inventory (put an ender chest + modem on the network)") end

-- index the controller once (which slots hold what)
local slotsByItem = {}
for slot, item in pairs(controller.list()) do
  slotsByItem[item.name] = slotsByItem[item.name] or {}
  local e = slotsByItem[item.name]
  e[#e + 1] = { slot = slot, count = item.count }
end

-- read the manifest
local manifest = {}
local f = fs.open("seed_manifest.txt", "r")
if not f then error("seed_manifest.txt missing (run `update`)") end
while true do
  local line = f.readLine()
  if not line then break end
  line = line:gsub("^%s+", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local id, count = line:match("^(%S+)%s+(%d+)$")
    if id then manifest[#manifest + 1] = { id = id, count = tonumber(count) } end
  end
end
f.close()

local function pull(id, want)
  local planned, actual = 0, 0
  local tasks = {}
  for _, s in ipairs(slotsByItem[id] or {}) do
    if planned >= want then break end
    local take = math.min(want - planned, s.count)
    planned = planned + take   -- for loop control only
    local slot = s.slot
    tasks[#tasks + 1] = function()
      actual = actual + controller.pushItems(deliveryName, slot, take)  -- real moved count
    end
  end
  if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end
  return actual
end

print("=== Paperclip bootstrap seed ===")
print("source: " .. controllerName)
print("into:   " .. deliveryName)
print("")
local slotsUsed, shortfalls = 0, {}
for _, m in ipairs(manifest) do
  local avail = 0
  for _, s in ipairs(slotsByItem[m.id] or {}) do avail = avail + s.count end
  local got = pull(m.id, math.min(m.count, avail))
  local name = m.id:gsub("^[^:]+:", ""):gsub("_", " ")
  local mark = got >= m.count and "ok" or ("SHORT (" .. got .. "/" .. m.count .. ")")
  print(("  %-22s %4d  %s"):format(name, got, mark))
  slotsUsed = slotsUsed + math.ceil(got / 64)
  if got < m.count then shortfalls[#shortfalls + 1] = name end
end

print("")
print(("~%d slots used (one inventory = 36)"):format(slotsUsed))
if slotsUsed > 36 then print("WARNING: exceeds one inventory - trim the manifest") end
if #shortfalls > 0 then print("short on: " .. table.concat(shortfalls, ", ")) end
print("")
print("-- bootstrap at the new base --")
print("1. empty the ender chest into a starter chest")
print("2. hand-craft: crafting table -> computer -> crafty turtle -> wired modems")
print("3. on the computer: wget the updater, then `update <repo-url>`, then `warehouse install`")
print("4. wire modems to a chest wall + the turtle; the warehouse auto-crafts the rest from raws")
print("5. build the first Mekanism enrichment chamber (uses the seed control circuits)")
print("6. plant a GeOre garden + run the harvest fleet for renewable raw materials")
