# ATM10 Translation — PaperclipOS v2 ("the acquisition")

2026-08-12. The corp is acquiring a distressed 500-subsidiary industrial
conglomerate ("All the Mods 10 + A few more", MC 1.21.1, neoforge-21.1.247,
501 jars). Org change: the rivals are now a commune — shared infrastructure,
departments instead of competitors. This doc is the translation blueprint
from Neutral Pack PaperclipOS to the ATM10 stack. All mod facts below are
jar-verified against the local instance (never launched yet), not wiki lore.

## Instance pre-flight (done / pending)

- DONE 2026-08-12: disabled `cc-tweaked-1.21.1-forge-1.113.1.jar`
  (renamed `.disabled`). Advanced Peripherals 0.7.62b hard-requires
  computercraft >= 1.119.0; the custom-added 1.120.0 jar is the intended
  one. Two jars with one modid = NeoForge launch crash.
- PENDING: confirm the server runs the same "+ A few more" set (CC:T
  1.120.0 + AP 0.7.62b). Client/server CC:T version skew breaks connect.
- PENDING: first launch (501 mods, expect a long first boot), then verify
  server-side CC limits once live. Local defaults match Neutral Pack
  (1MB disk, computer_threads=1, 10ms shared budget, $private denied)
  EXCEPT HTTP is `*`-allowed at 16MB/request download, 4MB upload —
  strictly better than what we had. All existing discipline (event-driven,
  stream-to-RAM, GitHub-raw deploy) carries forward unchanged.

## The headline: Advanced Peripherals exists here

The Neutral Pack had no AP — craftd v1 had to *implement* autocrafting:
recipedb as inline cache, planner, crafthub arrangement, craftcell
firmware, staging via pushItems. ATM10 ships AP 0.7.62b with everything
enabled in config, including the **RS Bridge** against **Refined Storage
2.0.9** (the RS2 rewrite) — jar-verified classes: RSBridgePeripheral,
RSCraftJob, RSItemHandler, RSFluidHandler, RSChemicalHandler, RSMekanismApi
(that last pair via the bundled refinedstorage-mekanism-integration:
Mekanism chemicals live IN the RS network and the bridge can see them).

RS Bridge Lua surface (extracted from class constant pool, needs in-game
semantics verification, esp. RS2-era filter table shapes):

- inventory: `getItems`, `getItem`, `getFluids/getFluid`,
  `getChemicals/getChemical`, `isCraftable`, `getCraftableItems/-Fluids/-Chemicals`
- crafting: `craftItem`, `craftFluid`, `craftChemical`, `isCrafting`,
  `getCraftingTasks`, `getCraftingTask`, `getPatterns`
- movement: `exportItem/-Fluid/-Chemical`, `importItem/-Fluid/-Chemical`,
  `exportToChest`, `exportToTank`, `importToRS`
- telemetry: `getTotalItemStorage/getUsedItemStorage/getAvailable...`
  (same trio for fluid/chemical/external), `listDrives`, `listCells`,
  `getStoredEnergy`, `getEnergyCapacity`, `getEnergyUsage`,
  `getAverageEnergyInput`, `isConnected`, `isOnline`

Also enabled: ME Bridge (AE2 19.2.17 + ExtendedAE + MegaCells are in the
pack — hybrid or late-game migration option), Inventory Manager
(push/pull a PLAYER's inventory via memory card), Chat Box (global range,
run_command wrapped at zero permission, dangerous commands banned),
Player Detector (exact positions, no random error, cross-dimension),
Geo Scanner, Block Reader, NBT Storage (1MB).

## Architecture: craftd v2 is an orchestration layer

User's pitch, ratified: RS runs the autocrafting network; CC "mini PCs"
sit at the edges and handle machine dispatch optimally.

Division of labor:
- **RS = the warehouse + BOM solver.** Storage, recipe graph, request
  resolution, grid recipes via native Crafters. Everything recipedb/
  planner/crafthub/craftcell did, at native speed, with a GUI the whole
  commune can use without learning our tooling. Do NOT reimplement any
  of it.
