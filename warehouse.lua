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
-- first match wins: ender chest channel beats local chest/barrel
local DELIVERY_MATCH = { "enderstorage", "minecraft:chest", "minecraft:barrel" }
local RESCAN_SECONDS = 10
local TAP_AMOUNT = 64

-- ---------------------------------------------------------------- peripherals
local function findPeripheral(matches)
  if type(matches) == "string" then matches = { matches } end
  for _, m in ipairs(matches) do
    for _, name in ipairs(peripheral.getNames()) do
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
  if not m then
    m = { count = 0, totalMs = 0, maxMs = 0, samples = {}, cursor = 1 }
    metrics[op] = m
  end
  m.count = m.count + 1
  m.totalMs = m.totalMs + dt
  if dt > m.maxMs then m.maxMs = dt end
  m.samples[m.cursor] = dt
  m.cursor = m.cursor % 512 + 1
  return table.unpack(results, 1, results.n)
end

local function percentile(samples, p)
  local sorted = {}
  for _, v in ipairs(samples) do sorted[#sorted + 1] = v end
  if #sorted == 0 then return 0 end
  table.sort(sorted)
  return sorted[math.max(1, math.ceil(p * #sorted))]
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
local planner, schedulerLib
do
  local ok, mod = pcall(require, "planner")
  if ok then planner = mod end
  local ok2, mod2 = pcall(require, "scheduler")
  if ok2 then schedulerLib = mod2 end
end

local crafters = {}   -- rednet id -> { name = peripheral name, seen = clock }
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "modem" then rednet.open(side) end
end

local reserved = {}   -- rednet id -> true while a batch is loaded on that turtle
local STALE = 30      -- a crafter is live if its heartbeat is within this many s
local sched = schedulerLib and schedulerLib.new() or nil

-- passive roster snapshot: pure table scan, no broadcast, no sleep. The old
-- ping+sleep(1) barrier per round put us far under SOL; heartbeats keep this
-- fresh for free (crafter.lua beats every few seconds).
local function idleCrafters()
  local idle = {}
  for id, c in pairs(crafters) do
    if not reserved[id] and (os.clock() - c.seen) < STALE then
      idle[#idle + 1] = { id = id, name = c.name }
    end
  end
  return idle
end

local function anyCrafters()
  for _, c in pairs(crafters) do
    if (os.clock() - c.seen) < STALE then return true end
  end
  return false
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

-- dispatch one batch to one turtle: load ingredients, craft, unload.
-- returns crafted count and an error class ("load" = missing ingredients now,
-- won't self-resolve; "craft" = transient turtle failure, worth retrying).
local function dispatchBatch(a)
  local step = a.step.spec
  local loaded, err = loadBatch(a.worker.name, step, a.count)
  if loaded == 0 then
    unloadTurtle(a.worker.name)
    return 0, "load", err
  end
  rednet.send(a.worker.id, { type = "craft", times = loaded }, PROTO)
  local ok, deadline = false, os.clock() + 30
  while os.clock() < deadline do
    local senderId, msg = rednet.receive(PROTO, 5)
    if senderId == a.worker.id and type(msg) == "table" and msg.type == "done" then
      ok = msg.ok
      break
    end
  end
  unloadTurtle(a.worker.name)
  return ok and loaded or 0, ok and nil or "craft"
end

-- the dispatch loop: OWNS all turtle I/O. Event-driven - blocks on
-- "sched_work" when idle, then drains eligible work in back-to-back rounds
-- with no artificial sleep. One rescan per round (not per batch). Multiple
-- craftItem callers submit jobs concurrently; priority decides service order.
local MAX_STUCK_ROUNDS = 3
local jobStuck = {}   -- scheduler entry -> consecutive no-progress rounds

local function schedulerLoop()
  while true do
    if not (sched and sched:pending()) then
      os.pullEvent("sched_work")
    end
    local workers = idleCrafters()
    if #workers == 0 then
      -- nothing to dispatch to; wait for a heartbeat/roster change rather
      -- than spin. crafters that come online re-fire sched_work via ping.
      if anyCrafters() then sleep(1) else os.pullEvent("sched_work") end
    else
      local assigns = sched:assign(workers)
      if #assigns == 0 then
        sleep(0.2)  -- eligible-but-not-ready (deps); brief yield
      else
        for _, a in ipairs(assigns) do
          reserved[a.worker.id] = true
        end
        local results, fns = {}, {}
        for i, a in ipairs(assigns) do
          fns[i] = function()
            local crafted, class, detail = dispatchBatch(a)
            results[i] = { a = a, crafted = crafted, class = class, detail = detail }
          end
        end
        parallel.waitForAll(table.unpack(fns))
        for _, r in ipairs(results) do
          reserved[r.a.worker.id] = nil
        end
        rescan()  -- one scan per round: slots moved as turtles pulled
        -- tally per-job outcomes for this round
        local progressed, loadFail, sample = {}, {}, {}
        for _, r in ipairs(results) do
          local job = r.a.job
          sample[job] = r.a.step.spec.output
          if r.crafted > 0 then progressed[job] = true end
          if r.class == "load" and r.crafted == 0 then
            loadFail[job] = r.detail or ("missing ingredients for " ..
              displayName(r.a.step.spec.output))
          end
        end
        -- credit successful/partial batches (load-failures contributed nothing)
        for _, r in ipairs(results) do
          if not (r.class == "load" and r.crafted == 0) then
            sched:complete(r.a, r.crafted)
          end
        end
        -- finish each touched job at most once: hard load-failure, or stuck
        local seen = {}
        for _, r in ipairs(results) do
          local job = r.a.job
          if not seen[job] then
            seen[job] = true
            if loadFail[job] and not progressed[job] then
              sched:fail(job, loadFail[job]); jobStuck[job.id] = nil
            elseif progressed[job] then
              jobStuck[job.id] = 0
            else
              jobStuck[job.id] = (jobStuck[job.id] or 0) + 1
              if jobStuck[job.id] >= MAX_STUCK_ROUNDS then
                sched:fail(job, "no progress on " .. displayName(sample[job]))
                jobStuck[job.id] = nil
              end
            end
          end
        end
        local snap = sched:snapshot()
        -- prune stuck-counters for jobs that are no longer live (bounded mem)
        local live = {}
        for _, s in ipairs(snap) do live[s.id] = true end
        for id in pairs(jobStuck) do
          if not live[id] then jobStuck[id] = nil end
        end
        if snap[1] then
          status = ("craft %s %d/%d  [queue %d]"):format(
            snap[1].label, snap[1].done, snap[1].total, #snap)
        end
        draw()
      end
    end
  end
end

-- submit a craft job and block THIS coroutine until it finishes. The scheduler
-- loop keeps running, so concurrent callers (player command + stock reconcile)
-- interleave by priority instead of serializing behind a global lock.
local jobSeq = 0
local function craftItem(targetId, count, priority, report)
  if not db or not planner then return false, "recipe db or planner not loaded" end
  if not sched then return false, "scheduler not loaded" end
  rescan()
  local have = {}
  for id, entry in pairs(index) do have[id] = entry.count end
  local steps, missingItems = planner.plan(db, have, targetId, count)
  if not steps then return false, nil, missingItems end

  jobSeq = jobSeq + 1
  local evt = "craftdone_" .. jobSeq
  local jobId = targetId .. "#" .. jobSeq
  sched:submit({
    id = jobId, priority = priority or 0, steps = steps,
    label = displayName(targetId),
    onDone = function(ok, reason) os.queueEvent(evt, ok, reason) end,
  })
  os.queueEvent("sched_work")
  rednet.broadcast({ type = "ping" }, PROTO)  -- warm roster once, not per round
  -- progress is rendered by schedulerLoop from sched:snapshot(); the caller's
  -- report closure (if any) is retained only for API compatibility.
  local _, ok, reason = os.pullEvent(evt)
  return ok, ok and #steps or reason
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

-- ----------------------------------------------------------------- grid mode
-- RS/AE2-style interactive terminal: live search, scroll, click to withdraw
local function gridSearchList(q)
  local list = {}
  local ql = q:lower()
  for _, id in ipairs(sorted) do
    if q == "" or id:gsub("^[^:]+:", ""):find(ql, 1, true)
      or displayName(id):lower():find(ql, 1, true) then
      list[#list + 1] = id
    end
  end
  if db and q ~= "" then
    local seen = {}
    for _, id in ipairs(list) do seen[id] = true end
    for _, id in ipairs(db.search(q, 30)) do
      if not seen[id] then list[#list + 1] = id end
    end
  end
  return list
end

local function gridLoop()
  local q, sel, top = "", 1, 1
  local msg = "type=search  click/enter=64  rclick=1  TAB=craft  DEL=exit"
  applyTheme(term)
  local timer = os.startTimer(5)

  local function statusLine(text)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    term.setTextColor(colors.lightGray)
    term.write(text:sub(1, w))
    term.setBackgroundColor(colors.black)
  end

  while true do
    local w, h = term.getSize()
    local rows = h - 2
    local list = gridSearchList(q)
    if sel > #list then sel = math.max(1, #list) end
    if sel < top then top = sel end
    if sel > top + rows - 1 then top = sel - rows + 1 end

    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    term.setTextColor(colors.cyan)
    term.write(" search: ")
    term.setTextColor(colors.white)
    term.write(q)
    term.setTextColor(colors.lightGray)
    term.write("_")
    for i = 1, rows do
      term.setCursorPos(1, i + 1)
      local id = list[top + i - 1]
      if id then
        local entry = index[id]
        local count = entry and entry.count or 0
        term.setBackgroundColor((top + i - 1) == sel and colors.blue or colors.black)
        term.clearLine()
        term.setTextColor(count > 0 and colors.cyan or colors.orange)
        term.write((" %6s "):format(count > 0 and fmt(count) or "craft"))
        term.setTextColor(colors.white)
        term.write(displayName(id):sub(1, w - 11))
        if db and db.isCraftable(id) then
          term.setTextColor(colors.green)
          term.write(" +")
        end
      else
        term.setBackgroundColor(colors.black)
        term.clearLine()
      end
    end
    statusLine(msg)

    local function takeRow(rowIdx, amount)
      local id = list[rowIdx]
      if not id then return end
      local entry = index[id]
      if entry and entry.count > 0 then
        local moved = withdraw(id, math.min(amount, entry.count))
        rescan()
        msg = ("took %d x %s -> barrel"):format(moved, displayName(id))
      elseif db and db.isCraftable(id) then
        msg = "not in stock - TAB to craft it"
      end
    end

    local function craftRow(rowIdx)
      local id = list[rowIdx]
      if not (id and db and db.isCraftable(id)) then
        msg = "not craftable"
        return
      end
      statusLine(" craft how many " .. displayName(id) .. "? ")
      term.setCursorPos(1, select(2, term.getSize()))
      term.setBackgroundColor(colors.gray)
      term.setTextColor(colors.white)
      write(" craft how many " .. displayName(id) .. "? ")
      local n = tonumber(read())
      term.setBackgroundColor(colors.black)
      if not n or n < 1 then
        msg = "cancelled"
        return
      end
      local ok, detail, missingItems = craftItem(id, n, 0, function(step, done, i, total)
        statusLine((" crafting %s (%s)"):format(displayName(step.output),
          i and (i .. "/" .. total) or tostring(done)))
      end)
      if ok then
        local moved = withdraw(id, n)
        rescan()
        msg = ("crafted %d x %s -> barrel"):format(moved, displayName(id))
      elseif missingItems then
        local firstId, firstAmount = next(missingItems)
        msg = ("missing materials e.g. %d x %s"):format(firstAmount or 0,
          displayName((firstId or "?"):gsub("^#", "")))
      else
        msg = "craft failed: " .. tostring(detail)
      end
    end

    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "char" then
      q = q .. ev[2]
      sel = 1
    elseif e == "key" then
      local k = ev[2]
      if k == keys.backspace then
        q = q:sub(1, -2)
        sel = 1
      elseif k == keys.up then sel = math.max(1, sel - 1)
      elseif k == keys.down then sel = sel + 1
      elseif k == keys.pageUp then sel = math.max(1, sel - rows)
      elseif k == keys.pageDown then sel = sel + rows
      elseif k == keys.enter then takeRow(sel, 64)
      elseif k == keys.tab then craftRow(sel)
      elseif k == keys.delete then break
      end
    elseif e == "mouse_scroll" then
      sel = math.max(1, sel + ev[2] * 3)
    elseif e == "mouse_click" then
      local btn, _, y = ev[2], ev[3], ev[4]
      if y >= 2 and y <= h - 1 then
        local rowIdx = top + (y - 2)
        if list[rowIdx] then
          sel = rowIdx
          takeRow(rowIdx, btn == 1 and 64 or 1)
        end
      end
    elseif e == "timer" and ev[2] == timer then
      timer = os.startTimer(5)
    end
  end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
end

local function rosterLoop()
  while true do
    local senderId, msg = rednet.receive(PROTO)
    if type(msg) == "table" and msg.type == "hello" and msg.name then
      local fresh = not crafters[senderId]
      crafters[senderId] = { name = msg.name, seen = os.clock() }
      -- a newly-online turtle may unblock a dispatch loop that stalled for
      -- lack of workers; nudge it (cheap, only on first sighting)
      if fresh then os.queueEvent("sched_work") end
    end
  end
end

-- -------------------------------------------------------------- auto-stocker
local STOCK_FILE = "stock.cfg"
local STOCK_INTERVAL = 60
local stockTargets = {}   -- item id -> target count
local stockStatusById = {} -- item id -> last reconcile note ("ok" / reason)

local function loadStock()
  stockTargets = {}
  local f = fs.open(STOCK_FILE, "r")
  if not f then return end
  while true do
    local line = f.readLine()
    if not line then break end
    local id, count = line:match("^(%S+)%s+(%d+)$")
    if id then stockTargets[id] = tonumber(count) end
  end
  f.close()
end

local function saveStock()
  local f = fs.open(STOCK_FILE, "w")
  for id, count in pairs(stockTargets) do
    f.write(id .. " " .. count .. "\n")
  end
  f.close()
end

local function stockLoop()
  sleep(30)
  while true do
    if db and planner then
      for id, target in pairs(stockTargets) do
        local haveCount = index[id] and index[id].count or 0
        if haveCount < target then
          local wanted = target - haveCount
          -- priority 10: background reconcile yields to player requests (p0)
          local ok, detail, missingItems = craftItem(id, wanted, 10, function(step, done, i, total)
            status = ("stock: %s (%s)"):format(displayName(step.output),
              i and (i .. "/" .. total) or tostring(done))
            draw()
          end)
          if ok then
            stockStatusById[id] = "ok"
            status = ("stocked %d x %s"):format(wanted, displayName(id))
          elseif missingItems then
            local mid, amount = next(missingItems)
            stockStatusById[id] = ("need %d %s"):format(amount or 0,
              displayName((mid or "?"):gsub("^#", "")))
          else
            stockStatusById[id] = detail or "blocked"
          end
          draw()
          break  -- one target per cycle; keep the factory polite
        else
          stockStatusById[id] = "ok"
        end
      end
    end
    sleep(STOCK_INTERVAL)
  end
end

local function printStats()
  print(("%-8s %6s %7s %7s %7s %7s"):format("op", "count", "avg", "p50", "p99", "max"))
  for op, m in pairs(metrics) do
    print(("%-8s %6d %7.1f %7d %7d %7d"):format(op, m.count, m.totalMs / m.count,
      percentile(m.samples, 0.5), percentile(m.samples, 0.99), m.maxMs))
  end
end

local function commandLoop()
  gridLoop()
  print("warehouse v3: " .. controllerName)
  print("delivery: " .. (deliveryName or "NONE FOUND"))
  print("recipes: " .. (db and (db.recipeCount() .. " loaded") or "not deployed"))
  print("'grid' reopens the item grid")
  print("commands: find <text> | get/craft <text> [count] | put | refresh | stats | quit")
  while true do
    write("> ")
    local line = read()
    local args = {}
    for word in line:gmatch("%S+") do args[#args + 1] = word end
    local cmd = table.remove(args, 1)

    if cmd == "quit" then
      return
    elseif cmd == "grid" then
      gridLoop()
      print("back to console - 'grid' to reopen")
    elseif cmd == "stats" then
      printStats()
    elseif cmd == "stock" then
      local sub = args[1]
      if sub == "add" and args[2] then
        local count = tonumber(args[#args])
        if count then table.remove(args) else count = 64 end
        table.remove(args, 1)
        local hits = db and db.search(table.concat(args, " "), 5) or {}
        if #hits == 0 then
          print("no craftable item matches")
        else
          stockTargets[hits[1]] = count
          saveStock()
          print(("keeping %d x %s stocked"):format(count, displayName(hits[1])))
        end
      elseif sub == "del" and args[2] then
        table.remove(args, 1)
        local query = table.concat(args, " "):lower()
        for id in pairs(stockTargets) do
          if id:lower():find(query, 1, true) or displayName(id):lower():find(query, 1, true) then
            stockTargets[id] = nil
            saveStock()
            print("no longer stocking " .. displayName(id))
          end
        end
      else
        local n = 0
        for id, target in pairs(stockTargets) do
          local haveCount = index[id] and index[id].count or 0
          local note = stockStatusById[id]
          local flag = ""
          if haveCount >= target then flag = "ok"
          elseif note and note ~= "ok" then flag = note end
          print(("%6d / %-6d %-18s %s"):format(haveCount, target,
            displayName(id):sub(1, 18), flag))
          n = n + 1
        end
        if n == 0 then print("no stock targets - stock add <item> <count>") end
      end
    elseif cmd == "crafters" then
      rednet.broadcast({ type = "ping" }, PROTO)
      sleep(1.5)
      local found = 0
      for id, c in pairs(crafters) do
        print(("  #%d %s (seen %ds ago)"):format(id, c.name, os.clock() - c.seen))
        found = found + 1
      end
      if found == 0 then print("no crafter turtles responding") end
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
          local ok, detail, missingItems = craftItem(target, count, 0, function(step, done, i, total)
            status = ("crafting %s"):format(displayName(step.output))
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
loadStock()
draw()
parallel.waitForAny(rescanLoop, touchLoop, commandLoop, rosterLoop, stockLoop, schedulerLoop)
