-- planner: turns "I want N of item X" into an ordered list of crafting steps,
-- resolving recipes recursively against current stock and the recipe database.
local planner = {}

-- db:    recipedb module (loaded)
-- have:  map of item id -> count in stock (MUTATED during planning)
-- returns steps, or nil + missing map (item/ingredient -> shortfall)
-- each step: { output, recipe, times, picks = { gridSlot -> concrete item id } }
function planner.plan(db, have, targetId, targetCount)
  local steps = {}
  local missing = {}
  local path = {}

  local function need(itemId, amount)
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

    path[itemId] = true
    local recipe = recipes[1]
    local times = math.ceil(amount / recipe.count)

    local picks = {}
    local depTotals = {}
    local ok = true
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
        ok = false
        break
      end
      picks[slot] = chosen
      depTotals[chosen] = (depTotals[chosen] or 0) + times
    end

    if ok then
      for depId, depAmount in pairs(depTotals) do
        if not need(depId, depAmount) then ok = false end
      end
    end
    path[itemId] = nil
    if not ok then return false end

    steps[#steps + 1] = { output = itemId, recipe = recipe, times = times, picks = picks }
    have[itemId] = (have[itemId] or 0) + times * recipe.count - amount
    return true
  end

  if need(targetId, targetCount) then
    return steps
  end
  return nil, missing
end

return planner
