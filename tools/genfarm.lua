-- genfarm: emits one F8 build order per printer bay - tier-matched
-- essence farmland on the 9x9 bed (minus the 5 water cells), then the
-- bay's seeds planted on top. Strict bottom-up: the whole farmland
-- layer goes down serpentine before the first seed. The flying body
-- is exempt from the turtle-farmland curse (a player is not a block),
-- which is the entire reason this op is possible.
--
--   lua54 tools/genfarm.lua <snapshot.json> <outDir>
--
-- Geometry from printfit.lua (datum frame): bay k bed = 9x9 at
-- x BAY_X(k)+1..+9, z Z0+1..Z0+9, y SLAB_Y+1; waters at (5,5) center
-- + 4 quadrants. World transform (solved against the 9 pylons):
-- world = datum + (frameZ, frameY, frameX). Orders emit fromDatum in
-- WORLD deltas, so x<->z swap happens here.
package.path = "./?.lua;./tools/?.lua;" .. package.path
local wasTest = _TEST
_TEST = true
local S = require("scan2map")
_TEST = wasTest

local M = {}

M.DATUM = { x = -364, y = 270, z = -1880 }
M.X0, M.Z0, M.SLAB_Y = 30, -5, 13
M.WATERS = { [11] = "33", [1] = "55" }  -- placeholder; real set below
M.WATERSET = { ["5,5"] = true, ["3,3"] = true, ["3,7"] = true,
  ["7,3"] = true, ["7,7"] = true }
local MA = "mysticalagriculture:"
M.BAYS = {
  { key = "inferium", seed = MA .. "inferium_seeds", farmland = MA .. "supremium_farmland" },
  { key = "iron", seed = MA .. "iron_seeds", farmland = MA .. "prudentium_farmland" },
  { key = "gold", seed = MA .. "gold_seeds", farmland = MA .. "tertium_farmland" },
  { key = "redstone", seed = MA .. "redstone_seeds", farmland = MA .. "prudentium_farmland" },
  { key = "osmium", seed = MA .. "osmium_seeds", farmland = MA .. "tertium_farmland" },
  { key = "diamond", seed = MA .. "diamond_seeds", farmland = MA .. "imperium_farmland" },
  { key = "obsidian", seed = MA .. "obsidian_seeds", farmland = MA .. "tertium_farmland" },
  { key = "uranium", seed = MA .. "uranium_seeds", farmland = MA .. "imperium_farmland" },
  { key = "netherite", seed = MA .. "netherite_seeds", farmland = MA .. "imperium_farmland" },
}

function M.bayX(k) return M.X0 + (k - 1) * 12 end

-- frame -> world
function M.world(fx, fy, fz)
  return M.DATUM.x + fz, M.DATUM.y + fy, M.DATUM.z + fx
end

-- world -> fromDatum offset (what BuildOrder adds to the datum)
function M.offset(fx, fy, fz)
  return fz, fy, fx
end

