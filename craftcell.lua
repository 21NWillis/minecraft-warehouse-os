-- craftcell: firmware for a craftd crafting cell (design: planning/craftd.md).
-- A crafty turtle docked between two chests: INPUT chest in FRONT,
-- OUTPUT chest BELOW. The hub stages exact ingredients into the input
-- chest and sends a job over rednet; the cell forms the grid, crafts
-- the batch, drops results into the output chest, reports done.
--
-- COMMISSIONING (once per cell):
--   1. Place: output chest, turtle on top of it, input chest in front
--      of the turtle. Wire BOTH chests into the warehouse network
--      (wired modems) - the hub reaches them by peripheral name.
--   2. On the turtle: craftcell <cellId> <inputChestName> <outputChestName>
--      (names as the wired network sees them, e.g. minecraft:chest_42)
--      Saved to craftcell.cfg; later runs need no args.
--   3. Attach a wireless modem (any side) for the job channel.
-- The turtle needs a crafting table upgrade (crafty turtle) and never
-- moves - fuel is irrelevant.
local hub = require("crafthub")

local PROTOCOL = "paperclip.craft"
local CFG = "craftcell.cfg"

local tArgs = { ... }
local cfg
if #tArgs >= 3 then
  cfg = { id = tArgs[1], input = tArgs[2], output = tArgs[3] }
  local h = fs.open(CFG, "w")
  h.write(textutils.serialize(cfg))
  h.close()
elseif fs.exists(CFG) then
  local h = fs.open(CFG, "r")
  cfg = textutils.unserialize(h.readAll())
  h.close()
else
  print("usage: craftcell <cellId> <inputChestName> <outputChestName>")
  return
end

for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" and peripheral.wrap(side).isWireless
      and peripheral.wrap(side).isWireless() then
    rednet.open(side)
  end
end

local function snapshot()
  local inv = {}
  for slot = 1, 16 do
    inv[slot] = turtle.getItemDetail(slot)
  end
  return inv
end

local function clearAll()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.dropDown()
    end
  end
  turtle.select(1)
end

local function runJob(job)
  -- pull everything staged for us
  while turtle.suck() do end
  local transfers, clears = hub.arrangePlan(snapshot(), job.grid, job.count)
  if not transfers then
    -- clears holds the missing item name in the error case
    clearAll()   -- return partial staging via output for hub recovery
    return false, "missing " .. tostring(clears)
  end
  for _, t in ipairs(transfers) do
    turtle.select(t.from)
    turtle.transferTo(t.to, t.count)
  end
  for _, slot in ipairs(clears) do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.dropDown()
    end
  end
  turtle.select(16)
  if not turtle.craft(job.count) then
    clearAll()
    return false, "craft failed for " .. tostring(job.output)
  end
  clearAll()   -- results (and any container-item returns) to output
  return true
end

print(("craftcell %s online (in=%s out=%s)"):format(cfg.id, cfg.input, cfg.output))
rednet.broadcast({ type = "hello", id = cfg.id, caps = { "craft" },
  input = cfg.input, output = cfg.output }, PROTOCOL)

while true do
  local sender, msg = rednet.receive(PROTOCOL)
  if type(msg) == "table" then
    if msg.type == "ping" then
      rednet.send(sender, { type = "hello", id = cfg.id, caps = { "craft" },
        input = cfg.input, output = cfg.output }, PROTOCOL)
    elseif msg.type == "job" and msg.cell == cfg.id then
      print(("job: %dx %s"):format(msg.count, msg.output))
      local ok, err = runJob(msg)
      rednet.send(sender, { type = ok and "done" or "error", id = cfg.id,
        job = msg.jobId, err = err }, PROTOCOL)
    end
  end
end
