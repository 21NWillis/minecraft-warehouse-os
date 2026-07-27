-- snake: because a warehouse computer should also play snake.
-- Run on a computer terminal (arrow keys / WASD, Q to quit).
local w, h = term.getSize()
local playH = h - 1

local snake = { { x = math.floor(w / 2), y = math.floor(playH / 2) } }
local dir = { x = 1, y = 0 }
local nextDir = dir
local food
local score = 0
local speed = 0.15

local function placeFood()
  while true do
    local fx = math.random(1, w)
    local fy = math.random(1, playH)
    local onSnake = false
    for _, s in ipairs(snake) do
      if s.x == fx and s.y == fy then onSnake = true break end
    end
    if not onSnake then food = { x = fx, y = fy } return end
  end
end
placeFood()

local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setBackgroundColor(colors.red)
  term.setCursorPos(food.x, food.y)
  term.write(" ")
  for i, s in ipairs(snake) do
    term.setBackgroundColor(i == 1 and colors.lime or colors.green)
    term.setCursorPos(s.x, s.y)
    term.write(" ")
  end
  term.setBackgroundColor(colors.gray)
  term.setCursorPos(1, h)
  term.clearLine()
  term.setTextColor(colors.white)
  term.write(" score: " .. score .. "   (arrows/WASD, Q quits)")
  term.setBackgroundColor(colors.black)
end

local function step()
  local head = snake[1]
  local nx = head.x + nextDir.x
  local ny = head.y + nextDir.y
  dir = nextDir
  if nx < 1 then nx = w elseif nx > w then nx = 1 end
  if ny < 1 then ny = playH elseif ny > playH then ny = 1 end
  for _, s in ipairs(snake) do
    if s.x == nx and s.y == ny then return false end
  end
  table.insert(snake, 1, { x = nx, y = ny })
  if nx == food.x and ny == food.y then
    score = score + 1
    speed = math.max(0.05, speed - 0.005)
    placeFood()
  else
    snake[#snake] = nil
  end
  return true
end

local KEYS = {
  [keys.up] = { x = 0, y = -1 }, [keys.w] = { x = 0, y = -1 },
  [keys.down] = { x = 0, y = 1 }, [keys.s] = { x = 0, y = 1 },
  [keys.left] = { x = -1, y = 0 }, [keys.a] = { x = -1, y = 0 },
  [keys.right] = { x = 1, y = 0 }, [keys.d] = { x = 1, y = 0 },
}

local timer = os.startTimer(speed)
draw()
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "key" then
    if ev[2] == keys.q then break end
    local nd = KEYS[ev[2]]
    if nd and not (nd.x == -dir.x and nd.y == -dir.y) then nextDir = nd end
  elseif ev[1] == "timer" and ev[2] == timer then
    if not step() then break end
    draw()
    timer = os.startTimer(speed)
  end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
print("game over - score " .. score)
