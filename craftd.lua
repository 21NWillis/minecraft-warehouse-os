-- craftd: the dispatcher daemon (design: planning/craftd.md).
-- Runs on the warehouse computer (wired modem to storage, wireless for
-- the cell channel). Takes an order, plans it with planner against live
-- storage, and drives DOCKLESS cells: each cell turtle sits on a wired
-- modem, so its own 16 slots are the staging chest AND the output chest.
-- Drain cell -> push exact BOM into the turtle -> send job -> pull
-- results back to storage. No per-cell chests exist.
--
-- SETUP: none. Storage auto-discovers: every inventory on the wired
-- network counts, EXCLUDING cell turtles and anything whose name
-- mentions "controller" (the SS controller refuses automation inserts -
-- the ancient wound stays closed). Optional craftd.cfg overrides:
--   { storage = { "chestName1", "chestName2", ... } }
--
-- USAGE:
--   craftd                       interactive: order loop
--   craftd <count> <search...>   one order, then exit
local db = require("recipedb")
local planner = require("planner")
local hub = require("crafthub")

local PROTOCOL = "paperclip.craft"
local CFG = "craftd.cfg"

local cfg = {}
if fs.exists(CFG) then
  local cfgFile = fs.open(CFG, "r")
  cfg = textutils.unserialize(cfgFile.readAll()) or {}
  cfgFile.close()
end

-- open EVERY modem for the job channel: rednet rides wired networks
-- too, and the cells are already on the wire - no wireless required
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    rednet.open(side)
  end
end

print("loading recipe database...")
local ok, err = db.load("data")
if not ok then
  printError("recipedb: " .. tostring(err))
  return
end

-- ---------------------------------------------------------------- storage
local cells = {}   -- filled by discoverCells; needed to exclude cell invs

-- Advanced Peripherals integration (activates automatically when the
-- server gets AP): the ME Bridge folds AE2 network stock into the
-- storage view and stages straight into cells; the Chat Box takes
-- !craft orders from anywhere and announces results. AP's Lua API
-- drifts between versions, so every call is pcall-armored - expect a
-- short field-rename session on first contact.
local function meBridge()
  return peripheral.find("meBridge")
end

local function chatBox()
  return peripheral.find("chatBox")
end

local voice = require("voice")
local function chatSay(msg)
  -- the corporate voice: department-bracketed, sanitized, filed
  voice.say(chatBox(), "PAYROLL", msg)
end

