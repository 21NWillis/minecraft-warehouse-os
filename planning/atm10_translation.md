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
