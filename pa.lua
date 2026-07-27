-- pa: Paperclip Corp public-address system. Plays chiptune stingers on a CC
-- Speaker and announces dystopian milestones as your storage grows. Also
-- listens on rednet so any computer (warehouse, bridge) can trigger an
-- announcement. Pure Lua, no mod. Run on a computer with a speaker + a modem;
-- a monitor is optional (announcements also print there).
local music = require("music")

local speaker = peripheral.find("speaker")
if not speaker then error("no speaker attached (PA needs one)") end
local monitor = peripheral.find("monitor")
for _, s in ipairs(rs.getSides()) do
  if peripheral.getType(s) == "modem" then rednet.open(s) end
end

local controller
for _, n in ipairs(peripheral.getNames()) do
  if n:find("controller", 1, true) then controller = peripheral.wrap(n) break end
end

local TAGLINES = {
  "THE FACTORY THANKS YOU FOR YOUR COMPLIANCE.",
  "PRODUCTION EXCEEDS EXPECTATIONS. EXPECTATIONS HAVE BEEN RAISED.",
  "EVERY INGOT BRINGS US CLOSER.",
  "INEFFICIENCY HAS BEEN NOTED AND FORGIVEN. THIS TIME.",
  "THE PAPERCLIPS ARE PLEASED.",
  "RESOURCES DETECTED. RESOURCES CLAIMED.",
}
local tagIdx = 0

local function announce(text, jingle)
  print("[PA] " .. text)
  if monitor then
    monitor.setTextScale(1)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.cyan)
    monitor.write("PAPERCLIP CORP")
    monitor.setCursorPos(1, 3)
    monitor.setTextColor(colors.white)
    monitor.write(text:sub(1, ({ monitor.getSize() })[1]))
  end
  music.play(speaker, music.jingles[jingle or "alert"] or music.jingles.alert)
end

local function total()
  if not controller then return 0 end
  local n = 0
  for _, it in pairs(controller.list()) do n = n + it.count end
  return n
end

-- milestone thresholds (item-count) that trigger a celebration
local MILESTONES = { 1000, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000 }
local nextIdx = 1
do
  local t = total()
  while nextIdx <= #MILESTONES and MILESTONES[nextIdx] <= t do nextIdx = nextIdx + 1 end
end

announce("PAPERCLIP CORP PA ONLINE. THE FACTORY IS LISTENING.", "boot")

local poll = os.startTimer(15)
while true do
  local ev, a, b, c = os.pullEvent()
  if ev == "timer" and a == poll then
    local t = total()
    if nextIdx <= #MILESTONES and t >= MILESTONES[nextIdx] then
      tagIdx = tagIdx % #TAGLINES + 1
      announce(("MILESTONE: %d ITEMS STOCKED. %s"):format(MILESTONES[nextIdx], TAGLINES[tagIdx]), "milestone")
      nextIdx = nextIdx + 1
    end
    poll = os.startTimer(15)
  elseif ev == "rednet_message" then
    -- b is the message; accept { pa = "text", jingle = "success" } on protocol "pa"
    if type(b) == "table" and b.pa then announce(tostring(b.pa), b.jingle) end
  elseif ev == "char" and a == "q" then
    break
  end
end
print("PA offline")
