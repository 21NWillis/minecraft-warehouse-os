-- BASEWALK: a first-person raycast engine for ComputerCraft that walks
-- you through YOUR OWN BASE - levels are compiled from survey scans by
-- tools/scan2map.lua, so the corridors on screen are the corridors the
-- turtle actually flew. Wolfenstein by way of a warehouse audit.
--
--   basewalk                      walk the campus (data/basewalk_campus)
--   basewalk <levelModule>        walk any compiled scan
--   basewalk <levelModule> <side> render to a monitor (textScale 0.5;
--                                 the NOC wall makes a glorious
--                                 screensaver)
--   basewalk tour [tourModule] [side]
--                                 a GUIDED tour: Claude authors tour
--                                 files (landmark waypoints + narration)
--                                 in the repo; the camera drives itself
--                                 and the captions are the guide
--                                 speaking. Default: data/tour_campus.
--                                 Tours address stops by landmark
--                                 ("near a monitor"), so they survive
--                                 base remodels.
--
-- Controls: W/S move, A/D strafe, LEFT/RIGHT turn, M map, P patrol
-- (self-guided drift - the screensaver), T resume tour, Q quit.
-- Touching the controls pauses a running tour; T hands it back.
local M = {}

M.FOV = math.pi / 3
M.MAXDIST = 24

-- portable atan2: CC's Cobalt keeps math.atan2, lua54 folds it into atan
M.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

function M.loadLevel(module)
  local level = require(module)
  level.at = function(x, z)
    if x < 0 or z < 0 or x >= level.w or z >= level.l then return "#" end
    return level.cells:sub(z * level.w + x + 1, z * level.w + x + 1)
  end
  level.open = function(x, z)
    return level.at(math.floor(x), math.floor(z)) == "."
  end
  return level
end

-- DDA raycast: walks the cell grid, returns distance to the first
-- solid cell, its legend char, and which axis face was struck
function M.cast(level, px, pz, angle)
  local dx, dz = math.cos(angle), math.sin(angle)
  local mapX, mapZ = math.floor(px), math.floor(pz)
  local deltaX = dx == 0 and 1e30 or math.abs(1 / dx)
  local deltaZ = dz == 0 and 1e30 or math.abs(1 / dz)
  local stepX, sideX, stepZ, sideZ
  if dx < 0 then
    stepX, sideX = -1, (px - mapX) * deltaX
  else
    stepX, sideX = 1, (mapX + 1 - px) * deltaX
  end
  if dz < 0 then
    stepZ, sideZ = -1, (pz - mapZ) * deltaZ
  else
    stepZ, sideZ = 1, (mapZ + 1 - pz) * deltaZ
  end
  local side
  for _ = 1, 64 do
    if sideX < sideZ then
      sideX = sideX + deltaX
      mapX = mapX + stepX
      side = 0
    else
      sideZ = sideZ + deltaZ
      mapZ = mapZ + stepZ
      side = 1
    end
    local c = level.at(mapX, mapZ)
    if c ~= "." then
      local dist = side == 0 and (sideX - deltaX) or (sideZ - deltaZ)
      return math.max(dist, 0.01), c, side
    end
  end
  return M.MAXDIST, nil, 0
end

-- collision-checked movement (slide along walls)
function M.move(level, px, pz, dx, dz)
  local r = 0.2
  local nx = px + dx
  if level.open(nx + (dx > 0 and r or -r), pz + r)
    and level.open(nx + (dx > 0 and r or -r), pz - r) then
    px = nx
  end
  local nz = pz + dz
  if level.open(px + r, nz + (dz > 0 and r or -r))
    and level.open(px - r, nz + (dz > 0 and r or -r)) then
    pz = nz
  end
  return px, pz
end

