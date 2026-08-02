-- reactorlogic: the pure decision core of the Mekanism fission controller.
-- No peripherals, no timers - just (state, readings) -> actions, so every
-- interlock and the burn ramp are provable headless before they ever guard
-- a real reactor. reactor.lua is the thin in-game shell around this.
--
-- Readings (normalized): temp (K), damage (%), coolant/heated/fuel/waste
-- (fraction 0..1), actual (mB/t), maxBurn (mB/t), running (bool).
local rlogic = {}

rlogic.LIMITS = {
  tempMax    = 1200,  -- K; damage starts accruing around 1200
  damageMax  = 5,     -- %
  coolantMin = 0.20,  -- fraction
  heatedMax  = 0.95,  -- fraction
  wasteMax   = 0.90,  -- fraction
}

rlogic.RAMP = 1       -- mB/t added per control step when ramping up

-- Mekanism filled-percentages are 0..1 doubles; tolerate 0..100 anyway
local function frac(v)
  if v == nil then return nil end
  if v > 1.5 then return v / 100 end
  return v
end

function rlogic.normalize(raw)
  return {
    temp = raw.temp, damage = raw.damage,
    coolant = frac(raw.coolant), heated = frac(raw.heated),
    fuel = frac(raw.fuel), waste = frac(raw.waste),
    actual = raw.actual, maxBurn = raw.maxBurn,
    running = raw.running or false,
  }
end

-- first tripped interlock as a human-readable cause, or nil if all clear.
-- Readings that are missing (nil) don't trip: a monitor-only setup with a
-- partial adapter still reports what it can.
function rlogic.breach(r, limits)
  local L = limits or rlogic.LIMITS
  if r.damage and r.damage > L.damageMax then
    return ("damage %.1f%% > %d%%"):format(r.damage, L.damageMax)
  end
  if r.temp and r.temp > L.tempMax then
    return ("temp %.0fK > %dK"):format(r.temp, L.tempMax)
  end
  if r.coolant and r.coolant < L.coolantMin then
    return ("coolant %.0f%% < %.0f%%"):format(r.coolant * 100, L.coolantMin * 100)
  end
  if r.heated and r.heated > L.heatedMax then
    return ("heated coolant %.0f%% > %.0f%%"):format(r.heated * 100, L.heatedMax * 100)
  end
  if r.waste and r.waste > L.wasteMax then
    return ("waste %.0f%% > %.0f%%"):format(r.waste * 100, L.wasteMax * 100)
  end
  return nil
end

function rlogic.newState()
  return { target = 0, lastSet = 0, latched = false, cause = nil }
end

-- may the operator start? A latch needs force; an active breach is an
-- absolute no, force or not.
function rlogic.canStart(state, r, force)
  local b = rlogic.breach(r)
  if b then return false, "unsafe: " .. b end
  if state.latched and not force then
    return false, "latched after scram (" .. tostring(state.cause) .. "); force to override"
  end
  return true
end

-- clamp + set the operator target
function rlogic.setTarget(state, rate, maxBurn)
  if not rate or rate < 0 then rate = 0 end
  if maxBurn and rate > maxBurn then rate = maxBurn end
  state.target = rate
  return rate
end

-- one control step. Mutates state, returns actions:
--   { scram = "<cause>" }   safety trip: caller must scram NOW (latch is set)
--   { setBurn = <rate> }    ramp step toward target (up: +RAMP, down: immediate)
--   { }                     steady state
function rlogic.step(state, r)
  if not r.running then return {} end
  local b = rlogic.breach(r)
  if b then
    state.latched = true
    state.cause = b
    state.target, state.lastSet = 0, 0
    return { scram = b }
  end
  if state.lastSet ~= state.target then
    local nextRate
    if state.lastSet < state.target then
      nextRate = math.min(state.target, state.lastSet + rlogic.RAMP)
    else
      nextRate = state.target
    end
    state.lastSet = nextRate
    return { setBurn = nextRate }
  end
  return {}
end

-- operator scram (immediate latch, distinct cause)
function rlogic.operatorScram(state)
  state.latched = true
  state.cause = "operator scram"
  state.target, state.lastSet = 0, 0
end

return rlogic
