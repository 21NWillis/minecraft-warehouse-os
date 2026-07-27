-- warehouse v3: storefront touch UI + recipe-aware index + batched transfers
-- usage: warehouse             (dashboard + command prompt)
--        warehouse install     (write startup.lua so it runs on boot)
-- terminal: find <text> | get/craft <text> [count] | put | refresh | stats | quit
-- monitor:  tap card = withdraw stack | FIND = on-screen keyboard
--           < > pages | PUT deposits barrel | SCAN reindexes

local runArgs = { ... }
if runArgs[1] == "install" then
  local f = fs.open("startup.lua", "w")
  f.write('shell.run("warehouse")')
  f.close()
  print("startup.lua written; warehouse now runs on boot")
  return
end

local CONTROLLER_MATCH = "controller"
local DELIVERY_MATCH = { "minecraft:chest", "minecraft:barrel" }
local RESCAN_SECONDS = 10
local TAP_AMOUNT = 64

-- ---------------------------------------------------------------- peripherals
local function findPeripheral(matches)
  if type(matches) == "string" then matches = { matches } end
  for _, name in ipairs(peripheral.getNames()) do
    for _, m in ipairs(matches) do
      if name:find(m, 1, true) then return name end
    end
  end
end

local controllerName = findPeripheral(CONTROLLER_MATCH)
if not controllerName then error("No storage controller found on the network") end
local controller = peripheral.wrap(controllerName)
local deliveryName = findPeripheral(DELIVERY_MATCH)
local monitor = peripheral.find("monitor")

-- ------------------------------------------------------------------- metrics
local metrics = {}
local function timed(op, fn, ...)
  local t0 = os.epoch("utc")
  local results = table.pack(fn(...))
  local dt = os.epoch("utc") - t0
  local m = metrics[op]
  if not m then m = { count = 0, totalMs = 0, maxMs = 0 }; metrics[op] = m end
  m.count = m.count + 1
  m.totalMs = m.totalMs + dt
  if dt > m.maxMs then m.maxMs = dt end
  return table.unpack(results, 1, results.n)
end

-- ----------------------------------------------------------------- recipe db
local db
do
  local ok, mod = pcall(require, "recipedb")
  if ok then
    local loaded = timed("dbload", mod.load, "data")
    if loaded then db = mod end
  end
end

local function displayName(id)
  if db then return db.name(id) end
  local pretty = id:gsub("^[^:]+:", ""):gsub("_", " ")
  return pretty:sub(1, 1):upper() .. pretty:sub(2)
end

-- ------------------------------------------------------------------- factory
local PROTO = "gigafactory"
local planner
do
  local ok, mod = pcall(require, "planner")
  if ok then planner = mod end
end

local crafters = {}   -- rednet id -> { name = peripheral name, seen = clock }
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end

local function pickCrafter()
  rednet.broadcast({ type = "ping" }, PROTO)
  sleep(1)
  for id, c in pairs(crafters) do
    if os.clock() - c.seen < 60 then return id, c.name end
  end
end

-- --------------------------------------------------------------------- index
local index = {}
local sorted = {}
local filtered = {}
local lastScan = "never"
local filter = ""

