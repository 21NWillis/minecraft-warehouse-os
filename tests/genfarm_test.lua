-- headless genfarm test: the bay-order generator that flies the player
-- (Lens OrderExecutor) over the printer bays. The one thing that must
-- never regress: the farmland layer flies at chest altitude, so every
-- straight-line leg of the flight path must clear the bay chest column
-- at center (5,5) horizontally. Player half-width 0.3 + chest
-- half-width 0.44 = 0.74 minimum; the route is built to keep 1.0.
package.path = "./?.lua;./tools/?.lua;" .. package.path
_TEST = true
local G = require("genfarm")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- invert the world-offset transform back to bay-frame (row, col, y):
-- offset(fx,fy,fz) = (fz,fy,fx), fx = bayX+row, fz = Z0+col
local function frameOf(k, b)
  return b.z - G.bayX(k), b.x - G.Z0, b.y
end

-- min distance from segment (r1,c1)-(r2,c2) to the chest center (5,5)
local function segDist(r1, c1, r2, c2)
  local dr, dc = r2 - r1, c2 - c1
  local len2 = dr * dr + dc * dc
  local t = 0
  if len2 > 0 then
    t = math.max(0, math.min(1, ((5 - r1) * dr + (5 - c1) * dc) / len2))
  end
  local pr, pc = r1 + t * dr, c1 + t * dc
  return math.sqrt((pr - 5) ^ 2 + (pc - 5) ^ 2)
end

for k = 1, #G.BAYS do
  local blocks = G.genBayOrder(k)
  local farm, seed = {}, {}
  local waterHit, orderOk = false, true
  for i, b in ipairs(blocks) do
    local row, col, y = frameOf(k, b)
    if G.WATERSET[row .. "," .. col] then waterHit = true end
    if y == G.SLAB_Y + 1 then
      if #seed > 0 then orderOk = false end   -- farmland after seeds = bad
      farm[#farm + 1] = { row = row, col = col, i = i }
    else
      seed[#seed + 1] = { row = row, col = col, i = i }
    end
  end
  if k == 1 then
    check("bay 1: 76 farmland + 76 seeds", #farm == 76 and #seed == 76,
      #farm .. "+" .. #seed)
    check("bay 1: no block in a water cell", not waterHit)
    check("bay 1: strict farmland-before-seeds", orderOk)
    check("bay 1: farmland is the right tier",
      blocks[1].b == "mysticalagriculture:supremium_farmland", blocks[1].b)
    check("bay 1: every cell covered exactly once", (function()
      local seen = {}
      for _, f in ipairs(farm) do
        local key = f.row .. "," .. f.col
        if seen[key] then return false end
        seen[key] = true
      end
      local n = 0
      for _ in pairs(seen) do n = n + 1 end
      return n == 76
    end)())
  end

  -- THE invariant: every consecutive leg that flies at chest altitude
  -- (all farmland legs + the final farmland->seed climb) keeps >= 0.99
  -- horizontal distance from the chest column
  local worst, worstLeg = math.huge, ""
  for i = 2, #farm do
    local a, b = farm[i - 1], farm[i]
    local d = segDist(a.row, a.col, b.row, b.col)
    if d < worst then
      worst = d
      worstLeg = ("(%d,%d)->(%d,%d)"):format(a.row, a.col, b.row, b.col)
    end
  end
  local lastF, firstS = farm[#farm], seed[1]
  local dClimb = segDist(lastF.row, lastF.col, firstS.row, firstS.col)
  if dClimb < worst then
    worst = dClimb
    worstLeg = ("climb (%d,%d)->(%d,%d)"):format(lastF.row, lastF.col,
      firstS.row, firstS.col)
  end
  check(("bay %d: all chest-altitude legs clear the chest"):format(k),
    worst >= 0.99, ("worst %.2f at %s"):format(worst, worstLeg))
end

-- the emitted JSON round-trips through the same shape BuildOrder reads
local blocks = G.genBayOrder(1)
local json = G.emit("BAY 1 TEST", blocks)
check("emit: has name and fromDatum", json:find('"name":"BAY 1 TEST"') ~= nil
  and json:find('"fromDatum":%[0,0,0%]') ~= nil)
local n = select(2, json:gsub('"b":', ""))
check("emit: one entry per block", n == #blocks, n)

-- regression pin for the exact bug: the old west-end (9,4) -> north-arm
-- (1,5) diagonal passed 0.49 from the chest and clipped it
check("regression: the old diagonal really was a clip", segDist(9, 4, 1, 5) < 0.74,
  segDist(9, 4, 1, 5))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