-- Controllers are PULL-ONLY: reading and extracting from the SS
-- controller works (that is how the whole spine becomes visible with
-- one modem) but inserting into it voids items - the emerald famine.
-- Results only ever return to insertable (non-controller) storage.
local function storagePeripherals()
  local names
  if cfg.storage then
    names = cfg.storage
  else
    names = {}
    local cellInvs = {}
    for _, c in pairs(cells) do cellInvs[c.inv] = true end
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name, "inventory")
          and not peripheral.hasType(name, "turtle")
          and not cellInvs[name] then
        names[#names + 1] = name
      end
    end
  end
  local out = {}
  for _, name in ipairs(names) do
    local p = peripheral.wrap(name)
    if p and p.list then
      out[#out + 1] = { name = name, p = p,
        pullOnly = name:find("controller") ~= nil }
    end
  end
  return out
end

-- live inventory: totals + location index
local function scanStorage()
  local have, where = {}, {}
  for _, s in ipairs(storagePeripherals()) do
    local okList, listing = pcall(s.p.list)
    if okList and listing then
      for slot, item in pairs(listing) do
        have[item.name] = (have[item.name] or 0) + item.count
        where[item.name] = where[item.name] or {}
        table.insert(where[item.name], { store = s, slot = slot, count = item.count })
      end
    else
      printError(("storage %s unreadable: %s"):format(s.name, tostring(listing)))
    end
  end
  -- AE2 network stock via the ME Bridge (pull-only, like the controller)
  local me = meBridge()
  if me then
    local okMe, items = pcall(me.listItems)
    if okMe and type(items) == "table" then
      for _, item in ipairs(items) do
        local n = item.amount or item.count or 0
        if item.name and n > 0 then
          have[item.name] = (have[item.name] or 0) + n
          where[item.name] = where[item.name] or {}
          table.insert(where[item.name], { me = true, count = n })
        end
      end
    end
  end
  return have, where
end

-- push `count` of `item` into a cell's input chest; pushItems moves at
-- most one stack per call (printfit lesson), so loop every location.
-- pushItems only works WITHIN one wired network: if the target name
-- does not exist from the source's network, that is a split-network
-- wiring problem, not a crash.
local function stage(where, item, count, targetName)
  local remaining = count
  for _, loc in ipairs(where[item] or {}) do
    -- AE2 location: export straight from the ME network into the cell
    if loc.me then
      local me = meBridge()
      while remaining > 0 and loc.count > 0 and me do
        local okExp, moved = pcall(me.exportItemToPeripheral,
          { name = item, count = math.min(remaining, 64) }, targetName)
        if not okExp or not moved or moved == 0 then break end
        remaining = remaining - moved
        loc.count = loc.count - moved
      end
      if remaining <= 0 then break end
    end
    while not loc.me and remaining > 0 and loc.count > 0 do
      local okPush, moved = pcall(loc.store.p.pushItems, targetName, loc.slot, remaining)
      if not okPush then
        printError(("stage: %s cannot reach %s (%s)"):format(
          loc.store.name, targetName, tostring(moved)))
        printError("SPLIT NETWORK: the cell's modem and the storage modems")
        printError("must share ONE cable tree - not just both touch this computer.")
        return false
      end
      if moved == 0 then break end
      remaining = remaining - moved
      loc.count = loc.count - moved
    end
    if remaining <= 0 then break end
  end
  return remaining <= 0
end

-- drain a cell turtle back into storage (also used pre-stage so the
-- cell always starts a job empty). Hardened per outside review:
-- peripheral list hoisted (was rebuilt 16x per drain), every push
-- pcall'd (a split network must not kill the daemon), and the count
-- of items stranded aboard is RETURNED - "order complete" while
-- results sit in a cell is a lie we no longer tell.
local function collect(invName)
  local out = peripheral.wrap(invName)
  if not (out and out.list) then return 0 end
  local okL, listing = pcall(out.list)
  if not (okL and listing) then return 0 end
  local stores = storagePeripherals()
  for slot in pairs(listing) do
    for _, s in ipairs(stores) do
      if not s.pullOnly then
        while true do
          local okP, moved = pcall(out.pushItems, s.name, slot)
          if not okP or not moved or moved == 0 then break end
        end
        local okD, d = pcall(out.getItemDetail, slot)
        if okD and not d then break end   -- slot empty, next slot
      end
    end
  end
  local leftover = 0
  local okA, after = pcall(out.list)
  if okA and after then
    for _, item in pairs(after) do leftover = leftover + item.count end
  end
  return leftover
end

-- ------------------------------------------------------------------ cells
local function discoverCells()
  rednet.broadcast({ type = "ping" }, PROTOCOL)
  local deadline = os.clock() + 2
  while os.clock() < deadline do
    local _, msg = rednet.receive(PROTOCOL, 0.5)
    if type(msg) == "table" and msg.type == "hello" and msg.id and msg.inv then
      -- a cell may hold several names (several modems); use whichever
      -- name this computer's wired network can actually reach
      local inv, reachable = msg.inv, peripheral.isPresent(msg.inv)
      for _, candidate in ipairs(msg.invs or {}) do
        if peripheral.isPresent(candidate) then
          inv, reachable = candidate, true
          break
        end
      end
      cells[msg.id] = { id = msg.id, busy = 0, inv = inv, reachable = reachable }
    end
  end
end

-- ------------------------------------------------------------------ orders
local nextJobId = 1

local function runStep(step, where)
  local batches = hub.batchSizes(step.times)
  local inFlight = {}
  local bi = 1
  -- every abort path MUST release busy counts, or the cells involved
  -- are excluded from pickCell until the daemon restarts (leak found
  -- by outside review)
  local function abort(why)
    for _, entry in pairs(inFlight) do
      entry.cell.busy = math.max(0, (entry.cell.busy or 1) - 1)
    end
    return false, why
  end
  while bi <= #batches or next(inFlight) do
    -- dispatch to every idle cell
    while bi <= #batches do
      local cell = hub.pickCell(cells)
      if not cell or (cell.busy or 0) > 0 then break end
      local batch = batches[bi]
      local totals = hub.stageTotals(step, batch)
      collect(cell.inv)   -- cell must start a job empty (dockless doctrine)
      local staged = true
      for item, count in pairs(totals) do
        if not stage(where, item, count, cell.inv) then
          staged = false
          break
        end
      end
      if not staged then
        collect(cell.inv)   -- return the partial stage to storage
        return abort("storage ran short staging " .. step.output)
      end
      local job = hub.jobFor(step, batch)
      job.type, job.cell, job.jobId = "job", cell.id, nextJobId
      nextJobId = nextJobId + 1
      rednet.broadcast(job, PROTOCOL)
      cell.busy = (cell.busy or 0) + 1
      inFlight[job.jobId] = { cell = cell, job = job, totals = totals }
      bi = bi + 1
    end
    -- await a completion
    local _, msg = rednet.receive(PROTOCOL, 30)
    if type(msg) == "table" and (msg.type == "done" or msg.type == "error")
        and inFlight[msg.job] then
      local entry = inFlight[msg.job]
      local cell = entry.cell
      cell.busy = cell.busy - 1
      local stranded = collect(cell.inv)
      if stranded > 0 then
        printError(("WARNING: %d item(s) stranded aboard %s - storage full?")
          :format(stranded, cell.id))
      end
      inFlight[msg.job] = nil
      if msg.type == "error" then
        -- surplus = stray items aboard the cell; we just drained it, so
        -- restage and resend the same job once before giving up
        if tostring(msg.err):find("surplus") and not entry.retried then
          local _, w2 = scanStorage()
          local restaged = true
          for item, cnt in pairs(entry.totals) do
            if not stage(w2, item, cnt, cell.inv) then restaged = false break end
          end
          if restaged then
            entry.retried = true
            rednet.broadcast(entry.job, PROTOCOL)
            cell.busy = cell.busy + 1
            inFlight[msg.job] = entry
          else
            return abort("restage after surplus failed for " .. step.output)
          end
        else
          return abort(("cell %s: %s"):format(msg.id, tostring(msg.err)))
        end
      end
    elseif msg == nil and next(inFlight) then
      return abort("timed out waiting on a cell")
    end
  end
  return true
end

-- returns ok, summary so serve mode can report to remote UIs
local function order(count, query)
  local target
  if query:sub(1, 3) == "id:" then
    -- exact form (craftui sends this): what was selected is what runs
    target = query:sub(4)
  else
    local hits = db.search(query, 5)
    if #hits == 0 then
      print("no recipe matches: " .. query)
      return false, "no recipe matches " .. query
    end
    target = hits[1]
  end
  print(("order: %d x %s"):format(count, db.name(target) or target))
  local have, where = scanStorage()
  local steps, missing = planner.plan(db, have, target, count)
  if not steps then
    -- our cells can't make it; can AE2's crafting CPUs? (patterned
    -- recipes forwarded via the ME Bridge, fire-and-forget)
    local me = meBridge()
    if me then
      local okC, craftable = pcall(me.isItemCraftable, { name = target })
      if okC and craftable then
        local okS = pcall(me.craftItem, { name = target, count = count })
        if okS then
          print("forwarded to AE2 crafting CPUs")
          return true, ("%d x %s -> AE2 CPUs"):format(count, db.name(target) or target)
        end
      end
    end
    print("cannot craft - missing:")
    local first
    for item, n in pairs(missing) do
      print(("  %d x %s"):format(n, item))
      first = first or (n .. "x " .. item)
    end
    return false, "missing " .. tostring(first)
  end
  print(("%d steps planned"):format(#steps))
  for i, step in ipairs(steps) do
    print(("step %d/%d: %dx %s"):format(i, #steps, step.times, step.output))
    local okStep, serr = runStep(step, where)
    if not okStep then
      printError("stopped: " .. tostring(serr))
      return false, tostring(serr)
    end
    -- refresh the location index: outputs just landed in storage
    have, where = scanStorage()
  end
  print("order complete.")
  return true, ("%d x %s done"):format(count, db.name(target) or target)
end

-- ------------------------------------------------------------------ main
discoverCells()
local n = 0
for _ in pairs(cells) do n = n + 1 end
print(("craftd online: %d cell(s), %d storage(s)%s"):format(n,
  #storagePeripherals(), cfg.storage and "" or " [auto-discovered]"))
for id, c in pairs(cells) do
  if not c.reachable then
    printError(("cell %s answers rednet but '%s' is NOT on my wired network")
      :format(id, c.inv))
    printError("- cable its modem into the same run as the storage modems")
  end
end
if not cfg.storage then
  -- show the whole network's inventories and each verdict, so a bad
  -- wiring day diagnoses itself from the screen
  local cellInvs = {}
  for _, c in pairs(cells) do cellInvs[c.inv] = true end
  local insertable = 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") then
      local verdict = "STORAGE"
      if peripheral.hasType(name, "turtle") then verdict = "skip: turtle"
      elseif cellInvs[name] then verdict = "skip: craft cell"
      elseif name:find("controller") then
        verdict = "STORAGE (pull-only: never insert into a controller)"
      else
        insertable = insertable + 1
      end
      print(("  %-40s %s"):format(name, verdict))
    end
  end
  if #storagePeripherals() == 0 then
    print("NO STORAGE ON THE WIRE: modem the SS controller (pull-only")
    print("spine visibility) plus ONE plain chest (the return tray).")
  elseif insertable == 0 then
    print("WARNING: no insertable storage - results have nowhere to go.")
    print("Wire ONE plain chest as the return tray.")
  end
end

local args = { ... }

-- queue daemon: orders arrive via the local orderq file (craftui in
-- another multishell tab) or rednet 'paperclip.order' (remote UIs, and
-- someday the Paperclip Terminal). Submissions return instantly; the
-- queue drains through the cells while every UI stays free.
if args[1] == "serve" then
  local Q = "paperclip.order"
  print("craftd queue daemon up (orderq file, rednet " .. Q .. ", terminals)")
  local queue = {}
  local lastCatalog = 0
  local lastDiscover = 0

  local function terminals()
    return { peripheral.find("paperclip_terminal") }
  end

  local function toastAll(text, okT)
    for _, t in ipairs(terminals()) do
      pcall(t.toast, text, okT and true or false)
    end
  end

  local function pushCatalog()
    local have = scanStorage()
    local entries = {}
    for item, n in pairs(have) do
      entries[#entries + 1] = { id = item, name = db.name(item) or item, stock = n }
    end
    table.sort(entries, function(a, b) return a.stock > b.stock end)
    while #entries > 200 do entries[#entries] = nil end
    for _, t in ipairs(terminals()) do
      pcall(t.setCatalog, entries)
    end
  end

  local function pushQueue(activeLabel)
    local lines = {}
    if activeLabel then
      lines[#lines + 1] = { label = activeLabel, status = "crafting..." }
    end
    for _, q in ipairs(queue) do
      lines[#lines + 1] = { label = q.count .. " x " .. (db.name(q.item) or q.item),
        status = "queued" }
    end
    for _, t in ipairs(terminals()) do
      pcall(t.setQueue, lines)
    end
  end

  while true do
    -- ingest: local file (craftui tab)
    if fs.exists("orderq") then
      local h = fs.open("orderq", "r")
      local text = h.readAll()
      h.close()
      fs.delete("orderq")
      for line in text:gmatch("[^\n]+") do
        local cnt, item = line:match("^(%d+)|(.+)$")
        if item then queue[#queue + 1] = { item = item, count = tonumber(cnt) } end
      end
    end
    -- ingest: terminal clicks
    for _, t in ipairs(terminals()) do
      local okG, orders = pcall(t.getOrders)
      if okG and type(orders) == "table" then
        for _, o in ipairs(orders) do
          queue[#queue + 1] = { item = o.item, count = o.count or 1 }
          print(("terminal order: %d x %s (%s)"):format(o.count or 1,
            o.item, tostring(o.player)))
        end
      end
    end
    -- ingest: one event pump for rednet, AP chat, and the tick timer.
    -- (rednet.receive DISCARDS other events - it would eat chat.)
    local sender, msg
    do
      local timer = os.startTimer(1)
      while true do
        local ev = { os.pullEvent() }
        if ev[1] == "timer" and ev[2] == timer then
          break
        elseif ev[1] == "rednet_message" and ev[4] == Q then
          sender, msg = ev[2], ev[3]
          os.cancelTimer(timer)
          break
        elseif ev[1] == "chat" then
          -- AP Chat Box: order from anywhere in the world.
          --   !craft <count> <query>   !stock <query>   !queue
          local user, text = ev[2], tostring(ev[3])
          local cnt, cq = text:match("^!craft%s+(%d+)%s+(.+)$")
          if cnt and cq then
            local hits = db.search(cq, 1)
            if #hits == 0 then
              chatSay("no recipe matches '" .. cq .. "'")
            else
              queue[#queue + 1] = { item = hits[1], count = tonumber(cnt) }
              chatSay(("queued %s x %s (#%d) for %s"):format(cnt,
                db.name(hits[1]) or hits[1], #queue, tostring(user)))
            end
          elseif text == "!queue" then
            chatSay(#queue == 0 and "queue empty"
              or (#queue .. " order(s) queued"))
          elseif text:match("^!stock%s+") then
            local sq = text:match("^!stock%s+(.+)$")
            local haveNow = scanStorage()
            local best, bestN
            for itm, n in pairs(haveNow) do
              if itm:find(sq, 1, true) and (not bestN or n > bestN) then
                best, bestN = itm, n
              end
            end
            chatSay(best and (bestN .. " x " .. best)
              or ("no stock matching " .. sq))
          end
        end
      end
    end
    if type(msg) == "table" and msg.type == "order" and msg.item then
      queue[#queue + 1] = { item = msg.item, count = msg.count or 1,
        sender = sender, tag = msg.tag }
      rednet.send(sender, { type = "queued", tag = msg.tag, depth = #queue }, Q)
    end
    -- catalog heartbeat every ~10s
    if os.clock() - lastCatalog > 10 then
      lastCatalog = os.clock()
      pushCatalog()
      pushQueue(nil)
    end
    -- nursery-grown cells announce on ping: re-discover every ~30s so
    -- fleet growth is actually zero-config (only while idle - discovery
    -- pumps the craft protocol and could eat order traffic mid-job)
    if #queue == 0 and os.clock() - (lastDiscover or 0) > 30 then
      lastDiscover = os.clock()
      discoverCells()
    end
    -- drain one order
    if #queue > 0 then
      local jobO = table.remove(queue, 1)
      local label = jobO.count .. " x " .. (db.name(jobO.item) or jobO.item)
      print(("[q:%d] %s"):format(#queue, label))
      pushQueue(label)
      -- pcall: one peripheral throw inside an order must not kill the
      -- daemon (a bad cable day is survivable; a dead storefront isn't)
      local okCall, okO, text = pcall(order, jobO.count, "id:" .. jobO.item)
      if not okCall then okO, text = false, "internal: " .. tostring(okO) end
      toastAll(okO and label or (label .. ": " .. tostring(text)), okO)
      chatSay((okO and "done: " or "FAILED: ") .. label)
      if jobO.sender then
        rednet.send(jobO.sender, { type = "result", ok = okO and true or false,
          text = tostring(text), tag = jobO.tag }, Q)
      end
      pushQueue(nil)
      pushCatalog()
      lastCatalog = os.clock()
    end
  end
end

if #args >= 2 then
  order(tonumber(args[1]) or 1, table.concat(args, " ", 2))
  return
end

while true do
  io.write("craft> ")
  local line = read()
  if line == "exit" then break end
  if line:match("^stock") then
    local filter = line:match("^stock%s+(.+)$")
    local have = scanStorage()
    local rows = {}
    for item, n in pairs(have) do
      if not filter or item:find(filter, 1, true) then
        rows[#rows + 1] = { item = item, n = n }
      end
    end
    table.sort(rows, function(a, b) return a.n > b.n end)
    print(#rows .. " item type(s) visible:")
    for i = 1, math.min(#rows, 12) do
      print(("  %6d  %s"):format(rows[i].n, rows[i].item))
    end
  elseif line == "cells" then
    discoverCells()
    for id, c in pairs(cells) do
      print(("  %s busy=%d inv=%s"):format(id, c.busy or 0, c.inv))
    end
  elseif line and line ~= "" then
    local count, query = line:match("^(%d+)%s+(.+)$")
    if count then
      order(tonumber(count), query)
    else
      order(1, line)
    end
  end
end
