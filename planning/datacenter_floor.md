# The Datacenter Floor — under-campus deck, power, Mekanism

The big-session plan. Bootstrap entirely from what the printer already
makes plus cobble. Campus floor sits at y=270 (sky campus); the deck
hangs beneath it as the machine floor, with a sun wing outside the
campus shadow for everything that needs sky.

## Balance sheet this plan spends (2026-08-04 dyno + census)

| resource | banked | rate | notes |
|---|---|---|---|
| iron essence | 34k | ~325/min | beams, steel, machine casings |
| osmium essence | 23k | ~milestone | THE Mekanism bootstrap metal |
| redstone essence | 22k | ramping | circuits, control |
| obsidian essence | 24k | ~329/min | deck facing (blast-proof, looks pro) |
| uranium essence | 24k | ~323/min | fission, later |
| gold/diamond/netherite | ~23k ea | steady | tiers, upgrades |
| inferium | 77k | ~765/min | tier-up feedstock |
| cobble | infinite | - | structural core, hidden faces |
| copper/lapis | SEEDS ONLY | 0 | sail bottleneck - see bays 10-12 |

## Geometry

```
        y=270  CAMPUS (purple, 37x37 + bay row)
        y=269  campus floor slabs
          |    (11-block clearance: machines, turtles, catwalks)
        y=258  THE DECK - machine floor, open face
        y=257  deck slab (cobble core, obsidian face)

   deck footprint: campus shadow + SUN WING extending south
   (guns + solar + wind need sky; nothing may roof them, ever -
    printfit solar-safety rule applies deck-wide)
```

- Deck at y=258: under-campus section = the "carpet". Machines, the
  craftd cell rack, storage annexes, pipez trunks along the ceiling.
- COMPASS LAW (operator, 2026-08-04): extensions legal to campus
  NORTH (past the NOC), SOUTH (behind the casino), EAST. WEST IS
  BANNED - never extend or plan beyond the west edge, ever.
- Corridor assignments: NORTH = printer row growth (bays 10-12+);
  EAST = the long-term open-face deck expansion (deepest legal
  span - spend it slowly); SOUTH = THE SUN WING.
- SUN WING: 40x16 platform off the south edge behind the casino,
  open sky by decree. Hosts gun rows + solar row + Ship One
  mooring. Session-start ritual: operator F10s near the south edge,
  sitefind-style scan verifies clear volume, wing build order emits
  fromDatum. The Dyson guns become the casino skyline - the house
  always wins, and it is solar powered.
- Open face doctrine: the deck's south and west edges stay unwalled -
  the "giant open platform" for future machines/turtles. Rails of
  glowstone every 8 blocks; no roof except where campus is already
  overhead.
- Materials: structural core CObBLE (free); walking surface + visible
  edges PRINTED OBSIDIAN (blast-proof, server-room black) with purple
  concrete accent lines (concrete.lua). The carpet under the campus is
  obsidian, not cobble - we print 300+/min, it costs nothing but time.

## Phase P0 — bays 10-12: copper, lapis, glass sand (the sail enablers)

Sandbox bay (10) refits to COPPER (seeds in hand). Extend the printer
row +2 bays (11 lapis, 12 sugar/sand-adjacent or spare). The entire
ritual is proven: genfarm order per bay, F8 flight, hoe+9x9 pylon,
lilypads, watering can. Farmland tiers: prudentium is fine for both.
Glass: strainer floor sand -> smelt, or trade; 4 panes/sail is light.
- BOM per new bay: 76 farmland + 76 seeds + pylon + user + chest +
  4 lilypads + hoe + watering can (the standard kit)

## Phase P1 — power bootstrap (CORRECTED: the pack DELETED wind)

Recipe-db verified: NO wind_generator recipe exists in this pack -
the author pre-empted the sky-altitude meta. The corrected ladder:

P1a - SOLAR ROW (day one, all printable): solar panel = 3 glass
panes + 2 redstone + infused alloy + 3 osmium; solar generator =
3 panels + 2 alloy + iron + energy tablet + 2 osmium; advanced =
3 solars + 2 alloy + 3 iron. Chain prereqs: metallurgic infuser
(4 iron + 2 furnace + 2 redstone + osmium), enriched carbon (coal),
steel, infused alloy (redstone infusion). Glass panes are the only
non-printed input (sand -> smelt; strainer floor makes sand).
Build 6-8 ADVANCED solars on the sun wing. Modest but immediate.

P1b - ETHYLENE FROM SEED SURPLUS (the real interim engine): the
bays over-produce seeds (+57 uranium, +50 obsidian, +26 gold/iron
seeds PER MINUTE, measured). Crusher -> bio fuel; electrolytic
separator -> hydrogen; pressurized reaction chamber -> ethylene;
gas-burning generators (osmium + alloy + steel casings +
electrolytic core) burn it hot. Waste seeds become watts - same
doctrine as trash-into-sails. This carries the factory until the
gun farm and fission outgrow it.

## Phase P2 — gun farm on the sun wing (the real curve)

