-- survey: non-destructive as-built scan of a wing -> pastebin. The
-- world-state channel: run it (or let surveyd run it nightly), then hand
-- the printed 6-char code to Claude, who fetches pastebin raw and gets
-- ground-truth voxel state to plan maintenance/retrofits against.
--
-- USAGE:  survey <width> <length> <height> [label]
--
-- SETUP (orientation is behavioral - the `go forward` test):
--   Park the turtle at the box's origin corner, at the LOWEST y level to
--   scan. Width grows to its RIGHT, length straight ahead, height UP; the
--   turtle's own cell is (0,0,0). It NEVER digs: obstacles are routed
--   around and recorded by name; sealed spaces report as unknown. A little
--   fuel in any slot (a scan costs roughly 2 moves per air cell). Ends
--   parked exactly where it started, so surveyd can loop it forever.
local s = require("surveylogic")

local tArgs = { ... }
local w = tonumber(tArgs[1])
local l = tonumber(tArgs[2])
local h = tonumber(tArgs[3])
local label = tArgs[4] or "wing"
if not w or not l or not h or w < 1 or l < 1 or h < 1 then
  print("usage: survey <width> <length> <height> [label]")
  return
end

local FUEL = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true,
  ["minecraft:coal_block"] = true,
}

local ops = {
  forward = turtle.forward, up = turtle.up, down = turtle.down,
  turnLeft = function() turtle.turnLeft() return true end,
  turnRight = function() turtle.turnRight() return true end,
  detect = turtle.detect, detectUp = turtle.detectUp, detectDown = turtle.detectDown,
  inspect = turtle.inspect, inspectUp = turtle.inspectUp, inspectDown = turtle.inspectDown,
  attack = turtle.attack, attackUp = turtle.attackUp, attackDown = turtle.attackDown,
  getFuelLevel = turtle.getFuelLevel,
  tryRefuel = function()
    local before = turtle.getFuelLevel()
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and FUEL[d.name] then turtle.select(slot); turtle.refuel(16) end
    end
    turtle.select(1)
    return turtle.getFuelLevel() > before
  end,
}

print(("survey %dx%dx%d '%s' - fuel %s"):format(w, l, h, label,
  tostring(turtle.getFuelLevel())))
local st = s.scan(ops, {
  w = w, l = l, h = h,
  onProgress = function(n)
    if n % 50 == 0 then print(("  %d cells scanned"):format(n)) end
  end,
})
print(("scan %s: %d air, %d solid, %d blocked, %d unknown"):format(
  st.stopped, st.visited, st.solids, st.blocked, st.unknown))

local json = s.encode(st, label)
local fname = "survey_" .. label .. ".json"
local fh = fs.open(fname, "w")
fh.write(json)
fh.close()

-- upload: pastebin's API with the dev key CC's own ROM program ships
-- (read from the ROM so a pack update can't strand us on a stale key)
local function devKey()
  local rom = fs.open("rom/programs/http/pastebin.lua", "r")
  if rom then
    local src = rom.readAll()
    rom.close()
    local key = src:match('key%s*=%s*"(%x+)"')
    if key then return key end
  end
  return "0ec2eb25b6166c0c27a394ae118ad829"
end

local code
if http then
  local resp = http.post("https://pastebin.com/api/api_post.php",
    "api_option=paste&api_dev_key=" .. devKey()
    .. "&api_paste_name=" .. textutils.urlEncode("paperclip survey " .. label)
    .. "&api_paste_code=" .. textutils.urlEncode(json))
  if resp then
    local url = resp.readAll()
    resp.close()
    code = url:match("pastebin%.com/(%w+)")
  end
end

if code then
  print("=====================================")
  print("  SURVEY '" .. label .. "' -> pastebin " .. code)
  print("=====================================")
  -- best-effort broadcast so the NOC board can display the code
  pcall(function()
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" then rednet.open(name) end
    end
    rednet.broadcast({
      type = "survey", label = label, code = code,
      visited = st.visited, solids = st.solids,
      blocked = st.blocked, unknown = st.unknown, stopped = st.stopped,
    }, "paperclip.survey")
  end)
else
  print("upload failed - saved locally as " .. fname)
  print("retry with: pastebin put " .. fname)
end

if st.stopped == "fuel" then
  print("NOTE: partial scan - ran low on fuel. Add coal and rerun.")
elseif st.stopped == "trapped" then
  print("WARNING: could not return to start pose - check on me!")
end
