package.path = "./?.lua;" .. package.path
_TEST = true
local vault = require("vault")
local p, f = 0, 0
local function check(n, c) if c then p=p+1; print("PASS  "..n) else f=f+1; print("FAIL  "..n) end end
check("hash is deterministic", vault.hash("s1","hunter2") == vault.hash("s1","hunter2"))
check("different password -> different hash", vault.hash("s1","a") ~= vault.hash("s1","b"))
check("different salt -> different hash", vault.hash("s1","x") ~= vault.hash("s2","x"))
check("hash is 8 hex chars", vault.hash("s","p"):match("^%x%x%x%x%x%x%x%x$") ~= nil)
print(("\n%d passed, %d failed"):format(p, f))
if f > 0 then os.exit(1) end
