-- craftcell: firmware for a craftd crafting cell (design: planning/craftd.md).
-- DOCKLESS (v2): the turtle IS the chest. A wired modem touching the
-- turtle exposes its 16 slots as a network inventory, so the hub pushes
-- ingredients straight into the turtle and pulls results straight out.
-- No input chest, no output chest, no per-cell cabling beyond touching
-- the spine.
--
-- COMMISSIONING (once per cell):
--   1. Park a crafty turtle against a wired modem on the warehouse
--      network. Right-click the modem so it activates (red ring ON).
--   2. Attach a wireless modem (any side) for the job channel.
--   3. Run: craftcell <cellId>     (saved to craftcell.cfg)
-- The turtle never moves - fuel is irrelevant.
local hub = require("crafthub")

local PROTOCOL = "paperclip.craft"
local CFG = "craftcell.cfg"

local tArgs = { ... }
local cfg
if #tArgs >= 1 then
  cfg = { id = tArgs[1] }
  local h = fs.open(CFG, "w")
  h.write(textutils.serialize(cfg))
  h.close()
  -- cells self-resurrect: chunk unloads killed the maiden cell, and an
  -- amnesiac turtle is just a chest with ambition
  local s = fs.open("startup", "w")
  s.write('shell.run("craftcell")')
  s.close()
elseif fs.exists(CFG) then
  local h = fs.open(CFG, "r")
  cfg = textutils.unserialize(h.readAll())
  h.close()
else
  print("usage: craftcell <cellId>")
  return
end

-- the wired modem is everything: it names this turtle on the item
-- network AND carries the rednet job channel. No wireless needed.
-- MULTIPLE modems can touch a turtle (leftovers from rewiring), each
-- binding it under a DIFFERENT name - announce every name we hold and
-- let the hub use whichever is reachable on its network.
local invNames = {}
for _, side in ipairs({ "left", "right", "top", "bottom", "front", "back" }) do
  if peripheral.getType(side) == "modem" then
    local m = peripheral.wrap(side)
    if m.isWireless and not m.isWireless() then
      local okN, name = pcall(m.getNameLocal)
      if okN and name then invNames[#invNames + 1] = name end
    end
    rednet.open(side)
  end
end
if #invNames == 0 then
  print("no ACTIVE wired modem touching me - park me on the spine and")
  print("right-click the modem (red ring must be lit), then rerun")
  return
end
local invName = invNames[1]
if #invNames > 1 then
  print("WARNING: " .. #invNames .. " wired modems touch me ("
    .. table.concat(invNames, ", ") .. ") - remove the stale ones")
end

local function snapshot()
  local inv = {}
  for slot = 1, 16 do
    inv[slot] = turtle.getItemDetail(slot)
  end
  return inv
end

local function runJob(job)
  -- ingredients were pushed into us over the wire; the hub drained us
  -- first, so the inventory holds exactly this job's BOM
  local transfers, clears = hub.arrangePlan(snapshot(), job.grid, job.count)
  if not transfers then
    return false, "missing " .. tostring(clears)
  end
  for _, t in ipairs(transfers) do
    turtle.select(t.from)
    if not turtle.transferTo(t.to, t.count) then
      return false, ("transfer %d->%d blocked"):format(t.from, t.to)
    end
  end
  if #clears > 0 then
    -- exact staging means nothing should be left over; surplus is a
    -- staging bug and the hub needs to drain and retry
    return false, ("unexpected surplus in %d slot(s)"):format(#clears)
  end
  -- verify the formed grid: exact item and count in every mapped slot,
  -- and every non-grid slot empty (turtle.craft requires it)
  local gridSlots = {}
  for g, item in pairs(job.grid) do
    local slot = hub.turtleSlot(g)
    gridSlots[slot] = true
    local d = turtle.getItemDetail(slot)
    if not d or d.name ~= item or d.count ~= job.count then
      return false, ("grid verify failed at slot %d"):format(slot)
    end
  end
  for slot = 1, 16 do
    if not gridSlots[slot] and turtle.getItemCount(slot) > 0 then
      return false, ("non-grid slot %d not empty"):format(slot)
    end
  end
  turtle.select(4)   -- results land starting in a non-grid slot
  if not turtle.craft(job.count) then
    return false, "craft failed for " .. tostring(job.output)
  end
  return true   -- results stay aboard; the hub pulls them over the wire
end

print(("craftcell %s online (inv=%s)"):format(cfg.id,
  table.concat(invNames, "/")))
rednet.broadcast({ type = "hello", id = cfg.id, caps = { "craft" },
  inv = invName, invs = invNames }, PROTOCOL)

while true do
  local sender, msg = rednet.receive(PROTOCOL)
  if type(msg) == "table" then
    if msg.type == "ping" then
      rednet.send(sender, { type = "hello", id = cfg.id, caps = { "craft" },
        inv = invName, invs = invNames }, PROTOCOL)
    elseif msg.type == "job" and msg.cell == cfg.id then
      print(("job: %dx %s"):format(msg.count, msg.output))
      local ok, err = runJob(msg)
      rednet.send(sender, { type = ok and "done" or "error", id = cfg.id,
        job = msg.jobId, err = err }, PROTOCOL)
    end
  end
end
