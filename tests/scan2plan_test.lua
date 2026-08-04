-- headless test for tools/scan2plan.lua: a synthetic SURVEY FORMAT v1 scan is
-- compiled to a plan and the result is proven end to end - the hand-rolled
-- JSON reader, the air/unknown/blocked/terrain/multiblock filters, the
-- build-safe ordering, the materials bill, the emitted module, the CLI flags,
-- and finally that builder.run actually builds the thing in a mock world.
package.path = "./?.lua;./tools/?.lua;" .. package.path
_TEST = true
local s2p = require("scan2plan")
local builder = require("builder")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- 4 x 3 x 2 scan (w x l x h). Layer 0 is a solid cobblestone slab (dense, so
-- serpentine adjacency is observable); layer 1 mixes planks, air, an unknown
-- cell, an entity-blocked cell, a grass block (default terrain skip) and a
-- formed multiblock ghost. The label carries an escaped quote on purpose.
local SCAN = [==[
{"v":1,"label":"test \"wing\"","w":4,"l":3,"h":2,"stopped":"done","visited":9,
 "palette":["minecraft:cobblestone","minecraft:grass_block","minecraft:oak_planks",
            "immersiveengineering:multiblock_structure"],
 "layers":[[1,1,1,1,1,1,1,1,1,1,1,1],
           [3,0,3,-1,2,4,3,-2,3,3,0,0]]}
]==]
local COBBLE = "minecraft:cobblestone"
local PLANKS = "minecraft:oak_planks"
local GRASS = "minecraft:grass_block"
local MULTI = "immersiveengineering:multiblock_structure"

-- ---- JSON reader -----------------------------------------------------------
local scan = s2p.parseJson(SCAN)
check("json: dimensions decode", scan.w == 4 and scan.l == 3 and scan.h == 2,
  tostring(scan.w) .. "x" .. tostring(scan.l) .. "x" .. tostring(scan.h))
check("json: palette is a 1-indexed array", #scan.palette == 4 and scan.palette[1] == COBBLE,
  tostring(scan.palette[1]))
