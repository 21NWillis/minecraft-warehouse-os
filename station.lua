-- station: the ATM10 mini-PC dispatcher IO shell. All decisions live in
-- stationlogic (headless-proven); this file only wraps peripherals,
-- moves items, and talks rednet. See planning/atm10_station_spec.md.
--
-- Setup: drop a station_cfg.lua next to this (see spec for shape),
-- wire buffer + importer + machines + this computer onto one wired
-- modem network, then run `station`.
--
-- Operator commands (rednet, protocol paperclip.station):
--   { cmd = "clearjam", machine = "<periph name>" }
--   { cmd = "status" }  -> replies with the heartbeat table

local sl = require("stationlogic")

local CFG_FILE  = "station_cfg.lua"
local PROTOCOL  = "paperclip.station"
local HEARTBEAT = 5     -- seconds between rednet heartbeats

assert(fs.exists(CFG_FILE), "station: missing " .. CFG_FILE)
local cfg = dofile(CFG_FILE)
cfg.pollFast = cfg.pollFast or 0.25
cfg.pollIdle = cfg.pollIdle or 2.0

local buffer   = peripheral.wrap(cfg.buffer)   or error("no buffer: "   .. cfg.buffer)
local importer = peripheral.wrap(cfg.importer) or error("no importer: " .. cfg.importer)
local machines = {}
for _, name in ipairs(cfg.machines) do
  machines[name] = peripheral.wrap(name) or error("no machine: " .. name)
end

-- open every modem for rednet (wired NIC needs no activation to use)
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then pcall(rednet.open, side) end
end

local st = sl.new(cfg)
local now = function() return os.epoch("utc") / 1000 end

local function log(msg) print(("[%s] %s"):format(cfg.class, msg)) end

local function alert(kind, detail)
  rednet.broadcast({ station = cfg.class, kind = kind, detail = detail }, PROTOCOL)
end

-- snapshot buffer contents as {slot -> {name=,count=}}
local function scanBuffer()
  local slots = {}
  for slot, item in pairs(buffer.list()) do
    slots[slot] = { name = item.name, count = item.count }
  end
  return slots
end

-- recipe lookup for the collect pass
local function recipeFor(key)
  for _, r in ipairs(cfg.recipes) do
    if r.key == key then return r end
  end
end

-- pull finished outputs from every machine into the importer chest;
-- each expected-output pull marks one in-flight set complete.
local function collect()
  local pulled = 0
  for mName in pairs(machines) do
    for _, q in ipairs(st.inFlight[mName] or {}) do
      local r = recipeFor(q.key)
      if r then
        for _, out in ipairs(r.outputs) do
          local n = importer.pullItems(mName, out.fromSlot)
          if n and n > 0 then
            sl.complete(st, mName, q.key)
            pulled = pulled + n
            break
          end
        end
      end
    end
  end
  return pulled
end

-- flush everything in the buffer to the importer (stale leftovers go
-- back to RS so the task re-plans instead of rotting here)
local function flushBuffer()
  for slot in pairs(buffer.list()) do
    importer.pullItems(cfg.buffer, slot)
  end
  log("flushed stale leftovers to importer")
  alert("flush")
end

log(("station up: %d machines, maxInFlight=%d"):format(#cfg.machines, cfg.maxInFlight))
local lastBeat = 0

while true do
  local t = now()

  -- 1. collect finished work first (frees in-flight slots for assign)
  local pulled = collect()

  -- 2. scan + parse + dispatch
  local slots = scanBuffer()
  local sets, leftovers = sl.parseSets(cfg, slots)
  local plan = sl.assign(st, sets, t)
  for _, a in ipairs(plan) do
    local moves
    moves, slots = sl.movePlan(cfg, slots, a.key)
    if moves then
      for _, mv in ipairs(moves) do
        buffer.pushItems(a.machine, mv.fromSlot, mv.count, mv.toSlot)
      end
    else
      -- ledger thinks a set exists that slots can't supply: undo the
      -- in-flight entry and let the next scan re-parse from scratch
      sl.complete(st, a.machine, a.key)
    end
  end

  -- 3. jams + stale leftovers
  for _, m in ipairs(sl.checkJams(st, t)) do
    log("JAM: " .. m)
    alert("jam", m)
  end
  if sl.staleLeftovers(st, leftovers, t) then flushBuffer() end

  -- 4. heartbeat + operator commands
  if t - lastBeat >= HEARTBEAT then
    local s = sl.status(st)
    s.station = cfg.class
    rednet.broadcast(s, PROTOCOL)
    lastBeat = t
  end

  -- 5. adaptive sleep: fast while there's work, idle otherwise
  local busy = (#plan > 0) or (pulled > 0) or (sl.status(st).inFlight > 0)
  local timer = os.startTimer(busy and cfg.pollFast or cfg.pollIdle)
  while true do
    local ev, p1, p2, p3 = os.pullEvent()
    if ev == "timer" and p1 == timer then break end
    if ev == "rednet_message" and p3 == PROTOCOL and type(p2) == "table" then
      if p2.cmd == "clearjam" and p2.machine then
        sl.clearJam(st, p2.machine)
        log("jam cleared by operator: " .. p2.machine)
      elseif p2.cmd == "status" then
        local s = sl.status(st)
        s.station = cfg.class
        rednet.send(p1, s, PROTOCOL)
      end
    end
  end
end
