-- conway: Game of Life on a monitor. The step rule is a pure function so it's
-- provable headless; the program just renders generations. Seeds with random
-- soup + a couple of gliders. Pure CC/Lua. `conway` on a computer with monitor.
local conway = {}

-- grid is a map "x,y"->true. step() returns the next generation. Toroidal wrap
-- over w x h so gliders loop the screen forever.
function conway.step(alive, w, h)
  local function k(x, y) return x .. "," .. y end
  local counts = {}
  for key in pairs(alive) do
    local x, y = key:match("^(%-?%d+),(%-?%d+)$")
    x, y = tonumber(x), tonumber(y)
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local nx, ny = (x + dx) % w, (y + dy) % h
          counts[k(nx, ny)] = (counts[k(nx, ny)] or 0) + 1
        end
      end
    end
  end
  local next = {}
  for key, n in pairs(counts) do
    if n == 3 or (n == 2 and alive[key]) then next[key] = true end
  end
  return next
end

-- program (skipped when required for tests: no monitor/term in the rig)
if peripheral and peripheral.find then
  local monitor = peripheral.find("monitor")
  if monitor then
    monitor.setTextScale(0.5)
    pcall(monitor.setPaletteColour, colors.black, 0x08120a)
    pcall(monitor.setPaletteColour, colors.lime, 0x8dffb0)
    local w, h = monitor.getSize()
    local alive = {}
    math.randomseed(os.time and os.time() or 1)
    for _ = 1, math.floor(w * h * 0.18) do
      alive[math.random(0, w - 1) .. "," .. math.random(0, h - 1)] = true
    end
    -- drop in a glider
    for _, c in ipairs({ { 1, 0 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }) do
      alive[c[1] .. "," .. c[2]] = true
    end
    local gen = 0
    local timer = os.startTimer(0.15)
    while true do
      local ev, a = os.pullEvent()
      if ev == "timer" and a == timer then
        monitor.setBackgroundColor(colors.black); monitor.clear()
        for key in pairs(alive) do
          local x, y = key:match("^(%-?%d+),(%-?%d+)$")
          monitor.setCursorPos(tonumber(x) + 1, tonumber(y) + 1)
          monitor.setTextColor(colors.lime); monitor.write("\7")
        end
        monitor.setCursorPos(1, h); monitor.setTextColor(colors.gray)
        monitor.write("gen " .. gen)
        alive = conway.step(alive, w, h)
        gen = gen + 1
        -- reseed if life dies out
        local n = 0; for _ in pairs(alive) do n = n + 1 end
        if n < 4 then
          for _ = 1, math.floor(w * h * 0.18) do
            alive[math.random(0, w - 1) .. "," .. math.random(0, h - 1)] = true
          end
        end
        timer = os.startTimer(0.15)
      elseif ev == "char" or ev == "monitor_touch" then
        break
      end
    end
    monitor.setBackgroundColor(colors.black); monitor.clear(); monitor.setCursorPos(1, 1)
  end
end

return conway
