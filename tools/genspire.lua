-- genspire: generates THE GOLDEN ASCENT - a double-helix monument
-- order for the Lens F8 executor. Gold and iron strands spiral around
-- an obsidian core with a diamond crown; every layer is a radial arm
-- off the core, so each block is face-connected to something already
-- placed and survival-legal placement can never strand. This is the
-- over-the-top decorative stress test for the schematic pipeline.
--
--   lua54 tools/genspire.lua <out.json> [--height N] [--radius N]
--                            [--turn N] [--name X]
--
-- Defaults: height 48, radius 4, full turn every 24 layers. Origin in
-- the emitted order is a placeholder - edit it to the build site
-- (ground level: layer 0 sits ON the origin y).
local M = {}

M.CORE = "minecraft:obsidian"
M.STRANDS = { "minecraft:gold_block", "minecraft:iron_block" }
M.CROWN = "minecraft:diamond_block"

function M.generate(opts)
  opts = opts or {}
  local H = opts.height or 48
  local R = opts.radius or 4
  local turn = opts.turn or 24
  local cells = {}
  local function put(x, y, z, b)
    local k = x .. "," .. y .. "," .. z
    if not cells[k] then cells[k] = { x = x, y = y, z = z, b = b } end
  end
  for y = 0, H - 1 do
    put(0, y, 0, M.CORE)
    for s = 0, 1 do
      local theta = (y / turn) * 2 * math.pi + s * math.pi
      local mat = M.STRANDS[s + 1]
      local tx = math.floor(R * math.cos(theta) + 0.5)
      local tz = math.floor(R * math.sin(theta) + 0.5)
      -- radial arm: L-path from the core out to the strand tip; every
      -- cell is orthogonally adjacent to the previous one
      local x, z = 0, 0
      while x ~= tx do
        x = x + (tx > x and 1 or -1)
        put(x, y, z, mat)
      end
      while z ~= tz do
        z = z + (tz > z and 1 or -1)
        put(x, y, z, mat)
      end
    end
  end
  -- diamond crown: 3x3 cap over the core plus a single finial
  for dx = -1, 1 do
    for dz = -1, 1 do
      put(dx, H, dz, M.CROWN)
    end
  end
  put(0, H + 1, 0, M.CROWN)
  local blocks = {}
  for _, c in pairs(cells) do blocks[#blocks + 1] = c end
  table.sort(blocks, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.z ~= b.z then return a.z < b.z end
    return a.x < b.x
  end)
  return blocks
end

-- placement-order support check: layer by layer, a block is supported
-- if it stands on a supported block below (layer 0 stands on ground)
-- or chains through same-layer orthogonal neighbors to one that does.
-- Returns true only if EVERY block is reachable that way.
function M.supported(blocks)
  local byY = {}
  local minY = math.huge
  for _, c in ipairs(blocks) do
    byY[c.y] = byY[c.y] or {}
    table.insert(byY[c.y], c)
    if c.y < minY then minY = c.y end
  end
  local ys = {}
  for y in pairs(byY) do ys[#ys + 1] = y end
  table.sort(ys)
  local placed = {}
  for _, y in ipairs(ys) do
    local layer = {}
    for _, c in ipairs(byY[y]) do layer[c.x .. "," .. c.z] = c end
    local reached, queue, qi = {}, {}, 1
    for k, c in pairs(layer) do
      if y == minY or placed[c.x .. "," .. (y - 1) .. "," .. c.z] then
        reached[k] = true
        queue[#queue + 1] = c
      end
    end
    while queue[qi] do
      local c = queue[qi]
      qi = qi + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local k = (c.x + d[1]) .. "," .. (c.z + d[2])
        if layer[k] and not reached[k] then
          reached[k] = true
          queue[#queue + 1] = layer[k]
        end
      end
    end
    for k in pairs(layer) do
      if not reached[k] then return false, y, k end
    end
    for k, c in pairs(layer) do
      placed[c.x .. "," .. y .. "," .. c.z] = true
    end
  end
  return true
end

function M.materials(blocks)
  local out = {}
  for _, c in ipairs(blocks) do out[c.b] = (out[c.b] or 0) + 1 end
  return out
end

function M.emitOrder(name, origin, blocks)
  local parts = {}
  for i, c in ipairs(blocks) do
    parts[i] = ('{"x":%d,"y":%d,"z":%d,"b":"%s"}'):format(c.x, c.y, c.z, c.b)
  end
  return ('{"name":"%s","origin":[%d,%d,%d],"blocks":[%s]}\n')
    :format(name, origin[1], origin[2], origin[3], table.concat(parts, ","))
end

if _TEST then return M end

local args = { ... }
if #args < 1 then
  print("usage: lua54 tools/genspire.lua <out.json> [--height N] [--radius N] [--turn N] [--name X]")
  os.exit(1)
end
local opts, name = {}, "golden_ascent"
for i = 2, #args do
  if args[i] == "--height" then opts.height = tonumber(args[i + 1])
  elseif args[i] == "--radius" then opts.radius = tonumber(args[i + 1])
  elseif args[i] == "--turn" then opts.turn = tonumber(args[i + 1])
  elseif args[i] == "--name" then name = args[i + 1] end
end
local blocks = M.generate(opts)
local ok, badY, badK = M.supported(blocks)
if not ok then
  print(("REFUSING to emit: unsupported block at layer %d cell %s")
    :format(badY, badK))
  os.exit(1)
end
local f = assert(io.open(args[1], "w"))
f:write(M.emitOrder(name, { 0, 100, 0 }, blocks))
f:close()
print(("%s: %d blocks, all placement-supported -> %s")
  :format(name, #blocks, args[1]))
print("materials (edit origin in the json before F8):")
for b, n in pairs(M.materials(blocks)) do
  print(("  %4d  %s"):format(n, b))
end
