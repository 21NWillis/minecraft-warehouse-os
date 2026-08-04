-- scan2plan: compile a survey scan (SURVEY FORMAT v1, see surveylogic.lua)
-- into a buildable plan module the builder pipeline can run. This closes the
-- loop: survey.lua reads the world -> scan2plan compiles it -> builder.run
-- rebuilds it anywhere. Any structure a turtle can walk around can be cloned.
--
-- OFFLINE TOOL: plain Lua 5.4 on the dev machine, no libraries (its own tiny
-- JSON reader), never uploaded to a computer.
--
--   lua54 tools/scan2plan.lua <scan.json> <out.lua>
--        [--skip <blockId,blockId,...>] [--only <blockId,...>]
--
-- FRAMES LINE UP EXACTLY - no transform is applied. survey's frame is "x to
-- the turtle's RIGHT, z along its start facing, y UP, origin = its own cell";
-- builder's frame is "origin corner, facing +z, f=1 is +x" (builder.DIRS).
-- Same handedness, same origin, so scan (x,y,z) IS plan (x,y,z): park the
-- build turtle where the survey turtle stood, facing the way it faced, and
-- the copy lands on the original.
--
-- OUTPUT (a loadable Lua module, drop it next to buildrun/datacenter):
--   return { w=, l=, h=, count=, blocks = { {x=,y=,z=,block=}, ... },
--            materials = { [blockId] = n } }
-- blocks are in builder order: bottom layer first, serpentine rows within a
-- layer, so the turtle always flies ABOVE finished work and places downward.
--
-- WHAT IS DROPPED (a scan is world truth, not a parts list):
--   air (0), never-seen (-1) and entity-blocked (-2) cells;
--   ids containing "multiblock_structure" - those are formed-structure ghost
--   blocks with no item form, so they are ALWAYS excluded, with a warning;
--   terrain noise (grass/dirt/stone by default) and anything --skip lists;
--   everything but --only, when --only is given.
local M = {}

-- terrain a scan of an outdoor build is full of and nobody wants rebuilt
M.DEFAULT_SKIP = {
  "minecraft:grass_block",
  "minecraft:dirt",
  "minecraft:stone",
}

-- formed multiblocks (IE/Mekanism/...) report this id from inspect(); it is a
-- render/logic placeholder, not an obtainable item
M.MULTIBLOCK_MARK = "multiblock_structure"

