-- schematic: a 3D block volume + generators + a build-order planner.
-- Pure data/logic (no turtle), so the whole build algorithm is testable in a
-- mock world. Coordinates: x = width (east), y = height (up), z = depth (north),
-- all zero-based. A cell is either a block id string or nil (air).
local schematic = {}
schematic.__index = schematic

function schematic.new(w, h, d)
  return setmetatable({ w = w, h = h, d = d, cells = {} }, schematic)
end

local function key(x, y, z) return x .. "," .. y .. "," .. z end

function schematic:set(x, y, z, block)
  self.cells[key(x, y, z)] = block
end

function schematic:get(x, y, z)
  return self.cells[key(x, y, z)]
end

function schematic:count()
  local n = 0
  for _ in pairs(self.cells) do n = n + 1 end
  return n
end

-- total materials required, by block id
function schematic:materials()
  local m = {}
  for _, block in pairs(self.cells) do
    m[block] = (m[block] or 0) + 1
  end
  return m
end

-- ---- generators (return a ready schematic) ---------------------------------

function schematic.floor(w, d, block)
  local s = schematic.new(w, 1, d)
  for x = 0, w - 1 do for z = 0, d - 1 do s:set(x, 0, z, block) end end
  return s
end

-- hollow box: four walls, optional floor and roof
function schematic.hollowBox(w, h, d, block, opts)
  opts = opts or {}
  local s = schematic.new(w, h, d)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      for z = 0, d - 1 do
        local edge = x == 0 or x == w - 1 or z == 0 or z == d - 1
        local floor = (y == 0) and opts.floor
        local roof = (y == h - 1) and opts.roof
        if edge or floor or roof then s:set(x, y, z, block) end
      end
    end
  end
  return s
end

-- solid rectangular prism
function schematic.solid(w, h, d, block)
  local s = schematic.new(w, h, d)
  for y = 0, h - 1 do for x = 0, w - 1 do for z = 0, d - 1 do
    s:set(x, y, z, block)
  end end end
  return s
end

-- a vertical cylinder shell of given radius/height, centered
function schematic.cylinder(radius, h, block)
  local size = radius * 2 + 1
  local s = schematic.new(size, h, size)
  local cx, cz = radius, radius
  for y = 0, h - 1 do
    for x = 0, size - 1 do
      for z = 0, size - 1 do
        local dist = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
        if dist > radius - 1 and dist <= radius + 0.5 then
          s:set(x, y, z, block)
        end
      end
    end
  end
  return s
end

-- an ominous corporate HQ: dark hollow tower, a glowing accent band, corner
-- spikes, and a rooftop antenna. Multi-material; the builder pulls each block
-- type from the turtle's inventory. palette keys: wall, glow, spire.
function schematic.evilTower(w, h, palette)
  palette = palette or {}
  local wall = palette.wall or "minecraft:blackstone"
  local glow = palette.glow or "minecraft:sea_lantern"
  local spire = palette.spire or "minecraft:obsidian"
  local antenna = 4
  local s = schematic.new(w, h + antenna, w)
  local bandY = math.floor(h * 0.72)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      for z = 0, w - 1 do
        local edge = x == 0 or x == w - 1 or z == 0 or z == w - 1
        local platform = (y % 5 == 0)              -- interior floors
        if edge then
          s:set(x, y, z, y == bandY and glow or wall)  -- glowing sign band
        elseif platform then
          s:set(x, y, z, wall)
        end
      end
    end
  end
  -- menacing corner spikes rising above the roof
  local corners = { { 0, 0 }, { 0, w - 1 }, { w - 1, 0 }, { w - 1, w - 1 } }
  for _, c in ipairs(corners) do
    for k = 0, 2 do s:set(c[1], h + k, c[2], spire) end
  end
  -- central antenna, glowing tip
  local mid = math.floor(w / 2)
  for k = 0, antenna - 1 do s:set(mid, h + k, mid, spire) end
  s:set(mid, h + antenna - 1, mid, glow)
  return s
end

