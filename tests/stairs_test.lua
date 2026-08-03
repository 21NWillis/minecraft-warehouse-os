-- headless brownfield test for towerstairs: run the staircase script inside
-- a mock world PRELOADED with the real paperclipHQ schematic (+ ground
-- floor), and prove it never touches the tower except the two sanctioned
-- ceiling digs, places every step, and ends in the head office.
package.path = "./?.lua;" .. package.path
_TEST = true
local stairs = require("towerstairs")
local schematic = require("schematic")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- ---------------------------------------------------------------- path data
-- every consecutive step must be humanly walkable: +1 rise, 1 block over
for i = 2, #stairs.PATH do
  local a, b = stairs.PATH[i - 1], stairs.PATH[i]
  local dy = b[2] - a[2]
  local dh = math.abs(b[1] - a[1]) + math.abs(b[3] - a[3])
  if not (dy == 1 and dh == 1) then
    check("path walkable at step " .. i, false,
      ("dy=%d dh=%d"):format(dy, dh))
  end
end
check("path is walkable end to end", true)
check("path rises ground to head-floor level",
  stairs.PATH[1][2] == 1 and stairs.PATH[#stairs.PATH][2] == 25)

-- ---------------------------------------------------------------- mock world
local key = function(x, y, z) return x .. "," .. y .. "," .. z end
local world = {}
for k, block in pairs(schematic.paperclipHQ().cells) do world[k] = block end
do -- ground floor as built by `buildrun pad 13 9` from the interior corner
  local pad = schematic.pad(13, 9, {})
  for k, block in pairs(pad.cells) do
    local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
    world[key(tonumber(x) + 1, tonumber(y), tonumber(z) + 1)] = block
  end
end

local slots = {
  { name = "minecraft:polished_blackstone", count = 21 },
  { name = "minecraft:glowstone", count = 3 },
}
local m = { x = stairs.START.x, y = stairs.START.y, z = stairs.START.z,
            f = stairs.START.f, sel = 1, digs = {}, placed = 0 }
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
local t = {
  turnLeft = function() m.f = (m.f + 3) % 4 end,
  turnRight = function() m.f = (m.f + 1) % 4 end,
  detect = function() return world[key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])] ~= nil end,
  detectUp = function() return world[key(m.x, m.y + 1, m.z)] ~= nil end,
  dig = function()
    local k = key(m.x + DIRS[m.f][1], m.y, m.z + DIRS[m.f][2])
    if world[k] then m.digs[#m.digs + 1] = k; world[k] = nil; return true end
    return false
  end,
  digUp = function()
    local k = key(m.x, m.y + 1, m.z)
    if world[k] then m.digs[#m.digs + 1] = k; world[k] = nil; return true end
    return false
  end,
  up = function()
    if world[key(m.x, m.y + 1, m.z)] then return false end
    m.y = m.y + 1
    return true
  end,
  forward = function()
    local nx, nz = m.x + DIRS[m.f][1], m.z + DIRS[m.f][2]
    if world[key(nx, m.y, nz)] then return false end
    m.x, m.z = nx, nz
    return true
  end,
  select = function(slot) m.sel = slot end,
  getItemDetail = function(slot)
    local s = slots[slot or m.sel]
    if s and s.count > 0 then return { name = s.name, count = s.count } end
    return nil
  end,
  inspectDown = function()
    local b = world[key(m.x, m.y - 1, m.z)]
    if b then return true, { name = b } end
    return false
  end,
  placeDown = function()
    local k = key(m.x, m.y - 1, m.z)
    local s = slots[m.sel]
    if world[k] or not s or s.count <= 0 then return false end
    s.count = s.count - 1
    world[k] = s.name
    m.placed = m.placed + 1
    return true
  end,
}

-- regression: a turtle placed facing OUT the door (the mirrored-build
-- incident) must be refused by the placement self-check, world untouched
do
  local saveF, saveX, saveZ = m.f, m.x, m.z
  m.f = 2                                     -- facing -z, out the door
  local before = 0
  for _ in pairs(world) do before = before + 1 end
  local ok2, err2 = stairs.run(t)
  local after = 0
  for _ in pairs(world) do after = after + 1 end
  check("mirrored placement is refused", not ok2 and tostring(err2):find("placement check") ~= nil, err2)
  check("refused run changes nothing", before == after and m.placed == 0)
  m.f, m.x, m.z = saveF, saveX, saveZ         -- back to the correct pose
end

local ok, err = stairs.run(t)
check("staircase builds clean in the real tower", ok, err)
check("placed all 24 steps", m.placed == 24, m.placed)
check("ends in the head office", m.x == 7 and m.y == 27 and m.z == 5,
  m.x .. "," .. m.y .. "," .. m.z)

-- only the two sanctioned ceiling blocks may be dug
local allowed = { [key(9, 7, 7)] = true, [key(8, 7, 7)] = true }
local rogue = nil
for _, k in ipairs(m.digs) do
  if not allowed[k] then rogue = k end
end
check("digs only the two shaft-mouth ceiling blocks", rogue == nil and #m.digs == 2,
  rogue or ("digs=" .. #m.digs))

-- every step cell holds the right material (incl. the kept roof block)
local wrong = nil
for i, p in ipairs(stairs.PATH) do
  local want = p[4] or "minecraft:purple_concrete"
  if world[key(p[1], p[2], p[3])] ~= want then
    wrong = i .. " has " .. tostring(world[key(p[1], p[2], p[3])])
  end
end
check("every step present with the right material", wrong == nil, wrong)

-- materials exactly consumed
check("used exactly 21 trim + 3 glow",
  slots[1].count == 0 and slots[2].count == 0,
  slots[1].count .. "/" .. slots[2].count)

-- headroom: the two cells above every step (standing space) must be clear
local blockedHead = nil
for i, p in ipairs(stairs.PATH) do
  for dy = 1, 2 do
    if world[key(p[1], p[2] + dy, p[3])] then
      blockedHead = i .. " at +" .. dy
    end
  end
end
check("full headroom over every step", blockedHead == nil, blockedHead)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
