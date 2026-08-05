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
- SUN WING: 40x16 platform extending past the campus southern edge,
  open sky guaranteed by decree. Hosts gun rows + wind masts + solars.
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

## Phase P1 — wind farm (day-one power, all printer-native)

At y=270+ each Mekanism wind turbine runs near max (~400-480 J/t).
Chain: metallurgic infuser (osmium+redstone+iron) -> enriched carbon
-> steel -> turbines. Build 12-16 on the sun wing masts, cable to a
basic energy cube bank.
- Target: ~5-7 kJ/t = enough for the whole ore-processing line and
  then some. Retires the three shameful solar panels.

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

## Bootstrap order for the long session

1. P0 bays (copper/lapis) - flights + your ritual, ~1 hour
2. Deck tile 1 (32x16 under SW campus) + spine trunk - turtles
3. P1 wind farm on first sun-wing mast row - immediate power
4. Mekanism ore line row 1 (infuser -> enrichment -> smelter)
5. P2 gun row 1 (12 guns) once sails flow
6. Iterate: more tiles, more rows, more guns, fission when bored
