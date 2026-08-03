-- surveylogic: non-destructive as-built scanner - the world-state channel.
-- A turtle sweeps a w x l x h box of (mostly) air, inspecting every face it
-- can reach, and produces a voxel report of what is ACTUALLY there. This is
-- how wings stay maintainable after the one-shot build: nightly surveys give
-- planning ground truth without trusting the schematic.
--
-- Doctrine: NEVER dig. The ops contract has no dig functions at all - the
-- turtle only enters cells it has inspected as air, routes around obstacles
-- (BFS over known-air), and records everything solid by name. Entities in
-- the way get attacked a few times (they wander/die), then written off as
-- "blocked". Cells sealed away from all reachable air end as "unknown".
--
-- Guarantees (proven in tests/survey_test.lua):
--   * every cell reachable through in-box air is visited and sensed
--   * every cell ADJACENT to visited air is classified (solid gets a name)
--   * nothing is ever dug, and the fuel governor parks the turtle home
--     with a partial report rather than stranding it
--   * the run ends at the start pose (survey station, original facing)
--
-- SURVEY FORMAT v1 (s.encode): layers[y+1][z*w + x + 1] ->
--   0 = air, -1 = never seen (enclosed), -2 = entity-blocked,
--   k > 0 = palette[k]. Frame: x grows to the turtle's RIGHT, z along its
--   start facing (the `go forward` test), y UP; turtle starts at (0,0,0).
local s = {}

-- facings as (dx, dz); index 0..3 clockwise from +z, same frame as
-- builder/quarry: f=0 is the direction the turtle faces at launch
local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
s.DIRS = DIRS

local function K(x, y, z) return x .. "," .. y .. "," .. z end
s.key = K

local NB = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

-- attempts against an entity squatting in a cell before writing it off
local ATTACK_CAP = 10

