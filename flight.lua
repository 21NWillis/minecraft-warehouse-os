-- flight: shared datum-launch safety for the fit programs.
local M = {}

-- Verify the launch frame from the datum: the casino deck physically defines
-- campus-south, so it must be found BEHIND the turtle - at depth (the deck
-- sits ~14-16 below the probe line; a NOC roof behind a mirrored turtle sits
-- much shallower and does NOT pass). Pure relative moves; returns the turtle
-- exactly to its start pose and facing. Born of two real mirrored-launch
-- incidents; textures lie, probes don't.
function M.verifyFrame(t)
  local FAIL_HELP = "FRAME CHECK FAILED: the casino deck is not behind me. " ..
    "Re-place me so `go forward` steps AWAY from the casino, then rerun."
  local climbed = 0
  while climbed < 15 and t.up() do climbed = climbed + 1 end
  if climbed < 15 then
    while climbed > 0 do t.down() climbed = climbed - 1 end
    return false, "frame check: blocked climbing above the datum"
  end
  t.turnRight()
  t.turnRight()                     -- look campus-south (behind the launch facing)
  -- probe distance 10: lands over the casino's SOUTH LIP row, which is
  -- always solid (channel columns can have open hopper holes - learned the
  -- hard way when the probe fell through one)
  local out = 0
  while out < 10 and t.forward() do out = out + 1 end
  local found = false
  if out == 10 then
    local dropped = 0
    while dropped < 18 and not t.detectDown() and t.down() do
      dropped = dropped + 1
    end
    -- deck depth check: casino found ~14+ down; anything shallower is the
    -- wrong building behind a mirrored turtle
    found = t.detectDown() and dropped >= 12
    while dropped > 0 do
      if not t.up() then return false, "frame check: stuck re-ascending" end
      dropped = dropped - 1
    end
  end
  t.turnRight()
  t.turnRight()                     -- face home (ends at original facing)
  while out > 0 do
    if not t.forward() then return false, "frame check: lost the way home" end
    out = out - 1
  end
  while climbed > 0 do
    if not t.down() then return false, "frame check: blocked descending home" end
    climbed = climbed - 1
  end
  if not found then return false, FAIL_HELP end
  return true
end

return M