-- one bay's order: farmland first, then seeds above. The farmland layer
-- flies at chest altitude: hover feet = target+1.35 (hoverHeight 0.85),
-- body spans +1.35..+3.15 over the bed while the chest at center (5,5)
-- spans +1.00..+1.875 - a 0.5-block vertical overlap, so clearance is
-- purely horizontal: player half-width 0.3 + chest half-width 0.44 =
-- 0.74 center-to-center minimum. Every leg here (including the
-- half-to-arm transitions and the final climb to the seed layer) keeps
-- >= 1.0: west half, SOUTH arm off row 9, east half rows 9->1, NORTH
-- arm off row 1, then climb to seeds from (4,5) - moving away from the
-- chest. A naive serpentine's diagonal transitions pass 0.49 from the
-- chest center and clip it. The seed layer (chest altitude + hover)
-- flies feet 0.475 above the chest lid and can serpentine plainly.
function M.genBayOrder(k)
  local bay = M.BAYS[k]
  local px = M.bayX(k)
  local blocks = {}
  local function add(row, col, y, item)
    if M.WATERSET[row .. "," .. col] then return end
    local ox, oy, oz = M.offset(px + row, y, M.Z0 + col)
    blocks[#blocks + 1] = { x = ox, y = oy, z = oz, b = item }
  end
  local fy = M.SLAB_Y + 1
  for row = 1, 9 do                    -- west half: cols 1..4 serpentine
    if row % 2 == 1 then
      for col = 1, 4 do add(row, col, fy, bay.farmland) end
    else
      for col = 4, 1, -1 do add(row, col, fy, bay.farmland) end
    end
  end
  for row = 9, 6, -1 do add(row, 5, fy, bay.farmland) end   -- south arm
  for row = 9, 1, -1 do                -- east half: rows 9->1, cols 6..9
    if row % 2 == 1 then
      for col = 6, 9 do add(row, col, fy, bay.farmland) end
    else
      for col = 9, 6, -1 do add(row, col, fy, bay.farmland) end
    end
  end
  for row = 1, 4 do add(row, 5, fy, bay.farmland) end   -- north arm
  for row = 1, 9 do                    -- seeds: plain serpentine, clears chest
    if row % 2 == 1 then
      for col = 1, 9 do add(row, col, M.SLAB_Y + 2, bay.seed) end
    else
      for col = 9, 1, -1 do add(row, col, M.SLAB_Y + 2, bay.seed) end
    end
  end
  return blocks
end

function M.emit(name, blocks)
  local parts = {}
  for i, c in ipairs(blocks) do
    parts[i] = ('{"x":%d,"y":%d,"z":%d,"b":"%s"}'):format(c.x, c.y, c.z, c.b)
  end
  return ('{"name":"%s","fromDatum":[0,0,0],"blocks":[%s]}\n')
    :format(name, table.concat(parts, ","))
end

if _TEST then return M end

local args = { ... }
if #args < 2 then
  print("usage: lua54 tools/genfarm.lua <snapshot.json> <outDir>")
  os.exit(1)
end
local f = assert(io.open(args[1], "r"))
local snap = S.parseJson(f:read("*a"))
f:close()
local solid = {}
for _, b in ipairs(snap.blocks) do
  solid[b[1] .. "," .. b[2] .. "," .. b[3]] = b[4]
end

for k, bay in ipairs(M.BAYS) do
  local px = M.bayX(k)
  -- sanity: pylon in the center water, slab under every farmland cell
  local cx, cy, cz = M.world(px + 5, M.SLAB_Y + 1, M.Z0 + 5)
  local pylon = solid[cx .. "," .. cy .. "," .. cz]
  local slabMissing, occupied = 0, 0
  for row = 1, 9 do
    for col = 1, 9 do
      if not M.WATERSET[row .. "," .. col] then
        local wx, wy, wz = M.world(px + row, M.SLAB_Y, M.Z0 + col)
        if not solid[wx .. "," .. wy .. "," .. wz] then
          slabMissing = slabMissing + 1
        end
        local bx, by, bz = M.world(px + row, M.SLAB_Y + 1, M.Z0 + col)
        local cur = solid[bx .. "," .. by .. "," .. bz]
        if cur and cur ~= "minecraft:dirt" then occupied = occupied + 1 end
      end
    end
  end
  if not (pylon and pylon:find("pylon")) then
    print(("bay %d %-9s SKIP: no pylon at %d,%d,%d"):format(k, bay.key, cx, cy, cz))
  elseif slabMissing > 0 then
    print(("bay %d %-9s SKIP: %d slab cells missing"):format(k, bay.key, slabMissing))
  else
    local blocks = M.genBayOrder(k)
    local out = assert(io.open(args[2] .. "/bay" .. k .. "_" .. bay.key .. ".json", "w"))
    out:write(M.emit("BAY " .. k .. " " .. bay.key:upper(), blocks))
    out:close()
    print(("bay %d %-9s OK: 76x %s + 76x %s%s"):format(k, bay.key,
      bay.farmland:gsub(MA, ""), bay.seed:gsub(MA, ""),
      occupied > 0 and ("  [%d cells hold non-dirt blocks]"):format(occupied) or ""))
  end
end
print("NOTE: executor skips any cell still holding dirt - break thoroughly.")