-- ops contract (NO dig - by design): forward/up/down/turnLeft/turnRight,
--   detect/detectUp/detectDown, inspect/inspectUp/inspectDown
--   (-> ok, {name=}), attack/attackUp/attackDown (optional),
--   getFuelLevel (-> n|"unlimited"), tryRefuel (consume carried fuel;
--   true if fuel increased)
-- opts: w, l, h (default 1), margin (fuel safety pad, default 20),
--   onProgress(visitedCount)
-- returns st: {w,l,h, cells = key->{state,name}, visited, solids, blocked,
--   unknown, stopped = "done"|"fuel"|"trapped", pose}
function s.scan(ops, opts)
  local w, l, h = opts.w, opts.l, opts.h or 1
  local margin = opts.margin or 20
  local pose = { x = 0, y = 0, z = 0, f = 0 }
  local cells = {}
  local seen = {}
  local st = { w = w, l = l, h = h, cells = cells,
    visited = 0, solids = 0, blocked = 0, unknown = 0, stopped = "done" }

  local function inBox(x, y, z)
    return x >= 0 and x < w and y >= 0 and y < h and z >= 0 and z < l
  end
  local function mark(x, y, z, state, name)
    cells[K(x, y, z)] = { state = state, name = name }
  end
  local function fuelLevel()
    local f = ops.getFuelLevel()
    if f == "unlimited" then return math.huge end
    return f
  end

  local function face(target)
    local diff = (target - pose.f) % 4
    if diff == 1 then ops.turnRight()
    elseif diff == 3 then ops.turnLeft()
    elseif diff == 2 then ops.turnRight(); ops.turnRight() end
    pose.f = target
  end

  -- classify every unknown neighbor of the current cell by LOOKING;
  -- rotation order starts at the current facing to minimize turns
  local function sense()
    for i = 0, 3 do
      local d = (pose.f + i) % 4
      local nx, nz = pose.x + DIRS[d][1], pose.z + DIRS[d][2]
      if inBox(nx, pose.y, nz) and not cells[K(nx, pose.y, nz)] then
        face(d)
        local ok, info = ops.inspect()
        if ok then mark(nx, pose.y, nz, "solid", info.name)
        else mark(nx, pose.y, nz, "air") end
      end
    end
    if inBox(pose.x, pose.y + 1, pose.z) and not cells[K(pose.x, pose.y + 1, pose.z)] then
      local ok, info = ops.inspectUp()
      if ok then mark(pose.x, pose.y + 1, pose.z, "solid", info.name)
      else mark(pose.x, pose.y + 1, pose.z, "air") end
    end
    if inBox(pose.x, pose.y - 1, pose.z) and not cells[K(pose.x, pose.y - 1, pose.z)] then
      local ok, info = ops.inspectDown()
      if ok then mark(pose.x, pose.y - 1, pose.z, "solid", info.name)
      else mark(pose.x, pose.y - 1, pose.z, "air") end
    end
  end

  -- BFS from the current pose over cells known to be air
  local function bfs()
    local dist, parent = {}, {}
    local queue, qi = { { x = pose.x, y = pose.y, z = pose.z } }, 1
    dist[K(pose.x, pose.y, pose.z)] = 0
    while queue[qi] do
      local c = queue[qi]; qi = qi + 1
      local ck = K(c.x, c.y, c.z)
      for _, d in ipairs(NB) do
        local nx, ny, nz = c.x + d[1], c.y + d[2], c.z + d[3]
        local nk = K(nx, ny, nz)
        if inBox(nx, ny, nz) and not dist[nk] then
          local cell = cells[nk]
          if cell and cell.state == "air" then
            dist[nk] = dist[ck] + 1
            parent[nk] = ck
            queue[#queue + 1] = { x = nx, y = ny, z = nz }
          end
        end
      end
    end
    return dist, parent
  end

  local function reconstruct(parent, k)
    local path = {}
    local cur = k
    while parent[cur] do
      local x, y, z = cur:match("(-?%d+),(-?%d+),(-?%d+)")
      table.insert(path, 1, { x = tonumber(x), y = tonumber(y), z = tonumber(z) })
      cur = parent[cur]
    end
    return path
  end

  local function nearestUnvisited(dist)
    local bk, bd
    for k, d in pairs(dist) do
      if not seen[k] and (not bd or d < bd) then bk, bd = k, d end
    end
    return bk, bd
  end

  -- move one cell to an adjacent target. A failure ALWAYS reclassifies the
  -- target cell (solid if the world changed, blocked if an entity holds it),
  -- so the planner is guaranteed to make progress on replan.
  local function step(to)
    local dy = to.y - pose.y
    local mover, attacker, detector, inspector
    if dy == 1 then
      mover, attacker, detector, inspector = ops.up, ops.attackUp, ops.detectUp, ops.inspectUp
    elseif dy == -1 then
      mover, attacker, detector, inspector = ops.down, ops.attackDown, ops.detectDown, ops.inspectDown
    else
      for d = 0, 3 do
        if pose.x + DIRS[d][1] == to.x and pose.z + DIRS[d][2] == to.z then face(d) end
      end
      mover, attacker, detector, inspector = ops.forward, ops.attack, ops.detect, ops.inspect
    end
    local tries = 0
    while not mover() do
      if detector() then
        -- the world changed since we sensed it (gravel, piston, a prank):
        -- record the truth and let the planner route around it
        local ok, info = inspector()
        mark(to.x, to.y, to.z, "solid", ok and info.name or nil)
        return false
      end
      tries = tries + 1
      if tries > ATTACK_CAP then
        mark(to.x, to.y, to.z, "blocked")
        return false
      end
      if attacker then attacker() end
    end
    pose.x, pose.y, pose.z = to.x, to.y, to.z
    return true
  end

  local function goHome()
    for _ = 1, 4 do
      if pose.x == 0 and pose.y == 0 and pose.z == 0 then face(0) return true end
      local dist, parent = bfs()
      local hk = K(0, 0, 0)
      if not dist[hk] then return false end
      local path = reconstruct(parent, hk)
      local ok = true
      for _, c in ipairs(path) do
        if not step(c) then ok = false break end
      end
      if ok then face(0) return true end
    end
    return false
  end

  mark(0, 0, 0, "air")
  seen[K(0, 0, 0)] = true
  st.visited = 1
  sense()

  while true do
    local dist, parent = bfs()
    local tk, td = nearestUnvisited(dist)
    if not tk then break end
    -- governor: the trip out plus the (bounded) trip home must be affordable
    local dh = dist[K(0, 0, 0)] or 0
    while fuelLevel() < td + dh + margin and ops.tryRefuel() do end
    if fuelLevel() < td + dh + margin then st.stopped = "fuel" break end
    local path = reconstruct(parent, tk)
    for _, c in ipairs(path) do
      if not step(c) then break end   -- reclassified; outer loop replans
      local ck = K(c.x, c.y, c.z)
      if not seen[ck] then
        seen[ck] = true
        st.visited = st.visited + 1
        sense()
        if opts.onProgress then opts.onProgress(st.visited) end
      end
    end
  end

  if not goHome() and st.stopped == "done" then st.stopped = "trapped" end

  for y = 0, h - 1 do
    for z = 0, l - 1 do
      for x = 0, w - 1 do
        local c = cells[K(x, y, z)]
        if not c then st.unknown = st.unknown + 1
        elseif c.state == "solid" then st.solids = st.solids + 1
        elseif c.state == "blocked" then st.blocked = st.blocked + 1
        end
      end
    end
  end
  st.pose = pose
  return st
end

-- compact JSON for upload (hand-rolled: headless-testable, no textutils).
-- See SURVEY FORMAT v1 in the header for the decode contract.
function s.encode(report, label)
  local palette, index = {}, {}
  local layerStrs = {}
  for y = 0, report.h - 1 do
    local vals = {}
    for z = 0, report.l - 1 do
      for x = 0, report.w - 1 do
        local c = report.cells[K(x, y, z)]
        local v
        if not c then v = -1
        elseif c.state == "air" then v = 0
        elseif c.state == "blocked" then v = -2
        else
          local name = c.name or "minecraft:unknown"
          if not index[name] then
            palette[#palette + 1] = name
            index[name] = #palette
          end
          v = index[name]
        end
        vals[#vals + 1] = v
      end
    end
    layerStrs[#layerStrs + 1] = "[" .. table.concat(vals, ",") .. "]"
  end
  local pal = {}
  for i, name in ipairs(palette) do
    pal[i] = '"' .. name:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  end
  return ('{"v":1,"label":"%s","w":%d,"l":%d,"h":%d,"stopped":"%s","visited":%d,'
    .. '"palette":[%s],"layers":[%s]}')
    :format(label or "wing", report.w, report.l, report.h, report.stopped,
      report.visited, table.concat(pal, ","), table.concat(layerStrs, ","))
end

return s