- **CC mini PCs = edge dispatchers.** RS's known weakness is processing
  patterns against machine banks: it shoves a whole batch at whatever
  inventory the pattern points at, serializes on one machine, no
  load-balancing, no per-machine buffer awareness. So: each *recipe
  class* (smelting, infusing, enriching, PRC, etc.) gets ONE RS external
  pattern pointing at a station buffer chest. A stationary CC computer
  owns that chest + a wired-modem bank of N machines: drains queued
  ingredient sets, round-robins across machines respecting buffer
  depth, tracks in-flight jobs, pushes outputs to the RS importer.
  RS thinks it's talking to one infinitely-parallel machine.
- GPU framing: RS is the global scheduler/frontend, mini PCs are warp
  schedulers, machine banks are SMs. RS issues; CC does register
  allocation and hides latency. The prefetch-pipeline doctrine from v1
  (stage ingredients ahead of demand, machine latency hides under tick
  overlap) survives intact — it just moved from crafthub to the station
  dispatchers.
- One generic `station.lua` firmware parameterized by (buffer, machine
  list, io map) beats N bespoke programs. Headless tests against
  mock_cc + a new mock_rsbridge.

Protocol: keep `paperclip.craft` / rednet conventions. craftd v2 talks
RS Bridge for global state and rednet to stations for dispatch health.

## What ports as-is

- `update.lua` GitHub-raw deploy (HTTP is *better* here), direct-to-main
  = deploy, manifest.txt, tests/mock_cc.lua harness, lua54 headless
  runner, QUIRKS.md ritual, STATE.md ritual, netprobe/netaudit doctrine,
  profiler/metrics, survey system + pastebin channel, corp launch
  convention (datum ritual), basewalk/tours.
- nocboard v2: now fed by RS Bridge telemetry (storage %, drive/cell
  health via listDrives/listCells, energy in/out, crafting task queue)
  instead of scraping Sophisticated Storage barrels. The Exchange
  scoreboard bit needs a new valuation basis (emc.txt fiction can port
  verbatim — EMC remains a scoreboard, never a mechanic; ProjectE is
  still absent from this pack).
- Paperclip Lens (client NeoForge 1.21.1 — same MC/loader!): rebuild vs
  new mappings-of-pack jars; the F8 order executor + world journal port
  directly. Client-side = no server adoption needed, same as before.
- Create 6 + aeronautics-bundled + hypertube are ALL here — the flight
  stack and hypertube transit plans survive the migration wholesale.

## What died in the move

- FTB Stuff water strainers (the casino / loot faucet): GONE. No idle
  loot income.
