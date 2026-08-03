-- quarry: JAMD strip-miner for the resource program (osmium first).
-- Logic lives in quarrylogic (headless-proven); this wraps the real turtle.
--
-- SETUP (all orientation is behavioral - the `go forward` test, never
-- textures):
--   1. In the mining dimension, dig/climb to the target level. Osmium band:
--      y -32..+32, richest near y0 (config/Mekanism/world.toml).
--   2. Place a CHEST, then place the turtle so its BACK touches the chest -
--      `go forward` must move it AWAY from the chest. That spot is home.
--   3. Load fuel (coal - the treasury has 57k) in any slot. A stack or two.
--   4. quarry <width> <length> [layers]
--      width grows to the turtle's RIGHT, length straight ahead; each layer
--      is a 3-tall slice, stacked downward. 16x16x4 layers ~ a chunk face.
--   5. After a fuel stop or reboot, put the turtle back on the chest corner
--      (same facing) if it isn't already parked there, then: quarry resume
--
-- Ores ride home to the chest; junk is flung into the dug corridors. The
-- program always parks at home before exiting, so `resume` can trust pose.
local q = require("quarrylogic")

local STATE = "quarry.state"
local tArgs = { ... }

local FUEL = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true,
  ["minecraft:coal_block"] = true,
}

local w, l, layers, resumeAt
if tArgs[1] == "resume" then
  if not fs.exists(STATE) then print("no saved quarry to resume") return end
  local h = fs.open(STATE, "r")
  local saved = textutils.unserialize(h.readAll())
  h.close()
  w, l, layers = saved.w, saved.l, saved.layers
  resumeAt = { layer = saved.layer, cell = saved.cell }
  print(("resuming %dx%d x%d at layer %d cell %d")
    :format(w, l, layers, saved.layer, saved.cell))
else
  w = tonumber(tArgs[1])
  l = tonumber(tArgs[2])
  layers = tonumber(tArgs[3] or "1")
  if not w or not l or w < 1 or l < 1 then
    print("usage: quarry <width> <length> [layers]")
    print("       quarry resume")
    return
  end
end

local function saveState(layer, cell)
  local h = fs.open(STATE, "w")
  h.write(textutils.serialize({ w = w, l = l, layers = layers, layer = layer, cell = cell }))
  h.close()
end

local function eachSlot(fn)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d then fn(slot, d) end
  end
end

local ops = {
  forward = turtle.forward, up = turtle.up, down = turtle.down,
  turnLeft = function() turtle.turnLeft() return true end,
  turnRight = function() turtle.turnRight() return true end,
  dig = turtle.dig, digUp = turtle.digUp, digDown = turtle.digDown,
  detect = turtle.detect, detectUp = turtle.detectUp, detectDown = turtle.detectDown,
  inspectUp = turtle.inspectUp, inspectDown = turtle.inspectDown,
  attack = turtle.attack,
  getFuelLevel = turtle.getFuelLevel,
  tryRefuel = function()
    local before = turtle.getFuelLevel()
    eachSlot(function(slot, d)
      if FUEL[d.name] then turtle.select(slot); turtle.refuel(16) end
    end)
    return turtle.getFuelLevel() > before
  end,
  isFull = function()
    for slot = 1, 16 do
      if turtle.getItemCount(slot) == 0 then return false end
    end
    return true
  end,
  dropJunk = function()
    eachSlot(function(slot, d)
      if not q.isKeeper(d.name) and not FUEL[d.name] then
        turtle.select(slot)
        -- fling into the corridor; if the face ahead is solid, the corridor
        -- we came from is always dug - net turns cancel, pose unchanged
        if not turtle.drop() then
          turtle.turnRight() turtle.turnRight()
          turtle.drop()
          turtle.turnRight() turtle.turnRight()
        end
      end
    end)
    turtle.select(1)
  end,
  dumpHome = function()
    -- parked at home facing away from the chest: about-face, unload
    -- keepers (one fuel stack stays aboard), face forward again
    turtle.turnRight() turtle.turnRight()
    local fuelKept = false
    eachSlot(function(slot, d)
      if FUEL[d.name] and not fuelKept then fuelKept = true
      else turtle.select(slot); turtle.drop() end
    end)
    turtle.select(1)
    turtle.turnRight() turtle.turnRight()
  end,
}

print(("quarry %dx%d, %d layer(s) - fuel %s"):format(w, l, layers, tostring(turtle.getFuelLevel())))
local st = q.run(ops, {
  w = w, l = l, layers = layers, resume = resumeAt,
  onProgress = function(layer, cell, total)
    saveState(layer, cell + 1)  -- next cell to do, not the one just done
    if cell % 25 == 0 then
      print(("layer %d: %d/%d cells"):format(layer, cell, total))
    end
  end,
})

if st.stopped == "done" then
  if fs.exists(STATE) then fs.delete(STATE) end
  print(("DONE: %d cells, %d bonus ores, %d haul trips"):format(st.cellsDone, st.ores, st.dumps))
else
  saveState(st.at.layer, st.at.cell)
  print(("STOPPED (%s) at layer %d cell %d - parked home, haul unloaded"):format(
    st.stopped, st.at.layer, st.at.cell))
  if st.stopped == "fuel" then
    print("add coal to my inventory, then: quarry resume")
  else
    print("clear the obstruction (bedrock? claim?), then: quarry resume")
  end
end
