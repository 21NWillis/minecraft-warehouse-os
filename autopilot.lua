-- autopilot: PID flight controller for a Sable / Create Aeronautics ship.
--
-- Pure control logic - no peripherals. The ship program supplies a sensor()
-- returning live pose and an actuator(cmd) that drives thrust/yaw; this module
-- decides the commands. That split lets the whole controller be validated
-- against a simulated ship in the headless rig before any airframe exists.
--
-- Each axis is an independent PID with:
--   - derivative-on-measurement (no setpoint-change "derivative kick")
--   - integral clamping (anti-windup, so a long climb doesn't overshoot)
--   - output saturation to the actuator's real range
local autopilot = {}

local PID = {}
PID.__index = PID

function autopilot.pid(kp, ki, kd, opts)
  opts = opts or {}
  return setmetatable({
    kp = kp, ki = ki, kd = kd,
    outMin = opts.outMin or -1, outMax = opts.outMax or 1,
    iMin = opts.iMin or -1, iMax = opts.iMax or 1,
    integral = 0, prevMeas = nil,
  }, PID)
end

function PID:reset()
  self.integral = 0
  self.prevMeas = nil
end

local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi else return x end
end

function PID:update(setpoint, measurement, dt)
  if dt <= 0 then return 0 end
  local err = setpoint - measurement

  -- integral with clamping (anti-windup)
  self.integral = clamp(self.integral + err * dt, self.iMin, self.iMax)

  -- derivative on measurement, not error: avoids a spike when setpoint jumps
  local deriv = 0
  if self.prevMeas ~= nil then
    deriv = -(measurement - self.prevMeas) / dt
  end
  self.prevMeas = measurement

  local out = self.kp * err + self.ki * self.integral + self.kd * deriv
  return clamp(out, self.outMin, self.outMax)
end

-- a heading controller wraps error into [-180, 180] so it turns the short way
local Heading = setmetatable({}, { __index = PID })
Heading.__index = Heading

function autopilot.heading(kp, ki, kd, opts)
  local p = autopilot.pid(kp, ki, kd, opts)
  return setmetatable(p, Heading)
end

local function wrap180(a)
  a = (a + 180) % 360 - 180
  if a < -180 then a = a + 360 end
  return a
end

function Heading:update(setpoint, measurement, dt)
  if dt <= 0 then return 0 end
  -- P/I on wrapped error (turn the short way around the 0/360 seam)
  local err = wrap180(setpoint - measurement)
  self.integral = clamp(self.integral + err * dt, self.iMin, self.iMax)
  -- D on the wrapped change in *measured* heading = yaw-rate damping. (The
  -- base PID's derivative-on-measurement breaks here because the seam makes
  -- raw measurement deltas jump 360; wrap them.)
  local deriv = 0
  if self.prevMeas ~= nil then
    deriv = -wrap180(measurement - self.prevMeas) / dt
  end
  self.prevMeas = measurement
  local out = self.kp * err + self.ki * self.integral + self.kd * deriv
  return clamp(out, self.outMin, self.outMax)
end

-- compose a full 2-axis autopilot (altitude + heading). tune per ship.
function autopilot.new(tuning)
  tuning = tuning or {}
  return {
    alt = autopilot.pid(
      (tuning.alt or {}).kp or 0.08,
      (tuning.alt or {}).ki or 0.004,
      (tuning.alt or {}).kd or 0.20,
      { outMin = -1, outMax = 1, iMin = -50, iMax = 50 }),
    yaw = autopilot.heading(
      (tuning.yaw or {}).kp or 0.03,
      (tuning.yaw or {}).ki or 0.0,
      (tuning.yaw or {}).kd or 0.08,
      { outMin = -1, outMax = 1, iMin = -30, iMax = 30 }),
  }
end

-- one control tick: returns {thrust=-1..1, yaw=-1..1}
function autopilot.step(ap, setpoint, pose, dt)
  return {
    thrust = ap.alt:update(setpoint.alt, pose.alt, dt),
    yaw = ap.yaw:update(setpoint.heading, pose.heading, dt),
  }
end

return autopilot
