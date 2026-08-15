-- stationgen: generate a station_cfg.lua by scanning the wired network.
-- Spares the operator from ever typing peripheral names by hand.
--
-- Usage:
--   stationgen furnace <inputItem> <fuelItem> <bufferName> <importerName>
--     e.g. stationgen furnace minecraft:raw_iron minecraft:coal minecraft:chest_0 minecraft:chest_1
--   Finds every furnace-family peripheral on the network as the bank.
--   Set ratio: 8x input + 1x fuel per set (one coal = 8 smelts).
--
--   stationgen list
--     just prints what's on the network, grouped by type.

local args = { ... }
local mode = args[1]

local function byType()
  local groups = {}
  for _, n in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(n) or "?"
    groups[t] = groups[t] or {}
    table.insert(groups[t], n)
  end
  return groups
end

if mode == "list" or not mode then
  for t, names in pairs(byType()) do
    print(t .. " (" .. #names .. ")")
    for _, n in ipairs(names) do print("  " .. n) end
  end
  if not mode then print("usage: stationgen furnace <in> <fuel> <buffer> <importer>") end
  return
end

if mode == "furnace" then
  local item, fuel, buffer, importer = args[2], args[3], args[4], args[5]
  if not (item and fuel and buffer and importer) then
    print("usage: stationgen furnace <inputItem> <fuelItem> <bufferName> <importerName>")
    return
  end
  local machines = {}
  for t, names in pairs(byType()) do
    if t:find("furnace") then
      for _, n in ipairs(names) do
        if n ~= buffer and n ~= importer then table.insert(machines, n) end
      end
    end
  end
  table.sort(machines)
  if #machines == 0 then
    print("no furnace-family peripherals on the network")
    return
  end
  local key = "smelt_" .. item:gsub("^.*:", "")
  local cfg = {
    class = key,
    buffer = buffer,
    importer = importer,
    machines = machines,
    recipes = {
      { key = key,
        inputs = { { name = item, n = 8, toSlot = 1 },
                   { name = fuel, n = 1, toSlot = 2 } },
        outputs = { { name = "output", fromSlot = 3 } } },
    },
    maxInFlight = 2,
    jamT = 90, staleT = 45,
    pollFast = 0.5, pollIdle = 3.0,
  }
  local f = fs.open("station_cfg.lua", "w")
  f.write("return " .. textutils.serialize(cfg))
  f.close()
  print(("station_cfg.lua written: %d furnaces, class %s"):format(#machines, key))
  print("run: station")
else
  print("unknown preset: " .. tostring(mode))
end
