package.path = "./?.lua;" .. package.path
_TEST = true
local oracle = require("oracle")
local p, f = 0, 0
local function check(n, c) if c then p=p+1; print("PASS  "..n) else f=f+1; print("FAIL  "..n) end end
check("same question -> same answer", oracle.answer("will i be rich?") == oracle.answer("will i be rich?"))
check("case/space-insensitive", oracle.answer("Will I  be RICH?") == oracle.answer("will i be rich?"))
check("answer is always valid", (function()
  for _,q in ipairs({"a","b","the factory","hello world","xyz"}) do
    local a = oracle.answer(q); local ok=false
    for _,v in ipairs(oracle.answers) do if v==a then ok=true end end
    if not ok then return false end
  end
  return true
end)())
print(("\n%d passed, %d failed"):format(p, f))
if f > 0 then os.exit(1) end
