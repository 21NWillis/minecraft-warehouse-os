-- headless test for warehousefit: mock world with the real warehouse hall at
-- its campus offset; prove the storage core lands exactly on plan, the
-- floppy goes in the drive, no collisions, clean datum return.
package.path = "./?.lua;" .. package.path
_TEST = true
local campus = require("campus")
local wfit = require("warehousefit")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local site = campus.site("warehouse")
local at = site.at
local key = function(x, y, z) return x .. "," .. y .. "," .. z end
local world = {}
local function loadSite(s)
  for k, block in pairs(s.gen().cells) do
    local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
    world[key(tonumber(x) + s.at[1], tonumber(y) + s.at[2], tonumber(z) + s.at[3])] = block
  end
end
loadSite(site)
loadSite(campus.site("casino"))   -- the frame-check probe must find the deck

local slots = {
  { name = "sophisticatedstorage:barrel", count = 18 },
  { name = "sophisticatedstorage:controller", count = 1 },
  { name = "computercraft:computer_normal", count = 1 },
  { name = "computercraft:wired_modem_full", count = 1 },
  { name = "computercraft:disk_drive", count = 1 },
  { name = "computercraft:disk", count = 1 },
}
local m = { x = 0, y = 0, z = 0, f = 0, sel = 1, dropped = nil }
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
local function ahead() return m.x + DIRS[m.f][1], m.z + DIRS[m.f][2] end
local t = {
  turnLeft = function() m.f = (m.f + 3) % 4 end,
  turnRight = function() m.f = (m.f + 1) % 4 end,
  up = function()
    if world[key(m.x, m.y + 1, m.z)] then return false end
    m.y = m.y + 1; return true
  end,
  down = function()
    if world[key(m.x, m.y - 1, m.z)] then return false end
    m.y = m.y - 1; return true
  end,
  forward = function()
    local nx, nz = ahead()
    if world[key(nx, m.y, nz)] then return false end
    m.x, m.z = nx, nz; return true
  end,
  select = function(s) m.sel = s end,
  getItemDetail = function(s)
    local it = slots[s or m.sel]
    if it and it.count > 0 then return { name = it.name, count = it.count } end
  end,
  inspect = function()
    local nx, nz = ahead()
    local b = world[key(nx, m.y, nz)]
    if b then return true, { name = b } end
    return false
  end,
  detectDown = function() return world[key(m.x, m.y - 1, m.z)] ~= nil end,
  place = function()
    local nx, nz = ahead()
    local k = key(nx, m.y, nz)
    local it = slots[m.sel]
    if world[k] or not it or it.count <= 0 then return false end
    it.count = it.count - 1
    world[k] = it.name
    return true
  end,
  drop = function()
    local nx, nz = ahead()
    local it = slots[m.sel]
    if world[key(nx, m.y, nz)] == "computercraft:disk_drive" and it and it.count > 0 then
      it.count = it.count - 1
      m.dropped = it.name
      return true
    end
    return false
  end,
}

local ok, res = wfit.run(t)
check("warehousefit completes", ok == true, tostring(res))
check("returns to the datum", m.x == 0 and m.y == 0 and m.z == 0,
  m.x .. "," .. m.y .. "," .. m.z)

local wrong = nil
for i, p in ipairs(wfit.PLAN) do
  if world[key(at[1] + p[1], at[2] + p[2], at[3] + p[3])] ~= p[4] then
    wrong = i .. " wants " .. p[4]
  end
end
check("every core block on plan (" .. #wfit.PLAN .. ")", wrong == nil, wrong)
check("nothing blocks the doorway walk cells", (function()
  for _, p in ipairs(wfit.PLAN) do
    if p[3] >= 5 and p[3] <= 7 and p[2] <= 2 then return false end
  end
  return true
end)())
check("floppy inserted into the drive", m.dropped == "computercraft:disk", m.dropped)
check("materials exactly consumed", (function()
  for _, it in ipairs(slots) do if it.count > 0 then return false end end
  return true
end)())

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