local function applyFilter()
  if filter == "" then
    filtered = sorted
    return
  end
  local q = filter:lower()
  filtered = {}
  for _, id in ipairs(sorted) do
    local path = id:gsub("^[^:]+:", "")
    if path:find(q, 1, true) or displayName(id):lower():find(q, 1, true) then
      filtered[#filtered + 1] = id
    end
  end
end

local function rescan()
  index = {}
  for slot, item in pairs(timed("list", controller.list)) do
    local entry = index[item.name]
    if not entry then
      entry = { count = 0, slots = {} }
      index[item.name] = entry
    end
    entry.count = entry.count + item.count
    entry.slots[#entry.slots + 1] = { slot = slot, count = item.count }
  end
  sorted = {}
  for id in pairs(index) do sorted[#sorted + 1] = id end
  table.sort(sorted, function(a, b) return index[a].count > index[b].count end)
  applyFilter()
  lastScan = textutils.formatTime(os.time("local"), true)
end

-- --------------------------------------------------------- batched transfers
local function withdraw(id, want)
  if not deliveryName then return 0, "no delivery chest" end
  local entry = index[id]
  if not entry then return 0, "not in index" end
  local moved, remaining, tasks = 0, want, {}
  for _, s in ipairs(entry.slots) do
    if remaining <= 0 then break end
    local take = math.min(remaining, s.count)
    remaining = remaining - take
    local slot = s.slot
    tasks[#tasks + 1] = function()
      moved = moved + timed("push", controller.pushItems, deliveryName, slot, take)
    end
  end
  if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end
  return moved
end

local function deposit()
  if not deliveryName then return 0 end
  local chest = peripheral.wrap(deliveryName)
  local moved, tasks = 0, {}
  for slot in pairs(chest.list()) do
    tasks[#tasks + 1] = function()
      moved = moved + timed("push", chest.pushItems, controllerName, slot)
    end
  end
  if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end
  return moved
end

-- turtle 4x4 inventory slots that form the 3x3 crafting grid
local TURTLE_GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

-- load one crafting batch into the turtle; returns how many crafts were loaded
local function loadBatch(crafterName, step, batch)
  local loadable = batch
  for gridSlot, itemId in pairs(step.picks) do
    local entry = index[itemId]
    if not entry then return 0, "no " .. displayName(itemId) .. " in storage" end
    local pushed, tasks = 0, {}
    local wanted = batch
    for _, s in ipairs(entry.slots) do
      if wanted <= 0 then break end
      local take = math.min(wanted, s.count)
      wanted = wanted - take
      local slot = s.slot
      tasks[#tasks + 1] = function()
        pushed = pushed + timed("push", controller.pushItems, crafterName, slot, take, TURTLE_GRID[gridSlot])
      end
    end
    if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end
    if pushed < loadable then loadable = pushed end
  end
  return loadable
end

local function unloadTurtle(crafterName)
  local tasks = {}
  for t = 1, 16 do
    tasks[#tasks + 1] = function() timed("push", controller.pullItems, crafterName, t) end
  end
  parallel.waitForAll(table.unpack(tasks))
end

local function executeStep(step, crafterId, crafterName, report)
  local remaining = step.times
  while remaining > 0 do
    local loaded, err = loadBatch(crafterName, step, math.min(remaining, 64))
    if loaded == 0 then
      unloadTurtle(crafterName)
      return false, err or ("could not load ingredients for " .. displayName(step.output))
    end
    rednet.send(crafterId, { type = "craft", times = loaded }, PROTO)
    local ok = false
    local deadline = os.clock() + 30
    while os.clock() < deadline do
      local senderId, msg = rednet.receive(PROTO, 5)
      if senderId == crafterId and type(msg) == "table" and msg.type == "done" then
        ok = msg.ok
        break
      end
    end
    unloadTurtle(crafterName)
    if not ok then return false, "crafter failed on " .. displayName(step.output) end
    remaining = remaining - loaded
    rescan()
    report(step, step.times - remaining)
  end
  return true
end

local function craftItem(targetId, count, report)
  if not db or not planner then return false, "recipe db or planner not loaded" end
  local crafterId, crafterName = pickCrafter()
  if not crafterId then return false, "no crafter turtle online" end
  rescan()
  local have = {}
  for id, entry in pairs(index) do have[id] = entry.count end
  local steps, missingItems = planner.plan(db, have, targetId, count)
  if not steps then return false, nil, missingItems end
  for i, step in ipairs(steps) do
    report(step, 0, i, #steps)
    local ok, err = executeStep(step, crafterId, crafterName, report)
    if not ok then return false, err end
  end
  return true, #steps
end

-- ------------------------------------------------------------------ theme/UI
local status = "ready"
local page = 1
local keyboardMode = false
local cardMap = {}
local buttonMap = {}

local THEME = {
  [colors.black] = 0x10131f,
  [colors.gray] = 0x1d2233,
  [colors.lightGray] = 0x707894,
  [colors.white] = 0xe8eaf2,
  [colors.cyan] = 0x4cc9f0,
  [colors.blue] = 0x2b3a67,
  [colors.green] = 0x51cf66,
  [colors.orange] = 0xffa94d,
  [colors.red] = 0xff6b6b,
  [colors.yellow] = 0xffd43b,
}

local function applyTheme(t)
  if not t.setPaletteColour then return end
  for color, rgb in pairs(THEME) do t.setPaletteColour(color, rgb) end
end

local function fmt(n)
  if n >= 1000000 then return ("%.1fM"):format(n / 1000000) end
  if n >= 10000 then return ("%.0fk"):format(n / 1000) end
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(n)
end

local function layout()
  local w, h = monitor.getSize()
  local cols = w >= 36 and 2 or 1
  local cardW = math.floor((w - (cols - 1)) / cols)
  local top = 4
  local bottom = keyboardMode and (h - 10) or (h - 2)
  local rows = math.max(1, math.floor((bottom - top + 1) / 3))
  return w, h, cols, cardW, top, rows
end

local function writeAt(x, y, text, fg, bg)
  monitor.setCursorPos(x, y)
  monitor.setTextColor(fg or colors.white)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.write(text)
end

local function pad(text, width)
  text = text:sub(1, width)
  return text .. string.rep(" ", width - #text)
end

local function addButton(x1, y, label, action, fg, bg)
  writeAt(x1, y, label, fg or colors.white, bg or colors.blue)
  buttonMap[#buttonMap + 1] = { x1 = x1, x2 = x1 + #label - 1, y = y, action = action }
  return x1 + #label + 1
end

local KEY_ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }

local function drawKeyboard(w, h)
  local y = h - 9
  writeAt(1, y - 1, pad(" search: " .. filter .. "_", w), colors.cyan, colors.gray)
  for rowIdx, rowKeys in ipairs(KEY_ROWS) do
    local rowY = y + (rowIdx - 1) * 2
    monitor.setCursorPos(1, rowY)
    monitor.setBackgroundColor(colors.black)
    monitor.clearLine()
    local x = rowIdx
    for i = 1, #rowKeys do
      local ch = rowKeys:sub(i, i)
      writeAt(x, rowY, " " .. ch .. " ", colors.white, colors.gray)
      buttonMap[#buttonMap + 1] = { x1 = x, x2 = x + 2, y = rowY, action = "key:" .. ch }
      x = x + 3
    end
    if rowIdx == 3 then
      writeAt(x, rowY, " <- ", colors.orange, colors.gray)
      buttonMap[#buttonMap + 1] = { x1 = x, x2 = x + 3, y = rowY, action = "backspace" }
    end
  end
  local x = 2
  local actionY = y + 6
  x = addButton(x, actionY, " SPACE ", "key: ", colors.white, colors.gray)
  x = addButton(x, actionY, " CLEAR ", "kbclear", colors.orange, colors.gray)
  addButton(x, actionY, " DONE ", "kbdone", colors.green, colors.gray)
end

local function draw()
  if not monitor then return end
  monitor.setTextScale(0.5)
  applyTheme(monitor)
  local w, h, cols, cardW, top, rows = layout()
  cardMap, buttonMap = {}, {}

  monitor.setBackgroundColor(colors.black)
  monitor.clear()

  writeAt(1, 1, pad("  WAREHOUSE", w - 12), colors.yellow, colors.blue)
  writeAt(w - 11, 1, pad(#sorted .. " types", 12), colors.white, colors.blue)
  local sub = filter ~= "" and (" filter: " .. filter .. "  [tap to clear]")
    or (" all items - by count - scan " .. lastScan)
  writeAt(1, 2, pad(sub, w), colors.lightGray, colors.gray)
  if filter ~= "" then
    buttonMap[#buttonMap + 1] = { x1 = 1, x2 = w, y = 2, action = "clearfilter" }
  end

  local perPage = cols * rows
  local pages = math.max(1, math.ceil(#filtered / perPage))
  if page > pages then page = pages end
  local offset = (page - 1) * perPage

  for i = 1, perPage do
    local id = filtered[offset + i]
    if not id then break end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = col * (cardW + 1) + 1
    local y = top + row * 3
    local entry = index[id]
    local craftable = db and db.isCraftable(id)
    writeAt(x, y, pad(" " .. displayName(id), cardW), colors.white, colors.gray)
    local countStr = " " .. fmt(entry.count)
    local badge = craftable and "+" or " "
    local mod = id:match("^([^:]+):") or ""
    writeAt(x, y + 1, pad(countStr, cardW - #mod - 3), colors.cyan, colors.gray)
    writeAt(x + cardW - #mod - 3, y + 1, badge, colors.green, colors.gray)
    writeAt(x + cardW - #mod - 2, y + 1, pad(mod, cardW - (cardW - #mod - 2) + 1), colors.lightGray, colors.gray)
    cardMap[#cardMap + 1] = { x1 = x, y1 = y, x2 = x + cardW - 1, y2 = y + 1, id = id }
  end

  if keyboardMode then drawKeyboard(w, h) end

  local navY = h - 1
  monitor.setCursorPos(1, navY)
  monitor.setBackgroundColor(colors.black)
  monitor.clearLine()
  local x = 1
  x = addButton(x, navY, " < ", "prev")
  writeAt(x, navY, ("%d/%d"):format(page, pages), colors.lightGray, colors.black)
  x = x + #("%d/%d"):format(page, pages) + 1
  x = addButton(x, navY, " > ", "next")
  x = addButton(x + 1, navY, " PUT ", "put", colors.white, colors.blue)
  x = addButton(x, navY, " SCAN ", "scan", colors.white, colors.blue)
  addButton(x, navY, " FIND ", "find", colors.black, colors.cyan)

  writeAt(1, h, pad(" " .. status, w), colors.lightGray, colors.black)
end

-- --------------------------------------------------------------------- loops
local function handleAction(action)
  if action == "prev" then
    page = math.max(1, page - 1)
  elseif action == "next" then
    page = page + 1
  elseif action == "put" then
    status = "deposited " .. deposit() .. " items"
    rescan()
  elseif action == "scan" then
    rescan()
    status = "rescanned"
  elseif action == "find" then
    keyboardMode = true
  elseif action == "kbdone" then
    keyboardMode = false
  elseif action == "kbclear" then
    filter = ""
    page = 1
    applyFilter()
  elseif action == "clearfilter" then
    filter = ""
    page = 1
    applyFilter()
  elseif action == "backspace" then
    filter = filter:sub(1, -2)
    page = 1
    applyFilter()
  elseif action:sub(1, 4) == "key:" then
    filter = filter .. action:sub(5)
    page = 1
    applyFilter()
  end
end

local function touchLoop()
  if not monitor then while true do sleep(60) end end
  while true do
    local _, _, tx, ty = os.pullEvent("monitor_touch")
    local handled = false
    for _, b in ipairs(buttonMap) do
      if ty == b.y and tx >= b.x1 and tx <= b.x2 then
        handleAction(b.action)
        handled = true
        break
      end
    end
    if not handled and not keyboardMode then
      for _, c in ipairs(cardMap) do
        if tx >= c.x1 and tx <= c.x2 and ty >= c.y1 and ty <= c.y2 then
          local moved, err = withdraw(c.id, TAP_AMOUNT)
          status = ("sent %d x %s%s"):format(moved, displayName(c.id), err and (" (" .. err .. ")") or "")
          rescan()
          break
        end
      end
    end
    draw()
  end
end

local function rescanLoop()
  while true do
    rescan()
    draw()
    sleep(RESCAN_SECONDS)
  end
end

local function rosterLoop()
  while true do
    local senderId, msg = rednet.receive(PROTO)
    if type(msg) == "table" and msg.type == "hello" and msg.name then
      crafters[senderId] = { name = msg.name, seen = os.clock() }
    end
  end
end

local function printStats()
  print(("%-8s %6s %8s %8s %8s"):format("op", "count", "total ms", "avg ms", "max ms"))
  for op, m in pairs(metrics) do
    print(("%-8s %6d %8d %8.1f %8d"):format(op, m.count, m.totalMs, m.totalMs / m.count, m.maxMs))
  end
end

local function commandLoop()
  print("warehouse v3: " .. controllerName)
  print("delivery: " .. (deliveryName or "NONE FOUND"))
  print("recipes: " .. (db and (db.recipeCount() .. " loaded") or "not deployed"))
  print("commands: find <text> | get/craft <text> [count] | put | refresh | stats | quit")
  while true do
    write("> ")
    local line = read()
    local args = {}
    for word in line:gmatch("%S+") do args[#args + 1] = word end
    local cmd = table.remove(args, 1)

    if cmd == "quit" then
      return
    elseif cmd == "stats" then
      printStats()
    elseif cmd == "refresh" then
      rescan()
      draw()
      print(#sorted .. " item types indexed")
    elseif cmd == "put" then
      print("deposited " .. deposit() .. " items")
      rescan()
      draw()
    elseif cmd == "find" and args[1] then
      filter = table.concat(args, " ")
      page = 1
      applyFilter()
      for i = 1, math.min(#filtered, 10) do
        local id = filtered[i]
        print(("%6d  %s  [%s]"):format(index[id].count, displayName(id), id:match("^([^:]+):") or "?"))
      end
      if #filtered == 0 then print("no matches") end
      if #filtered > 10 then print("... and " .. (#filtered - 10) .. " more") end
      draw()
    elseif cmd == "craft" and args[1] then
      local count = tonumber(args[#args])
      if count then table.remove(args) else count = 1 end
      if not db then
        print("recipe db not loaded")
      else
        local hits = db.search(table.concat(args, " "), 20)
        if #hits == 0 then
          print("no craftable item matches")
        else
          local target = hits[1]
          print(("crafting %d x %s"):format(count, displayName(target)))
          local ok, detail, missingItems = craftItem(target, count, function(step, done, i, total)
            if i then
              print(("[%d/%d] %s x%d"):format(i, total, displayName(step.output), step.times * step.recipe.count))
            end
            status = ("crafting %s (%d/%d)"):format(displayName(step.output), done, step.times)
            draw()
          end)
          if ok then
            local moved = withdraw(target, count)
            rescan()
            draw()
            print(("done: %d steps, %d delivered to barrel"):format(detail, moved))
          elseif missingItems then
            print("missing raw materials:")
            local shown = 0
            for mid, amount in pairs(missingItems) do
              print(("  %d x %s"):format(amount, displayName(mid:gsub("^#", ""))))
              shown = shown + 1
              if shown >= 10 then break end
            end
          else
            print("failed: " .. tostring(detail))
          end
        end
      end
    elseif cmd == "get" and args[1] then
      local count = tonumber(args[#args])
      if count then table.remove(args) else count = 64 end
      filter = table.concat(args, " ")
      applyFilter()
      local hits = filtered
      if #hits == 0 then
        print("no matches")
      elseif #hits > 1 and index[hits[1]].count < count then
        print("ambiguous, be more specific:")
        for i = 1, math.min(#hits, 5) do print("  " .. displayName(hits[i])) end
      else
        local moved, err = withdraw(hits[1], count)
        print(("moved %d x %s%s"):format(moved, displayName(hits[1]), err and (" (" .. err .. ")") or ""))
        rescan()
      end
      filter = ""
      applyFilter()
      draw()
    else
      print("commands: find <text> | get/craft <text> [count] | put | refresh | stats | quit")
    end
  end
end

rescan()
draw()
parallel.waitForAny(rescanLoop, touchLoop, commandLoop, rosterLoop)
