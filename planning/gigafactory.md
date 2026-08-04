# Gigafactory + Autocrafting — the post-printer industrial plan

The Item Printer changes the shape of industry: raw resources arrive as
ESSENCES (plus bonus seeds and fertilized essence), not ores. That
deletes half of classic Mekanism (no ore multiplication needed - there
are no ores) and reshapes autocrafting around one conversion layer.

## 1. The material flow (what actually lands in the system)

    bay chests -> pipez -> collector chest (SS network, warehouse)
      iron/gold/redstone/osmium/diamond/obsidian/uranium/netherite
      essence + inferium essence + ~10-20% bonus seeds + fertilized
      essence droppings

BISECT RULE: any ME storage bus must target the COLLECTOR CHEST BLOCK
directly, never the SS controller (the controller silently refuses
automation inserts; a bus through it inherits the bug).

## 2. The conversion layer (autocrafting phase 1)

One AE2 pattern per resource: essence -> item (ratios from JEI - MA 8
conversions are plain crafting, no catalyst for item conversions;
infusion crystals are only for SEED crafting). Keep essences stored,
convert on demand - essences are denser and the ME math prefers lazy
conversion.

Patterns v1 (crafting patterns, molecular assemblers):
  iron/gold/redstone/diamond/obsidian/netherite/osmium/uranium essence
    -> resource
  inferium ladder: inferium -> prudentium -> tertium -> imperium ->
    supremium (crystal-catalyzed - verify AE2 handles the returned
    crystal, else keep tier-ups manual/SFM)
  seed surplus: store 2 stacks per type, condense the rest

## 3. AE2 autocrafting infrastructure (shopping list)

Banked already: 64x of each processor, 9x 16k cells, controller LIVE
on wind power.

To build:
  * Crafting CPU cluster: 4-6x Crafting Storage (16k+), 2-4x Crafting
    Co-Processing Units, monitor
  * 6-10x Molecular Assembler + 2-3x Pattern Provider (conversion ring)
  * Storage bus (-> collector chest DIRECTLY), import/export buses
  * Dense/smart cable run down the ME wall

## 4. Mekanism lines (the gigafactory proper)

No ore processing. The factory exists for TRANSFORMATION chains:

  A. ALLOY LINE (feeds everything): Metallurgic Infuser(s) ->
     infused alloy -> reinforced -> atomic. Inputs: redstone essence
     conversions, osmium, diamonds, refined obsidian.
  B. STEEL LINE: Enrichment Chamber (coal -> compressed carbon) +
     Infuser (iron -> enriched iron -> steel). Steel casings gate every
     machine tier.
  C. CIRCUIT LINE: infuser chains for basic->advanced->elite->ultimate
     circuits. Eats osmium + alloys.
  D. URANIUM -> FISSION (the long pole, reactor.lua has waited 2 days):
     essence -> uranium -> yellow cake -> oxidizer/hex/centrifuge ->
     fissile fuel -> Fission Reactor + Industrial Turbine + waste line
     (-> plutonium/polonium -> SPS someday).
     ⚠ VERIFY FIRST: the essence conversion must yield a form that
     enters the yellow-cake chain (raw uranium or ingot-crushable).
     If only ingots come out, check ingot->dust->enrich paths in JEI
     before building the hall.
  E. ETHYLENE POWER (mid-game workhorse): sandbox-bay crops + printer
     surplus -> Crusher -> bio fuel -> PRC -> ethylene -> Gas-Burning
     Generators. Scales horizontally next to the wind row.

Machine tiering doctrine: skip basic/advanced singles - build FACTORY
variants (elite/ultimate) directly once the alloy line runs; the
printer makes materials cheap, so tier-rushing is correct.

  F. STORAGE/POWER SPINE: Induction Matrix (the grid battery) between
     the wind row, ethylene wall, and fission hall. Ultimate universal
     cables only - the printer pays for them.

## 4.5 The CC advantage (nobody else on the server has this)

The corp is hooked into ComputerCraft end-to-end, which makes the
finicky third of autocrafting trivial for us and miserable for
everyone else. Doctrine: AE2 patterns for clean item->item recipes;
CC CELLS for everything AE2 hates:

  * CONTAINER-ITEM CRAFTS: a crafty turtle holding the Master Infusion
    Crystal IS the MA tier-up machine - turtle.craft() the
    inferium->supremium ladder in a loop, crystal never leaves its
    inventory. No AE2 container-item pattern pain. (We already have
    recipedb + planner in the repo - the crafting brain exists.)
  * GAS/CHEMICAL CHAINS: Mekanism machines are CC peripherals - a
    computer can read tanks, gate inputs, and sequence the yellow-cake
    -> hex -> fissile line directly instead of fighting AE2's
    fluid/chemical pattern support. reactor.lua already proves the
    pattern.
  * FINICKY ANYTHING: peripheral pushItems between inventories is our
    printfit-proven staging technique - any machine that misbehaves
    under hoppers/buses gets a computer secretary instead.

Rule of thumb: if a pattern takes >5 minutes to make AE2 accept,
write 20 lines of Lua instead.

## 5. Siting

Power hall: the RESERVED 17x17 NE quadrant plot (datacenter build
power) - fission + turbine + matrix inside, wind row + gas wall
adjacent. Conversion/crafting cluster: warehouse interior beside the
ME controller (short cable runs, the collector chest is already
overhead through the roof).

## 6. Open verifications (JEI/field, before machine halls go up)

  [ ] essence -> resource ratios per type (fills the economy model)
  [ ] essence -> uranium FORM (raw vs ingot) - gates the fission line
  [ ] AE2 pattern with Master Infusion Crystal (container item return)
  [ ] Mek machine + pattern provider interaction (provider face push)
  [ ] measured printer throughput per bay (drawer-delta calibration
      from item_printer.md - sizes the ethylene + conversion scaling)
