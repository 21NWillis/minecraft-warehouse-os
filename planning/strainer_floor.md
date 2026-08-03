# The Strainer Floor — casino deck for Paperclip HQ

Source-verified from `ftb-stuff-things-21.1.19.jar` and the pack's live
`config/ftbstuff.snbt` (no pack-level loot overrides found in kubejs/datapacks).

## The device

`ftbstuff:oak_water_strainer` — crafted from **2 wooden rods + 3 cloth mesh +
2 planks**. The pack config points it at loot table
`ftbstuff:custom/water_strainer_test` with `strainer_tick_rate: 20` —
**one generation per second**.

## Loot math (oak variant, per generation)

The netherrack entry is conditioned on crimson/warped strainers, so for oak the
main pool weighs 26:

| Pool "main" (1 roll) | weight | odds |
|---|---|---|
| nothing | 20 | 76.9% |
| stone | 1 | 3.85% |
| gravel x2 | 1 | 3.85% |
| sand | 1 | 3.85% |
| roll `gameplay/fishing/fish` | 1 | 3.85% |
| roll `gameplay/fishing/junk` | 1 | 3.85% |
| roll `chests/ancient_city` | 1 | **3.85%** |

| Pool "gems" (1 roll, every generation) | weight | odds |
|---|---|---|
| nothing | 7 | 70% |
| lapis | 1 | 10% |
| **diamond** | 1 | **10%** |
| emerald | 1 | 10% |

## Expected value per strainer-hour (3600 generations)

- **~360 diamonds, ~360 emeralds, ~360 lapis**
- **~138 ancient-city chest rolls** — echo shards, disc fragments, swift sneak
  books, enchanted golden apples, diamond horse armor, sculk...
- ~138 fish rolls + ~138 junk rolls + ~415 stone/gravel/sand

This is, to be clear, completely unhinged for the crafting cost. Even if the
in-game mechanism is 10x slower than the config suggests, it out-earns
everything else we run.

## FIELD-VERIFIED (2026-08-02, one timed minute)

Measured: 4 diamonds, 8 emeralds, 6 lapis, 12 glowberries, 22 coal,
3 bejeweled apples (modded loot injection), enchanted hoe, saddle, XP, junk.
Gem pool: 18 hits/60 rolls vs 30% modeled - **exactly on prediction**.
Cadence ~1 roll/sec confirmed. Per strainer-hour: ~240 diamonds,
~480 emeralds, ~360 lapis, ~140 ancient-city pulls.

**Mechanism (FINAL, field-confirmed):** strainers work waterlogged in
SOURCE blocks - no flow engineering needed at all. Casino channel design:
fill the trough with water sources, place a strainer in EVERY cell (full
density, ~38 per channel, ~152 per deck). Strainers are pure inventories
(catch accumulates inside; no entity spit); collection = the courier turtle
harvesting each strainer from above via suckDown, with a mesh guard.
Still open: mesh durability over long runs.

## Verify in-game before scaling (assumptions to test with one strainer)

1. Does every 20-tick cycle actually roll, or is there a hidden chance/water
   condition? (Time 100 outputs against a clock.)
2. Water requirement: still vs flowing, and does it need a `pump`?
3. Mesh: the allowed-mesh block tags (cloth/iron/gold/diamond/blazing) gate
   which mesh fits which strainer — check whether mesh tier changes anything
   for the loot roll (the loot table itself has no mesh conditions) and
   whether meshes take durability damage.
4. Output path: does it eject into an internal buffer (hopper-extractable?) or
   spit item entities?

## Floor design (once verified)

A mezzanine floor of Paperclip HQ: rows of strainers over a water channel,
hoppers/pipez feeding warehouse ingest barrels. Wire the sorting so:

- gems + ancient-city treasure -> vault barrels (warehouse-indexed)
- fish -> food line / villager trading
- junk + stone/gravel/sand -> `transmute` burn for EMC (conservation-honest:
  the junk becomes budget)

Instrument it: a `metrics` counter per item class off the ingest barrel
(`machine.lua` driver) so `exchange` can price the floor's real yield/hour and
the dashboard can show DIAMONDS/SEC, which is a stat every evil HQ needs.
