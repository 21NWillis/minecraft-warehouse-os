# station.lua — mini-PC dispatcher spec (draft 1, 2026-08-12)

The edge-scheduler layer of craftd v2. One station = one RECIPE CLASS
(smelting, infusing, enriching, PRC...), one buffer chest, one machine
bank, one importer chest back into RS. RS thinks it's talking to a
single infinitely-parallel machine; the station does register
allocation.

## Why stations exist (from the RS Bridge research)

RS2 locks a crafting task's external steps to the single Autocrafter
holding the chosen pattern — duplicate patterns resolve by priority to
one machine, no load balancing (#952). CC at the edge is the only
parallelism mechanism. RS 2.0.7+ already fixed the
concurrent-tasks-one-machine stuck bug, so many tasks against one
station buffer is patched ground.

## Topology (per station)

```
[RS Autocrafter] --faces--> [BUFFER chest] <--wired modem-- [CC computer]
                                                    |  pushItems
                                          [machine 1..N] (wired modems)
                                                    |  pullItems
                            [IMPORTER chest] --RS Importer--> network
```

- The RS external/processing pattern for every recipe in this class
  targets the buffer chest (Autocrafter placed against it).
- Machines are plain wired-modem peripherals; station uses generic
  inventory pushItems/pullItems only — no machine-specific APIs in v1
  (Mekanism machines expose side-configured slots; configure machine
  ejection OFF, station owns all movement so it can count).
- Importer chest has an RS Importer on it: task completion accounting
  happens RS-side when outputs land there. The station never needs
  the RS Bridge for basic operation — bridge calls are craftd v2's
  job (telemetry, stock policy), keeping per-station Lua budget tiny.

## Config (per station, data file not code)

```lua
return {
  class    = "infusing",
  buffer   = "minecraft:chest_12",
  importer = "minecraft:chest_14",
  machines = { "mekanism:metallurgic_infuser_0", ... },
  recipes  = {         -- shapes this class can see in the buffer
    { key="infused_alloy",
      inputs  = { {name="mekanism:enriched_redstone", n=1, toSlot=2},
                  {name="minecraft:iron_ingot",      n=8, toSlot=1} },
      outputs = { {name="mekanism:infused_alloy", fromSlot=3} } },
  },
  maxInFlight = 2,      -- ingredient sets per machine before skip
  pollFast = 0.25, pollIdle = 2.0,  -- adaptive polling (10ms budget law)
}
```

## Core loop (event-driven, headless-testable)

1. **Scan buffer** → parse contents into complete ingredient SETS per
   recipe key (RS may interleave multiple concurrent tasks' pushes —
   set-parsing math is pure logic, unit-test it hard).
2. **Dispatch**: round-robin machines; skip machines at maxInFlight or
   flagged jammed; pushItems set into machine input slots.
3. **Collect**: pullItems machine outputs → importer chest; decrement
   in-flight on expected-output receipt.
4. **Jam watchdog**: in-flight set older than T with no output →
   mark machine jammed, rednet alert to craftd, retry once, then
   route around it. Partial ingredient sets aging in buffer > T →
   flush to importer (returns to RS, task re-plans).
5. Adaptive poll: fast while buffer nonempty or in-flight > 0.

Pure-logic module `stationlogic.lua` (set parsing, rotation, in-flight
ledger, jam detection) + thin `station.lua` IO shell — same split as
reactorlogic/quarrylogic. Tests in tests/ against mock_cc inventories.

## craftd v2 integration

- Stations heartbeat over rednet (`paperclip.station`): class, queue
  depth, in-flight, jams. craftd v2 registry feeds nocboard v2.
- craftd v2 owns the ONE rs_bridge: telemetry pulls, stock-policy
  crafting (`craftItem` on low-watermark intermediates — the
  branch-predictor doctrine ported), rs_crafting event watching.
- Bridge landmine handling (from research, encode in craftdlib):
  craftItem returns job object not boolean (async calc — watch
  rs_crafting events, poll job.isDone() fallback); NEVER
  presence-check by count (craftable-zero-stored clamps to 1);
  fingerprints for component-bearing items; modest craft batch sizes.

## mock_rsbridge test plan

`tests/mock_rsbridge.lua`: in-RAM item table + pattern list;
craftItem returns a job table with scriptable isDone/missing timing;
queues rs_crafting events into a mock os.pullEvent. Test cases:
(1) job lifecycle happy path; (2) MISSING_ITEMS event → craftd defers
and re-queues; (3) count=1 clamp — stock policy must not treat
craftable-only as stocked; (4) done-vs-canceled ordering race;
(5) station set-parse under interleaved pushes from 2 tasks;
(6) round-robin fairness + jam route-around.

## Field-test checklist (first in-game session)

Smelting station end-to-end first (furnace bank = simplest shapes),
then the 5-item RS Bridge checklist from atm10_translation.md
(duplicate-pattern parallelism question decides whether stations are
the only mechanism or just the best one).
