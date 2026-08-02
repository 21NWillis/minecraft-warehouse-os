# Paperclip datacenter — build runbook

The whole base hangs off **one block**: a Void Portal (`javd:portal_block`) in
the HQ's main room. The void side is the campus; every structure is built by
`datacenter build <phase>` from a turtle standing on the portal. This document
is the order of operations; the live checklists are `datacenter bill <phase>`
in-game (same numbers, computed from the same generators).

All numbers below are exact (generated headless from the schematics), fuel
estimates are generous. Coal = 80 moves each.

## Master material bill

| build | size | blocks | purple concrete | pol. blackstone | gray st. glass | sea lantern | fuel |
|---|---|---|---|---|---|---|---|
| HQ (overworld) | 15x38x11 | 1234 | 815 | 152 | 219 | 48 | ~3900 |
| 1. pad | 17x1x17 | 288 | 208 | 64 | 0 | 16 | ~1100 |
| 2. noc | 9x7x9 | 313 | 232 | 52 | 25 | 4 | ~1200 |
| 3. warehouse | 19x9x13 | 905 | 696 | 88 | 109 | 12 | ~3000 |
| 4. power | 17x13x17 | 1273 | 972 | 108 | 177 | 16 | ~4100 |
| 5. bays | 13x5x9 | 345 | 287 | 52 | 0 | 6 | ~1300 |
| 6. casino | 13x2x21 | 394 | 273 | 106 | 0 | 15 | ~1500 |
| **campus total** | | **3518** | **2668** (42 st) | **470** (8 st) | **311** (5 st) | **69** (2 st) | **~12200 (~153 coal)** |

Also craft: 1 Void Portal (8 obsidian + 1 ender pearl), 1 advanced turtle
("Constructor-1") + diamond pickaxe, 1 ender chest **pair** (one carried, one
at the staging chest — this is how big builds restock mid-flight), ~4 stacks
of coal total including the HQ.

## Phase 0 — overworld front door

1. `buildrun paperclip plan` for the HQ bill (above), stage materials.
2. Pick the HQ site; place Constructor-1 at the bottom-front-left corner
   facing into the build (+z). The P faces the *other* way (-z) — aim it at
   the road. `buildrun paperclip`.
3. Craft the Void Portal, place it in the main room (ground floor interior).
4. **Verify JAVD behavior before anything else**: step through, note where
   you arrive (JAVD mirrors the portal into the void at matching coords),
   confirm the return trip, and check whether mobs can spawn out there.
   Assumption to test, not trust.

## Phase 0.5 — the datum

Standing in the void: the portal block you arrived at IS the campus datum.
1. Decide campus-north (+z): every offset is in this frame, so pick once and
   mark it (a torch on the +z side).
2. Place Constructor-1 **on top of the portal block**, facing campus-north.
3. `datacenter map` to sanity-check the layout, `datacenter list` for order.

Every build starts and ends with the turtle on the portal. The loop for each
phase is always: `datacenter bill X` -> stage materials into the turtle (and
the ender chest for big phases) -> `datacenter build X` -> do the "after"
fit-out list it printed -> next phase.

## Phase 1 — pad (before anything else: it's the floor you'll stand on)

Fits in the turtle's inventory in one load. The portal keeps its center hole.
After: staging chests + the field ender chest by the portal.

## Phase 2 — noc (control room, so ops move into the void early)

After: advanced computer + ender modem inside; `update` then `menu` on it;
monitor wall on the back interior wall. From here on you can read this
runbook's checklists from the void (`datacenter bill` runs anywhere).

## Phase 3 — warehouse (logistics before the expensive phases)

905 blocks — more than a 16-slot hold: carry the ender chest, keep the
staging chest fed; the builder self-docks when it runs dry and resumes.
After: storage controller + barrels on a wired network, warehouse computer,
crafter pool. Once `warehouse` + `crafters` are live, later bills can be
autocrafted instead of hand-fed. (Cold-start order inside this phase:
TESTING.md — deploy, doctor, selftest, warehouse, crafters.)

## Phase 4 — power (the reactor gets a building before it gets fuel)

Biggest build (1273 blocks, ~4100 fuel) — ender-chest workflow again.
After: assemble the Mekanism fission multiblock inside (leave headroom for a
turbine later), Logic Adapter + computer running `reactor`. Do a dry
commissioning first: `reactor` in monitor-only (no fuel loaded) to confirm
every method binds — if names drift it says so, then `probe` and we fix.
First criticality: coolant full, burn target 1 mB/t, watch the interlocks.

## Phase 5 — bays (fleet expansion capacity)

After: disk drives + provisioning floppies per bay, fuel chest, spare parts.

## Phase 6 — casino (last, because it's gated on verification)

Before building anything here, run the 4-assumption strainer test from
`planning/strainer_floor.md` with ONE strainer in a puddle. If the numbers
hold (1 roll/sec, 10% diamond), fit out: water in the channels, strainer
rows, collection + sorting into the warehouse, and put DIAMONDS/SEC on the
NOC monitor wall.

## Bring-up order after construction (systems, not structures)

1. NOC computer: `update`, `menu install`, `profiler tick 60` for a baseline
   tick-lag number — save it; it's the reference as the fleet grows.
2. Warehouse network + crafter pool (TESTING.md cold-start).
3. Reactor commissioning (above). Power routing to the campus.
4. Strainer verification -> casino fit-out.
5. Fleet: provision worker turtles in the bays; harvest/fleet programs.
6. Then the fun roadmap: turbine control, GPS constellation, the GPU hall
   for the Java mod when the server adds it, orbital anything.

## Standing rules

- The turtle always launches from the portal, facing campus-north. If a build
  aborts (blocked/out of material), it flies home; restock and rerun the same
  `datacenter build X` — sites assume empty void, and a partial build resumes
  by re-placing into air (already-placed cells fail placement and would halt
  the plan — clear partial work if a build died mid-phase, or rerun and let
  it stop at the first occupied cell to find where it left off).
- Nothing builds in the datum column or the y=15 flight corridor: that's
  enforced by tests (tests/datacenter_test.lua), keep it that way when
  adding sites.
- New campus sites: add to `SITES` in datacenter.lua, run the test suite —
  overlap/corridor/datum-column violations fail CI before they fail a turtle.
