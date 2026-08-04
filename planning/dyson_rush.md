# Dyson Rush — "firehose the trash mats at the sun"

Config-verified economy (dysoncubeproject.toml):
  * Sphere = 50,000,000 sails at 100%; POWER = 20 FE/t PER SAIL
    -> full sphere = 1,000,000,000 FE/t. (Errot field data confirms:
    his 15k sails x 20 = 300k FE/t at 0.03%. The math is exact.)
  * 1 beam supports 6 sails (full sphere = 8.33M beams)
  * Ray Receiver: extracts up to 50M FE/t each (need ~20 at 100%)
  * Ejector: 40 FE per launched item - power is a non-issue; the
    bottleneck is GUN COUNT x ejection rate x supply

Milestones (sails -> FE/t):
    50k sails  (0.1%) = 1M FE/t      <- beats any fission setup
    500k sails (1%)   = 10M FE/t     <- post-scarcity
    5M sails   (10%)  = 100M FE/t    <- silly
    50M        (100%) = 1G FE/t      <- "You Own Daylight"

## Per-sail bill: 3 copper + 2 lapis + 4 glass panes
## Per-beam bill (x2 out): ~14 iron

At 0.1% target: 150k copper, 100k lapis (stock: 341k ✓ covers to
~0.34% alone), ~38k glass, ~120k iron + beams.

## Phase 0 — intelligence (tonight, zero build)
  [ ] SURVEY ERROT'S GUN: fly a turtle to his ejector, run
      `survey <w> <l> <h> gun`, send the pastebin code. The scan gives
      the exact multiblock shape -> `gunfit` (turtle mass-builder)
      gets written from ground truth, not guesswork.
  [ ] Copy one working ejector + receiver by hand meanwhile;
      measure ejection rate per gun (sails/min) - sizes the gun farm.
  [ ] Ask Errot for COPPER and LAPIS seed stacks while trading.

## Phase 1 — supply lines (the printer earns its name)
  * SAND STOPS DYING: curation currently voids sand into the
    condenser. Redirect: sand -> smelter line -> glass -> panes.
    The trash literally becomes the sphere.
  * Iron bay output -> beam autocraft (AE2 pattern: nuggets/bars/
    blocks all from iron essence conversions).
  * New crops: repurpose/extend bays (BAYS table in printfit is
    extendable - bay 11 copper, bay 12 lapis) or split the sandbox.
  * Sail + beam + PACKAGE patterns in AE2 (packages = dense gun feed).

## Phase 2 — the gun farm
  * `gunfit` (after the survey): a row of N ejectors on the sky
    campus, artillery-style, pipez trunk feeding packages from the
    conversion cluster, wind/ethylene power (40 FE/item is nothing).
  * Errot needed 32 guns for 0.03% by hand. We print guns.

## Phase 3 — harvest + display
  * Ray Receivers added as % climbs (50M FE/t cap each) -> Induction
    Matrix -> grid.
  * NOC board "Daylight Futures" page: sphere %, sails in flight,
    FE/t (check controllers for CC peripral API; else parse manually).

## Doctrine
Dyson = baseline grid + the permanent sink for printer overproduction.
Fission proceeds ONLY as chemistry (waste -> plutonium/polonium for
SPS/MekaSuit). Every trash material now has a job: stone/gravel ->
condenser singularities, sand -> glass -> sails, iron/copper/lapis ->
the sphere. The corp's garbage disposal is a star.
