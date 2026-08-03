-- campus: the sky-campus site plan as pure data/logic, shared by
-- datacenter.lua (builder), casinofit.lua (machinery), and the tests.
-- All offsets are datum-frame: the turtle's start cell on the gold datum
-- block is (0,0,0), campus ground plane is y=-1, +z is campus-north.
local schematic = require("schematic")

local M = {}

M.PALETTE = {
  wall = "minecraft:purple_concrete",
  trim = "minecraft:polished_blackstone",
  glass = "minecraft:gray_stained_glass",
  -- glowstone to match the HQ's bootstrap palette (no prismarine farming
  -- yet); swap back to sea_lantern when the ocean monument run happens
  glow = "minecraft:glowstone",
}
local P = M.PALETTE

-- flight level (datum frame) for travel between sites; above every roof
M.CORRIDOR_Y = 15

M.SITES = {
  { key = "pad", name = "Portal Plaza", at = { -8, -1, -8 },
    gen = function() return schematic.pad(17, 17, P, { holes = { { 8, 8 } } }) end,
    after = { "the gold datum sits in the center hole - do not cover it",
              "stage material chests + the field ender chest here" } },
  { key = "noc", name = "NOC / control room", at = { -4, -1, 10 },
    gen = function() return schematic.hall(9, 7, 9, P, { door = "-z" }) end,
    after = { "advanced computer + wireless modem inside; run `update` then `menu`",
              "monitor wall on the interior back wall (max 8x6)" } },
  { key = "warehouse", name = "Warehouse hall", at = { -28, -1, -6 },
    gen = function() return schematic.hall(19, 9, 13, P, { door = "+x" }) end,
    after = { "STORAGE CORE v1: sophisticatedstorage barrels + stack upgrades",
              "  behind sophisticatedstorage:controller (general tier), and a",
              "  functionalstorage drawer wall + its controller (bulk tier)",
              "wired modems + cable from the SS controller to a computer",
              "  running `warehouse` - the grid UI IS the pre-ME system",
              "pipez item pipes: casino barrels -> warehouse input",
              "crafter turtle pool on the west wall; AE2 fronts these same",
              "  storages via storage bus in phase 7 - nothing is throwaway" } },
  { key = "power", name = "Power wing", at = { 10, -1, -8 },
    gen = function() return schematic.hall(17, 13, 17, P, { door = "-x" }) end,
    after = { "assemble the Mekanism fission reactor multiblock inside",
              "computer on the Logic Adapter running `reactor`",
              "turbine/boiler are a later expansion - leave headroom" } },
  { key = "bays", name = "Turtle bays", at = { 10, -1, 10 },
    gen = function() return schematic.hall(13, 5, 9, P, { door = "-z" }) end,
    after = { "disk drive + provisioning floppy per bay, fuel + spare-part chests" } },
  { key = "casino", name = "Strainer casino deck", at = { -7, -1, -30 },
    gen = function() return schematic.channelPad(4, 21, P) end,
    after = { "run `casinofit` from the datum: it installs hoppers, barrels,",
              "water, and every strainer you load it with (rerun to add more)" } },
}

function M.site(key)
  for _, s in ipairs(M.SITES) do
    if s.key == key then return s end
  end
end

function M.bounds(site)
  local s = site.gen()
  return { x1 = site.at[1], y1 = site.at[2], z1 = site.at[3],
           x2 = site.at[1] + s.w - 1, y2 = site.at[2] + s.h - 1,
           z2 = site.at[3] + s.d - 1 }
end

-- travel there + build + travel back, plus restock/detour slack
function M.estimateFuel(site, s, planCount)
  local travel = 2 * (math.abs(site.at[1]) + math.abs(site.at[3]) + 2 * M.CORRIDOR_Y)
  return planCount * 3 + s.h * 4 + travel + 100
end

return M
