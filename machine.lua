-- machine: generic machine-tending driver - the first step of machine-driven
-- production. Turns any processing machine (Mekanism enrichment chamber,
-- crusher, smelter, an Actually Additions processor, ...) into a network-fed
-- auto-processor: keeps its input slot topped from the storage controller and
-- drains its output back into storage. Mod-agnostic via a slot config.
--
-- machines.cfg lines:  <peripheralName> <inSlot> <outSlot> <item> [target]
-- e.g.  mekanism:enrichment_chamber_0 1 2 minecraft:iron_ore 64
local machine = {}

-- pure policy: given current input/output slot counts, decide actions. Feed to
-- keep the input topped toward `target` in batches; drain whenever output has
-- anything. Kept pure so the decision logic is provable headless.
function machine.plan(inCount, outCount, cfg)
  local target = cfg.target or 64
  local feed = 0
  if inCount < target then feed = target - inCount end
  return { feed = feed, drain = outCount > 0 }
end

if not _TEST then
  local storagelib = require("storagelib")
  local controllerName
  for _, n in ipairs(peripheral.getNames()) do
    if n:find("controller", 1, true) then controllerName = n break end
  end
  if not controllerName then error("no storage controller on the network") end
  local controller = peripheral.wrap(controllerName)
  -- insertable return targets (pull-only law: the controller voids
  -- inserts; drains go to real inventories the controller can see).
  -- Assigned after stations parse: machines must never be targets.
  local machineStores

  local stations = {}
  if fs.exists("machines.cfg") then
    local f = fs.open("machines.cfg", "r")
    while true do
      local line = f.readLine(); if not line then break end
      line = line:gsub("^%s+", "")
      if line ~= "" and line:sub(1, 1) ~= "#" then
        local name, inS, outS, item, target = line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(%d*)$")
        if name then
          stations[#stations + 1] = { name = name, inSlot = tonumber(inS),
            outSlot = tonumber(outS), item = item, target = tonumber(target) or 64 }
        end
      end
    end
    f.close()
  end
  if #stations == 0 then
    print("no stations in machines.cfg")
    print("format: <peripheralName> <inSlot> <outSlot> <item> [target]")
    return
  end
  local exclude = {}
  for _, st in ipairs(stations) do exclude[st.name] = true end
  machineStores = storagelib.discover({ exclude = exclude })

  -- source slots for an item in the controller
  local function sourceSlots(item)
    local out = {}
    for slot, it in pairs(controller.list()) do
      if it.name == item then out[#out + 1] = { slot = slot, count = it.count } end
    end
    return out
  end

  print(("machine driver: tending %d station(s)"):format(#stations))
  while true do
    for _, st in ipairs(stations) do
      local ok, m = pcall(peripheral.wrap, st.name)
      if ok and m then
        local inItem = m.getItemDetail and m.getItemDetail(st.inSlot)
        local outItem = m.getItemDetail and m.getItemDetail(st.outSlot)
        local inCount = inItem and inItem.count or 0
        local outCount = outItem and outItem.count or 0
        local act = machine.plan(inCount, outCount, st)
        -- pull-only law: drain to insertable storage, never the controller
        if act.drain then
          pcall(storagelib.pushFirstFit, m, st.outSlot, machineStores)
        end
        if act.feed > 0 then
          local remaining = act.feed
          for _, s in ipairs(sourceSlots(st.item)) do
            if remaining <= 0 then break end
            local moved = controller.pushItems(st.name, s.slot, remaining, st.inSlot)
            remaining = remaining - moved
            if moved == 0 then break end
          end
        end
      end
    end
    sleep(2)
  end
end

return machine
