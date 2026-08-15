-- stockd: the ME stock-keeper. Watches the commune ME network and
-- fires autocraft jobs to hold configured minimum levels true.
-- The commune never sees this - they just never run out of anything.
-- (Stock-policy-as-branch-predictor doctrine: the only speculation in
-- the system is how much of each item to keep banked.)
--
-- Config: stock_cfg.lua next to this file, e.g.
--   return {
--     ["minecraft:iron_ingot"]   = 1000,
--     ["minecraft:glass"]        = 512,
--     ["ae2:fluix_crystal"]      = 256,
--   }
-- Items must have an AE2 pattern (visible in getCraftableItems) or
-- stockd reports them as unstockable and skips.
--
-- Run: stockd    (loops forever; put it in startup via bg/multishell)

local POLL = 30          -- seconds between sweeps (budget-polite)
local MAX_BATCH = 256    -- largest single craft request (RS2/AE2 calc safety)

local function findType(want)
  for _, n in ipairs(peripheral.getNames()) do
    local t = (peripheral.getType(n) or ""):lower():gsub("_", "")
    if t == want then return n, peripheral.wrap(n) end
  end
end

local _, me = findType("mebridge")
assert(me, "stockd: no me_bridge on the wired network")
assert(fs.exists("stock_cfg.lua"), "stockd: missing stock_cfg.lua")
local want = dofile("stock_cfg.lua")

local jobs = {}   -- item -> job object in flight

local function stored(name)
  local ok, it = pcall(me.getItem, { name = name })
  if ok and type(it) == "table" and it.count then
    -- landmine: craftable-but-zero-stored items clamp to count=1.
    -- Off-by-one on the shortfall is acceptable; never treat as "in stock".
    return it.count
  end
  return 0
end

local function sweep()
  for name, min in pairs(want) do
    -- reap finished/dead jobs
    local j = jobs[name]
    if j then
      local okD, done = pcall(function() return j.isDone() end)
      local okC, canc = pcall(function() return j.isCanceled() end)
      if (okD and done) or (okC and canc) then
        if okC and canc then
          print(("stockd: craft of %s canceled (missing ingredients?)"):format(name))
        end
        jobs[name] = nil
        j = nil
      end
    end
    if not j then
      local have = stored(name)
      if have < min then
        local okCr, craftable = pcall(me.isCraftable, { name = name })
        if okCr and craftable then
          local ask = math.min(min - have, MAX_BATCH)
          local ok, job = pcall(me.craftItem, { name = name, count = ask })
          if ok and job then
            jobs[name] = job
            print(("stockd: %s %d/%d -> crafting %d"):format(name, have, min, ask))
          end
        else
          print(("stockd: %s %d/%d but NO PATTERN - unstockable"):format(name, have, min))
        end
      end
    end
  end
end

print("stockd up: " .. tostring((function() local c = 0 for _ in pairs(want) do c = c + 1 end return c end)()) .. " watermarks")
while true do
  local ok, err = pcall(sweep)
  if not ok then print("stockd sweep error: " .. tostring(err)) end
  sleep(POLL)
end
