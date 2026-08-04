-- plan2order: converts a scan2plan-emitted plan module into a Lens
-- Claude-Control build order. The full replication pipeline:
--   survey <w> <l> <h>            (turtle scans anything, pastebin code)
--   lua54 tools/scan2plan.lua ... (scan -> buildable plan + materials)
--   lua54 tools/plan2order.lua plan.lua "name" <ox> <oy> <oz> order.json
--   drop order.json into <instance>/paperclip_lens/orders/
--   press F8 in-game                 (your body builds it)
-- Origin = the WORLD coordinates where the plan's (0,0,0) corner goes;
-- plan +z runs the direction the scanning turtle faced, +x its right.
local args = { ... }
if #args < 6 then
  print("usage: lua54 tools/plan2order.lua <plan.lua> <name> <ox> <oy> <oz> <out.json>")
  os.exit(1)
end
local planFile, name = args[1], args[2]
local ox, oy, oz = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
local outFile = args[6]
if not (ox and oy and oz) then
  print("origin coordinates must be numbers")
  os.exit(1)
end

local chunk, err = loadfile(planFile)
if not chunk then
  print("cannot load plan: " .. tostring(err))
  os.exit(1)
end
local plan = chunk()
if type(plan) ~= "table" or type(plan.blocks) ~= "table" then
  print("not a plan module (needs .blocks)")
  os.exit(1)
end

local function esc(s)
  return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local parts = {}
for i, b in ipairs(plan.blocks) do
  parts[i] = ('{"x":%d,"y":%d,"z":%d,"b":"%s"}'):format(b.x, b.y, b.z, esc(b.block))
end

local f = assert(io.open(outFile, "w"))
f:write(('{"name":"%s","origin":[%d,%d,%d],"blocks":[%s]}')
  :format(esc(name), ox, oy, oz, table.concat(parts, ",")))
f:close()

print(("order '%s': %d placements at origin %d,%d,%d -> %s")
  :format(name, #plan.blocks, ox, oy, oz, outFile))
print("materials:")
local mats = {}
for id, n in pairs(plan.materials or {}) do
  mats[#mats + 1] = { id = id, n = n }
end
table.sort(mats, function(a, b) return a.n > b.n end)
for _, m in ipairs(mats) do
  print(("  %5d x %s"):format(m.n, m.id))
end
