-- headless nursery test: the hatch loop against a mock boot spot -
-- placing, turning the newborn on, waiting for it to leave, the cap, the
-- restock stop, and the two ways a station goes wrong (stuck newborn,
-- missing drive/peripheral).
package.path = "./?.lua;" .. package.path
_TEST = true
local M = require("nursery")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- a boot spot in front of the nursery. cfg:
--   inv         slot list of {name=, count=}
--   leaveAfter  polls before the newborn walks off (math.huge = squatter)
--   occupied    spot already blocked at start
--   placeFails / noPeripheral / noTurnOn / wrapErrors / turnOnErrors
local function newMock(cfg)
  cfg = cfg or {}
  local m = {
    inv = cfg.inv or {}, sel = 0, occupied = cfg.occupied or false,
    places = 0, placed = 0, turnOns = 0, wrapSides = {},
    sleeps = 0, slept = 0, polls = 0, selected = {}, lines = {},
  }
  local leaveAfter = cfg.leaveAfter or 1
  local function newborn()
    if cfg.wrapErrors then error("no peripheral attached", 0) end
    if cfg.noPeripheral then return nil end
    local p = {}
    if not cfg.noTurnOn then
      p.turnOn = function()
        m.turnOns = m.turnOns + 1
        if cfg.turnOnErrors then error("turtle refused", 0) end
      end
    end
    return p
  end
  m.ops = {
    detect = function() return m.occupied end,
    select = function(s) m.sel = s; m.selected[#m.selected + 1] = s return true end,
    getItemDetail = function(s) return m.inv[s] end,
    place = function()
      m.places = m.places + 1
      if cfg.placeFails then return false end
      local d = m.inv[m.sel]
      if not d or d.count <= 0 or m.occupied then return false end
      d.count = d.count - 1
      if d.count <= 0 then m.inv[m.sel] = nil end
      m.occupied, m.polls = true, 0
      m.placed = m.placed + 1
      return true
    end,
    wrap = function(side)
      m.wrapSides[#m.wrapSides + 1] = side
      if not m.occupied then return nil end
      return newborn()
    end,
    sleep = function(n)
      m.sleeps, m.slept, m.polls = m.sleeps + 1, m.slept + n, m.polls + 1
      if m.polls >= leaveAfter then m.occupied = false end
      return true
    end,
  }
  m.log = function(line) m.lines[#m.lines + 1] = line end
  m.said = function(want)
    for _, l in ipairs(m.lines) do if l:find(want, 1, true) then return true end end
    return false
  end
  return m
end

local TURTLE = "computercraft:turtle_normal"
local function stack(n, name) return { { name = name or TURTLE, count = n } } end

-- ------------------------------------------------------------- item matching
check("turtle item recognised", M.isTurtleItem(TURTLE))
check("advanced turtle recognised", M.isTurtleItem("computercraft:turtle_advanced"))
check("coal is not a turtle", not M.isTurtleItem("minecraft:coal"))
check("nil name is not a turtle", not M.isTurtleItem(nil))

local slotMock = newMock({ inv = { { name = "minecraft:coal", count = 8 }, { name = TURTLE, count = 3 } } })
check("finds the turtle slot past the coal", M.findTurtleSlot(slotMock.ops) == 2,
  tostring(M.findTurtleSlot(slotMock.ops)))
check("no turtle slot when only coal",
  M.findTurtleSlot(newMock({ inv = { { name = "minecraft:coal", count = 8 } } }).ops) == nil)

-- ------------------------------------------------------------- a single hatch
local m = newMock({ inv = stack(1), leaveAfter = 2 })
local status, hatched = M.run(m.ops, { log = m.log })
check("one turtle -> one hatch then empty", status == "empty" and hatched == 1,
  tostring(status) .. "/" .. tostring(hatched))
check("placed exactly once", m.places == 1 and m.placed == 1, m.places)
check("newborn was turned on", m.turnOns == 1, m.turnOns)
check("wrapped the front face", m.wrapSides[1] == "front", tostring(m.wrapSides[1]))
check("no station warning on a clean hatch", not m.said("WARNING"))
check("counts out loud", m.said("nursery: 1 hatched"), table.concat(m.lines, " | "))

-- ------------------------------------------------------- restock / cap / count
local m2 = newMock({ inv = stack(4) })
local s2, h2 = M.run(m2.ops, { log = m2.log })
check("hatches the whole stack, then empty", s2 == "empty" and h2 == 4,
  tostring(s2) .. "/" .. tostring(h2))
check("hatch counter matches placements", m2.placed == 4 and m2.said("nursery: 4 hatched"), m2.placed)

local m3 = newMock({ inv = stack(5) })
local s3, h3 = M.run(m3.ops, { max = 3, log = m3.log })
check("count cap respected", s3 == "done" and h3 == 3 and m3.places == 3,
  tostring(s3) .. "/" .. tostring(h3) .. "/" .. m3.places)
check("cap leaves the rest in the inventory", m3.inv[1] and m3.inv[1].count == 2,
  m3.inv[1] and m3.inv[1].count)

local m4 = newMock({ inv = { { name = "minecraft:coal", count = 8 } } })
local s4, h4 = M.run(m4.ops, { log = m4.log })
check("no turtles -> empty with nothing placed", s4 == "empty" and h4 == 0 and m4.places == 0,
  tostring(s4) .. "/" .. m4.places)

-- ------------------------------------------------------------- the squatter
local m5 = newMock({ inv = stack(3), leaveAfter = math.huge })
local s5, h5, why5 = M.run(m5.ops, { timeout = 10, poll = 2, log = m5.log })
check("stuck newborn stops the run", s5 == "stuck" and h5 == 0, tostring(s5) .. "/" .. tostring(h5))
check("never places on top of a squatter", m5.places == 1, m5.places)
check("gives up after the configured timeout", m5.slept == 10 and m5.sleeps == 5,
  m5.slept .. "s in " .. m5.sleeps .. " polls")
check("says why it stopped", why5 and why5:find("10s", 1, true) ~= nil, tostring(why5))

-- a slow but honest newborn (49 polls) still hatches inside a 100s budget
local m6 = newMock({ inv = stack(1), leaveAfter = 49 })
local s6, h6 = M.run(m6.ops, { timeout = 100, poll = 2, log = m6.log })
check("slow newborn inside the budget still hatches", s6 == "empty" and h6 == 1,
  tostring(s6) .. "/" .. tostring(h6))

-- ---------------------------------------------------------- station problems
local m7 = newMock({ inv = stack(2), occupied = true })
local s7, h7 = M.run(m7.ops, { log = m7.log })
check("occupied spot at start -> blocked, nothing placed",
  s7 == "blocked" and h7 == 0 and m7.places == 0, tostring(s7) .. "/" .. m7.places)

local m8 = newMock({ inv = stack(2), placeFails = true })
local s8, h8 = M.run(m8.ops, { log = m8.log })
check("place refusal stops instead of looping",
  s8 == "placefail" and h8 == 0 and m8.places == 1, tostring(s8) .. "/" .. m8.places)

local m9 = newMock({ inv = stack(1), noPeripheral = true, leaveAfter = 1 })
local s9, h9 = M.run(m9.ops, { log = m9.log })
check("no front peripheral: warns but keeps waiting", s9 == "empty" and h9 == 1 and m9.said("WARNING"),
  tostring(s9) .. "/" .. tostring(h9))

local m10 = newMock({ inv = stack(1), noTurnOn = true })
local s10, h10 = M.run(m10.ops, { log = m10.log })
check("peripheral without turnOn: warns, still hatches",
  s10 == "empty" and h10 == 1 and m10.turnOns == 0 and m10.said("drive"),
  tostring(s10) .. "/" .. table.concat(m10.lines, " | "))

local m11 = newMock({ inv = stack(1), wrapErrors = true })
local s11, h11 = M.run(m11.ops, { log = m11.log })
check("a throwing wrap() does not kill the run", s11 == "empty" and h11 == 1 and m11.said("WARNING"),
  tostring(s11) .. "/" .. tostring(h11))

local m12 = newMock({ inv = stack(1), turnOnErrors = true })
local s12, h12 = M.run(m12.ops, { log = m12.log })
check("a throwing turnOn() does not kill the run",
  s12 == "empty" and h12 == 1 and m12.said("turnOn() failed"),
  tostring(s12) .. "/" .. table.concat(m12.lines, " | "))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
