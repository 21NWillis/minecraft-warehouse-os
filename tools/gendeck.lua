-- gendeck: emit a flat deck-tile build order for the F8 executor.
-- Serpentine over a WxD rectangle at one y level; every block after the
-- first is face-adjacent to the previous one, so a single hand-placed
-- anchor at the first corner supports the whole floating tile (the
-- executor's face search clicks side faces - OrderExecutor tries all
-- six directions).
--
-- usage: lua54 gendeck.lua <name> <ox> <oy> <oz> <width_x> <depth_z> <block> <outfile>
-- offsets are datum-relative (world = datum + offset), same convention
-- as the bay orders.

local name, ox, oy, oz, w, d, block, outfile =
  arg[1], tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]),
  tonumber(arg[5]), tonumber(arg[6]), arg[7], arg[8]

assert(name and ox and oy and oz and w and d and block and outfile,
  "usage: gendeck <name> <ox> <oy> <oz> <width_x> <depth_z> <block> <outfile>")

local parts = {}
for row = 0, d - 1 do
  local z = oz + row
  for col = 0, w - 1 do
    -- serpentine: even rows west->east, odd rows east->west
    local x = (row % 2 == 0) and (ox + col) or (ox + w - 1 - col)
    parts[#parts + 1] = string.format(
      '{"x":%d,"y":%d,"z":%d,"b":"%s"}', x, oy, z, block)
  end
end

local f = assert(io.open(outfile, "wb"))
f:write(string.format(
  '{"name":"%s","fromDatum":[0,0,0],"blocks":[%s]}',
  name, table.concat(parts, ",")))
f:close()

print(string.format("%s: %d blocks at y-offset %d, first block offset (%d,%d,%d)",
  outfile, w * d, oy, ox, oy, oz))
print("anchor: hand-place one block at the first-block position before arming")
