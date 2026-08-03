# Paperclip datacenter — build runbook

> **SITE CHANGE (2026-08-02):** the void dimension is claimed by another
> player (JAVD links to their spot). The campus is now a SKY CAMPUS ~200
> blocks directly above the HQ tower, same coordinate frame as every build.
> Nothing in the campus code changes: the datum is simply a placed block
> (a gold block) instead of the portal. Bootstrap: turtle on the original
> pedestal corner facing into the tower -> `go up 200` -> place gold block
> down -> it's standing on the datum -> `datacenter build pad` (the datum
> sits in the pad's center hole, as the portal would have).
> Access: scaffold up once, `/sethome campus` (FTB Essentials), hypertube
> later. Protection/chunkloading: FTB Chunks claims are column-wide - one
> claim covers tower AND campus; force-load for offline operation. Height
> check: ground ~y70 puts the corridor ~y285, under the y320 cap.

The whole base hangs off **one block**: the datum the turtle stands on.
Every structure is built by `datacenter build <phase>` from a turtle on that
block. This document is the order of operations; the live checklists are
`datacenter bill <phase>` in-game (same numbers, computed from the same
generators).

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

> **ORDER REVISION (post-verification):** with the strainer economy field
> confirmed, the casino jumps the queue: pad -> **casino** (+ hopper/chest
> plumbing from strainer #1 - loose item entities at battery scale are the
> performance bomb; bulk storage is part of the build, not an afterthought)
> -> noc -> warehouse (which the casino's sorting needs make urgent anyway)
> -> power -> bays. Sky bootstrap is `skyladder` (scaffolding column + gold
> datum from the anchor corner), then `datacenter build pad` on the same
> turtle. Strainers only tick in loaded chunks; force-load is a deliberate
> decision once throughput is seen.

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

## Phase 7 status (2026-08-03): STAGED PLAN ACTIVE

Storage doctrine (CC can't see into ME cells - no ME bridge in pack - so):
bulk stackables live in the CC-visible tier-5 barrel wall (storage bus,
HIGH priority; feeds grid/nocboard/Lens/curator); the long-tail item types
live in ME cells (LOW priority, native balancing). One terminal shows both.
- Stage 1 (bridge, done/tonight): energy acceptor + STORAGE BUS ON THE
  STORAGE CONTROLLER + crafting terminal, ad-hoc (no ME controller).
- Stage 2: meteorite sky stone -> ME Controller; drives + cells from the
  64x processor hoard; priorities barrels>cells; SFM `store` label moves to
  an ME Interface so the fast lane feeds the unified network.
- Stage 3: assemblers + pattern providers (autocrafting), ae2wtlib wireless
  terminal, tower ME lobby, server-room aesthetics fit-out.

## Phase 7 — ME uplink (the giga system)

Architecture: ALL storage/crafting hardware in the void; the tower is a
terminal lobby. One network, bridged across dimensions:

```
VOID (warehouse hall)                      OVERWORLD (HQ main room)
  ME Controller + drive walls                Quantum Ring (far side)
  autocrafting CPUs + assemblers    <-- Quantum Network Bridge -->
  Quantum Ring (near side)                   crafting/pattern terminals
  powered by the reactor wing                 (the "cute little ME system")
```

Order of operations:
1. Prereqs: AE2 meteorite for the inscriber presses (compass), certus
   budding farm, charger/inscriber line in the warehouse hall.
2. Core in the void warehouse hall: controller, energy acceptors fed from
   the power wing, drive wall, crafting CPUs. Channels: controller-first
   design; P2P later if 32 per bridge face gets tight.
3. Quantum bridge: 2x quantum ring (8 blocks each) + 2 entangled
   singularities; one ring by the warehouse hall, one in the HQ main room
   next to the portal. BOTH sides must be chunkloaded: FTB Chunks claims
   + force-load on the tower chunk and the campus core chunks.
4. Tower lobby fit-out: terminals on the overworld ring. Pocket access:
   ae2wtlib Wireless Universal Terminal + quantum card (+ AEInfinityBooster
   range) = the whole system from anywhere, any dimension.
5. CC <-> ME handshake: no ME Bridge peripheral in this pack (no Advanced
   Peripherals), so the warehouse OS talks to ME through ME Interfaces,
   which look like plain inventories to CC's generic peripheral methods.
   The CC warehouse keeps running ingest/metrics/strainer-sorting; ME is
   the human-facing UI layer on the same physical stock. melink.lua was
   built for exactly this handoff.

## Phase 7b — storage tiering / auto-balance (dump-proofing, later stage)

Goal: dumping a full inventory NEVER eats ME cell types. Design = priority
cascade where mass items go to typeless storage and cells only hold the
long tail:

1. **Drawer wall** (Functional Storage, in the void warehouse hall) behind
   an ME Storage Bus at HIGH priority, partitioned: every bulk item
   (cobble/stone/concrete/ores/ingots/strainer aggregate...) gets a drawer
   with max upgrades. Drawers are one-type-huge-count = no types math at
   all. This absorbs inventory dumps before any cell sees them.
2. **General cells** at LOW priority catch everything unrecognized (the
   long tail is exactly what the types system is fine at).
3. **Promotion loop**: the CC warehouse already indexes stock through ME
   Interfaces - a `defrag` service tracks which long-tail items keep
   showing up in volume and flags "promote to drawer" on the NOC dashboard
   (and later auto-crafts + places the drawer upgrade order). IO Port
   cycles migrate existing cell contents after each promotion.
4. Overflow policy: drawer void upgrades on true-junk bulk (cobble tiers),
   EMC-burn via transmute for surplus with value (the conservation-honest
   version of voiding).

## Bring-up order after construction (systems, not structures)

1. NOC computer: `update`, `menu install`, `profiler tick 60` for a baseline
   tick-lag number — save it; it's the reference as the fleet grows.
2. Warehouse network + crafter pool (TESTING.md cold-start).
3. Reactor commissioning (above). Power routing to the campus.
4. Strainer verification -> casino fit-out.
5. Fleet: provision worker turtles in the bays; harvest/fleet programs.
6. XP refinery (future campus site, near the casino): Apothic hyper-spawner
   (silk-touched enderman/blaze spawner + sugar/clock/comparator upgrades)
   -> Mob Grinding Utils fans + mashers -> absorption hoppers -> fluid XP.
   Storage via EnderIO XP Obelisk; Create: Enchantment Industry disenchants
   the casino's ancient-city loot into the same tanks. Endgame: Industrial
   Foregoing mob duplicator + crusher off reactor power. Sink: Apotheosis
   enchanting room in the HQ head office, piped from the void.
   Field prep NOW: keep silk touch when found; log spawner coordinates
   instead of breaking them (enderman/blaze prized); keep every Apotheosis
   gem + affix drop (salvage fodder for the sword program).
   6b. Weapons division: Apotheosis sword grind rides the refinery - hyper
   spawner box doubles as the gem/affix farm + Gateways arena; casino funds
   reforges; cataclysm boss mats feed it (apothic_cataclysm).
7. Food program (sooner than later - SoL Carrot makes variety a stat):
   tier 1 NOW: Easy Villagers Auto Trader + farmer villager, casino emeralds
   -> golden carrots automatically (butcher for variety). Tier 2: Cooking
   for Blockheads kitchen (tower or NOC) + Pam's = one-click variety for
   the SoL chart. Tier 3: "agri-deck" campus site - Create harvester rows
   feeding the warehouse; auto-stocker keeps the kitchen + lunchbox full.
7b. Gigasmelter annex (when smelting demand shows up - glass for builds,
   quarry ore, food): Create BULK BLASTING trench beside the warehouse -
   encased fan + lava turns a small channel into a fuel-free conveyor
   smelter; feed from the warehouse, wash output back in. Schematic-able
   (future `datacenter` site + fit program). Mekanism smelting factories
   supersede at power-wing tier.
8. Sharded construction (shardrun): partition a schematic into disjoint
   x-slabs, one per turtle - fleet.lua leases the slabs (no double-assign,
   dead-worker reclaim), every turtle docks against the same ender-chest
   channel, and each shard's serpentine/hover/home column stays inside its
   own slab so N turtles never share airspace. Provisioning via the floppy
   drive. Turns hall-scale builds into minutes and mega-builds into possible.
9. Then the fun roadmap: turbine control, GPS constellation, the GPU hall
   for the Java mod when the server adds it, orbital anything.

## Appendix A — zero-to-tower walkthrough (phase 0, exact steps)

From "a chest and some items" to the HQ standing:

1. **Craft the kit**: computer (7 stone ring, redstone center, glass pane
   bottom-middle) -> turtle (7 iron ring, computer center, chest
   bottom-middle) -> mining turtle (turtle + diamond pickaxe in a grid).
   2x EnderStorage ender chests (JEI: the one with colored latches; same
   colors = shared inventory). ~64 coal. Void portal for later
   (8 obsidian + ender pearl).
2. **Materials** (`buildrun paperclip plan` prints this in-game):
   815 purple concrete (102x powder crafts: 4 sand + 4 gravel + 1 purple dye
   -> 8 powder; water-convert BEFORE loading - the turtle places exact ids),
   152 polished blackstone, 219 gray stained glass (8 glass + gray dye -> 8),
   48 sea lanterns (4 prismarine shards + 5 crystals each). Budget palette if
   prismarine/purple is annoying: `buildrun paperclip minecraft:purple_terracotta
   minecraft:polished_blackstone minecraft:gray_stained_glass minecraft:glowstone`.
3. **Site**: 15 wide x 11 deep flat, 38 of clear sky. Stand at your viewpoint:
   the P faces you; the turtle goes at the front-LEFT corner facing AWAY.
4. **Placement**: temp block at that corner, turtle ON TOP facing into the
   build, break the temp block (turtle floats). Ground floor forms level with
   where the temp block was.
5. **Software**: in the turtle: `label set constructor-1`, then
   `wget https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/update.lua update`
   then `update https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/`.
6. **Load**: base ender chest at your chest area holding ALL spare stacks;
   turtle carries: coal, the paired ender chest, 14 slots of materials.
7. **Launch**: `buildrun paperclip`. ~30-45 min. It self-restocks from the
   ender chest when dry - your only job is keeping the base chest fed.
8. **If it stops**: it parks at the origin column and saves its pose. Fix the
   cause (usually an empty paired chest), then `buildrun paperclip resume` -
   it locates the first missing block and continues (idempotent, tested).
9. **Then**: portal in the main room, step through, phase 0.5 of this runbook.

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