check("json: escaped quotes in strings", scan.label == 'test "wing"', tostring(scan.label))
check("json: two layers of w*l cells", #scan.layers == 2 and #scan.layers[1] == 12 and #scan.layers[2] == 12,
  #scan.layers .. " layers")
check("json: negative sentinels survive", scan.layers[2][4] == -1 and scan.layers[2][8] == -2,
  tostring(scan.layers[2][4]) .. "/" .. tostring(scan.layers[2][8]))
check("json: nested objects/arrays and trailing whitespace ok",
  scan.v == 1 and scan.visited == 9 and scan.stopped == "done")
do
  local ok = pcall(s2p.parseJson, '{"w":1,')
  check("json: malformed input raises", not ok)
end

-- ---- default compile -------------------------------------------------------
local plan = s2p.compile(scan)
check("compile: 17 placements (12 slab + 5 planks)", plan.count == 17 and #plan.blocks == 17, plan.count)
check("compile: air/unknown/blocked counted, never placed",
  plan.stats.air == 3 and plan.stats.unknown == 1 and plan.stats.blocked == 1,
  ("air=%d unk=%d blk=%d"):format(plan.stats.air, plan.stats.unknown, plan.stats.blocked))
do
  local bad
  for _, p in ipairs(plan.blocks) do
    if p.block == nil or p.block == "" then bad = "empty id" end
    if p.x < 0 or p.x >= plan.w or p.y < 0 or p.y >= plan.h or p.z < 0 or p.z >= plan.l then
      bad = ("out of box %d,%d,%d"):format(p.x, p.y, p.z)
    end
  end
  check("compile: every placement is a named block inside the box", bad == nil, bad)
end
check("compile: dimensions carried through", plan.w == 4 and plan.l == 3 and plan.h == 2)

-- ---- filters ---------------------------------------------------------------
check("filter: default terrain skip drops grass_block",
  plan.materials[GRASS] == nil and plan.stats.skipped == 1, plan.stats.skipped)
do
  local p = s2p.compile(scan, { skip = { COBBLE } })
  check("filter: --skip drops the listed id (on top of defaults)",
    p.count == 5 and p.materials[COBBLE] == nil and p.materials[PLANKS] == 5, p.count)
  check("filter: --skip leaves defaults in force", p.materials[GRASS] == nil)
end
do
  local p = s2p.compile(scan, { only = { GRASS } })
  check("filter: --only keeps just the listed id, overriding defaults",
    p.count == 1 and p.materials[GRASS] == 1, p.count)
end
do
  local p = s2p.compile(scan, { only = { COBBLE, PLANKS } })
  check("filter: --only with several ids", p.count == 17 and p.materials[GRASS] == nil, p.count)
end
do
  local p = s2p.compile(scan, { noDefaults = true })
  check("filter: noDefaults keeps terrain", p.count == 18 and p.materials[GRASS] == 1, p.count)
end

-- ---- multiblock ------------------------------------------------------------
check("multiblock: excluded from placements and bill",
  plan.materials[MULTI] == nil and plan.stats.multiblock == 1, plan.stats.multiblock)
check("multiblock: warning flag + message", plan.hasMultiblock == true and #plan.warnings == 1
  and plan.warnings[1]:find(MULTI, 1, true) ~= nil, plan.warnings[1])
check("multiblock: counted per id", plan.multiblock[MULTI] == 1, tostring(plan.multiblock[MULTI]))
do
  local p = s2p.compile(scan, { only = { MULTI } })
  check("multiblock: --only cannot resurrect it", p.count == 0 and p.hasMultiblock == true, p.count)
end

-- ---- ordering (build-safe) -------------------------------------------------
do
  local monotone, prevY = true, -1
  for _, p in ipairs(plan.blocks) do
    if p.y < prevY then monotone = false end
    prevY = p.y
  end
  check("order: layers run bottom-up, never backwards", monotone)
end
check("order: starts at the origin cell of the bottom layer",
  plan.blocks[1].x == 0 and plan.blocks[1].y == 0 and plan.blocks[1].z == 0)
do
  -- layer 0 is dense, so consecutive placements must be neighbours (serpentine)
  local jump
  for i = 2, 12 do
    local a, b = plan.blocks[i - 1], plan.blocks[i]
    local d = math.abs(a.x - b.x) + math.abs(a.z - b.z)
    if a.y ~= 0 or b.y ~= 0 or d ~= 1 then
      jump = ("%d,%d -> %d,%d"):format(a.x, a.z, b.x, b.z)
    end
  end
  check("order: serpentine within a layer (consecutive cells adjacent)", jump == nil, jump)
end
do
  -- explicit shape of the snake: x forward on z=0, backwards on z=1
  local want = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 3, 1 }, { 2, 1 }, { 1, 1 }, { 0, 1 } }
  local bad
  for i, xz in ipairs(want) do
    local p = plan.blocks[i]
    if p.x ~= xz[1] or p.z ~= xz[2] then bad = ("#%d = %d,%d"):format(i, p.x, p.z) end
  end
  check("order: row 0 forward, row 1 reversed", bad == nil, bad)
end
do
  -- no cell is ever planned twice
  local seen, dup = {}, nil
  for _, p in ipairs(plan.blocks) do
    local k = p.x .. "," .. p.y .. "," .. p.z
    if seen[k] then dup = k end
    seen[k] = true
  end
  check("order: no duplicate cells", dup == nil, dup)
end

-- ---- materials bill --------------------------------------------------------
check("bill: exact counts", plan.materials[COBBLE] == 12 and plan.materials[PLANKS] == 5,
  tostring(plan.materials[COBBLE]) .. "/" .. tostring(plan.materials[PLANKS]))
do
  local bill = s2p.bill(plan)
  check("bill: sorted descending", #bill == 2 and bill[1].id == COBBLE and bill[1].n == 12
    and bill[2].id == PLANKS and bill[2].n == 5, bill[1] and bill[1].id)
  local total = 0
  for _, m in ipairs(bill) do total = total + m.n end
  check("bill: totals equal the placement count", total == plan.count, total)
end
do
  local lines = table.concat(s2p.summary(plan), "\n")
  check("summary: mentions dimensions and the bill",
    lines:find("4 x 3 x 2", 1, true) and lines:find(COBBLE, 1, true) ~= nil)
end

