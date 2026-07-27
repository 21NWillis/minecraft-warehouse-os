-- headless flight test: drive the PID autopilot against a simulated ship
-- (double-integrator plant with drag + gravity) and assert it reaches the
-- commanded altitude/heading, holds it, and never goes unstable.
package.path = "./?.lua;" .. package.path
local autopilot = require("autopilot")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- simple ship plant. thrust command in [-1,1] maps to force; gravity pulls
-- down; drag opposes velocity. heading integrates yaw command against inertia.
local function newShip(alt, heading)
  return { alt = alt or 64, valt = 0, heading = heading or 0, vyaw = 0 }
end

local function stepShip(s, cmd, dt)
  local THRUST = 30      -- max upward accel from full thrust
  local GRAV = 9.8
  local DRAG = 0.8
  local acc = cmd.thrust * THRUST - GRAV - DRAG * s.valt
  s.valt = s.valt + acc * dt
  s.alt = s.alt + s.valt * dt

  local YAWACC = 90      -- deg/s^2 at full yaw
  local YAWDRAG = 1.2
  s.vyaw = s.vyaw + (cmd.yaw * YAWACC - YAWDRAG * s.vyaw) * dt
  s.heading = (s.heading + s.vyaw * dt) % 360
  return s
end

-- fly to a setpoint for T seconds; return trace + final state
local function fly(ap, ship, setpoint, T, dt)
  local maxAlt, minAltAfterRise = -1e9, 1e9
  local t = 0
  local risen = false
  while t < T do
    local cmd = autopilot.step(ap, setpoint, ship, dt)
    stepShip(ship, cmd, dt)
    if ship.alt > maxAlt then maxAlt = ship.alt end
    if ship.alt >= setpoint.alt - 1 then risen = true end
    if risen and ship.alt < minAltAfterRise then minAltAfterRise = ship.alt end
    if ship.alt ~= ship.alt or math.abs(ship.alt) > 1e6 then
      return nil, "diverged"  -- NaN or blowup
    end
    t = t + dt
  end
  return { maxAlt = maxAlt, minAltAfterRise = minAltAfterRise }
end

local dt = 0.05  -- 20 Hz, ~1 control tick

-- 1. altitude hold: climb 64 -> 200 and settle
do
  local ap = autopilot.new()
  local ship = newShip(64, 0)
  local trace = fly(ap, ship, { alt = 200, heading = 0 }, 60, dt)
  check("altitude controller does not diverge", trace ~= nil)
  if trace then
    check("reaches commanded altitude", math.abs(ship.alt - 200) < 3,
      ("final alt %.1f"):format(ship.alt))
    check("overshoot under 15%", trace.maxAlt <= 200 + 0.15 * (200 - 64),
      ("peak %.1f"):format(trace.maxAlt))
    check("holds altitude (velocity ~0)", math.abs(ship.valt) < 0.5,
      ("valt %.2f"):format(ship.valt))
  end
end

-- 2. heading hold: turn to 90 and settle, taking the short way from 0
do
  local ap = autopilot.new()
  local ship = newShip(200, 0)
  fly(ap, ship, { alt = 200, heading = 90 }, 40, dt)
  local err = math.abs((ship.heading - 90 + 180) % 360 - 180)
  check("reaches commanded heading", err < 3, ("final heading %.1f"):format(ship.heading))
end

-- 3. shortest-turn: from 350 to 10 should go +20 (through 0), not -340
do
  local ap = autopilot.new()
  local ship = newShip(200, 350)
  -- initial command from 350 -> 10 is a +20 wrapped error, so yaw must be
  -- positive (turn up through 0), not a -340 long way around
  local firstYaw = autopilot.step(ap, { alt = 200, heading = 10 }, ship, dt).yaw
  check("initial turn is the short way (+, through 0)", firstYaw > 0,
    ("first yaw %.3f"):format(firstYaw))
  local t = 0
  while t < 20 do
    local cmd = autopilot.step(ap, { alt = 200, heading = 10 }, ship, dt)
    stepShip(ship, cmd, dt)
    t = t + dt
  end
  local err = math.abs((ship.heading - 10 + 180) % 360 - 180)
  check("wraps to nearest heading", err < 5, ("final %.1f"):format(ship.heading))
end

-- 4. disturbance rejection: hold altitude, then a shove, recovers
do
  local ap = autopilot.new()
  local ship = newShip(200, 0)
  fly(ap, ship, { alt = 200, heading = 0 }, 30, dt)
  ship.valt = ship.valt + 20  -- sudden updraft
  fly(ap, ship, { alt = 200, heading = 0 }, 30, dt)
  check("recovers to setpoint after disturbance", math.abs(ship.alt - 200) < 3,
    ("recovered alt %.1f"):format(ship.alt))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
