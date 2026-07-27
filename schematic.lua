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
