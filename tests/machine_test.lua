package.path = "./?.lua;" .. package.path
_TEST = true
local machine = require("machine")
local p, f = 0, 0
local function check(n, c, d) if c then p=p+1; print("PASS  "..n) else f=f+1; print("FAIL  "..n..(d and("  -- "..tostring(d))or"")) end end
local cfg = { target = 64 }
check("feeds up to target when empty", machine.plan(0, 0, cfg).feed == 64)
check("tops up a partial input", machine.plan(50, 0, cfg).feed == 14)
check("no feed when at target", machine.plan(64, 0, cfg).feed == 0)
check("no overfeed above target", machine.plan(70, 0, cfg).feed == 0)
check("drains when output present", machine.plan(64, 5, cfg).drain == true)
check("no drain when output empty", machine.plan(64, 0, cfg).drain == false)
check("respects custom target", machine.plan(0, 0, { target = 16 }).feed == 16)
print(("\n%d passed, %d failed"):format(p, f))
if f > 0 then os.exit(1) end
