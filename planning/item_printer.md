# The Item Printer — multi-resource printing plant (design + model)

Objective: **consistent output across ~9 core resources**, not maximum
throughput of one. Bootstrap is a grant from Errot: ~700k inferium,
autocrafting through supremium, and a stack of any of: iron, diamond,
gold, netherite, uranium, osmium, inferium, redstone, obsidian seeds.

Design is Errot's proven rig, standardized into identical **bays** and
audited against this pack's actual configs (all values below verified
from jars/config on 2026-08-03).

## Verified physics

| Mechanic | Value (this pack) | Source |
|---|---|---|
| Harvester Pylon (Pylons) | 3x3–9x9 range, one pass / **60 ticks (3s)**, outputs to inventory **above**, sits **inside a water block** or level with crops | pylons jar + pylons-server.toml |
| Pylon tool rule | **Requires a hoe**, 1 durability/harvest, cannot be piped in (`canBeAutomated=false`), unbreakable hoes = full automation | pylons-server.toml |
| Lilypad of Fertility (Reliquary) | growth ticks every **10s**, radius **4**, full potency within 1, **multiple pads stack** | reliquary-common.toml + JEI text |
| MA Growth Accelerator | each block ticks the crop above it every **10s**; stack any depth, any tier mix (range measured from below the farmland) | MA jar book + mysticalagriculture-common.toml |
| Watering via machine | **`fakePlayerWatering = true`** — Cyclic Item User + MA watering can is explicitly enabled | mysticalagriculture-common.toml |
| Cyclic Item User | right-clicks the block in front with the held item on a configurable tick delay | cyclic jar |
| Seed economics | `secondarySeedDrops=true` (~10% any essence farmland +10% matching tier), 10% fertilized essence, `requiresEffectiveFarmland=false` | MA config/book |

## The bay (one per resource, identical)

9x9 essence-farmland bed. Five water cells: center (hosts the
**waterlogged Harvester Pylon**) and the four quadrant centers, each
carrying a **Fertile Lilypad** — every crop is within lilypad range and
within 4 of water. 76 crops per bay.

```
. . . . . . . . .        # = crop (76)
. . # # # # # . .        L = water + fertile lilypad (4)
. # L # # # L # .        P = water + pylon; stack-upgraded SS chest
. # # # # # # # .            floats directly above P
. # # # P # # # .        U = Cyclic Item User at bed level on the
. # # # # # # # .            south rim, facing a row-1 crop, holding
. # L # # # L # .            a supremium watering can (13x13 AoE
U # # # # # # # .            covers the whole bed from there)
. . . . . . . . .
```

Growth stack, per crop: watering-can AoE (dominant, ~continuous),
lilypad ticks (1-2 pads in range each), plus **accelerator pillars
growing downward** under each column as budget allows — the sky-platform
underside is open, so acceleration scales by digging into the void.

No sower needed: MA crops right-click harvest; the pylon resets them in
place. Seeds only leave via the bonus-seed drop chance.

## Throughput model (calibrate in field, don't trust the priors)

Crop maturity ≈ stages(7) / growth-ticks-per-second. With an active
watering can + 4 lilypads and no accelerators, expect maturity in
roughly 10–30s → **~9k–27k essence/hr/bay** (76 crops, pylon takes all
mature crops each 3s pass — the pylon is not the bottleneck until
maturity ≈ 3s). Nine bays ≈ order **100k essence/hr** portfolio-wide.

These priors are soft. The calibration protocol is the real model:
1. run each bay 10 minutes, read its drawer count delta
2. items/hr = delta x 6; record per resource on the runbook
3. **equalize the portfolio by accelerator depth**, adding pillar
   layers under the SLOW bays only — consistency is tuned downward
   into the void, not by nerfing fast bays

## The hoe problem (industrial miracles)

At thousands of harvests/hr, durability hoes die in minutes.
`canBeAutomated=false` means no hoe restocking by pipe. Therefore each
pylon wants an **Unbreakable hoe** — the Apotheosis mythic reforge 1%
unbreakable roll, on netherite hoes, x9. The reforge-spam economy now
produces capital equipment. (Fallback: Unbreaking-X printed hoes and a
weekly hand-swap, but the 1% roll is cheaper than the labor.)

## Storage spine (user's architecture, ratified)

1. Per-bay buffer: SS chest with stack upgrades above the pylon.
2. pipez ultimate trunk: all bay chests -> the farm drawer bank.
3. **Functional Storage drawer bank + its own Storage Controller**,
   fronted into ME by a **single Storage Bus on the controller** at
   high priority: one drawer per essence, one per seed type.
4. Seed drawers get **void upgrades** after a 2-stack buffer (spares
   for expansion; the rest is entropy).
5. Conversion lane: essence -> resource crafts (JEI is authority on
   ratios per resource), then **compacting drawers** for final items
   (ingot/block/nugget). Inferium tier-ups ride Errot's supremium
   autocrafting until our own ME crafting CPUs exist.

## Field checks before committing the build

- [ ] Cyclic Item User: confirm whether it wants RF in this pack
- [ ] Pylon harvest of MA crops: confirm in-place reset (no seed cost)
- [ ] Watering can AoE from a row-1 target covers row 9 (13x13 check)
- [ ] One lilypad + one crop test: visible growth-rate change
- [ ] Essence->item ratios per resource from JEI (fills the model)

## Rollout

Bay 1 = inferium (calibration reference), then iron, osmium, uranium,
redstone, gold, diamond, obsidian, netherite. Site: east of the
warehouse past x28, 12-block pitch, pipez trunk west into the ME.
`printfit` (turtle builder) follows once bay 1 is field-validated —
farmfit v1 (sower/gatherer variant) is superseded by this design.