-- BFS route between open cells (patrol + tour brain)
function M.route(level, sx, sz, tx, tz)
  local function key(x, z) return x .. "," .. z end
  local from = { [key(sx, sz)] = "start" }
  local queue, qi = { { sx, sz } }, 1
  while queue[qi] do
    local c = queue[qi]
    qi = qi + 1
    if c[1] == tx and c[2] == tz then
      local path = {}
      local cur = { tx, tz }
      while from[key(cur[1], cur[2])] ~= "start" do
        table.insert(path, 1, { x = cur[1], z = cur[2] })
        cur = from[key(cur[1], cur[2])]
      end
      return path
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, nz = c[1] + d[1], c[2] + d[2]
      if level.at(nx, nz) == "." and not from[key(nx, nz)] then
        from[key(nx, nz)] = c
        queue[#queue + 1] = { nx, nz }
      end
    end
  end
  return nil
end

function M.openCells(level)
  local out = {}
  for z = 0, level.l - 1 do
    for x = 0, level.w - 1 do
      if level.at(x, z) == "." then out[#out + 1] = { x = x, z = z } end
    end
  end
  return out
end

-- word-wrap narration into caption lines
function M.wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else lines[#lines + 1] = line; line = word end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- resolve tour stops against a level. A stop is either explicit
-- ({x=, z=, fx=, fz=}) or by landmark ({near = "N", index = 2}): the
-- index-th open cell adjacent to that legend char, facing it. Stops
-- whose landmark no longer exists are skipped, so an old tour keeps
-- working after a remodel instead of crashing the NOC. When origin is
-- given, only cells routable from it count - eye-level scans have
-- walled-off pockets, and a tour must never strand the camera in one.
function M.resolveStops(level, stops, origin)
  local reach = nil
  if origin then
    reach = { [origin.x .. "," .. origin.z] = true }
    local queue, qi = { { origin.x, origin.z } }, 1
    while queue[qi] do
      local c = queue[qi]
      qi = qi + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, nz = c[1] + d[1], c[2] + d[2]
        if level.at(nx, nz) == "." and not reach[nx .. "," .. nz] then
          reach[nx .. "," .. nz] = true
          queue[#queue + 1] = { nx, nz }
        end
      end
    end
  end
  local function standable(x, z)
    if level.at(x, z) ~= "." then return false end
    if reach and not reach[x .. "," .. z] then return false end
    return true
  end
  local out = {}
  for _, s in ipairs(stops) do
    if s.x then
      out[#out + 1] = { x = s.x, z = s.z, fx = s.fx, fz = s.fz,
        say = s.say, dwell = s.dwell }
    elseif s.near then
      local want, n, found = s.index or 1, 0, false
      for z = 0, level.l - 1 do
        for x = 0, level.w - 1 do
          if not found and level.at(x, z) == s.near then
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local ox, oz = x + d[1], z + d[2]
              if not found and standable(ox, oz) then
                n = n + 1
                if n >= want then
                  out[#out + 1] = { x = ox, z = oz, fx = x, fz = z,
                    say = s.say, dwell = s.dwell }
                  found = true
                end
              end
            end
          end
        end
      end
    end
  end
  return out
end

if _TEST then return M end

-- ==================================================================== program
local args = { ... }
local tourMode = args[1] == "tour"
local tourName = tourMode and (args[2] or "data.tour_campus") or nil
local monSide = tourMode and args[3] or args[2]

local tourDef = nil
if tourMode then
  local okT
  okT, tourDef = pcall(require, tourName)
  if not okT or type(tourDef) ~= "table" then
    print("cannot load tour module: " .. tostring(tourName))
    return
  end
end

local levelName = (tourDef and tourDef.level) or (not tourMode and args[1])
  or "data.basewalk_campus"
local ok, level = pcall(function() return M.loadLevel(levelName) end)
if not ok or not level then
  print("cannot load level module: " .. tostring(levelName))
  return
end

local screen = term.current()
if monSide then
  local mon = peripheral.wrap(monSide)
  if mon then
    mon.setTextScale(0.5)
    screen = mon
  end
end
local W, H = screen.getSize()

-- color ramps: near / far shade per legend color
local RAMP = {
  purple = { colors.purple, colors.magenta },
  gray = { colors.gray, colors.black },
  lightBlue = { colors.lightBlue, colors.blue },
  brown = { colors.brown, colors.gray },
  orange = { colors.orange, colors.brown },
  blue = { colors.blue, colors.gray },
  green = { colors.green, colors.gray },
  cyan = { colors.cyan, colors.gray },
  red = { colors.red, colors.gray },
  magenta = { colors.magenta, colors.purple },
  lime = { colors.lime, colors.green },
  pink = { colors.pink, colors.magenta },
  yellow = { colors.yellow, colors.orange },
  lightGray = { colors.lightGray, colors.gray },
  white = { colors.white, colors.lightGray },
}
local CEIL = colors.toBlit(colors.black)
local FLOOR = colors.toBlit(colors.gray)

local px = level.spawn.x + 0.5
local pz = level.spawn.z + 0.5
local heading = 0
local patrol = false
local path, pathAt = nil, 1
local showMap = false
local caption = nil

-- tour state
local tourStops, tourAt, tourPhase, tourWait = nil, 1, "travel", 0
local tourActive = false
if tourDef then
  tourStops = M.resolveStops(level, tourDef.stops or {}, level.spawn)
  if #tourStops == 0 then
    print("tour has no resolvable stops on this level")
    return
  end
  tourActive = true
end

local function colorFor(char, dist, side)
  local entry = level.legend[char]
  local ramp = entry and RAMP[entry.color] or RAMP.white
  local c = (dist > 8 or side == 1) and ramp[2] or ramp[1]
  return colors.toBlit(c)
end

local function render()
  local cols = {}
  for x = 1, W do
    local rel = (x - 1) / math.max(1, W - 1) - 0.5
    local angle = heading + rel * M.FOV
    local dist, char, side = M.cast(level, px, pz, angle)
    dist = dist * math.cos(rel * M.FOV)   -- fisheye correction
    local h = math.min(H, math.floor(H / math.max(dist, 0.3)))
    local top = math.floor((H - h) / 2)
    cols[x] = { top = top, bottom = top + h,
      blit = char and colorFor(char, dist, side) or CEIL }
  end
  local text = string.rep(" ", W)
  local fgRow = string.rep("0", W)
  for y = 1, H do
    local bg = {}
    for x = 1, W do
      local c = cols[x]
      if y <= c.top then bg[x] = CEIL
      elseif y > c.bottom then bg[x] = FLOOR
      else bg[x] = c.blit end
    end
    screen.setCursorPos(1, y)
    screen.blit(text, fgRow, table.concat(bg))
  end
  screen.setCursorPos(1, 1)
  screen.setTextColor(colors.white)
  screen.setBackgroundColor(colors.black)
  screen.write((" BASEWALK %s%s%s "):format(
    levelName:match("[^./]+$") or levelName,
    patrol and " [patrol]" or "",
    tourActive and " [tour]" or (tourDef and " [tour paused - T]" or "")))
  if caption then
    screen.setTextColor(colors.lime)
    screen.setBackgroundColor(colors.black)
    for i, line in ipairs(caption) do
      screen.setCursorPos(1, H - #caption + i)
      screen.clearLine()
      screen.write(line)
    end
  end
end

local function renderMap()
  screen.setBackgroundColor(colors.black)
  screen.clear()
  local ox = math.max(1, math.floor((W - level.w) / 2))
  local oz = math.max(1, math.floor((H - level.l) / 2))
  for z = 0, math.min(level.l - 1, H - 1) do
    screen.setCursorPos(ox, oz + z)
    for x = 0, math.min(level.w - 1, W - ox) do
      local c = level.at(x, z)
      if math.floor(px) == x and math.floor(pz) == z then
        screen.setTextColor(colors.lime)
        screen.write("@")
      elseif c == "." then
        screen.setTextColor(colors.gray)
        screen.write(".")
      else
        local entry = level.legend[c]
        screen.setTextColor(entry and colors[entry.color] or colors.white)
        screen.write(c)
      end
    end
  end
  screen.setCursorPos(1, 1)
  screen.setTextColor(colors.white)
  screen.write(" map - M to return ")
end

-- advance along the current BFS path (shared by patrol + tour)
local function followTick(speed)
  local wp = path and path[pathAt]
  if not wp then return end
  local tx, tz = wp.x + 0.5, wp.z + 0.5
  local dx, dz = tx - px, tz - pz
  if math.sqrt(dx * dx + dz * dz) < 0.15 then
    pathAt = pathAt + 1
    return
  end
  local want = M.atan2(dz, dx)
  local diff = (want - heading + math.pi) % (2 * math.pi) - math.pi
  heading = heading + math.max(-0.12, math.min(0.12, diff))
  if math.abs(diff) < 0.6 then
    px, pz = M.move(level, px, pz, math.cos(heading) * speed,
      math.sin(heading) * speed)
  end
end

local function patrolTick()
  if not path or pathAt > #path then
    local cells = M.openCells(level)
    path = nil
    for _ = 1, 20 do
      local target = cells[math.random(#cells)]
      local try = M.route(level, math.floor(px), math.floor(pz), target.x, target.z)
      if try and #try > 4 then
        path, pathAt = try, 1
        break
      end
    end
    if not path then return end
  end
  followTick(0.1)
end

local function tourTick()
  local stop = tourStops[tourAt]
  if not stop then
    tourAt = 1
    if tourDef.loop == false then
      tourActive = false
      caption = nil
    end
    return
  end
  if tourPhase == "travel" then
    if not path then
      path = M.route(level, math.floor(px), math.floor(pz), stop.x, stop.z)
      pathAt = 1
      if not path then   -- unreachable landmark: skip the stop
        tourAt = tourAt + 1
        return
      end
    end
    if pathAt > #path then
      path = nil
      tourPhase = "face"
      return
    end
    followTick(0.12)
  elseif tourPhase == "face" then
    local want = heading
    if stop.fx then
      want = M.atan2(stop.fz + 0.5 - pz, stop.fx + 0.5 - px)
    end
    local diff = (want - heading + math.pi) % (2 * math.pi) - math.pi
    if math.abs(diff) < 0.06 then
      heading = want
      caption = stop.say and M.wrap(stop.say, W - 1) or nil
      tourWait = (stop.dwell or 7) * 5
      tourPhase = "talk"
    else
      heading = heading + math.max(-0.15, math.min(0.15, diff))
    end
  elseif tourPhase == "talk" then
    tourWait = tourWait - 1
    if tourWait <= 0 then
      caption = nil
      tourAt = tourAt + 1
      tourPhase = "travel"
    end
  end
end

local function pauseTour()
  if tourActive then
    tourActive = false
    caption = nil
    path = nil
    tourPhase = "travel"
  end
end

print("BASEWALK - your base, from the inside. Q quits.")
sleep(1)
local timer = os.startTimer(0.15)
while true do
  local event, a = os.pullEvent()
  if event == "timer" and a == timer then
    if tourActive then tourTick()
    elseif patrol then patrolTick() end
    if showMap then renderMap() else render() end
    timer = os.startTimer((patrol or tourActive) and 0.2 or 0.15)
  elseif event == "key" then
    local k = a
    local step = 0.35
    if k == keys.q then
      screen.setBackgroundColor(colors.black)
      screen.clear()
      screen.setCursorPos(1, 1)
      return
    elseif k == keys.m then
      showMap = not showMap
    elseif k == keys.p then
      pauseTour()
      patrol = not patrol
      path = nil
    elseif k == keys.t and tourDef then
      patrol = false
      path = nil
      tourPhase = "travel"
      tourActive = not tourActive
      if not tourActive then caption = nil end
    elseif k == keys.left then pauseTour() heading = heading - 0.22
    elseif k == keys.right then pauseTour() heading = heading + 0.22
    elseif k == keys.w then
      pauseTour()
      px, pz = M.move(level, px, pz, math.cos(heading) * step, math.sin(heading) * step)
    elseif k == keys.s then
      pauseTour()
      px, pz = M.move(level, px, pz, -math.cos(heading) * step, -math.sin(heading) * step)
    elseif k == keys.a then
      pauseTour()
      px, pz = M.move(level, px, pz, math.cos(heading - math.pi / 2) * step,
        math.sin(heading - math.pi / 2) * step)
    elseif k == keys.d then
      pauseTour()
      px, pz = M.move(level, px, pz, math.cos(heading + math.pi / 2) * step,
        math.sin(heading + math.pi / 2) * step)
    end
  end
end