-- ---- emitted module --------------------------------------------------------
do
  local src = s2p.emit(plan, "synthetic.json")
  local chunk, lerr = load(src, "emitted")
  check("emit: output is loadable Lua", chunk ~= nil, lerr)
  local mod = chunk and chunk()
  check("emit: module shape (w,l,h,blocks,materials)", mod ~= nil and mod.w == 4 and mod.l == 3
    and mod.h == 2 and #mod.blocks == 17 and mod.materials[COBBLE] == 12)
  local mismatch
  for i, p in ipairs(plan.blocks) do
    local q = mod.blocks[i]
    if not q or q.x ~= p.x or q.y ~= p.y or q.z ~= p.z or q.block ~= p.block then mismatch = i end
  end
  check("emit: placements round-trip in order", mismatch == nil, mismatch)
  check("emit: multiblock warning is recorded in the header",
    src:find("warning:", 1, true) ~= nil and src:find(MULTI, 1, true) ~= nil)
end

-- ---- CLI (real files, real flag parsing) -----------------------------------
local TMP_JSON = "tests/.scan2plan_tmp.json"
local TMP_OUT = "tests/.scan2plan_tmp_out.lua"
do
  local f = assert(io.open(TMP_JSON, "wb"))
  f:write(SCAN)
  f:close()

  local p1, err1 = s2p.main({ TMP_JSON, TMP_OUT, "--quiet" })
  check("cli: default run compiles the file", p1 ~= nil and p1.count == 17, err1 or (p1 and p1.count))
  local mod = assert(loadfile(TMP_OUT))()
  check("cli: wrote a loadable plan module", #mod.blocks == 17 and mod.count == 17, #mod.blocks)

  local p2 = s2p.main({ TMP_JSON, TMP_OUT, "--skip", "minecraft:oak_planks", "--quiet" })
  check("cli: --skip <a,b> parsed", p2 ~= nil and p2.count == 12 and p2.materials[PLANKS] == nil,
    p2 and p2.count)

  local p3 = s2p.main({ TMP_JSON, TMP_OUT, "--only", PLANKS .. "," .. GRASS, "--quiet" })
  check("cli: --only <a,b> parsed", p3 ~= nil and p3.count == 6 and p3.materials[COBBLE] == nil,
    p3 and p3.count)

  local _, err4 = s2p.main({ TMP_JSON, "--quiet" })
  check("cli: missing outfile is an error", err4 ~= nil, err4)
  local _, err5 = s2p.main({ TMP_JSON, TMP_OUT, "--bogus" })
  check("cli: unknown flag is an error", err5 ~= nil, err5)
  local _, err6 = s2p.main({ "tests/.no_such_scan.json", TMP_OUT })
  check("cli: missing scan file is an error", err6 ~= nil, err6)

  os.remove(TMP_JSON)
  os.remove(TMP_OUT)
  check("cli: temp files cleaned up", io.open(TMP_JSON) == nil and io.open(TMP_OUT) == nil)
end

-- ---- the plan actually builds ----------------------------------------------
-- Same mock as tests/build_test.lua: a turtle that refuses to move into an
-- occupied cell, so a plan ordered badly enough to trap the turtle FAILS here.
do
  local DIRS = builder._internal.DIRS
  local m = { x = 0, y = 1, z = 0, f = 0, world = {}, placed = 0, inv = {} }
  for block, n in pairs(plan.materials) do m.inv[block] = n end
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  local function occupied(x, y, z) return m.world[key(x, y, z)] ~= nil end
  local ops = {
    up = function() if occupied(m.x, m.y + 1, m.z) then return false end m.y = m.y + 1 return true end,
    down = function()
      if occupied(m.x, m.y - 1, m.z) or m.y - 1 < 0 then return false end
      m.y = m.y - 1 return true
    end,
    forward = function()
      local nx, nz = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
      if occupied(nx, m.y, nz) then return false end
      m.x, m.z = nx, nz return true
    end,
    turnLeft = function() m.f = (m.f - 1) % 4 end,
    turnRight = function() m.f = (m.f + 1) % 4 end,
    ensure = function(block) return (m.inv[block] or 0) > 0 end,
    placeDown = function(block)
      local bx, by, bz = m.x, m.y - 1, m.z
      if occupied(bx, by, bz) or (m.inv[block] or 0) <= 0 then return false end
      m.inv[block] = m.inv[block] - 1
      m.world[key(bx, by, bz)] = block
      m.placed = m.placed + 1
      return true
    end,
  }
  local placed, err = builder.run(plan.blocks, ops)
  check("builder: runs the compiled plan to completion", err == nil and placed == plan.count,
    tostring(placed) .. "/" .. plan.count .. " err=" .. tostring(err))
  local mismatch
  for _, p in ipairs(plan.blocks) do
    if m.world[key(p.x, p.y, p.z)] ~= p.block then mismatch = key(p.x, p.y, p.z) end
  end
  check("builder: rebuilt world matches the scan (minus filtered cells)", mismatch == nil, mismatch)
  check("builder: the bill was exactly enough", (function()
    for _, n in pairs(m.inv) do if n ~= 0 then return false end end
    return true
  end)())
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
