-- headless build test: run the builder against a mock turtle+world and assert
-- the resulting structure matches the schematic exactly (every block placed
-- once, in the right cell, no self-trapping, turtle returns home).
package.path = "./?.lua;" .. package.path
local schematic = require("schematic")
local builder = require("builder")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- mock turtle: tracks pose in the same frame as the builder, records blocks it
-- places into a virtual world, and refuses to move into an occupied cell (so
-- a self-trapping plan would fail the navigation, not silently pass).
local DIRS = builder._internal.DIRS
local function newMock(materials)
  local m = {
    x = 0, y = 1, z = 0, f = 0,
    world = {}, placedCount = 0, moves = 0,
    inv = {}, selected = nil,
  }
  for block, n in pairs(materials or {}) do m.inv[block] = n end
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  local function occupied(x, y, z) return m.world[key(x, y, z)] ~= nil end
  m.ops = {
    up = function() if occupied(m.x, m.y + 1, m.z) then return false end m.y = m.y + 1; m.moves = m.moves + 1; return true end,
    down = function() if occupied(m.x, m.y - 1, m.z) or m.y - 1 < 0 then return false end m.y = m.y - 1; m.moves = m.moves + 1; return true end,
    forward = function()
      local nx, nz = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
      if occupied(nx, m.y, nz) then return false end
      m.x, m.z = nx, nz; m.moves = m.moves + 1; return true
    end,
    turnLeft = function() m.f = (m.f - 1) % 4 end,
    turnRight = function() m.f = (m.f + 1) % 4 end,
    ensure = function(block)
      if (m.inv[block] or 0) <= 0 then return false end
      m.selected = block; return true
    end,
    placeDown = function(block)
      local bx, by, bz = m.x, m.y - 1, m.z
      if occupied(bx, by, bz) then return false end
      if (m.inv[block] or 0) <= 0 then return false end
      m.inv[block] = m.inv[block] - 1
      m.world[key(bx, by, bz)] = block
      m.placedCount = m.placedCount + 1
      return true
    end,
  }
  m.key = key
  return m
end

local function verify(name, s, materials)
  local plan = s:plan()
  local mock = newMock(materials or s:materials())
  local placed, err = builder.run(plan, mock.ops)
  check(name .. ": completes without error", err == nil, err)
  check(name .. ": placed all blocks", placed == s:count(), placed .. "/" .. s:count())
  -- world must match schematic cell-for-cell
  local mismatch = nil
  for k, block in pairs(s.cells) do
    if mock.world[k] ~= block then mismatch = k .. " want " .. block .. " got " .. tostring(mock.world[k]) end
  end
  for k, block in pairs(mock.world) do
    if s.cells[k] ~= block then mismatch = mismatch or ("extra " .. k) end
  end
  check(name .. ": world matches schematic exactly", mismatch == nil, mismatch)
  check(name .. ": turtle returned to origin xz", mock.x == 0 and mock.z == 0,
    ("at %d,%d"):format(mock.x, mock.z))
  return mock
end

verify("floor 5x5", schematic.floor(5, 5, "minecraft:stone"))
verify("hollow box 5x4x5 w/ floor", schematic.hollowBox(5, 4, 5, "minecraft:stone", { floor = true }))
verify("solid 3x3x3", schematic.solid(3, 3, 3, "minecraft:dirt"))
verify("cylinder r4 h6", schematic.cylinder(4, 6, "minecraft:glass"))
verify("evil HQ 9x20", schematic.evilTower(9, 20))

-- out-of-material stops cleanly partway (no crash, reports remaining)
do
  local s = schematic.floor(4, 4, "minecraft:stone")  -- needs 16
  local plan = s:plan()
  local mock = newMock({ ["minecraft:stone"] = 10 })
  local placed, err = builder.run(plan, mock.ops)
  check("stops when material runs out", err ~= nil and placed == 10, (placed or "?") .. " / err=" .. tostring(err))