- easy_villagers emerald printer: GONE.
- Cyclic Item User (the watering-can trick in the item printer): GONE —
  fake-player clicker needs a new host (candidates to verify in-game:
  JustDireThings clickers, Create deployers, Modular Routers isn't in).
- Income/bootstrap thinking must be rebuilt around ATM10's own faucets —
  candidates to investigate: Productive Bees, Mystical Agriculture
  (present + Agradditions), HNN (present), Occultism ritual economy,
  Apotheosis salvaging (present). ATM10 is progression-gated: allthemodium
  3.0.1 + occultism_kubejs custom gates — map the actual gate graph
  before designing the resource wing.

## New toys (beyond RS Bridge)

- **toms-peripherals 1.3.1**: real GPU/VRAM/framebuffer peripherals for
  CC. NOC wall v2 in raster graphics. The GPU bit stops being a bit.
- **Chat Box**: corp announcements + a chat-command concierge
  ("@AP craft 256 infused_alloy" from anywhere, any commune member, no
  terminal needed). Command wrapping is zero-permission and ban-listed,
  so it's safe to expose.
- **Inventory Manager + memory cards**: quartermaster stations — auto
  restock any player's kit from RS when they stand at the depot.
  Commune-shaped feature #1.
- **Player Detector**: presence-aware campus (arrival toasts on the NOC
  board, auto-lighting, who's-online without F3).
- **Geo Scanner on turtles**: prospecting for allthemodium in the mining
  dim — scan, upload, heatmap. Replaces blind strip-quarry entirely.
- Compact Machines 7.0.81 + Shrink 2.0.1 (see snow-globe idea below).
- SFM, xnet, laserio, pipez, Integrated suite, RFTools crafter/storage
  all present as dumb-plumbing options where CC shouldn't burn budget.

## Snow-globe factory (user mod wish, 2026-08-12 morning)

Wish: sub-voxel factory physically inside one block, visible ("glass
block anyone?"). Reality: Chisels & Bits (the 1/16-mining mod remembered)
is decorative-only and not in this pack; nothing ships functioning
1/16-scale machines. But the pack HAS: **Shrink** (player goes tiny) and
**Compact Machines** (factory in a pocket dimension behind one block).
Mod idea worth prototyping: a client-side(-ish) viewport renderer — a
BlockEntityRenderer on (or beside) a Compact Machine wall block that
renders the room's captured structure as a miniature (structure template
snapshot, scaled ~1/16) inside a glass shell. Pocket dimension does the
function, the glass block does the fiction: a snow-globe factory on the
shelf that IS the real factory. Live-ish updates via periodic structure
re-capture server-side (needs a small server component — commune server
= friendly adoption odds, precedent: paperclipos terminal 48h window).
Feasibility notes: render via schematic-ghost pathway like Lens's
blueprint renderer; capture via StructureTemplate on the CM room bounds;
budget = one template sync per N sec, render cost ~= one contained
chunk section. Genuinely novel — nothing in the 501 jars does this.

## Bring-up order (draft, pre-gate-map)

1. First boot + server connect; verify server CC config + AP versions.
2. CC bootstrap: one computer, update.lua, wired backbone. (CC is
   nearly free: stone/redstone/glass.)
3. RS core online (RS2 bring-up path needs research — controller/disk
   economics differ from RS1), bridge on it, `rsprobe.lua` to dump the
   real Lua semantics → QUIRKS.md.
4. nocboard v2 minimal: storage + energy + task queue on one monitor.
5. First station (smelting bank) end-to-end: RS pattern → buffer →
   station.lua → furnace bank → importer. Prove the dispatcher shape.
6. Scale stations per recipe class; craftd v2 thin orchestration on top.
7. Geo-scanner prospecting fleet once allthemodium gates demand it.

Open questions for the day-grind: exact RS Bridge RS2 semantics + known
AP/RS2 bugs; ATM10 gate graph (allthemodium/occultism kubejs); RS2
autocrafting internals (does it already parallelize externals better
than RS1?); toms-peripherals API; income faucet shortlist; snow-globe
prototype scoping.

---

# Day-grind findings (2026-08-12)

## RS Bridge × RS2 — research report (web/source-verified)

**The big one: RS2 does NOT parallelize external crafting.** A task's
external steps lock to the single Autocrafter holding the chosen
pattern; duplicate patterns for the same output resolve by priority to
one machine (RS2 #952). The mini-PC dispatcher design is therefore
VALIDATED as the only route to parallel machine banks — not an
optimization, the mechanism. (Possible alt: many small craftItem jobs
against duplicate patterns — UNKNOWN if concurrent tasks pick different
machines; test in-game.) RS 2.0.7 already fixed the
concurrent-tasks-through-one-external-machine stuck bug, so our
many-small-jobs pattern lands on patched ground.

**craftItem semantics (AP 0.7.62b, source-verified):**
- Returns a **CraftingJob object immediately**; RS2 preview calc runs
  async. Non-nil ≠ success — failures surface via `job.getMissingItems()`
  or the **`rs_crafting` event**: `os.pullEvent("rs_crafting")` →
  `(ev, error, id, debug_message)`, fires on CALCULATION_STARTED /
  MISSING_ITEMS / JOB_DONE / JOB_CANCELED. Event delivery has an open
  issue history (#688) — poll `job.isDone()` as fallback.
- Job API: getId, isDone, isCanceled, getMissingItems, cancel.
  AP detects "canceled" as absence-from-statuses — a done task also
  leaves; check isDone before concluding canceled (race, needs test).
- Peripheral type name: **`rs_bridge`**. Trust the JAR for method names
  (listDrives/listCells) — 0.7 docs partially describe newer builds.
  `getCrafters()` (autocrafter enumeration) lands in 0.7.63b+ (PR #826).

**Filter table (1.21, from ItemFilter.java):** keys = `name` (id or
`#tag`), `count` (default 64), `components` (REPLACES `nbt`; exact-match
against the FULL component patch — partial matches fail), `fingerprint`
(MD5; overrides everything; get via getItems() field or
/advancedperipherals getHashItem), `fromSlot`/`toSlot`. Use fingerprint
for any item with components; components-tables only for exact known
patches.

**Landmines:**
- **count=1 clamp**: craftable items with 0 stored report count 1
  (client-crash workaround in RSApi). NEVER presence-check by count;
  cross-check getCraftableItems.
- getCraftableItems = outputs of patterns INSERTED IN AUTOCRAFTERS
  network-wide; patterns sitting in a Pattern Grid don't count.
- Keep craft request counts modest — RS2 had runaway-CPU calc on huge
  trees (#1018, ATM10-reported); improved but unproven at 2.0.9.
- Autocrafter chaining (face-to-face for >9 patterns) had a
  first-in-chain-only bug (#808) — verify in 2.0.9 before relying.
- Task progress numbers approximate (AP works around an RS2 "stored"
  attr bug by subtraction).

**RS2 block vocabulary:** Crafter → **Autocrafter** (faces its machine,
front-face chains), encode in **Pattern Grid**, watch tasks in
**Autocrafting Monitor**, fleet view in **Autocrafter Manager**.
Per-Autocrafter lock modes: never / redstone-pulse / machine-empty /
all-outputs-received / high-low signal — machine-empty is the one for
mixed-input machines.

**First in-game test checklist:** (1) craftItem with missing
ingredients → event vs silence; (2) duplicate pattern in 2 Autocrafters
on 2 machines, 2 concurrent jobs → both machines used?; (3) confirm
count=1 clamp; (4) components exact-match failure on enchanted book;
(5) done-vs-canceled ordering race.

Full sources: AP PRs/issues #684 #688 #754 #775 #795 #816 #826, RSApi/
RSCraftJob/ItemFilter source on dev/1.21.1, RS2 changelog + issues #808
#952 #1018, docs.advanced-peripherals.de 0.7 guides, refinedmods.com
autocrafter docs.

## ATM10 gate graph + break-things map (web-researched, sources in
agent report; [C]=confirmed multi-source, [L]=community lore)

**The spine [C]:** netherite pick → **Allthemodium** (Deep Dark
below ~Y-40, glowing; or brush Suspicious Clay in Ancient Cities →
ore + smithing template) → ATM nuggets → Teleport Pad: Overworld
placement = **Mining Dim** (ATM in deepslate layer ~Y112-129), Nether
placement = **The Other** → ATM pick → **Vibranium** (Nether
crimson/warped ceilings) → Vib pick → **Unobtainium** (End Highlands
post-dragon; templates ONLY from Library of Dungeons in The Other).
**LAW [C]: spine ores drop for real players only — no quarry, no
Occultism miner, no fake player (ATM-10 #858, intentional).** Hand-mine
the spine once; automate everything else.

**The recurring tax [C]: Piglich Hearts** (elite mobs in The Other) —
in all 3 ATM alloys + Dragon Soul. ATM alloys also gate: Powah
Energizing Orb @ 1B FE/ingot, Ars Nouveau apparatus @ 10k Source,
IF Dissolution Chamber + Soul Lava. ATM Star = Runic Star Altar, 8
components + 3 alloys; master gates = Mekanism antimatter, AE2
singularity, Powah, Ars source economy, IF soul lava, Cataclysm
bosses, MystAg insanium, wither farm. MystAg tiers gate resources,
not the spine (ATM-metal SEEDS exist [C] — the legal bypass for
repeat acquisition).

**Break-things ratings (how broken / notes):**
- **HNN loot fabrication 5/5 [C mechanism]**: level a Deep Learner on
  a mob ~dozens of kills → Simulation Chambers print its loot from
  RF + polymer clay forever. **Piglich model = hearts from
  electricity.** The strainer-casino spiritual successor.
- **Drygmy milking + Apothic Spawners 5/5 [C]**: drygmys extract drops
  from LIVING caged mobs, no kills; jar one piglich (Tablet of
  Containment) → ~20 drygmys ≈ 32 hearts/cycle passive. Apothic
  Spawner modifiers (min delay, no-AI, ignore-player) = elite conveyor.
- **Productive Bees ATM bees 5/5 late-mid [C exists]**: the ONLY
  automation for spine metals — Ancient Bee spawn eggs + cast molten
  ATM metal on egg in Productive Metalworks foundry → metal bee →
  comb → centrifuge → ingots forever. (CC BEES ANGLE: this is the
  wing the user wants; dispatcher-friendly plain inventories, see
  agent 3 report.)
- **Occultism miner spirits 4/5 [C]**: passive virtual-dim ore stream,
  early-reachable, capped (no spine metals). Crusher spirits = best
  early ore multiplication.
- **Apotheosis World Tiers + gem/salvage flywheel 4/5 [C features]**;
  Apoth flight potions = early creative-ish flight, trivializes
  exploration gates.
- **MystAg inferium→insanium 4/5 [C]** "biggest unlock" per guides;
  Time in a Bottle on growth accelerators.
- **EvilCraft Vengeance Pick (Fortune V, buyable early) 3/5 [C]** —
  triples the first hand-mined spine veins. Blood Chest = free repair.
- **Mek Digital Miner AFK 3/5**, **wind >Y100 + Player Transmitter
  power cheese 2/5**, **Soul Lava thermo 9x [C]**.
- **Actual dupes (0/5 legitimacy)**: rolling patched history (Pocket
  Storage #199, Router+briefcase #992, suspicious-block #2299,
  Toolbox+Bundle #3565/#4147) — social decision on a friend server,
  assume patched, don't build on them.
- Gravel/sieve economies are ATM10-To-The-Sky ONLY — not in base pack.

**Week-one faucet order [C]:** copper Ore Hammer (hour one, free ore
doubling) → inferium field 30+ crops → Mek wind row >Y100 + Player
Transmitter → Create cobbleworks → Occultism crusher→miner spirits →
HNN corner as soon as RF + mob farm exist → wild bee nests early
(feeds the eventual ATM-bee wing). MineColonies supply camp = free
day-one loot. Strainer-era mapping: inferium field = strainers, HNN +
drygmys = emerald printer, ATM bees = endgame version.

**Version caveat:** ATM10 patches monthly; dupe list + piglich drop
behavior are version-sensitive — re-verify vs the server's pinned
pack version.

## Compact Machines 7 / Productive Bees / Tom's GPU (agent 3 report)

**CM7 (7.0.81) — the walls are INERT [C]:** the tunnel system
(item/fluid/energy/redstone) was STRIPPED entirely in the 1.21 rewrite
(mod FAQ; replacement "Room Upgrades" targeted at CM 9.x, not 7.0.x).
Nothing passes CM walls natively. Cross-dimension mods are the bridge:
ender chests/tanks, AE2 quantum bridge, Flux Networks. CC specifics:
- No wired-modem passthrough, ever (wired nets can't span dimensions).
- Plain wireless modems DON'T cross dimensions; **ender modems DO** —
  computer + ender modem inside a room talks to the campus net fine.
- **Rooms UNLOAD when players leave** (intentional CM7 change, #595).
  A chunk-loading Room Upgrade reportedly exists in recent 7.0.x —
  VERIFY IN JEI in-game; also test whether FTB Chunks can claim the CM
  dim. A computer in an unloaded room is a dead computer.
- Net: pocket factory halls = possible but logistics go through
  ender-tech, not walls; snow-globe viewport mod idea unaffected
  (rendering is our own mod's job) but the "live" capture needs the
  room chunkloaded.

**Productive Bees (13.13.5) — the apiary wing is CC-shaped [C]:**
no native CC integration, but the whole line is generic `inventory`
peripherals via wired modem (pushItems/pullItems): Advanced Beehive
(output slots; Expansion Boxes raise capacity — own-peripheral status
needs test), Centrifuge/Powered (comb → items + 10-bucket tank),
Incubator (baby bee + honey treats → adult; gene imprinting),
Breeding Chamber (2 caged bees + flower + FE — cage-slot automation
insertability needs test), Gene Indexer (**redstone-triggered** — CC
hook), Bottler (dispenser+piston squash line, CC-clockable).
Player-required: catching bees in cages, initial setup. Everything
else machine-driven. **Simulation upgrade CONFIRMED in 13.13.x**:
bees never leave the hive (server-perf win) — one in every hive.
Pipeline: dispense caged bee → squash → centrifuge → 6 gene types →
Gene Indexer 100% → treat → Incubator → Breeding Chamber.

**Tom's Peripherals 1.3.1 — real GPU [C from source]:** peripheral
`tm_gpu` + dumb Bitmap Monitor multiblock (GPU claims horizontally
adjacent array), `tm_keyboard` (kbd+mouse, works on CC advanced
monitors too), `tm_rsPort`, `tm_wdt` (watchdog reboot — nice for
station firmware). GPU: VRAM pool (default 16MiB/GPU, server config),
32-bit ARGB framebuffer, per-block resolution setSize(16..64)px,
default screen cap 16x16 blocks → 1024x1024px. API: fill/rect/line/
drawText/drawImage/decodeImage(PNG!)/newBuffer + full GL1.x-style 3D
immediate mode; touch events tm_monitor_touch. **Perf law: sync() is
the cost** — each monitor block ships width² ints in a BE packet per
flush; bandwidth is the hazard, and drawing runs on the shared Lua
budget. Batch draws, sync once per frame, low res until proven.
nocboard v2 = tm_gpu raster dashboard; PNG decode means pre-rendered
assets can ship from GitHub.

## Armament Division: broken renewable ranged weapons (agent report,
2026-08-12; user directive: prefer REAL BOWS this pack, not crossbows)

**Fastest broken overall [C mechanics]:** Apotheosis-reforged vanilla
crossbow, hours 2-6 — Salvaging→Reforging tables, Spectral/crit/
armor-pierce affixes, Apothic Enchanting lvl-100 table with
**Crescendo of Bolts** (extra shots, no ammo) + **Endless Quiver**
(infinite arrows). Scales via World Tiers (Haven→Pinnacle, CTRL+T;
higher tier = better Mythic odds, Tier Augments cost Max Eterna).
User is bow-gang this pack, so this is reference-only.

**The BOW plan:**
- Hour 1 stopgap: Iron's Spells Firebolt scroll in a Flimsy Journal
  (Wizard Towers near villages; mana = infinite ammo). 3/5.
- Mid-game centerpiece (~6-10h): **Twilight Forest Tri-bow** — Snow
  Queen drop (Aurora Palace, after Lich→Minoshroom/Hydra chain), a
  REAL bow firing 3 arrows for 1 ammo; takes full Apotheosis affix/
  gem/augment stack + over-cap Power + Endless Quiver. 4/5. Same boss
  alternatively drops the **Seeker Bow** (homing) — user theorycraft:
  seeker + multishot + drawspeed = boss-deleter but a farm-safety
  hazard (homing + fast fire = cow genocide in one right click);
  UNKNOWN whether seeker arrows filter hostiles — verify in-game.
  Doctrine if not: two-loadout (seeker = regulated boss ordnance,
  directional bow = daily driver).
- Endgame: **Silent Gear bow, max-grade ATM-alloy limbs** (ATM/Vib/
  Unob are registered SG materials) + Apotheosis stack — community
  "one-shot Withers" build [L, strong]. SG limb materials are
  narrow (Crimson/Tyrian Steel best natives, GH #513); grading via
  Material Grader (MC grade), ATM10 bug: re-smelting graded ingots
  wipes grade (#2828). Repair kits forever + Endless Quiver.
- Sidearm: **Cataclysm Laser Gatling** (Harbinger boss → Witherite;
  full magazine recharges on 1 redstone) 4.5/5 once nether-star-boss
  capable; Harbinger is re-summonable = farmable.
- Dead ends: MystAg bows don't exist in 1.21; Mek Electric Bow still
  eats arrows; PneumaticCraft minigun has a real ammo economy; potato
  cannon = 2/5 meme (air-tank durability trick is cute).

## QoL staging (done)

7 jars staged in `<ATM10 instance>\mods-qol-staged\` + MANIFEST.md:
Sound Physics Remastered 1.5.1, Chat Heads 0.15.6, BetterF3 11.0.3,
Equipment Compare 1.3.13, Legendary Tooltips 1.5.5, Inventory HUD+
3.4.28 (real 8M-download project, impostor dodged), Durability Tooltip
1.1.6. All four required libs (Cloth Config, Iceberg, Prism, SM642
ConfigLib) already ship in the pack — zero extra jars. Move into mods/
after first successful boot.
