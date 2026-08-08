-- buildrun: turtle program that builds a generated schematic from its own
-- inventory. Place the turtle at the build origin (bottom-front-left corner),
-- facing into the build (+z), with materials + fuel loaded, then e.g.:
--   buildrun box 16 10 16 minecraft:stone
--   buildrun floor 9 9 minecraft:oak_planks
--   buildrun cylinder 5 8 minecraft:glass
--   buildrun tower 12 8 12 minecraft:stone   (hollow box + floor + roof)
-- It flies bottom-up placing blocks downward, and beams progress over starlink
-- if an ender/wireless modem is attached.
local schematic = require("schematic")
local builder = require("builder")

local args = { ... }
-- trailing flags: "plan" = dry run (bill + fuel, no build); "resume" =
-- continue a parked partial build of the same shape
local dryRun, resuming, anchored = false, false, false
while true do
  if args[#args] == "plan" then table.remove(args); dryRun = true
  elseif args[#args] == "resume" then table.remove(args); resuming = true
  elseif args[#args] == "anchor" then table.remove(args); anchored = true; resuming = true
  else break end
end
local argsline = table.concat(args, " ")
local shape = args[1]

local function usage()
  print("buildrun <shape> <dims...> <block>")
  print("  box W H D block      hollow walls only")
  print("  tower W H D block     walls + floor + roof")
  print("  floor W D block")
  print("  solid W H D block")
  print("  cylinder R H block")
  print("  pad W D [wall trim glow]   lit platform (trim rim, glow grid)")
  print("  evilhq W H [wall glow spire]   generic evil tower")
  print("  paperclip [wall trim glass glow]  Paperclip Corp HQ (the Doofenshmirtz special)")
  print("append 'plan' to any shape for a dry run (materials + fuel, no build)")
end

local s, block
if shape == "box" or shape == "solid" or shape == "tower" then
  local w, h, d = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
  block = args[5]
  if not (w and h and d and block) then usage() return end
  if shape == "solid" then s = schematic.solid(w, h, d, block)
  elseif shape == "tower" then s = schematic.hollowBox(w, h, d, block, { floor = true, roof = true })
  else s = schematic.hollowBox(w, h, d, block, { floor = true }) end
elseif shape == "floor" then
  local w, d = tonumber(args[2]), tonumber(args[3])
  block = args[4]
  if not (w and d and block) then usage() return end
  s = schematic.floor(w, d, block)
elseif shape == "cylinder" then
  local r, h = tonumber(args[2]), tonumber(args[3])
  block = args[4]
  if not (r and h and block) then usage() return end
  s = schematic.cylinder(r, h, block)
elseif shape == "evilhq" then
  local w, h = tonumber(args[2]), tonumber(args[3])
  if not (w and h) then usage() return end
  -- palette optional: buildrun evilhq 9 20 [wall glow spire]
  s = schematic.evilTower(w, h, { wall = args[4], glow = args[5], spire = args[6] })
elseif shape == "pad" then
  local w, d = tonumber(args[2]), tonumber(args[3])
  if not (w and d) then usage() return end
  s = schematic.pad(w, d, { wall = args[4], trim = args[5], glow = args[6] })
elseif shape == "paperclip" then
  s = schematic.paperclipHQ({ wall = args[2], trim = args[3], glass = args[4], glow = args[5] })
else
  usage() return
end

local plan = s:plan()
local mats = s:materials()
print(("plan: %d blocks, %d placements"):format(s:count(), #plan))
for b, n in pairs(mats) do print(("  need %d x %s"):format(n, b)) end

-- fuel: turtles burn 1 fuel per move. estimate generously and refuel from any
-- fuel item in the inventory before starting.
local estMoves = #plan * 3 + s.h * 4
if dryRun then
  print(("estimated fuel: ~%d moves"):format(estMoves))
  print("(plan only - nothing built)")
  return
end
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < estMoves then
  -- COAL-ONLY: blanket refuel() eats wooden chests and anything else
  -- combustible aboard (QUIRKS law; printfit learned this the hard way)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal"
        or d.name == "minecraft:coal_block") then
      turtle.select(slot)
      turtle.refuel()
    end
  end
  print(("fuel: %s (est need %d)"):format(tostring(turtle.getFuelLevel()), estMoves))
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < estMoves then
    print("WARNING: may run out of fuel mid-build")
  end
end

-- optional starlink progress beacon
local net
do
  local ok, starlink = pcall(require, "starlink")
  if ok then
    net = starlink.new("builder-" .. os.getComputerID(), "builder")
  end
end

-- standard turtle ops (slot-scan ensure + ender-chest network refill) live in
-- builder.turtleOps so datacenter.lua shares the exact same machinery.
local ops = builder.turtleOps()

local function progressCb(done, total)
  if done % 16 == 0 or done == total then
    term.clearLine()
    local _, y = term.getCursorPos()
    term.setCursorPos(1, y)
    term.write(("building %d/%d"):format(done, total))
    if net then
      net:setTelemetry({ built = done, total = total, alt = nil })
      net:beacon()
    end
  end
end

-- park file: written when a build stops partway (pose recorded while the
-- turtle is stationary at its park spot), consumed by `... resume`
local PARK = ".buildrun_park"

local placed, err, endPose
if anchored then
  -- pose-free resume: trusts a physical convention instead of saved state.
  -- Requires the turtle to be sitting ON TOP of the origin-column's highest
  -- block (the roofline corner where the build started), facing the
  -- original build direction.
  local pose = builder.anchorPose(plan)
  print(("anchor resume: assuming I'm at the origin column top (y=%d), facing the build"):format(pose.y))
  placed, err, endPose = builder.resume(plan, ops, progressCb, pose)
elseif resuming then
  if not fs.exists(PARK) then
    print("no parked build here to resume (try `... resume anchor`)")
    return
  end
  local f = fs.open(PARK, "r")
  local saved = textutils.unserialize(f.readAll() or "")
  f.close()
  if not (saved and saved.pose) or saved.line ~= argsline then
    print("parked build was: buildrun " .. tostring(saved and saved.line))
    print("resume with exactly those arguments")
    return
  end
  print("resuming parked build (locating first missing block)...")
  placed, err, endPose = builder.resume(plan, ops, progressCb, saved.pose)
else
  placed, err, endPose = builder.run(plan, ops, progressCb)
end

print("")
if err then
  if endPose then
    local f = fs.open(PARK, "w")
    f.write(textutils.serialize({ line = argsline,
      pose = { x = endPose.x, y = endPose.y, z = endPose.z, f = endPose.f } }))
    f.close()
  end
  print(("stopped at %d/%d: %s"):format(placed, #plan, err))
  if endPose and endPose.x == 0 and endPose.z == 0 then
    print("turtle parked at the origin column. restock (or fill the paired")
    print("ender chest), then: buildrun " .. argsline .. " resume")
  elseif endPose then
    print(("could NOT fly home - parked at %d right, %d fwd, %d up of origin.")
      :format(endPose.x, endPose.z, endPose.y))
    print("something blocks the sky path; clear it, then: buildrun " .. argsline .. " resume")
  end
else
  if fs.exists(PARK) then fs.delete(PARK) end
  print(("done: %d blocks placed"):format(placed))
end
