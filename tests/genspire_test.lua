-- headless genspire test: helix geometry, the placement-support
-- invariant the Lens executor depends on, and order JSON validity.
package.path = "./?.lua;./tools/?.lua;" .. package.path
_TEST = true
local G = require("genspire")
local S = require("scan2map")   -- reuse its JSON parser to validate output

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local blocks = G.generate({ height = 48, radius = 4, turn = 24 })
check("generate: produces blocks", #blocks > 300, #blocks)
check("generate: deterministic",
  #blocks == #G.generate({ height = 48, radius = 4, turn = 24 }))

-- the invariant: every block face-connects to the supported structure
check("supported: default spire fully placeable", G.supported(blocks))

-- bigger and tighter variants hold the invariant too
check("supported: tall wide spire",
  G.supported(G.generate({ height = 100, radius = 7, turn = 32 })))
check("supported: fast-twist spire",
  G.supported(G.generate({ height = 30, radius = 5, turn = 8 })))

-- the checker itself catches a genuinely floating block
local floating = { { x = 0, y = 0, z = 0, b = "b" }, { x = 5, y = 3, z = 5, b = "b" } }
check("supported: detects floaters", G.supported(floating) == false)

-- geometry: core runs full height, crown sits on top
local coreCount, crownTop = 0, false
for _, c in ipairs(blocks) do
  if c.b == G.CORE then coreCount = coreCount + 1 end
  if c.b == G.CROWN and c.y == 49 and c.x == 0 and c.z == 0 then crownTop = true end
end
check("generate: obsidian core full height", coreCount == 48, coreCount)
check("generate: diamond finial at the top", crownTop)

-- strands stay within radius and both materials appear
local mats = G.materials(blocks)
check("materials: gold strand", (mats["minecraft:gold_block"] or 0) > 50)
check("materials: iron strand", (mats["minecraft:iron_block"] or 0) > 50)
check("materials: crown is 10 diamond", mats["minecraft:diamond_block"] == 10,
  mats["minecraft:diamond_block"])
local within = true
for _, c in ipairs(blocks) do
  if math.abs(c.x) > 4 or math.abs(c.z) > 4 then within = false end
end
check("generate: bounded by radius", within)

-- blocks sorted bottom-up (executor placement order)
local sorted = true
for i = 2, #blocks do
  if blocks[i].y < blocks[i - 1].y then sorted = false end
end
check("generate: bottom-up order", sorted)

-- emitted order round-trips through a JSON parser in BuildOrder shape
local json = G.emitOrder("test_spire", { 10, 64, -20 }, blocks)
local order = S.parseJson(json)
check("emit: name", order.name == "test_spire")
check("emit: origin", order.origin[1] == 10 and order.origin[2] == 64
  and order.origin[3] == -20)
check("emit: block count", #order.blocks == #blocks, #order.blocks)
check("emit: block shape", order.blocks[1].x ~= nil and order.blocks[1].y ~= nil
  and order.blocks[1].z ~= nil and order.blocks[1].b ~= nil)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
