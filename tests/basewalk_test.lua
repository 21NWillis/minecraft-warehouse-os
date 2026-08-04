-- headless basewalk test: the raycaster's geometry, collision slide,
-- patrol routing, and the scan2map compile pipeline that feeds it.
package.path = "./?.lua;./tools/?.lua;" .. package.path
_TEST = true
local B = require("basewalk")
local S = require("scan2map")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- synthetic 7x7 level: border walls, one pillar at (3,3)
local cells = {}
for z = 0, 6 do
  for x = 0, 6 do
    local border = x == 0 or z == 0 or x == 6 or z == 6
    cells[#cells + 1] = (border or (x == 3 and z == 3)) and "#" or "."
  end
end
local level = {
  w = 7, l = 7, cells = table.concat(cells),
  legend = { ["#"] = { name = "wall", color = "white" } },
  spawn = { x = 1, z = 1 },
}
level.at = function(x, z)
  if x < 0 or z < 0 or x >= 7 or z >= 7 then return "#" end
  return level.cells:sub(z * 7 + x + 1, z * 7 + x + 1)
end
level.open = function(x, z)
  return level.at(math.floor(x), math.floor(z)) == "."
end

-- ------------------------------------------------------------ raycasts
-- from center of (1,1) looking +x: wall at x=6 -> distance 4.5
local d, c, side = B.cast(level, 1.5, 1.5, 0)
check("cast: +x axis distance", math.abs(d - 4.5) < 0.01, d)
check("cast: hits the wall char", c == "#", c)
check("cast: x-face side", side == 0, side)

-- looking +z from (1.5,1.5): wall at z=6 -> 4.5, z-face
d, c, side = B.cast(level, 1.5, 1.5, math.pi / 2)
check("cast: +z axis distance", math.abs(d - 4.5) < 0.01, d)
check("cast: z-face side", side == 1, side)

-- looking at the pillar from (1.5,3.5) facing +x: pillar at x=3 -> 1.5
d, c = B.cast(level, 1.5, 3.5, 0)
check("cast: pillar intercept", math.abs(d - 1.5) < 0.01, d)

-- diagonal 45 degrees from (1.5,1.5): pillar corner region or far wall,
-- distance must be positive and finite and less than the map diagonal
d = B.cast(level, 1.5, 1.5, math.pi / 4)
check("cast: diagonal sane", d > 0 and d < 10, d)

-- fisheye envelope: in an empty border-walled room, sweeping +/-15
-- degrees against the flat +x wall, corrected distance (d*cos(rel))
-- must stay constant at the perpendicular distance
local flat = {
  w = 9, l = 9,
  legend = { ["#"] = { name = "wall", color = "white" } },
}
local fc = {}
for z = 0, 8 do
  for x = 0, 8 do
    fc[#fc + 1] = (x == 0 or z == 0 or x == 8 or z == 8) and "#" or "."
  end
end
flat.cells = table.concat(fc)
flat.at = function(x, z)
  if x < 0 or z < 0 or x >= 9 or z >= 9 then return "#" end
  return flat.cells:sub(z * 9 + x + 1, z * 9 + x + 1)
end
local maxDev = 0
for i = -10, 10 do
  local rel = i / 10 * (math.pi / 12)
  local dist = B.cast(flat, 1.5, 4.5, rel) * math.cos(rel)
  maxDev = math.max(maxDev, math.abs(dist - 6.5))
end
check("cast: fisheye correction flattens the wall", maxDev < 0.05, maxDev)

-- ------------------------------------------------------------- movement
local px, pz = B.move(level, 1.5, 1.5, 10, 0)
check("move: cannot pass walls", px < 6, px)
px, pz = B.move(level, 1.5, 1.5, 0.3, 0)
check("move: open step lands", math.abs(px - 1.8) < 0.01, px)
-- slide: pushing diagonally into the border keeps the free axis moving
px, pz = B.move(level, 1.5, 1.5, -10, 0.3)
check("move: slides along the wall", math.abs(pz - 1.8) < 0.01 and px > 0.9,
  px .. "," .. pz)

-- --------------------------------------------------------------- patrol
local path = B.route(level, 1, 1, 5, 5)
check("route: found", path ~= nil)
if path then
  check("route: ends at target", path[#path].x == 5 and path[#path].z == 5)
  local okSteps = true
  local prev = { x = 1, z = 1 }
  for _, step in ipairs(path) do
    local dist = math.abs(step.x - prev.x) + math.abs(step.z - prev.z)
    if dist ~= 1 or level.at(step.x, step.z) ~= "." then okSteps = false end
    prev = step
  end
  check("route: adjacent open steps only", okSteps)
end
check("route: unreachable returns nil", B.route(level, 1, 1, 3, 3) == nil)
check("openCells: counts the floor", #B.openCells(level) == 24, #B.openCells(level))

-- ----------------------------------------------------------------- tour
local lines = B.wrap("the quick brown fox jumps over the lazy dog", 12)
local wrapOk = #lines > 1
for _, l in ipairs(lines) do if #l > 12 then wrapOk = false end end
check("wrap: respects width", wrapOk, table.concat(lines, "|"))
check("wrap: keeps every word",
  table.concat(lines, " ") == "the quick brown fox jumps over the lazy dog")
check("wrap: single short line", #B.wrap("hi there", 40) == 1)

-- landmark resolution: first open cell adjacent to a '#' in scan order
-- is (1,1) standing beside the border wall at (1,0)
local stops = B.resolveStops(level, {
  { near = "#", say = "a wall" },
  { x = 5, z = 5, fx = 5, fz = 6, say = "explicit" },
  { near = "Z", say = "landmark that no longer exists" },
})
check("resolveStops: skips missing landmarks", #stops == 2, #stops)
check("resolveStops: landmark stand cell is open",
  level.at(stops[1].x, stops[1].z) == ".",
  stops[1].x .. "," .. stops[1].z)
check("resolveStops: faces the landmark",
  math.abs(stops[1].fx - stops[1].x) + math.abs(stops[1].fz - stops[1].z) == 1)
check("resolveStops: explicit stop passes through",
  stops[2].x == 5 and stops[2].z == 5 and stops[2].say == "explicit")
-- index picks a later adjacency, and it differs from the first
local idx2 = B.resolveStops(level, { { near = "#", index = 2 } })
check("resolveStops: index selects a different cell", #idx2 == 1
  and not (idx2[1].x == stops[1].x and idx2[1].z == stops[1].z
    and idx2[1].fx == stops[1].fx and idx2[1].fz == stops[1].fz))
-- every resolved stop must be routable from spawn (tour never strands)
local reachable = true
for _, s in ipairs(stops) do
  if not B.route(level, 1, 1, s.x, s.z) then reachable = false end
end
check("resolveStops: stops reachable from spawn", reachable)

-- --------------------------------------------- scan2map -> level pipeline
local scanJson = [==[
{"v":1,"label":"t","w":4,"l":3,"h":2,"stopped":"done","visited":9,
"palette":["minecraft:purple_concrete","minecraft:water"],
"layers":[[0,1,0,2, 0,0,0,0, 1,1,0,0],[0,1,0,0, 0,0,0,0, -1,1,0,0]]}
]==]
local scan = S.parseJson(scanJson)
check("scan2map: json parsed", scan.w == 4 and scan.l == 3 and #scan.palette == 2)
local map = S.compile(scan, 1)
check("scan2map: eye-level wall kept", map.cells:sub(2, 2) == "P", map.cells)
check("scan2map: ground furniture blocks", map.cells:sub(4, 4) == "W", map.cells)
check("scan2map: unknown at eye + solid ground = wall",
  map.cells:sub(9, 9) == "P", map.cells)
check("scan2map: open where both layers clear", map.cells:sub(1, 1) == ".", map.cells)
check("scan2map: legend colors", map.legend["P"].color == "purple"
  and map.legend["W"].color == "blue")

-- emitted module loads and drives the caster
local emitted = S.emit(map, "test")
local chunk = load(emitted)
check("scan2map: emitted module loads", chunk ~= nil)
if chunk then
  local lvl = chunk()
  lvl.at = function(x, z)
    if x < 0 or z < 0 or x >= lvl.w or z >= lvl.l then return "#" end
    return lvl.cells:sub(z * lvl.w + x + 1, z * lvl.w + x + 1)
  end
  local dd, cc = B.cast(lvl, 0.5, 0.5, 0)
  check("pipeline: caster reads the compiled base", cc == "P", tostring(cc))
  check("pipeline: distance to the wall", math.abs(dd - 0.5) < 0.01, dd)
end

-- the real campus level compiles and has a navigable floor
local campus = dofile("data/basewalk_campus.lua")
check("campus: dimensions", campus.w == 37 and campus.l == 37)
local open = 0
for i = 1, #campus.cells do
  if campus.cells:sub(i, i) == "." then open = open + 1 end
end
check("campus: walkable", open > 1000, open)
check("campus: has the purple walls", campus.cells:find("P") ~= nil)

-- the shipped campus tour resolves against the shipped campus level
campus.at = function(x, z)
  if x < 0 or z < 0 or x >= campus.w or z >= campus.l then return "#" end
  return campus.cells:sub(z * campus.w + x + 1, z * campus.w + x + 1)
end
local tour = dofile("data/tour_campus.lua")
check("tour: names the campus level", tour.level == "data.basewalk_campus")
local tstops = B.resolveStops(campus, tour.stops, campus.spawn)
check("tour: most stops resolve on the real campus", #tstops >= 8, #tstops)
local allSpeak, allRouted = true, true
for _, s in ipairs(tstops) do
  if not s.say then allSpeak = false end
  if not B.route(campus, campus.spawn.x, campus.spawn.z, s.x, s.z) then
    allRouted = false
  end
end
check("tour: every stop has narration", allSpeak)
check("tour: every stop reachable from spawn", allRouted)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
