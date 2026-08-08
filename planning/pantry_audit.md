# The Pantry Audit — what 408 installed mods say we're sleeping on

Distilled from the Kimi K3 grounded-creative pass (2026-08-08), verified
against our own docs where possible. The pack author deletes recipes
(the wind precedent), so every recipe-dependent item carries
[VERIFY IN JEI]. Board synthesis; the raw reasoning is in the session
scratchpad.

## The headline finding

**AE2 is fully installed — with five addon mods — and our plans treat
it as future tech.** ExtendedAE (Ex Molecular Assemblers: parallel
server-side crafting, no CC budget), AdvancedAE, AppliedFlux (ME as
power backbone), ae2wtlib + AEInfinityBooster (wireless terminal from
anywhere), and **ae2jeiintegration — one-click JEI-to-pattern
transfer, which partially deflates craftd.md's "everyone else
hand-encodes patterns" moat claim.** The real moat is machine-aware
planning + the fleet; update that paragraph.

And the theological kicker: the Matter Condenser — the machine in our
founding myth, the thing that makes `ae2:singularity`, the relic the
B800's cornerstone needs nine of — **is an AE2 machine.**

> **OPERATOR CORRECTION (2026-08-08): the ME system is FULLY LIVE and
> always-on — daily-driven storage across the main base (31 mending
> books in residence). The planning docs' "phase 7 staged" framing is
> STALE; the base outran its own paperwork.** What remains unverified
> in-game (check, don't assume): pattern-based autocrafting + Ex
> Molecular Assemblers, ae2jeiintegration pattern transfer in use,
> ae2wtlib wireless terminal + infinity booster, AppliedFlux power
> backbone. Whatever's missing from that list is the actual sleeping
> fraction of giant #1.

## Sleeping giants, ranked

1. **AE2 stack** (above). First build: pattern terminal + JEI-transfer
   the sail/beam/circuit hot paths; Ex Assembler wall when the
   controller lands. Keep turtle cells for container-item crafts
   (infusion crystal tier-ups) - that niche is genuinely ours.
2. **Super Factory Manager** — server-native scheduling that costs no
   CC budget: machine.lua's polling, curator bulk pre-sort (id rules;
   turtle keeps the enchant-book judgment), condenser feeding. Bonus
   trick: **SFM programs gate on redstone, so a CC computer + redstone
   line + SFM script = a working CC<->ME bridge with no Advanced
   Peripherals.** The update-day fallback if AP slips.
3. **Mekanism Digital Miner** [VERIFY IN JEI] — one machine in JAMD
   with an osmium filter + anchor kills the planned quarry-fleet
   expedition. Fleet pivots to bulk/area work. (Oritech's quarry rig
   is the backup if the DM recipe died.)
4. **Modular Routers** (+mekanisticrouters) — one router with N
   sender modules feeds every Dyson gun (no under-slab trench for row
   2+); breaker module IS the missing harvest.lua driver (GeOre
   garden with zero turtles); activator module replaces cyclic:user;
   player module = Daylight Subscription hardware. [VERIFY module
   lineup in JEI]
5. **Remote-hands family: Tesseract / Entangled / AA Phantomfaces** —
   tesseract channel = JAMD quarry chest streams home live
   (items+energy, cross-dim). Note: CC's wired network cannot ride
   any of these - the Carpet cable spine stays for CC.
6. **IF Laser Drill + Bioreactor** [VERIFY] — passive on-campus ore
   (lens-targeted) and the two-machine version of seed-surplus power
   before the ethylene line stands.
7. **Hostile Neural Networks** — the casino is a loot farm that needs
   attendance; HNN doesn't. Sim chamber + fabricator under the
   Carpet: pearls, blaze rods, wither skulls -> nether stars -> **a
   beacon in the Socket. The Gold Standard glows.**
8. **EnderIO conduits + Travel Anchors** — bundled conduits for
   Carpet wiring (conduit_opt installed); Travel Anchors = THE
   ELEVATOR (towerstairs.lua's "jump carefully" finally resolved).
   [VERIFY anchor range vs the 200-block climb; Mek Teleporter
   fallback]
9. **PneumaticCraft** — drones as zero-budget couriers; Aphorism Tile
   as diegetic Board signage; Amadron makes the subscription desk
   real commerce.
10. **Ars Nouveau** — warp portal commute, starbuncle Internal Mail
    (never sips coal), drygmy passive loot.

## Plan-specific corrections

- **datacenter_floor**: tesseract carries items/energy down the
  spine; CC cable still drops (CC can't ride it). Deck tiles: BG2
  building gadget surface mode is the fast alternative; F8 stays the
  art form. The "hoe+9x9 ritual" line is stale — genfarm+F8 already
  places farmland.
- **dyson_rush**: trench = art, router = the row-2 upgrade. Sail
  pattern on ME once stage 2 lands. Receiver FE/t stays manual until
  AP (nothing installed reads FE from CC).
- **craftd**: moat paragraph needs the ae2jeiintegration footnote;
  T1 alternatives = EnderIO Crafter / Mek Formulaic Assemblicator /
  ME patterns.
- **update_day additions**: re-run the EMC fixpoint after recipe
  re-index (or the Exchange lies); add to JEI checks: digital miner,
  createaddition alternator, laser drill lenses, router modules,
  cyclic disenchanter/uncrafter, Charging Gadgets turtle support
  [60% confidence it charges turtles - would kill the coal liturgy].

## Operator pain deletions

- **Enchanting Infuser + TaxFreeLevels are installed**: pick
  enchantments deterministically for XP, no anvil tax escalation.
  With 31 mending books banked and the XP refinery planned, the
  sword program's RNG tax is optional now.
- **Cyclic Disenchanter + Uncrafter** [VERIFY]: the Curator gets a
  third ruling - STRIP - and the casino's junk gear becomes books +
  materials instead of trash.
- **BG2 Exchanging Gadget**: the Trace relight (glowstone -> sea
  lantern, campus-wide) becomes one drag. **mcw-lights neon strips /
  Mek glow panels** may be the better Trace material outright.
- **Create bulk washing**: encased fan + water converts concrete
  powder at belt speed - concrete.lua's bath retires when convenient.
- **Tweakerge freecam** for inspections without a Surrendering;
  **trade-cycling** at the auto-trader; **Observable + spark** for
  the metrics religion (block-entity lag attribution beyond what
  profiler.lua sees).

## Flagged question (third independent catch)

warehouse.lua deposit()/unloadTurtle() insert into the SS controller;
QUIRKS law says controller inserts VOID. Either the famine was fixed
and the law is stale, or the PUT button is a live landmine. The
storage.lua shared-module refactor (outside review round 1) resolves
this properly.

## Unidentified jars (someone check in-game)

arseng, mctier_engine, matmores, tailormade, tantle, linktablet,
places, trenzalore, acedium, nyctography, almanac, nowheel,
mekanism_unleashed, mekanism_lasers, smallcolonies, linked-copycats,
createendertransmission. If arseng is Ars Energistique, ME can store
Source - relevant someday.
