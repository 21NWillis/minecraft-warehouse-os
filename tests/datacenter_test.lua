-- headless tests for the void campus: layout invariants (sites can't overlap,
-- corridor stays clear, the portal hole lines up with the datum) and a full
-- mock-turtle build of every site's schematic.
package.path = "./?.lua;" .. package.path
_TEST = true
local dc = require("datacenter")
local schematic = require("schematic")
local builder = require("builder")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

check("campus has all six sites", #dc.SITES == 6, #dc.SITES)

-- ---------------------------------------------------------------- layout
local bounds = {}
for _, site in ipairs(dc.SITES) do bounds[site.key] = dc.bounds(site) end

for i = 1, #dc.SITES do
  for j = i + 1, #dc.SITES do
    local a, b = bounds[dc.SITES[i].key], bounds[dc.SITES[j].key]
    local overlap = a.x1 <= b.x2 and b.x1 <= a.x2 and a.z1 <= b.z2 and b.z1 <= a.z2
    check(("no overlap: %s vs %s"):format(dc.SITES[i].key, dc.SITES[j].key),
      not overlap)
  end
end

for _, site in ipairs(dc.SITES) do
  local b = bounds[site.key]
  check(site.key .. " stays under the flight corridor", b.y2 < dc.CORRIDOR_Y,
    b.y2 .. " vs " .. dc.CORRIDOR_Y)
  check(site.key .. " sits on the campus ground plane", b.y1 == -1, b.y1)
end

-- the portal hole: pad local (8,8) must map exactly onto datum (0,?,0), and
-- the pad floor cell there must be open so the portal block survives
local pad = dc.site("pad")
check("pad hole aligns with the portal",
  pad.at[1] + 8 == 0 and pad.at[3] + 8 == 0)
check("pad leaves the portal cell open", pad.gen():get(8, 0, 8) == nil)

-- the datum column (turtle start + climb to corridor) must be clear of every
-- schematic, or homecoming would crash into a roof
for _, site in ipairs(dc.SITES) do
  local b = bounds[site.key]
  local clear = true
  if b.x1 <= 0 and 0 <= b.x2 and b.z1 <= 0 and 0 <= b.z2 then
    local s = site.gen()
    for y = 0, dc.CORRIDOR_Y do
      if s:get(0 - site.at[1], y - site.at[2], 0 - site.at[3]) ~= nil then
        clear = false
      end
    end
  end
  check(site.key .. " keeps the datum column clear", clear)
end

-- door and channel geometry
local noc = dc.site("noc").gen()
check("noc doorway is open", noc:get(4, 2, 0) == nil)
check("noc wall beside doorway is solid", noc:get(2, 2, 0) ~= nil)
local wh = dc.site("warehouse").gen()
check("warehouse doorway faces the plaza (-x)", wh:get(0, 2, 6) == nil)
local casino = dc.site("casino").gen()
check("casino channels are open", casino:get(1, 1, 1) == nil and casino:get(2, 1, 1) == nil)
check("casino walkways are solid", casino:get(3, 1, 1) ~= nil)
check("casino underlayer is watertight", casino:get(1, 0, 1) ~= nil)

-- ---------------------------------------------------------------- buildable
-- every site must build exactly in the mock world (same harness as build_test)
local DIRS = builder._internal.DIRS
local function newMock(materials)
  local m = { x = 0, y = 1, z = 0, f = 0, world = {}, inv = {} }
  for block, n in pairs(materials) do m.inv[block] = n end
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  local function occupied(x, y, z) return m.world[key(x, y, z)] ~= nil end
  m.ops = {
    up = function() if occupied(m.x, m.y + 1, m.z) then return false end m.y = m.y + 1; return true end,
    down = function() if occupied(m.x, m.y - 1, m.z) or m.y - 1 < 0 then return false end m.y = m.y - 1; return true end,
    forward = function()
      local nx, nz = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
      if occupied(nx, m.y, nz) then return false end
      m.x, m.z = nx, nz; return true
    end,
    turnLeft = function() m.f = (m.f - 1) % 4 end,
    turnRight = function() m.f = (m.f + 1) % 4 end,
    ensure = function(block) return (m.inv[block] or 0) > 0 end,
    placeDown = function(block)
      if occupied(m.x, m.y - 1, m.z) or (m.inv[block] or 0) <= 0 then return false end
      m.inv[block] = m.inv[block] - 1
      m.world[key(m.x, m.y - 1, m.z)] = block
      return true
    end,
  }
  m.key = key
  return m
end

for _, site in ipairs(dc.SITES) do
  local s = site.gen()
  local mock = newMock(s:materials())
  local placed, err = builder.run(s:plan(), mock.ops)
  check(site.key .. " builds clean in mock", err == nil and placed == s:count(),
    tostring(err) .. " " .. tostring(placed) .. "/" .. s:count())
  local mismatch
  for k, block in pairs(s.cells) do
    if mock.world[k] ~= block then mismatch = k end
  end
  check(site.key .. " world matches schematic", mismatch == nil, mismatch)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
