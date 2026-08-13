# Consultant findings â ATM10 commune bring-up (2026-08-12)

Ranking by (impact Ã probability you haven't already got it). Everything [KNOWN] is version-sensitive training knowledge â verify against your pinned jars.

---

## 1. Sleeping-on: HNN Ã station.lua is your highest-leverage unbuilt composition [SPEC on composition / DOCS on parts]

Your docs rate HNN "5/5" as a faucet and then drop it. But HNN Simulation Chambers + Loot Fabricators are *plain inventories with side-configurable slots* â they are the single most station-shaped machine line in the pack, and they're the strainer-casino successor, i.e., your old core competency. A dedicated `class = "hnn_fab"` station (buffer of polymer clay + matter keys â bank of fabricators â importer) turns "Piglich hearts from electricity" into "Piglich hearts *as an RS craftable*" â which means the Piglich Heart tax on all three ATM alloys stops being a farm you visit and becomes a line item `craftd v2` can order. Nobody does this; everyone hand-feeds HNN. The spec needs one extension: HNN fabricators consume a *key item* (the model) that must persist in the machine â your current "station owns all movement" rule would rip it out. Add a `staticSlots` recipe field marking slots the dispatcher must never pull. [SPEC]

Related: the drygmy piglich farm and the HNN sim farm compete for the same mob. Deliberate choice: drygmys for *passive* hearts (no RF), HNN for *on-demand crafting integration*. I'd build drygmys first (hearts gate alloys), then HNN as the crafting-visible path once the model is leveled â the leveled Deep Learner transfers. [SPEC]

## 2. Sleeping-on: the Inventory Manager is under-scoped [DOCS/KNOWN]

You've framed it as "quartermaster depot." Two sharper uses:

- **Death-recovery concierge.** Player Detector + Inventory Manager + a "corpse kit" memory card: when a player respawns at campus (detector sees them with empty inv â heuristic), auto-issue a standardized recovery kit (food, tools, flight item). On a friend server this is the single most *felt* feature you can build. The kit spec lives in a data file per player â commune members will enjoy curating their own loadouts, which is free engagement. [SPEC]
- **Mining-dim loadout swap.** Because spine ores need real-player pickaxes [DOCS], everyone does repetitive hand-mining runs. A gate-adjacent depot that swaps your inventory: out goes loot, in comes fresh pickaxes (Vengeance Pick [DOCS], repaired via Blood Chest), food, torches. This directly serves the one progression step that can't be automated. [SPEC]

## 3. Holes: the station spec

- **Mekanism side-config is a bigger tax than the spec admits.** [KNOWN] 1.21 Mekanism machine side configs are per-machine, per-slot-type, and not exposed to CC. Your "configure ejection OFF, station owns movement" doctrine requires a *manual* click-through of every machine's config GUI at setup, and (worse) factory-tier upgrades and some machines reset or complicate side config. Mitigation, not solution: add a `station doctor` self-test â push a known probe item, verify it lands in the expected slot, verify pull works, rednet-alert on failure. Machines will silently misbehave without this; a doctor turns config drift into an alert instead of a jam mystery. [SPEC]
- **Set-parsing has a poison case you haven't enumerated: recipe ambiguity within a class.** Your infuser example (enriched_redstone + iron â infused_alloy) shares an input (enriched_redstone) with other infuser recipes (e.g., steel uses enriched carbon + iron â iron is shared there). If RS interleaves tasks for two recipes sharing an ingredient, set-parsing math needs a *deterministic claim order* (priority by recipe key) or you can dispatch mixed sets that craft neither output. Your test case (5) says "interleaved pushes from 2 tasks" â make sure the two tasks' recipes share an input; disjoint sets are the easy case. [KNOWN for recipe overlap / SPEC for failure mode]
- **`pollFast = 0.25` with many stations will breach the 10ms shared budget.** [DOCS: budget law] Each fast-polling station does a `list()` on the buffer + N machine scans per cycle. With 8+ stations, worst-case alignment eats the tick for everyone. The doc says adaptive polling but nothing about *cross-station* coordination. Cheap fix: craftd v2 issues staggered "you may poll" windows via the existing heartbeat channel (stations self-throttle to idle rate unless granted a slot), or just hash-offset poll phases by station name. [SPEC]
- **RS2 behaviors possibly mismodeled:** the duplicate-pattern question [DOCS checklist item 2] is load-bearing â if 2.0.9 concurrent jobs *do* pick different Autocrafters, then for simple 1-machine-per-pattern classes (crafters, smelting banks of 1-2) stations are overkill and you should spend the dispatcher budget only on big banks (infuser/PRC/HNN). Don't build N stations before that test returns. [DOCS]
- **Jam watchdog retry once then route-around** â with Mekanism, a common real jam cause is *gas/chemical starvation* (infuser out of redstone type in its internal tank, PRC out of water), which looks identical to a stuck item. The watchdog should attempt a diagnostic pull of the machine's full inventory before flagging; if ingredients are present but no output, it's a resource-side jam and routing around it is wrong â the whole bank will jam next. Alert class should distinguish "this machine" from "this class is starved." [KNOWN for Mek behavior / SPEC for design]

## 4. Commune angle: the infrastructure-felt gap is *consumption*, not production

You have boards, depots, heatmaps. What's missing is anyone noticing the system when they *take* things:

- **Receipts.** Chat Box prints a one-line corp receipt whenever a craftItem job completes for a requester ("PC-ORDER: 256x infused_alloy for Torgo â 41s â have a compliant day"). Zero-permission wrapped commands are banned-listed safe [DOCS], and this makes RS crafting *visible* to people who never open the grid. [SPEC]
- **Exchange ticker on real flows.** Your emc.txt fiction ports verbatim [DOCS] â but price the ticker off *actual RS crafting task throughput* (getCraftingTasks polling): items that move a lot get "volume," items nobody crafts get DELISTED jokes. The scoreboard fiction gets funnier when it's downstream of real telemetry. [SPEC]
- **Prospecting heatmap â claim culture.** Geo Scanner turtles [DOCS] produce data; the multiplayer move is publishing "survey charters" â a chat command any member runs to request a scan of a region, which queues a turtle job and DMs them the heatmap when done. Turns your scanner fleet into a *service the commune orders from*, which is the corp fiction working at the social layer. [SPEC]

## 5. Airport sharpening

- **Flight numbers from the crafting queue.** [SPEC] Departure board rows generated from live RS task IDs (`getCraftingTasks` [DOCS]): "FLT PC-4821 Â· 64x SIGNALUM Â· BOARDING." The board is literally the autocrafting monitor in a trench coat. This is the cheapest load-bearing joke available â tm_gpu board + one bridge call.
- **DELAYED states from jam watchdogs.** Station jams [DOCS spec] map to flight delays; a station in jam-alert state shows its recipe class as DELAYED on the board with an announced apology. The airport becomes a real status page for your automation health â ops visibility disguised as set dressing. [SPEC]
- **Security checkpoint with the Block Reader or Player Detector + a random delay.** [SPEC] It detects you, pauses 2-6s ("additional screening"), then CLEARED. Randomized delay makes it funnier and it's ~20 lines.
- **Baggage claim as the actual RS dump chest.** [SPEC] "Lost luggage" = items that failed set-parsing and got flushed to the importer [DOCS: partial-set flush]. A literal carousel of misfit items with names on signs. Your error path becomes a tourist attraction.
- **Hypertube = the budget airline.** [DOCS] Brand it in-fiction ("Paperclip Basic â no frills, some concussions") with its own sad departure board row that always says ON TIME.

## 6. Gate-map corrections / under-weights

- **Occultism miner spirits are under-weighted as an *early CC* target, not just an income faucet.** [DOCS rates 4/5] The ritual setup is one of the few early systems with redstone-triggerable steps, and dimensional storage Actuator logistics are plain-inventory shaped â a candidate first "real" station before Mekanism banks exist. [KNOWN/SPEC]
- **The Teleport Pad is a commute, and nobody's treating it as transit.** [DOCS: pad â mining dim] Put the pad *in the airport* as "Gate 0." It's thematically perfect (the one destination CC can't fly you to, the airline still sells the ticket) and it concentrates foot traffic where your detectors and depots live. [SPEC]
- **Dragon Soul / ATM Star prerequisites (Cataclysm bosses, Wither farm) are marked as gates but not as *schedulable work*.** [DOCS] These are boss-summon loops â summoning, arena reset, loot collection are all plain-inventory/redstone. A "boss arena" station class late-game is the natural end of the dispatcher architecture, and the Harbinger is re-summonable [DOCS] â your armament report and your gate map are pointing at the same build without saying so. [SPEC]
- **One caution on bees as the spine-metal bypass:** [KNOWN] Productive Bees ATM-metal bees have notoriously low per-comb yields and long centrifuge chains; "the legal bypass" is real but the *throughput* is the actual gate. Your docs treat bees as the endgame solve â correct â but under-weight that the bee wing needs the dispatcher infrastructure (many centrifuges in parallel) to deliver meaningful rates, which is another argument for generic station.lua rather than a bespoke bee rig. Good news: your architecture is already right for it. [KNOWN yield lore / SPEC on sizing]

---

**One-line summary:** the plan is architecturally sound and unusually well-verified; the biggest gaps are (1) HNN never got its station, (2) side-config drift and starvation need diagnostics, not just jam flags, and (3) your error paths (flushed partials, jams, delays) are free entertainment the airport should be displaying.