-- aefab: AE2 component production line. A turtle conducts an inscriber and
-- your (Functional Storage) controller network: raw materials flow drawers ->
-- inscriber -> drawers with the turtle as pure orchestrator - it never even
-- holds the items. Self-calibrating: it learns the inscriber's slot layout
-- by probing, so no hardcoded assumptions about AE2's inventory order.
--
-- Rig: turtle adjacent to BOTH the inscriber and the storage controller
-- (directly, or via wired modems on one network). Coal generator powering
-- the inscriber. Presses + raw materials in the drawer network.
--
--   aefab probe             show what I can see (run this FIRST, send output)
--   aefab press             duplicate all 4 presses (needs iron blocks)
--   aefab make <n>          produce n of each processor (logic/calc/engineering)
--
-- Materials for `make 16`: 16 gold ingots, 16 certus quartz crystals,
-- 16 diamonds, 48 redstone, 48 silicon, + the 4 presses, all in the drawers.
local PRESSES = {
  silicon = "ae2:silicon_press",
  logic = "ae2:logic_processor_press",
  calculation = "ae2:calculation_processor_press",
  engineering = "ae2:engineering_processor_press",
}
local RECIPES = {
  { press = "silicon", input = "ae2:silicon", output = "ae2:printed_silicon" },
  { press = "logic", input = "minecraft:gold_ingot", output = "ae2:printed_logic_processor" },
  { press = "calculation", input = "ae2:certus_quartz_crystal", output = "ae2:printed_calculation_processor" },
  { press = "engineering", input = "minecraft:diamond", output = "ae2:printed_engineering_processor" },
}
local COMBINE = {
  { top = "ae2:printed_logic_processor", bottom = "ae2:printed_silicon",
    mid = "minecraft:redstone", output = "ae2:logic_processor" },
  { top = "ae2:printed_calculation_processor", bottom = "ae2:printed_silicon",
    mid = "minecraft:redstone", output = "ae2:calculation_processor" },
  { top = "ae2:printed_engineering_processor", bottom = "ae2:printed_silicon",
    mid = "minecraft:redstone", output = "ae2:engineering_processor" },
}

-- ---- find the two peripherals -----------------------------------------------
local function findPeripherals()
  local insc, store
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name) or ""
    if tostring(t):lower():find("inscriber") then insc = name
    elseif tostring(t):lower():find("controller") or tostring(t):lower():find("storage") then
      store = store or name
    end
  end
  -- fallback: any non-inscriber inventory-ish peripheral is the store
  if not store then
    for _, name in ipairs(peripheral.getNames()) do
      if name ~= insc then
        local p = peripheral.wrap(name)
        if p and p.list then store = name end
      end
    end
  end
  return insc, store
end

local function findIn(listing, item)
  for slot, st in pairs(listing) do
    if st.name == item then return slot, st.count end
  end
end

local args = { ... }
local cmd = args[1]
local insc, store = findPeripherals()

if cmd == "probe" or not cmd then
  print("peripherals I can reach:")
  for _, name in ipairs(peripheral.getNames()) do
    print(("  %s [%s]"):format(name, tostring(peripheral.getType(name))))
  end
  print("inscriber: " .. tostring(insc))
  print("storage:   " .. tostring(store))
  if insc then
    local p = peripheral.wrap(insc)
    if p.list then
      print("inscriber slots currently:")
      for slot, st in pairs(p.list()) do
        print(("  slot %d: %s x%d"):format(slot, st.name, st.count))
      end
      print(("inscriber reports %s slots total"):format(tostring(p.size and p.size())))
    else
      print("inscriber exposes NO inventory API - send me this output")
    end
  end
  if not cmd then print("usage: aefab probe|press|make <n>") end
  return
end

if not insc or not store then
  print("cannot find both peripherals (inscriber=" .. tostring(insc)
    .. ", storage=" .. tostring(store) .. ") - run `aefab probe`")
  return
end
local I = peripheral.wrap(insc)
local S = peripheral.wrap(store)