-- ---- minimal JSON reader ---------------------------------------------------
-- Just enough for SURVEY FORMAT v1: objects, arrays, strings (with \" and \\),
-- integers including negatives, plus true/false/null for good measure. No
-- unicode escapes - the survey encoder never emits any.

local function parseError(str, pos, msg)
  local line = 1
  for _ in str:sub(1, pos):gmatch("\n") do line = line + 1 end
  error(("scan2plan: bad JSON at line %d (offset %d): %s"):format(line, pos, msg), 0)
end

function M.parseJson(str)
  if type(str) ~= "string" then error("scan2plan: parseJson wants a string", 0) end
  local pos = 1

  local function skipws()
    local nxt = str:find("[^ \t\r\n]", pos)
    pos = nxt or (#str + 1)
  end

  local function parseString()
    pos = pos + 1                                  -- opening quote
    local buf = {}
    while true do
      local c = str:sub(pos, pos)
      if c == "" then parseError(str, pos, "unterminated string") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then
        local e = str:sub(pos + 1, pos + 1)
        if e == "n" then buf[#buf + 1] = "\n"
        elseif e == "t" then buf[#buf + 1] = "\t"
        elseif e == "r" then buf[#buf + 1] = "\r"
        elseif e == "b" then buf[#buf + 1] = "\b"
        elseif e == "f" then buf[#buf + 1] = "\f"
        elseif e == "" then parseError(str, pos, "unterminated escape")
        else buf[#buf + 1] = e end                 -- \" \\ \/ and friends
        pos = pos + 2
      else
        local nxt = str:find('[\\"]', pos) or (#str + 1)
        buf[#buf + 1] = str:sub(pos, nxt - 1)
        pos = nxt
      end
    end
    return table.concat(buf)
  end

  local parseValue

  local function parseArray()
    pos = pos + 1
    local out = {}
    skipws()
    if str:sub(pos, pos) == "]" then pos = pos + 1 return out end
    while true do
      out[#out + 1] = parseValue()
      skipws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "]" then pos = pos + 1 return out
      else parseError(str, pos, "expected ',' or ']'") end
    end
  end

  local function parseObject()
    pos = pos + 1
    local out = {}
    skipws()
    if str:sub(pos, pos) == "}" then pos = pos + 1 return out end
    while true do
      skipws()
      if str:sub(pos, pos) ~= '"' then parseError(str, pos, "expected a key string") end
      local k = parseString()
      skipws()
      if str:sub(pos, pos) ~= ":" then parseError(str, pos, "expected ':'") end
      pos = pos + 1
      out[k] = parseValue()
      skipws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "}" then pos = pos + 1 return out
      else parseError(str, pos, "expected ',' or '}'") end
    end
  end

  parseValue = function()
    skipws()
    local c = str:sub(pos, pos)
    if c == "" then parseError(str, pos, "unexpected end of input") end
    if c == "{" then return parseObject() end
    if c == "[" then return parseArray() end
    if c == '"' then return parseString() end
    if str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
    if str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
    if str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
    -- number: leading '-' allowed (the survey uses -1/-2 sentinels)
    local lit = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
    local n = lit and tonumber(lit)
    if not n then parseError(str, pos, "unexpected character " .. string.format("%q", c)) end
    pos = pos + #lit
    return n
  end

  local v = parseValue()
  skipws()
  if pos <= #str then parseError(str, pos, "trailing garbage") end
  return v
end

-- ---- compile ---------------------------------------------------------------

local function listToSet(list, into)
  local set = into or {}
  for _, id in ipairs(list or {}) do
    id = tostring(id):match("^%s*(.-)%s*$")
    if id ~= "" then set[id] = true end
  end
  return set
end

-- compile(scan, opts) -> plan
-- opts.skip  = { blockId, ... }  dropped on top of DEFAULT_SKIP
-- opts.only  = { blockId, ... }  keep ONLY these (DEFAULT_SKIP is then ignored,
--                                so `--only minecraft:stone` really means it)
-- opts.noDefaults = true         drop the DEFAULT_SKIP terrain list
-- plan = { w,l,h, count, blocks, materials, warnings, hasMultiblock,
--          multiblock = {[id]=n}, stats = {air,unknown,blocked,skipped,
--          multiblock,solid} }
function M.compile(scan, opts)
  opts = opts or {}
  if type(scan) ~= "table" then error("scan2plan: compile wants a decoded scan table", 0) end
  local w, l, h = scan.w, scan.l, scan.h
  if type(w) ~= "number" or type(l) ~= "number" or type(h) ~= "number" then
    error("scan2plan: scan is missing w/l/h", 0)
  end
  local palette = scan.palette or {}
  local layers = scan.layers
  if type(layers) ~= "table" then error("scan2plan: scan has no layers array", 0) end
  if #layers < h then
    error(("scan2plan: scan claims h=%d but carries %d layers"):format(h, #layers), 0)
  end

  local only = nil
  if opts.only and #opts.only > 0 then only = listToSet(opts.only) end
  local skip = {}
  if not only and not opts.noDefaults then listToSet(M.DEFAULT_SKIP, skip) end
  listToSet(opts.skip, skip)

  local blocks, materials = {}, {}
  local multiblock, warnings = {}, {}
  local stats = { air = 0, unknown = 0, blocked = 0, skipped = 0, multiblock = 0, solid = 0 }

  for y = 0, h - 1 do
    local layer = layers[y + 1]
    if type(layer) ~= "table" then
      error(("scan2plan: layer %d is not an array"):format(y), 0)
    end
    if #layer < w * l then
      error(("scan2plan: layer %d has %d cells, expected %d (w*l)"):format(y, #layer, w * l), 0)
    end
    -- serpentine within the layer, exactly like schematic:plan() - the builder
    -- flies one cell above the layer it is filling, so travel is minimized and
    -- it never has to pass under finished work
    local flip = false
    for z = 0, l - 1 do
      local xs = {}
      if flip then
        for x = w - 1, 0, -1 do xs[#xs + 1] = x end
      else
        for x = 0, w - 1 do xs[#xs + 1] = x end
      end
      for _, x in ipairs(xs) do
        local v = layer[z * w + x + 1]
        if v == 0 then stats.air = stats.air + 1
        elseif v == -2 then stats.blocked = stats.blocked + 1
        elseif type(v) ~= "number" or v < 0 then stats.unknown = stats.unknown + 1
        else
          local id = palette[v]
          if not id then
            error(("scan2plan: palette has no entry %d (cell %d,%d,%d)"):format(v, x, y, z), 0)
          end
          stats.solid = stats.solid + 1
          if id:find(M.MULTIBLOCK_MARK, 1, true) then
            -- formed-structure ghost block: no item exists, placing is impossible
            stats.multiblock = stats.multiblock + 1
            multiblock[id] = (multiblock[id] or 0) + 1
          elseif (only and not only[id]) or skip[id] then
            stats.skipped = stats.skipped + 1
          else
            blocks[#blocks + 1] = { x = x, y = y, z = z, block = id }
            materials[id] = (materials[id] or 0) + 1
          end
        end
      end
      flip = not flip
    end
  end

  local mbIds = {}
  for id in pairs(multiblock) do mbIds[#mbIds + 1] = id end
  table.sort(mbIds)
  for _, id in ipairs(mbIds) do
    warnings[#warnings + 1] = ("EXCLUDED %d cell(s) of %s: formed multiblock, not a placeable item")
      :format(multiblock[id], id)
  end

  return {
    w = w, l = l, h = h,
    label = scan.label,
    count = #blocks,
    blocks = blocks,
    materials = materials,
    multiblock = multiblock,
    hasMultiblock = #mbIds > 0,
    warnings = warnings,
    stats = stats,
  }
end

-- materials bill as a sorted array: biggest pile first, ties by name
function M.bill(plan)
  local out = {}
  for id, n in pairs(plan.materials) do out[#out + 1] = { id = id, n = n } end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.id < b.id
  end)
  return out
end

-- ---- emit ------------------------------------------------------------------

-- emit(plan, source) -> Lua module source text
function M.emit(plan, source)
  local out = {}
  local function add(s) out[#out + 1] = s end
  add("-- generated by tools/scan2plan.lua - do not edit by hand")
  if source then add("-- source scan: " .. tostring(source)) end
  if plan.label then add("-- label: " .. tostring(plan.label)) end
  add(("-- %d placements, %d x %d x %d (w x l x h), builder frame (origin corner, facing +z)")
    :format(plan.count, plan.w, plan.l, plan.h))
  for _, warn in ipairs(plan.warnings or {}) do add("-- warning: " .. warn) end
  add("return {")
  add(("  w = %d, l = %d, h = %d, count = %d,"):format(plan.w, plan.l, plan.h, plan.count))
  add("  blocks = {")
  for _, p in ipairs(plan.blocks) do
    add(("    { x = %d, y = %d, z = %d, block = %q },"):format(p.x, p.y, p.z, p.block))
  end
  add("  },")
  add("  materials = {")
  for _, m in ipairs(M.bill(plan)) do
    add(("    [%q] = %d,"):format(m.id, m.n))
  end
  add("  },")
  add("}")
  return table.concat(out, "\n") .. "\n"
end

-- human summary lines (stdout)
function M.summary(plan)
  local lines = {}
  lines[#lines + 1] = ("scan: %d x %d x %d (w x l x h)%s")
    :format(plan.w, plan.l, plan.h, plan.label and (", label " .. plan.label) or "")
  local s = plan.stats
  lines[#lines + 1] = ("cells: %d solid, %d air, %d unknown, %d blocked")
    :format(s.solid, s.air, s.unknown, s.blocked)
  lines[#lines + 1] = ("placements: %d  (dropped %d filtered, %d multiblock)")
    :format(plan.count, s.skipped, s.multiblock)
  lines[#lines + 1] = "materials:"
  for _, m in ipairs(M.bill(plan)) do
    lines[#lines + 1] = ("  %-40s %6d"):format(m.id, m.n)
  end
  if plan.count == 0 then
    lines[#lines + 1] = "  (nothing to build - every cell was air or filtered out)"
  end
  return lines
end

-- ---- CLI -------------------------------------------------------------------

local function splitList(s)
  local out = {}
  for item in tostring(s):gmatch("[^,]+") do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then out[#out + 1] = item end
  end
  return out
end

M.USAGE = table.concat({
  "usage: lua54 tools/scan2plan.lua <scan.json> <out.lua> [--skip a,b] [--only a,b]",
  "  --skip a,b   also drop these block ids (added to the terrain defaults)",
  "  --only a,b   keep ONLY these block ids (terrain defaults not applied)",
  "  default skips: " .. table.concat(M.DEFAULT_SKIP, ", "),
}, "\n")

-- parseArgs(argv) -> opts | nil, err
function M.parseArgs(argv)
  local o = { skip = {}, only = {} }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--skip" or a == "--only" then
      local v = argv[i + 1]
      if not v then return nil, "missing value for " .. a end
      local dst = (a == "--skip") and o.skip or o.only
      for _, id in ipairs(splitList(v)) do dst[#dst + 1] = id end
      i = i + 2
    elseif a == "--quiet" then
      o.quiet = true; i = i + 1
    elseif a:sub(1, 2) == "--" then
      return nil, "unknown flag " .. a
    elseif not o.scan then
      o.scan = a; i = i + 1
    elseif not o.out then
      o.out = a; i = i + 1
    else
      return nil, "unexpected argument " .. a
    end
  end
  if not o.scan or not o.out then return nil, "need <scan.json> and <out.lua>" end
  return o
end

-- main(argv) -> plan | nil, err. Reads, compiles, writes, prints.
function M.main(argv)
  local o, err = M.parseArgs(argv)
  if not o then return nil, err end
  local f, ferr = io.open(o.scan, "rb")
  if not f then return nil, "cannot read " .. o.scan .. ": " .. tostring(ferr) end
  local text = f:read("a")
  f:close()
  local ok, scan = pcall(M.parseJson, text)
  if not ok then return nil, tostring(scan) end
  if scan.v and scan.v ~= 1 then
    print(("!! scan claims format v%s; this tool speaks SURVEY FORMAT v1"):format(tostring(scan.v)))
  end
  local ok2, plan = pcall(M.compile, scan, o)
  if not ok2 then return nil, tostring(plan) end
  local src = M.emit(plan, o.scan)
  local out, oerr = io.open(o.out, "wb")
  if not out then return nil, "cannot write " .. o.out .. ": " .. tostring(oerr) end
  out:write(src)
  out:close()
  if not o.quiet then
    for _, warn in ipairs(plan.warnings) do print("!! " .. warn) end
    for _, line in ipairs(M.summary(plan)) do print(line) end
    print(("wrote %s (%d placements)"):format(o.out, plan.count))
  end
  return plan
end

if _TEST then return M end

-- run the CLI only when invoked as a script (require() passes the module name
-- as ..., which must never be mistaken for a scan path)
local argv = { ... }
if type(arg) == "table" and arg[0] then
  if #argv == 0 then
    print(M.USAGE)
    os.exit(1)
  end
  local plan, err = M.main(argv)
  if not plan then
    io.stderr:write("scan2plan: " .. tostring(err) .. "\n")
    os.exit(1)
  end
end

return M
