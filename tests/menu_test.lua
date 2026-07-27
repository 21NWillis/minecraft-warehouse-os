package.path = "./?.lua;" .. package.path
_TEST = true
local menu = require("menu")
local p, f = 0, 0
local function check(n, c) if c then p=p+1; print("PASS  "..n) else f=f+1; print("FAIL  "..n) end end
check("registry non-empty", #menu.programs > 0)
check("every entry has script + desc", (function()
  for _, e in ipairs(menu.programs) do
    if type(e.script) ~= "string" or type(e.desc) ~= "string" then return false end
  end
  return true
end)())
-- each listed script should actually exist in the repo
local missing = {}
for _, e in ipairs(menu.programs) do
  local fh = io.open(e.script .. ".lua", "r")
  if fh then fh:close() else missing[#missing+1] = e.script end
end
check("all listed programs exist as files", #missing == 0, table.concat(missing, ","))
print(("\n%d passed, %d failed"):format(p, f))
if f > 0 then os.exit(1) end
