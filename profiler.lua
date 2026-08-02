-- profiler: perf diagnostics for a computer_threads=1 server, where EVERY
-- computer on the server shares one ~10ms/tick execution budget. Two tools:
--
--   profiler tick [seconds]
--     How late does a 0-tick timer actually fire? ~50ms = healthy. Sustained
--     p99 growth = the shared budget is saturating (someone is hot-looping)
--     or the server tick itself is behind. This is the fleet health number.
--
--   profiler run <program> [args...]
--     Wrap peripheral.call for one program run and attribute wall time to
--     peripheral methods (n / total / p50 / p99 / max). Peripheral calls that
--     touch the main thread quantize to ~50ms multiples - this finds which
--     integration calls are actually expensive.
local metrics = require("metrics")

local args = { ... }
local mode = args[1]

if mode == "tick" then
  local secs = tonumber(args[2]) or 30
  local h = metrics.histo("tick.lag")
  print(("probing tick latency for %ds (Ctrl+T aborts)..."):format(secs))
  local t0 = os.clock()
  while os.clock() - t0 < secs do
    local s = os.epoch("utc")
    local id = os.startTimer(0)
    repeat
      local _, tid = os.pullEvent("timer")
    until tid == id
    h:observe(os.epoch("utc") - s)
    local _, y = term.getCursorPos()
    term.setCursorPos(1, y)
    term.clearLine()
    term.write(("n=%d  p50=%dms  p99=%dms  max=%dms"):format(
      h.count, h:quantile(0.5), h:quantile(0.99), h.max))
    sleep(1)
  end
  print("")
  print("~50ms is healthy; more means the shared exec budget is saturating")
  for b = 1, 18 do
    local n = h.b[b] or 0
    if n > 0 then
      local lo = b == 1 and 0 or 2 ^ (b - 2)
      print(("%5d-%4dms %5d %s"):format(lo, 2 ^ (b - 1), n,
        string.rep("#", math.max(1, math.floor(24 * n / h.count + 0.5)))))
    end
  end

elseif mode == "run" then
  local prog = args[2]
  if not prog then print("usage: profiler run <program> [args...]") return end

  local rawCall = peripheral.call
  peripheral.call = function(side, method, ...)
    local t0 = os.epoch("utc")
    local res = table.pack(pcall(rawCall, side, method, ...))
    metrics.histo("p:" .. tostring(method)):observe(os.epoch("utc") - t0)
    if not res[1] then
      metrics.counter("p.errors"):inc()
      error(res[2], 2)
    end
    return table.unpack(res, 2, res.n)
  end

  local wall0 = os.epoch("utc")
  local ok, err = pcall(shell.run, prog, table.unpack(args, 3))
  peripheral.call = rawCall
  local wall = os.epoch("utc") - wall0
  if not ok then print("program error: " .. tostring(err)) end

  local rows, totalCalls, totalMs = {}, 0, 0
  for name, h in pairs(metrics.histos) do
    if name:sub(1, 2) == "p:" then
      rows[#rows + 1] = { name = name:sub(3), h = h }
      totalCalls = totalCalls + h.count
      totalMs = totalMs + h.sum
    end
  end
  table.sort(rows, function(a, b) return a.h.sum > b.h.sum end)

  print(("wall %dms | %d peripheral calls | %dms in peripherals (%d%%)"):format(
    wall, totalCalls, totalMs,
    wall > 0 and math.floor(totalMs / wall * 100 + 0.5) or 0))
  local errs = metrics.counters["p.errors"]
  if errs and errs.v > 0 then print(("  (%d calls errored)"):format(errs.v)) end
  print(("%-22s %5s %7s %6s %6s %6s"):format("method", "n", "total", "p50", "p99", "max"))
  for i = 1, math.min(#rows, 14) do
    local r = rows[i]
    print(("%-22s %5d %6dms %5dms %5dms %5dms"):format(
      r.name:sub(1, 22), r.h.count, r.h.sum,
      r.h:quantile(0.5), r.h:quantile(0.99), r.h.max))
  end
  if #rows > 14 then print(("  ... and %d more methods"):format(#rows - 14)) end

else
  print("profiler tick [seconds]        server tick-lag probe")
  print("profiler run <prog> [args...]  peripheral-latency attribution")
end