-- lit platform: trim rim, glow grid every 4 blocks (spawn-proofing doubles as
-- decor), optional holes (e.g. leave the void portal block in place at the
-- campus datum). opts.holes = { {x,z}, ... }
function schematic.pad(w, d, palette, opts)
  palette = palette or {}
  opts = opts or {}
  local wall = palette.wall or "minecraft:purple_concrete"
  local trim = palette.trim or "minecraft:polished_blackstone"
  local glow = palette.glow or "minecraft:sea_lantern"
  local s = schematic.new(w, 1, d)
  local holes = {}
  for _, hxz in ipairs(opts.holes or {}) do holes[hxz[1] .. "," .. hxz[2]] = true end
  for x = 0, w - 1 do
    for z = 0, d - 1 do
      if not holes[x .. "," .. z] then
        if x == 0 or x == w - 1 or z == 0 or z == d - 1 then s:set(x, 0, z, trim)
        elseif x % 4 == 2 and z % 4 == 2 then s:set(x, 0, z, glow)
        else s:set(x, 0, z, wall) end
      end
    end
  end
  return s
end

-- a hall: perimeter walls with corner trim + glass window bands, full roof,
-- lit interior floor, and a 3-wide 3-tall doorway. opts.door picks the face
-- the doorway is on: "-z" (default), "+z", "-x", "+x".
function schematic.hall(w, h, d, palette, opts)
  palette = palette or {}
  opts = opts or {}
  local wall = palette.wall or "minecraft:purple_concrete"
  local trim = palette.trim or "minecraft:polished_blackstone"
  local glass = palette.glass or "minecraft:gray_stained_glass"
  local glow = palette.glow or "minecraft:sea_lantern"
  local s = schematic.new(w, h, d)
  local door = opts.door or "-z"
  local mx, mz = math.floor(w / 2), math.floor(d / 2)
  local function inDoor(x, y, z)
    if y < 1 or y > 3 then return false end
    if door == "-z" then return z == 0 and x >= mx - 1 and x <= mx + 1 end
    if door == "+z" then return z == d - 1 and x >= mx - 1 and x <= mx + 1 end
    if door == "-x" then return x == 0 and z >= mz - 1 and z <= mz + 1 end
    if door == "+x" then return x == w - 1 and z >= mz - 1 and z <= mz + 1 end
    return false
  end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      for z = 0, d - 1 do
        local edge = x == 0 or x == w - 1 or z == 0 or z == d - 1
        local corner = (x == 0 or x == w - 1) and (z == 0 or z == d - 1)
        if y == 0 then
          if edge then s:set(x, y, z, trim)
          elseif x % 4 == 2 and z % 4 == 2 then s:set(x, y, z, glow)
          else s:set(x, y, z, wall) end
        elseif y == h - 1 then
          s:set(x, y, z, wall)
        elseif edge and not inDoor(x, y, z) then
          local band = y >= 3 and y <= h - 3 and y % 3 == 0
          if corner then s:set(x, y, z, trim)
          elseif band then s:set(x, y, z, glass)
          else s:set(x, y, z, wall) end
        end
      end
    end
  end
  return s
end

