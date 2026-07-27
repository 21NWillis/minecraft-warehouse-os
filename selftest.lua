-- selftest: functional smoke test (complements doctor's presence checks by
-- actually EXERCISING operations). Moves one real item out and back to prove
-- transfers work bidirectionally, verifies recipe search and EMC lookups, and
-- reports PASS/FAIL. Non-destructive: anything it moves, it moves right back.
local pass, fail = 0, 0
local function ok(m) pass = pass + 1; print("[ OK ] " .. m) end
local function bad(m) fail = fail + 1; print("[FAIL] " .. m) end

print("== PaperclipOS selftest (functional) ==")

local controllerName
for _, n in ipairs(peripheral.getNames()) do
  if n:find("controller", 1, true) then controllerName = n break end
end
local scratchName
for _, n in ipairs(peripheral.getNames()) do
  if n:find("enderstorage", 1, true) or n:find("minecraft:chest", 1, true)
     or n:find("minecraft:barrel", 1, true) then scratchName = n break end
end

-- round-trip transfer test
if not controllerName then
  bad("no controller - cannot test transfers")
elseif not scratchName then
  print("[WARN] no scratch chest/barrel - skipping transfer test")
else
  local c = peripheral.wrap(controllerName)
  local srcSlot, srcName
  for slot, it in pairs(c.list()) do srcSlot, srcName = slot, it.name; break end
  if not srcSlot then
    print("[WARN] controller empty - cannot test transfer")
  else
    local moved = c.pushItems(scratchName, srcSlot, 1)
    if moved ~= 1 then
      bad("pushItems to scratch moved " .. moved .. " (expected 1)")
    else
      -- verify it landed
      local scratch = peripheral.wrap(scratchName)
      local found = false
      for _, it in pairs(scratch.list()) do if it.name == srcName then found = true end end
      if found then ok("transfer out works (1x " .. srcName .. " -> scratch)")
      else bad("item did not appear in scratch after push") end
      -- move it back
      local returned = 0
      for slot, it in pairs(scratch.list()) do
        if it.name == srcName then returned = returned + scratch.pushItems(controllerName, slot, 1) end
      end
      if returned >= 1 then ok("transfer back works (item returned to storage)")
      else bad("could not return item to storage - CHECK BEFORE RUNNING WAREHOUSE") end
    end
  end
end

-- recipe DB functional check
local okDb, db = pcall(require, "recipedb")
if okDb and db.load and db.load("data") then
  local hits = db.search("iron", 20)
  if #hits > 0 then ok("recipe search works (" .. #hits .. " hits for 'iron')")
  else bad("recipe search returned nothing") end
  if db.isCraftable("minecraft:chest") then ok("craftability lookup works (chest is craftable)")
  else bad("chest not marked craftable - DB may be incomplete") end
else
  print("[WARN] recipedb not loaded - crafting features unavailable")
end

-- EMC functional check (streams into RAM if not on disk)
local okE, emcload = pcall(require, "emcload")
if okE and next(emcload.load()) then ok("EMC data loads (disk or streamed)")
else print("[WARN] no EMC data (economy tools degrade)") end

print(("\n== %d OK, %d FAIL =="):format(pass, fail))
if fail == 0 then print("functional checks passed - the warehouse should work.")
else print("functional FAILs found - fix these before relying on it.") end