From dyson_rush.md: gun = ONE em_railejector_controller item placed
into a validated 3x3x3 AIR volume (F8 executor places these BETTER
than turtles - turtles fail the air check by existing inside it).
Errot's field: 24 guns at 3-pitch. Ours: 2 rows x 12 at 3-pitch on
the wing, under-slab item trenches feeding from a sail buffer chest.
- Sail line: 3 copper + 2 lapis + 4 panes; craftd hot path once
  bays 10-11 flow. Feed guns via pipez trench (user's art).
- Benchmark: friend's 32 guns at 0.03% sphere = 300k RF/t. Receiver
  caps 50M FE/t; sphere caps 50M sails. This is the long curve.

## Phase P3 — Mekanism line on the carpet

Under-campus deck, in rows (leave turtle aisles, 2-wide, marked):
1. Ore-processing: metallurgic infuser, enrichment chamber x4,
   crusher x2, energized smelter x4 -> factory upgrades as essence
   allows (osmium is rich: go elite tier early).
2. Electrolytic separator + rotary condensentrator (hydrogen line).
3. FISSION (uranium essence -> yellow cake -> fissile fuel): the
   printer prints reactor fuel at 323/min. Small 1-burn-rate reactor
   first, turbine loop, THEN scale. Reactor gets its own annex with
   blast-mat (obsidian, naturally) - not on the open face.
4. Circuits/alloys hot path in craftd (infused alloy, basic->elite
   circuits) - the Terminal orders them, cells + machines make them.

## Phase P4 — the long-term open face

The deck extends west as demand appears: more cell racks, ME annex
(sovereign controller when meteorite trip happens), aeronautics dock
(Ship One moors at deck edge - it needs open sky too), accelerator-
free GPU shrine (a B800 on a pedestal, purely to flex).

## Build mechanics

- Deck slabs: turtle fitters (flat serpentine slab = the easiest
  program in the fleet; deckfit.lua from campus.lua pattern) in
  32x16 tiles, cobble core first pass, obsidian face second pass.
- Gun wing + machine placement: F8 orders (support-checked), user
  places GUI-config blocks (pylons lesson: owner-tracked blocks by
  hand).
- Chunk claims: deck chunks claimed + force-loaded the day the
  limit bump lands (it is in tonight's push).
- Wired spine: one cable trunk down a campus pillar, along the deck
  ceiling, stubs every 8 blocks. Lay cable FIRST, modems after,
  netprobe before declaring anything done (the doctrine).

## SHARD 1 — LIVE (order staged 2026-08-05)

The first deck tile, sited from the 08-05 snapshot (under-campus is
verified empty air y=261..267, zero obstructions). 32x16 obsidian at
y=257 (walk surface 258), directly under the storage/craftd hub so the
cable spine is a straight 11-block drop.

- World rect: x -376..-345, z -1872..-1857, block layer y=257.
- Order file: shard1_deck.json (512 obsidian, serpentine, fully
  adjacency-chained - verified offline, 0 non-adjacent transitions).
- ANCHOR: hand-place ONE obsidian at world (-376, 257, -1872) - the
  NW corner - before arming. Floating tile: every other block chains
  sideways off it (executor face search tries all six directions).
- Spine: break one campus floor block near the hub (storage cluster
  x -369..-359, z -1869..-1861), cable column straight down to deck
  ceiling, wired modem stubs at the bottom. Cable = stone + redstone
  (6/craft), wired modem = 8 stone + redstone - smelt ~2 stacks
  cobble to stone first, everything else is grid work.
- Machine row 1 (hand-placed, GUI-block doctrine): pitiful generator
  + metallurgic infuser near the spine foot, ~(-368, 258, -1866).

First-power path (recipe-db verified, planner-simulated 08-05):
NO copper needed. industrialforegoing:pitiful_generator = cobble +
gold ingot + 2 iron bars + furnace + machine_frame_pity (4 logs +
4 iron + redstone block). Every input is logs/cobble/essence. Burns
wood or coal, outputs RF; pipez energy pipe (or adjacency) feeds the
metallurgic infuser -> infused alloy -> circuits -> the whole tree.
Planner dry-run resolves it as a 9-step, 3-level recursive plan; the
infuser as 5 steps; obsidian 1:1 from essence (8 -> 8).

Recursive showcase orders (exact-id, via craftui or orderq):
  256|id:minecraft:obsidian            (x2 - deck material, keeps
                                        each cell job under the 64-run
                                        / free-slot ceiling)
  1|id:industrialforegoing:pitiful_generator
  1|id:mekanism:metallurgic_infuser

## Bootstrap order for the long session

1. P0 bays (copper/lapis) - flights + your ritual, ~1 hour
2. Deck tile 1 (32x16 under SW campus) + spine trunk - turtles
3. P1 wind farm on first sun-wing mast row - immediate power
4. Mekanism ore line row 1 (infuser -> enrichment -> smelter)
5. P2 gun row 1 (12 guns) once sails flow
6. Iterate: more tiles, more rows, more guns, fission when bored