-- strainer deck: watertight underlayer + a lip level with open 2-wide water
-- channels running the full length, 1-wide lit walkways between, and a full
-- perimeter lip (water stays in, you don't walk into the void). Width is
-- derived from the channel count: w = channels*3 + 1.
function schematic.channelPad(channels, d, palette)
  palette = palette or {}
  local wall = palette.wall or "minecraft:purple_concrete"
  local trim = palette.trim or "minecraft:polished_blackstone"
  local glow = palette.glow or "minecraft:sea_lantern"
  local w = channels * 3 + 1
  local s = schematic.new(w, 2, d)
  for x = 0, w - 1 do
    for z = 0, d - 1 do
      s:set(x, 0, z, wall)
      local ix = x - 1
      if x == 0 or x == w - 1 or z == 0 or z == d - 1 then
        s:set(x, 1, z, trim)
      elseif ix % 3 == 2 then
        s:set(x, 1, z, z % 4 == 2 and glow or trim)
      end
    end
  end
  return s
end

-- Paperclip Corp HQ: a Doofenshmirtz-grade corporate tower. Wide base with an
-- arched entry and window band, a tapered purple shaft with tinted window
-- rings and a glowing "P", an overhanging head with a lit sign band, and a
-- swooping rooftop fin that curls over the edge (you know the silhouette).
-- ~1200 blocks, 4 materials, 15x11 footprint, 38 tall. The P faces -z.
function schematic.paperclipHQ(palette)
  palette = palette or {}
  local wall  = palette.wall  or "minecraft:purple_concrete"
  local trim  = palette.trim  or "minecraft:polished_blackstone"
  local glass = palette.glass or "minecraft:gray_stained_glass"
  local glow  = palette.glow  or "minecraft:sea_lantern"

  local s = schematic.new(15, 38, 11)

  -- base: 15x11, y 0..7 - walls with corner trim, window band, entry arch
  for y = 0, 7 do
    for x = 0, 14 do
      for z = 0, 10 do
        if x == 0 or x == 14 or z == 0 or z == 10 then
          local corner = (x == 0 or x == 14) and (z == 0 or z == 10)
          local door = z == 0 and x >= 6 and x <= 8 and y >= 1 and y <= 3
          if not door then
            if corner then s:set(x, y, z, trim)
            elseif y >= 3 and y <= 5 then s:set(x, y, z, glass)
            else s:set(x, y, z, wall) end
          end
        end
      end
    end
  end
  for x = 0, 14 do
    for z = 0, 10 do
      if not s:get(x, 7, z) then s:set(x, 7, z, wall) end  -- base roof
    end
  end

  -- shaft: 7x7 (x 4..10, z 2..8), y 8..25 - corner trim + window rings
  for y = 8, 25 do
    for x = 4, 10 do
      for z = 2, 8 do
        if x == 4 or x == 10 or z == 2 or z == 8 then
          local corner = (x == 4 or x == 10) and (z == 2 or z == 8)
          if corner then s:set(x, y, z, trim)
          elseif (y - 8) % 3 == 2 and y < 25 then s:set(x, y, z, glass)
          else s:set(x, y, z, wall) end
        end
      end
    end
  end

  -- the P: 5x7 glowing sign on the shaft's front face, wall backdrop
  local P = { "XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...." }
  for r = 1, #P do
    for c = 1, 5 do
      s:set(4 + c, 24 - r, 2, P[r]:sub(c, c) == "X" and glow or wall)
    end
  end

  -- head: 11x9 (x 2..12, z 1..9), y 26..30 - overhangs the shaft by 2 on
  -- every side; floor forms the cantilever underside, sign band glows at 28
  for y = 26, 30 do
    for x = 2, 12 do
      for z = 1, 9 do
        local edge = x == 2 or x == 12 or z == 1 or z == 9
        local corner = (x == 2 or x == 12) and (z == 1 or z == 9)
        local shaftInterior = x >= 5 and x <= 9 and z >= 3 and z <= 7
        if edge then
          if corner then s:set(x, y, z, trim)
          elseif y == 28 then s:set(x, y, z, glow)
          else s:set(x, y, z, wall) end
        elseif y == 26 and not shaftInterior then
          s:set(x, y, z, wall)          -- underside of the overhang
        elseif y == 30 then
          s:set(x, y, z, wall)          -- head roof
        end
      end
    end
  end

  -- rooftop fin: quadratic swoosh along the spine (z=5), rising toward +x
  -- and curling over the edge; lit at the tip
  for i = 0, 10 do
    local hgt = math.floor(7 * (i / 10) ^ 2 + 0.5)
    for k = 1, hgt do s:set(2 + i, 30 + k, 5, trim) end
  end
  s:set(13, 37, 5, glow)
  s:set(14, 36, 5, trim)

  return s
end

-- ---- build planner ---------------------------------------------------------

-- Produce placements in a build-safe order: bottom layer first, then up. Within
-- a layer, serpentine over x/z to minimize travel. The turtle flies one block
-- ABOVE the layer it places (place-down), so it never stands where a block must
-- go and never rises into an occupied cell. Air cells are skipped.
function schematic:plan()
  local placements = {}
  for y = 0, self.h - 1 do
    local flip = false
    for z = 0, self.d - 1 do
      local xs = {}
      if flip then
        for x = self.w - 1, 0, -1 do xs[#xs + 1] = x end
      else
        for x = 0, self.w - 1 do xs[#xs + 1] = x end
      end
      for _, x in ipairs(xs) do
        local block = self:get(x, y, z)
        if block then
          placements[#placements + 1] = { x = x, y = y, z = z, block = block }
        end
      end
      flip = not flip
    end
  end
  return placements
end

return schematic
