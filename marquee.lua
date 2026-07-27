-- marquee: a big scrolling sign for a monitor - base signage / propaganda.
-- Usage: marquee [message...]   (defaults to a Paperclip Corp banner)
-- Uses the largest readable text scale and smooth right-to-left scroll.
local monitor = peripheral.find("monitor")
if not monitor then error("no monitor attached") end

local args = { ... }
local msg = #args > 0 and table.concat(args, " ")
  or "PAPERCLIP CORP  *  AUTHORIZED PERSONNEL ONLY  *  THE FACTORY MUST GROW  *  "
if not msg:find("  %*  ") then msg = msg .. "   " end   -- pad single messages

monitor.setTextScale(2)
pcall(monitor.setPaletteColour, colors.black, 0x0a0e12)
pcall(monitor.setPaletteColour, colors.cyan, 0x4cc9f0)
local w, h = monitor.getSize()
local row = math.max(1, math.floor(h / 2))
local pad = string.rep(" ", w)
local strip = pad .. msg           -- lead-in so it scrolls onto an empty screen
local offset = 0

local timer = os.startTimer(0.08)
while true do
  local ev, a = os.pullEvent()
  if ev == "timer" and a == timer then
    monitor.setBackgroundColor(colors.black); monitor.clear()
    monitor.setCursorPos(1, row); monitor.setTextColor(colors.cyan)
    local window = {}
    for i = 0, w - 1 do
      local idx = ((offset + i) % #strip) + 1
      window[#window + 1] = strip:sub(idx, idx)
    end
    monitor.write(table.concat(window))
    offset = (offset + 1) % #strip
    timer = os.startTimer(0.08)
  elseif ev == "char" or ev == "monitor_touch" then
    break
  end
end
monitor.setTextScale(1); monitor.setBackgroundColor(colors.black); monitor.clear()
monitor.setCursorPos(1, 1)
