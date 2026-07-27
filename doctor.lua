-- doctor: PaperclipOS self-diagnostic. Run this FIRST in-game on a fresh
-- deploy - it checks every assumption the toolkit makes (peripherals, storage
-- controller, monitor capabilities, speaker, recipe DB, crafter turtles, disk)
-- and prints a PASS/WARN/FAIL report, then uploads it to pastebin so the whole
-- environment can be diagnosed at a glance. Pure CC/Lua.
local out = {}
local pass, warn, fail = 0, 0, 0
local function line(s) out[#out + 1] = s; print(s) end
local function ok(m)   pass = pass + 1; line("[ OK ] " .. m) end
local function w(m)    warn = warn + 1; line("[WARN] " .. m) end
local function bad(m)  fail = fail + 1; line("[FAIL] " .. m) end

line("== PaperclipOS doctor ==")
line("computer #" .. os.getComputerID() .. "  label " .. tostring(os.getComputerLabel()))

-- disk
local free = fs.getFreeSpace("/")
local cap = fs.getCapacity and fs.getCapacity("/") or nil
line(("disk: %s free / %s cap"):format(tostring(free), tostring(cap)))
if cap and cap <= 1000000 then w("disk cap is 1MB - recipe DB must stream from GitHub (ok) but tight")
else ok("disk cap adequate") end

-- peripherals inventory
line("\n-- peripherals --")
local kinds = {}
for _, n in ipairs(peripheral.getNames()) do
  local t = peripheral.getType(n)
  kinds[t] = (kinds[t] or 0) + 1
  line(("  %s [%s]"):format(n, t))
end

-- storage controller
line("")
local controllerName
for _, n in ipairs(peripheral.getNames()) do
  if n:find("controller", 1, true) then controllerName = n break end
end
if not controllerName then
  bad("no storage controller found (warehouse/exchange/melink need one)")
else
  local c = peripheral.wrap(controllerName)
  local okList, list = pcall(c.list)
  if not okList then bad("controller " .. controllerName .. " did not respond to list()")
  else
    local slots, items = 0, 0
    for _, it in pairs(list) do slots = slots + 1; items = items + it.count end
    ok(("controller %s: %d slots, %d items indexed"):format(controllerName, slots, items))
    if c.pushItems then ok("controller supports pushItems (transfers will work)")
    else bad("controller has no pushItems - transfers won't work") end
  end
end

-- monitor
line("")
local mon = peripheral.find("monitor")
if not mon then w("no monitor (dashboards/attract/exchange need one)")
else
  mon.setTextScale(0.5)
  local mw, mh = mon.getSize()
  ok(("monitor: %dx%d, color=%s"):format(mw, mh, tostring(mon.isColor and mon.isColor())))
  if mon.setPaletteColour then ok("monitor supports palette (themed UIs ok)") else w("no palette support") end
  if mon.setGraphicsMode then ok("monitor reports pixel graphics mode") else w("no pixel mode (CC:Graphics) - text UIs only") end
end

-- speaker
if peripheral.find("speaker") then ok("speaker present (PA/oracle/vault audio ok)")
else w("no speaker (PA/audio silent)") end

-- modem / mesh
local hasModem, hasWireless = false, false
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then
    hasModem = true
    local m = peripheral.wrap(n)
    if m.isWireless and m.isWireless() then hasWireless = true end
  end
end
if hasModem then ok("modem present" .. (hasWireless and " (incl. wireless/ender - Starlink mesh ok)" or " (wired only - no mesh)"))
else w("no modem (no networking / crafter pool / mesh)") end

-- recipe DB
line("")
local haveRecipes = fs.exists("data/recipes.txt")
local baseUrl = fs.exists(".updatebase")
if haveRecipes then ok("data/recipes.txt on disk")
elseif baseUrl then w("no local recipe DB - will stream from GitHub at load (ok if online)")
else bad("no recipe DB and no update base url (run `update <url>`)") end
-- EMC streams into RAM (too big for the 1MB disk); actually load it to check
local okE, emcload = pcall(require, "emcload")
if okE then
  local emc = emcload.load()
  local ne = 0; for _ in pairs(emc) do ne = ne + 1 end
  if ne > 0 then ok(("EMC data loads (%d items priced%s)"):format(ne, haveRecipes and ", disk" or ", streamed"))
  else w("EMC data empty (transmute/exchange/cost-planner degrade)") end
else w("emcload.lua not deployed") end

-- try loading the DB
local okDb, db = pcall(require, "recipedb")
if okDb and db.load then
  local loaded = db.load("data")
  if loaded then ok("recipedb loaded: " .. db.recipeCount() .. " recipes")
  else w("recipedb present but load() failed (missing data files?)") end
else w("recipedb.lua not deployed") end

-- crafter turtles
line("")
for _, s in ipairs(rs.getSides()) do
  if peripheral.getType(s) == "modem" then rednet.open(s) end
end
rednet.broadcast({ type = "ping" }, "gigafactory")
local seen = {}
local deadline = os.epoch("utc") + 1500
while os.epoch("utc") < deadline do
  local _, msg = rednet.receive("gigafactory", 0.3)
  if type(msg) == "table" and msg.type == "hello" then seen[msg.name] = true end
end
local nturtles = 0; for _ in pairs(seen) do nturtles = nturtles + 1 end
if nturtles > 0 then ok(nturtles .. " crafter turtle(s) responding")
else w("no crafter turtles online (autocrafting will report 'no crafter')") end

-- summary
line(("\n== %d OK, %d WARN, %d FAIL =="):format(pass, warn, fail))
if fail == 0 then line("core looks healthy. warnings are optional features.")
else line("fix FAILs before expecting the warehouse to work.") end

-- upload for remote diagnosis
local f = fs.open(".doctor.txt", "w"); f.write(table.concat(out, "\n")); f.close()
line("\nuploading report...")
shell.run("pastebin", "put", ".doctor.txt")
line("^ send that code to get a full diagnosis")