end

-- resume: a partial build parks at a deterministic pose; builder.resume picks
-- up from that pose, binary-searches for the first missing block, and
-- finishes without re-placing anything - restock-and-resume is idempotent
do
  local s = schematic.hollowBox(5, 4, 5, "minecraft:stone", { floor = true })
  local plan = s:plan()
  local mock = newMock({ ["minecraft:stone"] = 20 })      -- runs dry partway
  mock.ops.checkDown = function(block)
    return mock.world[mock.key(mock.x, mock.y - 1, mock.z)] == block
  end
  local placed1, err1, pose1 = builder.run(plan, mock.ops)
  check("partial build stopped", err1 ~= nil and placed1 == 20, tostring(placed1))
  check("park pose matches the physical turtle", pose1 ~= nil
    and pose1.x == mock.x and pose1.y == mock.y and pose1.z == mock.z,
    pose1 and ("%d,%d,%d vs %d,%d,%d"):format(pose1.x, pose1.y, pose1.z, mock.x, mock.y, mock.z))
  mock.inv["minecraft:stone"] = 999                        -- restock, resume
  local placed2, err2 = builder.resume(plan, mock.ops, nil, pose1)
  check("resume completes the partial build", err2 == nil and placed2 == #plan,
    tostring(placed2) .. "/" .. #plan .. " err=" .. tostring(err2))
  check("resume placed only the missing blocks", mock.placedCount == s:count(),
    mock.placedCount .. "/" .. s:count())
  local mismatch
  for k, block in pairs(s.cells) do
    if mock.world[k] ~= block then mismatch = k end
  end
  check("resumed world matches schematic", mismatch == nil, mismatch)
end

-- network-refill: a turtle whose hold is far too small still completes a large
-- build by docking to restock (ops.dock tops it up, like an ender chest at home)
do
  local s = schematic.solid(6, 6, 6, "minecraft:stone")  -- 216 blocks
  local plan = s:plan()
  local mock = newMock({ ["minecraft:stone"] = 32 })       -- only 32 in hold
  local dockRuns = 0
  mock.ops.dock = function(block)
    dockRuns = dockRuns + 1
    mock.inv[block] = (mock.inv[block] or 0) + 64            -- restock a stack
  end
  local placed, err = builder.run(plan, mock.ops)
  check("refill build completes despite tiny hold", err == nil and placed == 216,
    (placed or "?") .. "/216 err=" .. tostring(err))
  check("refill build matched (docked " .. dockRuns .. "x)", (function()
    for k, b in pairs(s.cells) do if mock.world[k] ~= b then return false end end
    return true
  end)(), "dockRuns=" .. dockRuns)
end

-- Paperclip Corp HQ: multi-material, cantilevered head, rooftop fin - the
-- hardest geometry we generate. Exact-match build proves the whole thing.
do
  local s = schematic.paperclipHQ()
  local mock = verify("paperclip HQ", s)
  local mats = s:materials()
  local kinds = 0
  for _ in pairs(mats) do kinds = kinds + 1 end
  check("paperclip HQ uses 4 materials", kinds == 4, kinds)
  check("paperclip HQ has a lit P + sign band",
    (mats["minecraft:sea_lantern"] or 0) >= 40, mats["minecraft:sea_lantern"])
  -- the head must actually overhang: a solid cell at head-floor level whose
  -- support column below is air all the way to the base roof
  local hasOverhang = s:get(2, 26, 5) ~= nil
  for y = 8, 25 do
    if s:get(2, y, 5) ~= nil then hasOverhang = false end
  end
  check("paperclip HQ head cantilevers past the shaft", hasOverhang)
  print(("      (HQ: %d blocks, %d turtle moves)"):format(s:count(), mock.moves))
end

-- anchor resume: no saved pose at all - the turtle is physically re-placed
-- on top of the origin column and resume runs from builder.anchorPose
do
  local s = schematic.hollowBox(5, 4, 5, "minecraft:stone", { floor = true })
  local plan = s:plan()
  local mock = newMock({ ["minecraft:stone"] = 68 })      -- dies 5 short
  mock.ops.checkDown = function(block)
    return mock.world[mock.key(mock.x, mock.y - 1, mock.z)] == block
  end
  local placed1 = builder.run(plan, mock.ops)
  check("anchor scenario: died near the end", placed1 == 68, placed1)
  local anchor = builder.anchorPose(plan)
  check("anchor pose tops the origin column", anchor.y == 4, anchor.y)
  -- simulate the player placing the turtle at the anchor spot
  mock.x, mock.y, mock.z, mock.f = anchor.x, anchor.y, anchor.z, anchor.f
  mock.inv["minecraft:stone"] = 99
  local placed2, err2 = builder.resume(plan, mock.ops, nil,
    { x = anchor.x, y = anchor.y, z = anchor.z, f = anchor.f })
  check("anchor resume completes", err2 == nil and placed2 == #plan,
    tostring(placed2) .. "/" .. #plan .. " err=" .. tostring(err2))
  local mismatch
  for k, block in pairs(s.cells) do
    if mock.world[k] ~= block then mismatch = k end
  end
  check("anchor-resumed world matches schematic", mismatch == nil, mismatch)
end

-- big structure: 16x10x16 hollow tower, sanity on scale
do
  local s = schematic.hollowBox(16, 10, 16, "minecraft:stone", { floor = true, roof = true })
  local mock = verify("tower 16x10x16", s)
  print(("      (tower: %d blocks, %d turtle moves)"):format(s:count(), mock.moves))
end

-- ADJUDICATED 2026-08-08 (two outside reviews, unanimous): binary-search
-- resume must NEVER conclude completion from probes alone. World state can
-- violate the strict-prefix assumption (matching blocks beyond the stop
-- point make every probe read "placed" and the search overshoot the hole).
-- The fix: "probes say done" falls back to a full in-order verification
-- pass. This is the minimal counterexample from the adjudication.
do
  local plan = {
    { x = 0, y = 0, z = 0, block = "minecraft:stone" },
    { x = 1, y = 0, z = 0, block = "minecraft:stone" },
    { x = 2, y = 0, z = 0, block = "minecraft:stone" },
    { x = 3, y = 0, z = 0, block = "minecraft:stone" },
  }
  local mock = newMock({ ["minecraft:stone"] = 5 })
  mock.ops.checkDown = function(block)
    return mock.world[mock.key(mock.x, mock.y - 1, mock.z)] == block
  end
  -- world: index 1 placed, index 2 MISSING, indices 3-4 pre-existing
  -- (non-monotonic predicate: probes at 3 and 4 both read "placed")
  mock.world[mock.key(0, 0, 0)] = "minecraft:stone"
  mock.world[mock.key(2, 0, 0)] = "minecraft:stone"
  mock.world[mock.key(3, 0, 0)] = "minecraft:stone"
  local pose = { x = 0, y = 1, z = 0, f = 0 }
  local placed, err = builder.resume(plan, mock.ops, nil, pose)
  check("overshoot resume does not falsely report done", err == nil, err)
  check("overshoot resume fills the buried hole",
    mock.world[mock.key(1, 0, 0)] == "minecraft:stone",
    "index 2 cell still empty")
end

-- pose must travel with resume errors: a caller persisting the park file
-- would otherwise trust a stale pose while the turtle physically moved
do
  local plan = { { x = 0, y = 0, z = 0, block = "minecraft:stone" } }
  local mock = newMock({})
  local pose = { x = 0, y = 1, z = 0, f = 0 }
  local placed, err, epose = builder.resume(plan, mock.ops, nil, pose)
  check("resume without checkDown errors WITH a pose",
    err ~= nil and epose ~= nil, tostring(err) .. " pose=" .. tostring(epose))
end
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