-- ---- self-calibration: learn which inscriber slots accept what --------------
-- push a press: the slots that accept it are the press slots (top/bottom).
-- push a material with a press seated: the accepting slot is the middle.
-- output slot = where the product shows up.
local function learnSlots()
  local pressName
  local sList = S.list()
  for _, id in pairs(PRESSES) do
    if findIn(sList, id) then pressName = id break end
  end
  if not pressName then return nil, "no press found in storage" end
  local from = findIn(S.list(), pressName)
  local pressSlot
  for slot = 1, (I.size and I.size() or 4) do
    if S.pushItems(insc, from, 1, slot) > 0 then pressSlot = slot break end
  end
  if not pressSlot then return nil, "inscriber refused a press in every slot" end
  local midSlot
  local matFrom = findIn(S.list(), "minecraft:redstone")
    or findIn(S.list(), "minecraft:gold_ingot")
  if matFrom then
    for slot = 1, (I.size and I.size() or 4) do
      if slot ~= pressSlot and S.pushItems(insc, matFrom, 1, slot) > 0 then
        midSlot = slot
        I.pushItems(store, slot)         -- take the probe material back
        break
      end
    end
  end
  I.pushItems(store, pressSlot)          -- take the probe press back
  return { press = pressSlot, mid = midSlot }
end

local function clearInscriber()
  for slot in pairs(I.list()) do I.pushItems(store, slot) end
end

local function waitFor(item, timeout)
  local deadline = os.clock() + (timeout or 30)
  while os.clock() < deadline do
    local slot = findIn(I.list(), item)
    if slot then return slot end
    sleep(1)
  end
end

--- seat `press` (or nil), feed inputs, wait for output, return it to storage.
local function craft(pressId, inputs, output, slots)
  if pressId then
    local from = findIn(S.list(), pressId)
    if not from then return false, "missing " .. pressId end
    if S.pushItems(insc, from, 1, slots.press) == 0 then return false, "press slot refused" end
  end
  for slot, item in pairs(inputs) do
    local from = findIn(S.list(), item)
    if not from then clearInscriber() return false, "missing " .. item end
    if S.pushItems(insc, from, 1, slot) == 0 then
      clearInscriber()
      return false, "inscriber refused " .. item .. " in slot " .. slot
    end
  end
  local outSlot = waitFor(output, 30)
  clearInscriber()
  if not outSlot then return false, "timed out waiting for " .. output .. " (is the inscriber powered?)" end
  return true
end

if cmd == "press" then
  local slots, err = learnSlots()
  if not slots then print("calibration failed: " .. err) return end
  print(("calibrated: press slot %d, middle slot %s"):format(slots.press, tostring(slots.mid)))
  for key, id in pairs(PRESSES) do
    local ok, cerr = craft(id, { [slots.mid] = "minecraft:iron_block" }, id, slots)
    print((ok and "duplicated %s" or "FAILED %s: " .. tostring(cerr)):format(key))
  end

elseif cmd == "make" then
  local n = tonumber(args[2]) or 8
  local slots, err = learnSlots()
  if not slots then print("calibration failed: " .. err) return end
  print(("calibrated: press slot %d, middle slot %s"):format(slots.press, tostring(slots.mid)))
  -- prints first (n of each + n silicon per processor type)
  for _, r in ipairs(RECIPES) do
    local want = r.press == "silicon" and n * 3 or n
    for i = 1, want do
      local ok, cerr = craft(PRESSES[r.press], { [slots.mid] = r.input }, r.output, slots)
      if not ok then print(("%s %d/%d FAILED: %s"):format(r.output, i, want, cerr)) break end
      if i % 4 == 0 or i == want then print(("%s %d/%d"):format(r.output, i, want)) end
    end
  end
  -- processors: print top, silicon print bottom, redstone middle, no press
  local other = slots.press          -- with no press seated, both press slots free
  for _, c in ipairs(COMBINE) do
    for i = 1, n do
      local ok, cerr = (function()
        local f1 = findIn(S.list(), c.top)
        local f2 = findIn(S.list(), c.bottom)
        if not (f1 and f2) then return false, "missing prints" end
        if S.pushItems(insc, f1, 1, slots.press) == 0 then return false, "top refused" end
        -- find the second press-capable slot for the silicon print
        local seated = false
        for slot = 1, (I.size and I.size() or 4) do
          if slot ~= slots.press and slot ~= slots.mid then
            if S.pushItems(insc, f2, 1, slot) > 0 then seated = true break end
          end
        end
        if not seated then clearInscriber() return false, "bottom refused" end
        local fr = findIn(S.list(), c.mid)
        if not fr or S.pushItems(insc, fr, 1, slots.mid) == 0 then
          clearInscriber()
          return false, "redstone refused"
        end
        local out = waitFor(c.output, 30)
        clearInscriber()
        if not out then return false, "timeout" end
        return true
      end)()
      if not ok then print(("%s %d/%d FAILED: %s"):format(c.output, i, n, cerr)) break end
      if i % 4 == 0 or i == n then print(("%s %d/%d"):format(c.output, i, n)) end
    end
  end
  print("done - components are in the drawers")
else
  print("aefab probe|press|make <n>")
end
