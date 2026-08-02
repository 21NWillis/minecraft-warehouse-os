-- headless tests for metrics: histogram bucketing + quantile math, since
-- profiler/reactor decisions get read off these numbers.
package.path = "./?.lua;" .. package.path
local metrics = require("metrics")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- counters / gauges
local c = metrics.counter("t.count")
c:inc()
c:inc(4)
check("counter accumulates", c.v == 5, c.v)
metrics.gauge("t.gauge"):set(42)
check("gauge sets", metrics.gauges["t.gauge"].v == 42)
check("same name returns same instance", metrics.counter("t.count") == c)

-- histogram bucket edges: bucket b covers [2^(b-2), 2^(b-1)), bucket 1 is <1
local h = metrics.histo("t.edges")
h:observe(0.5)   -- bucket 1
h:observe(1)     -- bucket 2  [1,2)
h:observe(3)     -- bucket 3  [2,4)
h:observe(100)   -- bucket 8  [64,128)
check("count/sum/max track", h.count == 4 and h.sum == 104.5 and h.max == 100,
  h.count .. "/" .. h.sum .. "/" .. h.max)
check("sub-1ms lands in bucket 1", h.b[1] == 1)
check("1ms lands in [1,2)", h.b[2] == 1)
check("3ms lands in [2,4)", h.b[3] == 1)
check("100ms lands in [64,128)", h.b[8] == 1)

-- quantiles report bucket upper bounds and are monotone in q
local q50, q99 = h:quantile(0.5), h:quantile(0.99)
check("p50 of {0.5,1,3,100} is 2", q50 == 2, q50)
check("p99 covers the tail bucket", q99 == 128, q99)
check("quantile monotone", h:quantile(0.25) <= q50 and q50 <= q99)

-- p50 of a uniform 1..1000 spread lands near the middle (log2 upper bound)
local u = metrics.histo("t.uniform")
for i = 1, 1000 do u:observe(i) end
local p50 = u:quantile(0.5)
check("uniform p50 within a bucket of true median", p50 >= 256 and p50 <= 1024, p50)
check("empty histo quantile is 0", metrics.histo("t.empty"):quantile(0.5) == 0)

-- giant value saturates the top bucket rather than exploding
local g = metrics.histo("t.big")
g:observe(1e9)
check("huge observation lands in top bucket", g.b[18] == 1)
check("huge quantile reports top bound", g:quantile(0.5) == 2 ^ 17, g:quantile(0.5))

-- snapshot is flat + complete
local snap = metrics.snapshot()
check("snapshot has counter", snap.c["t.count"] == 5)
check("snapshot has gauge", snap.g["t.gauge"] == 42)
check("snapshot histo has percentiles",
  snap.h["t.edges"].p50 == 2 and snap.h["t.edges"].count == 4)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
