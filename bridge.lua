-- bridge: cross-layer comms between the Minecraft world and Claude, relayed by
-- you. Two directions:
--
--   bridge snapshot   -- gather live world state, upload to pastebin, print a
--                        code. You paste the code to Claude; Claude now SEES
--                        the world (inventory, crafters, peripherals, disk, and
--                        the warehouse's serve metrics if running).
--
--   bridge run        -- fetch a Lua command file Claude committed to the repo
--                        (bridge_commands.lua), run it against the world in a
--                        sandboxed pcall, capture its output, upload it, print a
--                        code. Claude now ACTS on the world and reads the result.
--
-- The loop: you relay two short codes, Claude operates the base between them.
local BASE_FILE = ".updatebase"

local function readBase()
  if not fs.exists(BASE_FILE) then return nil end
  local f = fs.open(BASE_FILE, "r"); local b = f.readAll(); f.close()
  return b
end

local function uploadFile(path)
  -- reuse the built-in pastebin uploader; the user reads the printed code
  shell.run("pastebin", "put", path)
end

local function openModems()
  for _, s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" then rednet.open(s) end
  end
end

local function gatherState()
  local L = {}
  local function w(...) L[#L + 1] = table.concat({ ... }) end

  w("== DATACENTER SNAPSHOT ==")
  w("computer: id=", os.getComputerID(), " label=", tostring(os.getComputerLabel()))
  w("disk: ", fs.getFreeSpace("/"), " free / ", fs.getCapacity and fs.getCapacity("/") or "?", " cap")

  w("\n-- peripherals --")
  for _, name in ipairs(peripheral.getNames()) do
    w("  ", name, "  [", peripheral.getType(name), "]")
  end

  -- storage controller summary
  local controllerName
  for _, name in ipairs(peripheral.getNames()) do
    if name:find("controller", 1, true) then controllerName = name break end
  end
  if controllerName then
    local c = peripheral.wrap(controllerName)
    local counts = {}
    local slots = 0
    for _, item in pairs(c.list()) do
      counts[item.name] = (counts[item.name] or 0) + item.count
      slots = slots + 1
    end
    local sorted, total, types = {}, 0, 0
    for id, n in pairs(counts) do sorted[#sorted + 1] = { id, n }; total = total + n; types = types + 1 end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    w("\n-- storage (", controllerName, "): ", total, " items, ", types, " types, ", slots, " slots --")
    for i = 1, math.min(20, #sorted) do w("  ", sorted[i][2], "x  ", sorted[i][1]) end
  else
    w("\n-- storage: no controller on network --")
  end

  -- crafter roster (ping the gigafactory protocol)
  openModems()
  rednet.broadcast({ type = "ping" }, "gigafactory")
  local seen = {}
  local deadline = os.epoch("utc") + 1500
  while os.epoch("utc") < deadline do
    local id, msg = rednet.receive("gigafactory", 0.3)
    if type(msg) == "table" and msg.type == "hello" then seen[msg.name] = id end
  end
  w("\n-- crafter turtles --")
  local n = 0
  for name, id in pairs(seen) do w("  ", name, " (#", id, ")"); n = n + 1 end
  if n == 0 then w("  none responding") end

  -- warehouse serve metrics, if it wrote a state file
  if fs.exists("wh_state.txt") then
    local f = fs.open("wh_state.txt", "r"); local s = f.readAll(); f.close()
    w("\n-- warehouse state --")
    w(s)
  end

  return table.concat(L, "\n")
end

local args = { ... }
local cmd = args[1]

if cmd == "snapshot" then
  local text = gatherState()
  local f = fs.open(".snapshot.txt", "w"); f.write(text); f.close()
  print("uploading snapshot...")
  uploadFile(".snapshot.txt")
  print("^ give Claude that code")

elseif cmd == "run" then
  local base = readBase()
  if not base then print("no update base url set; run `update <url>` first") return end
  if base:sub(-1) ~= "/" then base = base .. "/" end
  print("fetching bridge_commands.lua ...")
  local res, err = http.get(base .. "bridge_commands.lua")
  if not res then print("fetch failed: " .. tostring(err)) return end
  local code = res.readAll(); res.close()

  -- run Claude's code with output captured to a window, then upload it
  local w, h = term.getSize()
  local win = window.create(term.current(), 1, 1, w, h, false)
  local fn, cErr = load(code, "bridge_commands", "t", _ENV)
  local lines = {}
  if not fn then
    lines = { "compile error: " .. tostring(cErr) }
  else
    local old = term.redirect(win)
    local ok, runErr = pcall(fn)
    term.redirect(old)
    for y = 1, h do lines[y] = (win.getLine(y) or ""):gsub("%s+$", "") end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    if not ok then lines[#lines + 1] = "runtime error: " .. tostring(runErr) end
  end
  local f = fs.open(".bridge_out.txt", "w"); f.write(table.concat(lines, "\n")); f.close()
  print("uploading result...")
  uploadFile(".bridge_out.txt")
  print("^ give Claude that code")

else
  print("bridge snapshot   - dump world state for Claude to read")
  print("bridge run        - run Claude's committed commands against the world")
end
