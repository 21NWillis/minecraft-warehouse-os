-- planner: turns "I want N of item X" into an ordered list of crafting steps,
-- resolving recipes recursively against current stock and the recipe database.
-- Tries up to MAX_RECIPE_TRIES recipes per item (best-stocked first) and rolls
-- back cleanly when a candidate recipe's tree dead-ends.
local planner = {}

local MAX_RECIPE_TRIES = 3

-- db:    recipedb module (loaded)
-- have:  map of item id -> count in stock (MUTATED during planning)
-- returns steps, or nil + missing map (item/ingredient -> shortfall)
-- each step: { output, recipe, times, picks = { gridSlot -> concrete item id } }
function planner.plan(db, have, targetId, targetCount)
  local steps = {}
  local missing = {}
  local path = {}

  local function snapshot()
    local copy = {}
    for k, v in pairs(have) do copy[k] = v end
    return copy
  end

  local function restore(copy, stepsMark)
    for k in pairs(have) do have[k] = nil end
    for k, v in pairs(copy) do have[k] = v end
    while #steps > stepsMark do steps[#steps] = nil end
  end

  local function recipeScore(recipe)
    local score = 0
    for _, ing in pairs(recipe.grid) do
      for _, opt in ipairs(db.options(ing)) do
        if (have[opt] or 0) > 0 then
          score = score + 1
          break
        end
      end
    end
    return score
  end

  local need

  local function tryRecipe(itemId, amount, recipe)
    local times = math.ceil(amount / recipe.count)
    local picks = {}
    local depTotals = {}
    for slot, ing in pairs(recipe.grid) do
      local opts = db.options(ing)
      local chosen
      for _, opt in ipairs(opts) do
        if (have[opt] or 0) > 0 then chosen = opt break end
      end
      if not chosen then
        for _, opt in ipairs(opts) do
          if db.isCraftable(opt) then chosen = opt break end
        end
      end
      chosen = chosen or opts[1]
      if not chosen then
        missing[ing] = (missing[ing] or 0) + times
        return false
      end
      picks[slot] = chosen
      depTotals[chosen] = (depTotals[chosen] or 0) + times
    end
    for depId, depAmount in pairs(depTotals) do
      if not need(depId, depAmount) then return false end
    end
    steps[#steps + 1] = { output = itemId, recipe = recipe, times = times, picks = picks }
    have[itemId] = (have[itemId] or 0) + times * recipe.count - amount
    return true
  end

  need = function(itemId, amount)
    local stock = have[itemId] or 0
    local take = math.min(stock, amount)
    have[itemId] = stock - take
    amount = amount - take
    if amount <= 0 then return true end

    if path[itemId] then
      missing[itemId] = (missing[itemId] or 0) + amount
      return false
    end
    local recipes = db.recipesFor(itemId)
    if #recipes == 0 then
      missing[itemId] = (missing[itemId] or 0) + amount
      return false
    end

    table.sort(recipes, function(a, b) return recipeScore(a) > recipeScore(b) end)

    path[itemId] = true
    local ok = false
    for attempt = 1, math.min(#recipes, MAX_RECIPE_TRIES) do
      local saved = snapshot()
      local mark = #steps
      if tryRecipe(itemId, amount, recipes[attempt]) then
        ok = true
        break
      end
      restore(saved, mark)
    end
    path[itemId] = nil
    if not ok then
      missing[itemId] = (missing[itemId] or 0) + amount
    end
    return ok
  end

  if need(targetId, targetCount) then
    return steps
  end
  return nil, missing
end

return planner
