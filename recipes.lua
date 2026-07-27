-- recipes <search text>: look up crafting recipes from the compiled database
-- example: recipes iron gear
local db = require("recipedb")

local args = { ... }
if #args == 0 then
  print("usage: recipes <item name>")
  return
end

local ok, err = db.load("data")
if not ok then
  print(err)
  print("deploy data/recipes.txt, tags.txt, names.txt first")
  return
end

local query = table.concat(args, " ")
local hits = db.search(query, 50)
if #hits == 0 then
  print("no craftable item matches '" .. query .. "'")
  return
end

local id = hits[1]
if #hits > 1 then
  print("matches: " .. db.name(hits[1]) .. (#hits > 2 and (" (+" .. (#hits - 1) .. " more)") or ""))
end

local function ingLabel(ing, legend)
  if not ing then return "." end
  if not legend[ing] then
    local n = 0
    for _ in pairs(legend) do n = n + 1 end
    legend[ing] = string.char(65 + n)
  end
  return legend[ing]
end

for i, r in ipairs(db.recipesFor(id)) do
  print("")
  print(("[%d] %s x%d  (%s)"):format(i, db.name(r.output), r.count, r.shaped and "shaped" or "shapeless"))
  local legend = {}
  if r.shaped then
    for row = 0, 2 do
      local cells = {}
      for col = 1, 3 do
        cells[col] = ingLabel(r.grid[row * 3 + col], legend)
      end
      print("  " .. table.concat(cells, " "))
    end
  else
    local cells = {}
    for _, ing in pairs(r.grid) do cells[#cells + 1] = ingLabel(ing, legend) end
    print("  " .. table.concat(cells, " "))
  end
  local keys = {}
  for ing, letter in pairs(legend) do keys[#keys + 1] = { letter = letter, ing = ing } end
  table.sort(keys, function(a, b) return a.letter < b.letter end)
  for _, k in ipairs(keys) do
    local label
    if k.ing:sub(1, 1) == "#" or k.ing:find(";", 1, true) then
      local opts = db.options(k.ing)
      label = #opts > 0 and (db.name(opts[1]) .. " (or " .. (#opts - 1) .. " alternatives)") or ("UNRESOLVED " .. k.ing)
    else
      label = db.name(k.ing)
    end
    print("  " .. k.letter .. " = " .. label)
  end
  if i >= 3 then
    print("(more recipes exist; showing first 3)")
    break
  end
end
