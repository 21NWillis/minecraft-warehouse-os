-- concrete: convert concrete powder to concrete with a turtle + one water
-- source, ~5/sec. The classic chore-killer for big builds.
--
-- Rig (10 seconds to set up):
--     [water source] [empty space] [TURTLE ->]
-- i.e. the empty space directly in FRONT of the turtle must touch a water
-- source on any side (or from above). Load any concrete powders into the
-- turtle (mixed colors fine), run `concrete`. It places each powder (touching
-- water = instant conversion), mines the concrete back, and keeps going
-- until it holds no more powder. Needs a pickaxe equipped.
local function findPowder()
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name:find("concrete_powder") then return slot end
  end
end

local done = 0
while true do
  local slot = findPowder()
  if not slot then break end
  turtle.select(slot)
  if turtle.place() then
    local ok, info = turtle.inspect()
    if ok and info.name:find("concrete_powder") then
      turtle.dig()
      print("powder did not convert!")
      print("the space in front must touch a water source - fix the rig and rerun")
      return
    end
    turtle.dig()
    done = done + 1
    if done % 64 == 0 then print(done .. " converted...") end
  else
    print("cannot place forward - clear the space in front, rerunning in 2s")
    sleep(2)
  end
end
print(("done: %d concrete"):format(done))
