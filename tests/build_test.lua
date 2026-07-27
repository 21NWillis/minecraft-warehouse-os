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

-- out-of-material stops cleanly partway (no crash, reports remaining)
do
  local s = schematic.floor(4, 4, "minecraft:stone")  -- needs 16
  local plan = s:plan()
  local mock = newMock({ ["minecraft:stone"] = 10 })
  local placed, err = builder.run(plan, mock.ops)
  check("stops when material runs out", err ~= nil and placed == 10, (placed or "?") .. " / err=" .. tostring(err))
end

-- big structure: 16x10x16 hollow tower, sanity on scale
do
  local s = schematic.hollowBox(16, 10, 16, "minecraft:stone", { floor = true, roof = true })
  local mock = verify("tower 16x10x16", s)
  print(("      (tower: %d blocks, %d turtle moves)"):format(s:count(), mock.moves))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
