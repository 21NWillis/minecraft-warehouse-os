-- conway test: the canonical correctness check - a glider translates by (1,1)
-- every 4 generations. Proves the step rule without a monitor.
package.path = "./?.lua;" .. package.path
local conway = require("conway")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local W, H = 30, 30   -- big enough that toroidal wrap doesn't interfere
local function seed(cells)
  local g = {}
  for _, c in ipairs(cells) do g[c[1] .. "," .. c[2]] = true end
  return g
end
local function keyset(g)
  local ks = {}
  for k in pairs(g) do ks[#ks + 1] = k end
  table.sort(ks)
  return table.concat(ks, " ")
end

local glider = { { 1, 0 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }
local g = seed(glider)
for _ = 1, 4 do g = conway.step(g, W, H) end

local shifted = {}
for _, c in ipairs(glider) do shifted[#shifted + 1] = { c[1] + 1, c[2] + 1 } end
check("glider translates by (1,1) after 4 generations",
  keyset(g) == keyset(seed(shifted)), keyset(g))

-- a blinker (3 in a row) oscillates with period 2
local blinker = seed({ { 5, 5 }, { 6, 5 }, { 7, 5 } })
local b1 = conway.step(blinker, W, H)
local b2 = conway.step(b1, W, H)
check("blinker returns to itself after 2 steps", keyset(b2) == keyset(blinker), keyset(b2))
check("blinker actually flips at step 1", keyset(b1) ~= keyset(blinker))

-- a lone cell dies
check("lone cell dies", next(conway.step(seed({ { 3, 3 } }), W, H)) == nil)

-- a 2x2 block is still life (stable)
local block = seed({ { 10, 10 }, { 11, 10 }, { 10, 11 }, { 11, 11 } })
check("2x2 block is stable", keyset(conway.step(block, W, H)) == keyset(block))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
