-- headless test suite: run from cc-scripts/ with
--   lua54 tests/run.lua
-- exercises recipedb + planner against the REAL compiled database.

package.path = "./?.lua;" .. package.path
dofile("tests/mock_cc.lua")

local passed, failed = 0, 0
local function check(name, condition, detail)
  if condition then
    passed = passed + 1
    print("PASS  " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end

-- ---------------------------------------------------------------- recipedb
local db = require("recipedb")
local t0 = os.clock()
local ok, err = db.load("data")
local loadSecs = os.clock() - t0
check("db loads", ok, err)
print(("      (load took %.2fs)"):format(loadSecs))

check("recipe count sane", db.recipeCount() > 20000, db.recipeCount())
check("display name lookup", db.name("minecraft:iron_ingot") == "Iron Ingot",
  db.name("minecraft:iron_ingot"))
check("chest is craftable", db.isCraftable("minecraft:chest"))
check("bedrock is not craftable", not db.isCraftable("minecraft:bedrock"))

local ironOpts = db.options("#c:ingots/iron")
check("iron ingot tag resolves", #ironOpts > 0 and ironOpts[1]:find("iron"),
  #ironOpts .. " options")

local hits = db.search("iron ingot", 20)
local found = false
for _, id in ipairs(hits) do
  if id == "minecraft:iron_ingot" then found = true end
end
check("search finds iron ingot", found, #hits .. " hits")

local chestRecipes = db.recipesFor("minecraft:chest")
check("chest has recipes", #chestRecipes > 0, #chestRecipes)
local maxSlots = 0
for _, r in ipairs(chestRecipes) do
  local slots = 0
  for _ in pairs(r.grid) do slots = slots + 1 end
  if slots > maxSlots then maxSlots = slots end
end
check("a chest recipe has 8 ingredients", maxSlots == 8, maxSlots)
-- vanilla-first ordering should surface the 8-plank recipe at #1
local firstSlots = 0
for _ in pairs(chestRecipes[1].grid) do firstSlots = firstSlots + 1 end
check("vanilla chest recipe sorts first", firstSlots == 8, firstSlots)

-- ----------------------------------------------------------------- planner
local planner = require("planner")

-- direct craft from stock
local have = { ["minecraft:oak_planks"] = 64 }
local steps, missing, stats = planner.plan(db, have, "minecraft:chest", 1)
check("plan chest from planks", steps and #steps == 1,
  steps and #steps or next(missing or {}))
check("cache stats: 8 planks served, 1 chest crafted",
  stats and stats.served == 8 and stats.crafted == 1,
  stats and (stats.served .. "/" .. stats.crafted))
if steps then
  check("chest step targets chest", steps[1].output == "minecraft:chest",
    steps[1].output)
end

-- recursive: logs -> planks -> crafting table
have = { ["minecraft:oak_log"] = 64 }
steps = planner.plan(db, have, "minecraft:crafting_table", 1)
check("plan crafting table from logs", steps ~= nil)
if steps then
  local sawPlanks, planksBeforeTable = false, false
  for i, step in ipairs(steps) do
    if step.output:find("planks") then
      sawPlanks = true
      planksBeforeTable = true
    end
    if step.output == "minecraft:crafting_table" then
      check("table is final step", i == #steps, i .. "/" .. #steps)
      break
    end
  end
  check("plan includes planks step", sawPlanks and planksBeforeTable)
end

-- multi-count: 2 chests need 16 planks -> times should scale
have = { ["minecraft:oak_planks"] = 64 }
steps = planner.plan(db, have, "minecraft:chest", 2)
check("plan 2 chests", steps and steps[#steps].times == 2,
  steps and steps[#steps].times)

-- impossible: nothing in stock, raw materials unobtainable
have = {}
steps, missing = planner.plan(db, have, "minecraft:piston", 1)
local missingCount = 0
for _ in pairs(missing or {}) do missingCount = missingCount + 1 end
check("piston from nothing fails with missing list", steps == nil and missingCount > 0,
  missingCount .. " missing")

-- deep modded recipe: plan something from the pack if craftable
local target = "computercraft:computer_normal"
if db.isCraftable(target) then
  have = { ["minecraft:stone"] = 64, ["minecraft:redstone"] = 64, ["minecraft:glass_pane"] = 64 }
  steps, missing = planner.plan(db, have, target, 1)
  check("plan CC computer from parts", steps ~= nil,
    not steps and next(missing or {}) or (#steps .. " steps"))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
