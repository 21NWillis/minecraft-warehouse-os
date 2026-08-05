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

for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    local m = peripheral.wrap(side)
    if m.isWireless and m.isWireless() then rednet.open(side) end
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
  return have, where
end

-- push `count` of `item` into a cell's input chest; pushItems moves at
-- most one stack per call (printfit lesson), so loop every location
local function stage(where, item, count, targetName)
  local remaining = count
  for _, loc in ipairs(where[item] or {}) do
    while remaining > 0 and loc.count > 0 do
      local moved = loc.store.p.pushItems(targetName, loc.slot, remaining)
      if moved == 0 then break end
      remaining = remaining - moved
      loc.count = loc.count - moved
    end
    if remaining <= 0 then break end
  end
  return remaining <= 0
end

-- drain a cell turtle back into storage (also used pre-stage so the
-- cell always starts a job empty)
local function collect(invName)
  local out = peripheral.wrap(invName)
  if not (out and out.list) then return end
  for slot in pairs(out.list()) do
    for _, s in ipairs(storagePeripherals()) do
      if not s.pullOnly then
        while out.pushItems(s.name, slot) > 0 do end
        if not out.list()[slot] then break end
      end
    end
  end
end

-- ------------------------------------------------------------------ cells
local function discoverCells()
  rednet.broadcast({ type = "ping" }, PROTOCOL)
  local deadline = os.clock() + 2
  while os.clock() < deadline do
    local _, msg = rednet.receive(PROTOCOL, 0.5)
    if type(msg) == "table" and msg.type == "hello" and msg.id and msg.inv then
      cells[msg.id] = { id = msg.id, busy = 0, inv = msg.inv }
    end
  end
end

-- ------------------------------------------------------------------ orders
local nextJobId = 1

local function runStep(step, where)
  local batches = hub.batchSizes(step.times)
  local inFlight = {}
  local bi = 1
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
        return false, "storage ran short staging " .. step.output
      end
      local job = hub.jobFor(step, batch)
      job.type, job.cell, job.jobId = "job", cell.id, nextJobId
      nextJobId = nextJobId + 1
      rednet.broadcast(job, PROTOCOL)
      cell.busy = (cell.busy or 0) + 1
      inFlight[job.jobId] = cell
      bi = bi + 1
    end
    -- await a completion
    local _, msg = rednet.receive(PROTOCOL, 30)
    if type(msg) == "table" and (msg.type == "done" or msg.type == "error")
        and inFlight[msg.job] then
      local cell = inFlight[msg.job]
      cell.busy = cell.busy - 1
      collect(cell.inv)
      inFlight[msg.job] = nil
      if msg.type == "error" then
        return false, ("cell %s: %s"):format(msg.id, tostring(msg.err))
      end
    elseif msg == nil and next(inFlight) then
      return false, "timed out waiting on a cell"
    end
  end
  return true
end

local function order(count, query)
  local hits = db.search(query, 5)
  if #hits == 0 then
    print("no recipe matches: " .. query)
    return
  end
  local target = hits[1]
  print(("order: %d x %s"):format(count, db.name(target) or target))
  local have, where = scanStorage()
  local steps, missing = planner.plan(db, have, target, count)
  if not steps then
    print("cannot craft - missing:")
    for item, n in pairs(missing) do
      print(("  %d x %s"):format(n, item))
    end
    return
  end
  print(("%d steps planned"):format(#steps))
  for i, step in ipairs(steps) do
    print(("step %d/%d: %dx %s"):format(i, #steps, step.times, step.output))
    local okStep, serr = runStep(step, where)
    if not okStep then
      printError("stopped: " .. tostring(serr))
      return
    end
    -- refresh the location index: outputs just landed in storage
    have, where = scanStorage()
  end
  print("order complete.")
end

-- ------------------------------------------------------------------ main
discoverCells()
local n = 0
for _ in pairs(cells) do n = n + 1 end
print(("craftd online: %d cell(s), %d storage(s)%s"):format(n,
  #storagePeripherals(), cfg.storage and "" or " [auto-discovered]"))
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
if #args >= 2 then
  order(tonumber(args[1]) or 1, table.concat(args, " ", 2))
  return
end

while true do
  io.write("craft> ")
  local line = read()
  if line == "exit" then break end
  if line == "cells" then
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
