-- metrics: counters, gauges, and log2-bucketed latency histograms with cheap
-- p50/p99. Pure Lua (no CC APIs), shared by profiler/reactor/anything that
-- wants numbers instead of vibes. Bucket b covers [2^(b-2), 2^(b-1)) ms;
-- bucket 1 is <1ms. Quantiles report the bucket's upper bound.
local metrics = { counters = {}, gauges = {}, histos = {} }

local Counter = {}
Counter.__index = Counter
function Counter:inc(n) self.v = self.v + (n or 1) end

local Gauge = {}
Gauge.__index = Gauge
function Gauge:set(v) self.v = v end

local Histo = {}
Histo.__index = Histo

function Histo:observe(v)
  self.count = self.count + 1
  self.sum = self.sum + v
  if v > self.max then self.max = v end
  local b = 1
  while v >= 1 and b < 18 do
    v = v / 2
    b = b + 1
  end
  self.b[b] = (self.b[b] or 0) + 1
end

-- upper-bound estimate of the q-quantile (q in (0,1])
function Histo:quantile(q)
  if self.count == 0 then return 0 end
  local target = self.count * q
  local acc = 0
  for b = 1, 18 do
    acc = acc + (self.b[b] or 0)
    if acc >= target then return 2 ^ (b - 1) end
  end
  return self.max
end

function metrics.counter(name)
  local c = metrics.counters[name]
  if not c then
    c = setmetatable({ v = 0 }, Counter)
    metrics.counters[name] = c
  end
  return c
end

function metrics.gauge(name)
  local g = metrics.gauges[name]
  if not g then
    g = setmetatable({ v = 0 }, Gauge)
    metrics.gauges[name] = g
  end
  return g
end

function metrics.histo(name)
  local h = metrics.histos[name]
  if not h then
    h = setmetatable({ count = 0, sum = 0, max = 0, b = {} }, Histo)
    metrics.histos[name] = h
  end
  return h
end

-- flat, serializable snapshot (ship over starlink telemetry, etc.)
function metrics.snapshot()
  local out = { c = {}, g = {}, h = {} }
  for k, v in pairs(metrics.counters) do out.c[k] = v.v end
  for k, v in pairs(metrics.gauges) do out.g[k] = v.v end
  for k, v in pairs(metrics.histos) do
    out.h[k] = { count = v.count, sum = v.sum, max = v.max,
                 p50 = v:quantile(0.5), p99 = v:quantile(0.99) }
  end
  return out
end

return metrics
