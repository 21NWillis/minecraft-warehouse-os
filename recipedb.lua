-- recipedb: loads the compiled recipe/tag/name database
-- local db = require("recipedb")
-- db.load("data")  -- once at startup
local db = {}

local recipeLines = {}
local byOutput = {}   -- item id -> { line indexes }
local tags = {}       -- "c:ingots/iron" -> { concrete item ids }
local names = {}      -- item id -> display name

-- open a data file from disk, or stream it from the update base URL
-- (the 1MB computer disk can't hold the database; RAM can)
local function openLines(dir, fname)
  local path = fs.combine(dir, fname)
  if fs.exists(path) then return fs.open(path, "r") end
  if http and fs.exists(".updatebase") then
    local f = fs.open(".updatebase", "r")
    local base = f.readAll()
    f.close()
    return (http.get(base .. "data/" .. fname))
  end
end

local function eachLine(handle, fn)
  if not handle then return false end
  while true do
    local line = handle.readLine()
    if not line then break end
    if line ~= "" then fn(line) end
  end
  handle.close()
  return true
end

function db.load(dir)
  recipeLines, byOutput, tags, names = {}, {}, {}, {}
  local ok = eachLine(openLines(dir, "recipes.txt"), function(line)
    recipeLines[#recipeLines + 1] = line
    local out = line:match("^[SL]|([^|]+)|")
    if out then
      local list = byOutput[out]
      if not list then list = {}; byOutput[out] = list end
      list[#list + 1] = #recipeLines
    end
  end)
  if not ok then return false, "no recipes.txt on disk and no update base url for streaming" end
  eachLine(openLines(dir, "tags.txt"), function(line)
    local fields = {}
    for field in line:gmatch("[^|]+") do fields[#fields + 1] = field end
    local tag = table.remove(fields, 1):sub(2)
    tags[tag] = fields
  end)
  eachLine(openLines(dir, "names.txt"), function(line)
    local id, name = line:match("^([^\t]+)\t(.+)$")
    if id then names[id] = name end
  end)
  return true
end

function db.name(id)
  if names[id] then return names[id] end
  local pretty = id:gsub("^[^:]+:", ""):gsub("_", " ")
  return pretty:sub(1, 1):upper() .. pretty:sub(2)
end

function db.recipeCount()
  return #recipeLines
end

function db.isCraftable(id)
  return byOutput[id] ~= nil
end

-- ingredient string -> list of acceptable concrete item ids
function db.options(ing)
  if ing:sub(1, 1) == "#" then
    return tags[ing:sub(2)] or {}
  end
  if ing:find(";", 1, true) then
    local opts = {}
    for opt in ing:gmatch("[^;]+") do
      if opt:sub(1, 1) == "#" then
        for _, id in ipairs(tags[opt:sub(2)] or {}) do opts[#opts + 1] = id end
      else
        opts[#opts + 1] = opt
      end
    end
    return opts
  end
  return { ing }
end

local function parseLine(line)
  local fields = {}
  for field in (line .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = field end
  local recipe = {
    shaped = fields[1] == "S",
    output = fields[2],
    count = tonumber(fields[3]) or 1,
    grid = {},
  }
  for i = 4, #fields do
    recipe.grid[i - 3] = fields[i] ~= "" and fields[i] or nil
  end
  return recipe
end

function db.recipesFor(id)
  local result = {}
  for _, lineIdx in ipairs(byOutput[id] or {}) do
    result[#result + 1] = parseLine(recipeLines[lineIdx])
  end
  return result
end

-- search display names + id paths; returns list of item ids (craftable first)
function db.search(query, limit)
  query = query:lower()
  local hits = {}
  for id in pairs(byOutput) do
    local path = id:gsub("^[^:]+:", "")
    if path:find(query, 1, true) or db.name(id):lower():find(query, 1, true) then
      hits[#hits + 1] = id
      if limit and #hits >= limit then break end
    end
  end
  table.sort(hits, function(a, b) return #a < #b end)
  return hits
end

return db
