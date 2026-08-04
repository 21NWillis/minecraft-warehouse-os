# Aeronautics: the airship program

Jar-verified against `create-aeronautics-bundled-1.21.1-1.3.0` (bundles
`aeronautics`, `simulated` physics engine, `offroad`). Also in pack:
createpropulsion, createthrusters, create_tilting_control,
create_hypertube, create_aeronautics_automated_logistics.

## How flight actually works (from the jars + ponder text)

- **Physics Assembler** (`simulated:physics_assembler`) converts a built
  structure into a *simulated contraption* — free 6-DOF physics, no grid.
- **Lift, two ways:**
  - **Hot air**: build an airtight hull of **Hot Air Envelope** blocks
    (16 dye colors, right-click dye to paint), fill from the top down
    with a **Hot Air Burner** (`aeronautics:adjustable_burner`) or
    **Steam Vent** fed by a Create boiler. Blocks inside the balloon
    reduce usable volume. Shafts pass through walls via **Envelope
    Encased Shaft**. Lift weakens with altitude → ship settles where
    lift = weight, so altitude is controlled by burner output.
  - **Levitite** / **Pearlescent Levitite**: magic floating rock, no
    burner needed. Crystallized from **Levitite Blend** (end stone
    powder involved). Fixed lift — good for static platforms.
- **Thrust**: Wooden/Andesite/Smart **Propellers** on a **Propeller
  Bearing** (or spun shaft). **Gyroscopic Propeller Bearing**
  auto-pitches to stay upright — mount facing down to stabilize
  top-heavy ships; redstone signal zeroes its tilt. Thrust also weakens
  with altitude. **Portable Engines** (16 colors) provide onboard
  rotation with fuel (right-click coal).
- **Controls**: **Linked Typewriter** — hijacks the player's movement
  keys while active and maps them to **Redstone Link frequencies**;
  bind a Linked Controller to it. This is the helm. Propellers/burners
  on the ship listen on link receivers (`directional_linked_receiver`).
- **Instruments**: **Altitude Sensor** (air pressure/altitude readout,
  redstone), **Gimbal Sensor** (orientation), stress goggles HUD via
  Aviator's Goggles.
- **Docking**: **Docking Connector** / **Paired Docking Connector** —
  ship-to-ground or ship-to-ship hard attach. This is how an airship
  parks at the campus.

## Ship One: "PHI Zeppelin" (first flight BOM)

Small proof hull, hot-air, single prop:

- ~7x5x5 envelope balloon (purple, obviously) = ~166 envelope blocks
  for the shell; keep the interior EMPTY (volume = lift)
- 1 Hot Air Burner underneath the balloon, coal-fed
- Gondola: a few deck blocks under the balloon
- 1 Portable Engine + shaft + Propeller Bearing + Andesite Propeller
  at the stern, 1 gyroscopic bearing facing down for stability
- Linked Typewriter at the helm + receivers on engine/burner lines
- Altitude Sensor on deck, Docking Connector on the keel
- Assemble with the Physics Assembler last

## Why this is our department

1. **The hull is a schematic.** A genspire-style generator emits an
   ellipsoid envelope hull as an F8 build order — Claude designs the
   ship, the executor builds it, the assembler makes it fly. Decorative
   over-the-top hulls are exactly the pipeline test the statue and the
   Golden Ascent are.
2. **Automated logistics**: `create_aeronautics_automated_logistics`
   suggests unmanned cargo runs — a flying courier that is NOT a turtle
   (the turtle-courier ban stays intact; pipez rule applies on the
   ground, airships are for range).
3. **Open question for CC**: the typewriter is player-facing. Whether a
   CC computer can drive Redstone Link frequencies (Create redstone
   link + CC redstone out into a link transmitter should work) decides
   if we get autonomous flight. Investigate on the ground first with
   one link pair.

## Order of operations

1. User flies Ship One manually (learn the physics, verify pack
   versions behave).
2. Write `tools/genhull.lua`: parametric ellipsoid envelope + gondola
   as a build order (support-checked like genspire).
3. Ground test CC → redstone link. If it works: autopilot follows.
