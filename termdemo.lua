-- termdemo: drive a Paperclip Order Terminal with a demo catalog so the
-- GUI can be exercised without a full craftd rig. Place a computer with
-- a wired modem next to the terminal (activate the modem), run this.
-- Clicks in the GUI come back here and get fake-completed with toasts.
local t = peripheral.find("paperclip_terminal")
if not t then
  print("no terminal on the network - modem activated?")
  return
end

local DEMO = {
  { id = "minecraft:iron_ingot", name = "Iron Ingot", stock = 34008 },
  { id = "minecraft:gold_ingot", name = "Gold Ingot", stock = 23401 },
  { id = "minecraft:diamond", name = "Diamond", stock = 22311 },
  { id = "minecraft:redstone", name = "Redstone Dust", stock = 22606 },
  { id = "minecraft:obsidian", name = "Obsidian", stock = 24187 },
  { id = "minecraft:netherite_ingot", name = "Netherite Ingot", stock = 2211 },
  { id = "mysticalagriculture:inferium_essence", name = "Inferium Essence", stock = 76743 },
  { id = "minecraft:iron_block", name = "Block of Iron", stock = 3778 },
  { id = "minecraft:glass", name = "Glass", stock = 12000 },
  { id = "minecraft:copper_ingot", name = "Copper Ingot", stock = 51234 },
  { id = "minecraft:lapis_lazuli", name = "Lapis Lazuli", stock = 9800 },
  { id = "minecraft:coal", name = "Coal", stock = 40210 },
  { id = "minecraft:oak_planks", name = "Oak Planks", stock = 6000 },
  { id = "minecraft:stick", name = "Stick", stock = 400 },
  { id = "minecraft:ender_pearl", name = "Ender Pearl", stock = 777 },
  { id = "computercraft:cable", name = "Networking Cable", stock = 128 },
}

t.setCatalog(DEMO)
t.setQueue({})
t.toast("demo catalog loaded - click things", true)
print("terminal loaded with demo catalog. Watching for orders...")

while true do
  local orders = t.getOrders()
  for _, o in ipairs(orders) do
    print(("order: %d x %s from %s"):format(o.count, o.item, o.player))
    t.setQueue({ { label = o.count .. " x " .. o.item:gsub("^[^:]+:", ""),
      status = "crafting (demo)..." } })
    sleep(2)
    t.setQueue({})
    t.toast(("%d x %s (demo)"):format(o.count, o.item:gsub("^[^:]+:", "")), true)
  end
  sleep(0.5)
end
