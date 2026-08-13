[SPEC] Ranked Findings, tagged per your request.

### 1. What is this plan SLEEPING ON? (Weaponizable Interactions)

**1.1 [SPEC] Integrated Dynamics/Tunnels as a Zero-Code Parallel Dispatcher**
Your `station.lua` spec is elegant, but you are solving a problem that Integrated Tunnels' "Operator" system might already solve natively. An "Operator" positioned on a network cable between an inventory reader (facing your RS Autocrafter output) and a variable store can dynamically distribute a list of items across multiple inventories (your machine bank) using round-robin or input-rate logic, entirely without CC budget. Itâs a potential "station killer" for simple `pull-from-A, push-to-bank-B` patterns. For complex jobs like Mekanism infusing with specific slot semantics (your `infused_alloy` example), a Tunnels `Predicate` can filter by slot, keeping the operator's logic.
*   *Why it's a win*: Moves edge dispatch off the shared 10ms Lua budget onto Java-side logic that can't yield-error.
*   *How to test*: Connect an Integrated Tunnels `Logic Cable` from the buffer chest to a `World Item Importer` interface, then to a `World Item Exporter` variable card for each machine. If it load-balances Mekanism side-config slots correctly, `station.lua` becomes the advanced-jam-detection tool, not the primary dispatcher.

**1.2 [KNOWN] EvilCraft Environmental Accumulator for Weather Control**
ATM10 has EvilCraft. The Environmental Accumulator can clear rain/thunder. CC has no native weather API via Advanced Peripherals, but a block reader on the Accumulator or a redstone signal from it can feed into a CC-controlled redstone circuit. Why does this matter? Rain kills framerates and makes outdoor farms slower (growth ticks are half-rate in rain). Your NOC wall can show a weather forecast, and an automated system can nuke rain the moment it starts, a huge QoL win for the commune that costs next to nothing in CC budget.

**1.3 [SPEC] Ars Nouveau Automation Tie-in**
The doc mentions Ars Nouveau for the ATM Star but undervalues its utility as a transport and crafting layer.
*   *Starbuncle transport*: A starbuncle wheel on your buffer chest IS a zero-budget push/pull mechanism. For a station that just needs to push to a single machine (like an Enchanting Apparatus), a starbuncle removes the need for a CC computer entirely. It's a "dumb station" that costs nothing.
*   *Spell Turret + CC*: A `Touch` spell turret with a `Place Block` glyph next to a source jar acts as a deployer. Did JustDireThings clickers not pan out? A turret-triggered-by-redstone is a deployer. Redstone is cheaper than CC budget for a one-off fake-player click.

**1.4 [SPEC] LaserIO as a `station.lua` Budget-Saver**
You mentioned `laserio` as "dumb-plumbing." Smart usage: A Laser Node with an Item Card on the buffer chest can PULL with an adult filter (`max_durability`, `only_filled`, etc.) and INSERT with the same card into multiple machines. The node's logic runs server-side, cost-free to CC. For a machine bank with 12 identical furnaces, one LaserIO node network replaces the entire CC computer for dispatching and collection. CC only wakes up for jam detection, watching the LaserIO node's status via a Block Reader or doing a periodic inventory count to find aged items.

### 2. Holes: Where the station/dispatcher design will hurt in practice

**2.1 [KNOWN] Mekanism Side-Config is a Landmine**
Your station spec assumes `configure machine ejection OFF, station owns all movement`. Mekanism machines in 1.21.1 have strict side-config: input, output, energy, and possibly "extra" (for upgrades/gases). The `pushItems` function from CC pushes into the first valid *input* slot it finds from a given side.
*   *The hole*: A Metallurgic Infuser with `Redstone (Input)` from the left and `Iron (Input)` from the right. Your buffer chest `pushItems` against the *bottom* will push both items into the first available slot, jamming it. You **cannot** define the target slot for a CC push.
*   *Mitigation 1*: Use two buffer chests, one pushing into the left face, one into the right. Requires two RS Autocrafters for one recipe, which breaks the "one pattern per class" model.
*   *Mitigation 2*: Use a modded pipe with slot filtering (Mekanism Logistical Sorter, or your LaserIO "smart usage" idea above) as the *final inch* into the machine. The buffer chest pushes into the pipe network, which sorts to correct faces. This costs no extra CC budget.
*   *Mitigation 3 (fastest check)*: Test if CC's `pushItems(toName, fromSlot, limit, toSlot)` works on Mekanism machines with "auto-eject" off. The `toSlot` parameter might be the key. You have it in the recipe spec, but your station loop algorithm text omits it.

**2.2 [DOCS] `set-parsing` under RS2 Interleaved Pushes**
Your `station.lua` set-parsing logic is identified as a "hard-unit-test" problem. The specific failure mode you haven't modeled is the **Mekanism Gas Shroud**. RS2 pushes processing batches that include *gaseous/liquid* items alongside solids for a single craft. For the Pressurized Reaction Chamber (PRC), the buffer inventory will have a mix of `HDPE Pellet`, `Substrate`, and `Oxygen Bucket`. Your `stationlogic.lua` set parser must understand that `Oxygen Bucket` completes the set, even though it's a fluid container. Your current config spec shows a simple `inputs` list of namesâit has no concept of "this item is a catalyst/container that will be returned empty." You need an `outputs` list that includes an `{name="minecraft:bucket", fromSlot=X}` entry, and the parser must factor *expected returns* against *new inputs* to know when a craft is truly "done."

**2.3 [KNOWN] The `From/To Slot` Assumption**
Your recipe config has `toSlot` in inputs and `fromSlot` in outputs. This is a Mekanism-ism that doesn't port well.
*   *Mekanism*: Slot layout is fixed. `toSlot=1` means slot 1. It's predictable.
*   *Productive Bees Centrifuge*: Slot layout is variable based on upgrades, but the output is always the first 7 slots. The input comb is always slot 0.
*   *Thermal Expansion/Beyond*: Slots are often `input` and `output` and `augment` and `upgrade`. A generic `station.lua` config that declares `machineApi: {from=1, to=2}` is safer than a hard-toSlot number in a recipe. A Mekanism PRC needs `tankInput` and `gasInput` which CC sees as inventories? Unlikely for gas. This means the PRC CANNOT be a generic station machine. It's special. Your spec needs a list of machine classes that are `special` and require a bespoke firmware module (`prc_station_firmware.lua`).

### 3. The Commune Angle: Making 4-6 Friends FEEL the Infrastructure

**3.1 [SPEC] The Prospecting Heatmap as a Shared Mini-Game**
You have this listed. It can be deeper than just a map.
*   *Claim Stakes*: Players can place a "claim beacon" (a CC computer on a post) in a chunk. The `Geo Scanner` turtle scans, posts data to a central server. The server calculates "who claimed this chunk first?" and gives them a bonus on the Exchange ticker for any ores pulled from that chunk by the commune mining operation (Digital Miner, etc.). This turns exploration into a real-estate game.

**3.2 [KNOWN] The "Quartermaster Loadout Depot" Needs a UI**
The `Inventory Manager + memory cards` system is powerful, but standing on a pressure plate and getting a full shulker crammed into your inventory is a vibe killer. Here's the fix:
*   A `tm_keyboard` terminal at the depot lets a player type their name and select a loadout from a list (`mining`, `boss-fighting`, `building`).
*   The depot then resinspects their current kit, prints a manifest on the screen ("Swapping out your Fortune V pick for a Silk Touch pick?"), waits 5 seconds, then executes.
*   This is the difference between "an automation system stuffed things in my pockets" and "the armory issued me a kit." The fiction matters.

**3.3 [SPEC] Chat Concierge: Belt-and-Suspenders Error Handling**
The AP Chat Box `run_command` is "zero-permission and ban-listed." This is a trap. It means it's safe from a server admin panic standpoint, not from a "will it fail silently?" standpoint.
*   Wrap every command in a `pccall` wrapper. If the command fails, the concierge must *respond in chat* with the failure reason.
*   If a user asks `@AP craft 256 vibranium_alloy` and the job fails because of a missing HNN heart, the concierge must say: `ERROR: Missing 17 Piglich Hearts.` Not just a blank stare.
*   This requires your `craftd v2` orchestrator to expose a query endpoint: `paperclip.status.request(<item>, <count>)` â `{ ok: false, missing: { "piglich_heart": 17 } }`. The concierge reports that, turning it from a black box into a helper.

**3.4 [SPEC] The "Night Bell"**
A redstone clock connected to a daylight sensor. 5 minutes before nightfall server time (which you can compute), the Chat Box announces: "The sun sets on the campus. Lights on in five minutes." All campus lighting paths fire redstone signals. Spawn-proofing with visible, rhythmic, automated action.

### 4. The Gimmick: Sharpen the Airport/Train Station

**4.1 [SPEC] "At Capacity" Gate Control**
The Player Detector at the security checkpoint isn't just for show. Count players. If `count >= 3` at gate 4, the flight is overbooked. The departure board flips a flight to "STAND BY" with a randomized reason (`WEATHER`/`MECHANICAL`/`CREW REST`). The next player to approach gets a "STANDBY - SEAT ASSIGNED" message and the remaining are "DENIED BOARDING." The denied player must go to the customer service desk (another terminal) and rebook. Itâs a 100% artificial nuisance that makes the airport feel punishingly, hilariously real.

**4.2 [SPEC] The Baggage Carousel is a Job System**
The "baggage" is a stream of Package items going into the carousel. But the carousel is also a "dumb station." The commune job-board (a monitor) lists tasks: `{ "cobblestone": 4096, "requester": "Commune Expansion Fund" }`. When a player accepts a task, the carousel starts spitting out the raw materials from RS storage onto the belt. The player physically grabs the items from the carousel, crafts the thing (or feeds it into a machine), and places the finished goods on a different belt (Departures). The system tracks what they put on the Departures belt and decrements their task. This turns "auto-crafting" into a multiplayer physical logistics game, with the airport as the visual interface.

**4.3 [KNOWN] "Flight PC-101 to THE NETHER" - Make it Real**
Don't just announce it. A Create train departs Grand Central, enters an unloaded chunk tunnel (the "flight tunnel"), and emerges at a Nether station 45 seconds later. A display link board in the train car shows altitude, airspeed, and a looping view of clouds (a `tm_gpu` running a pre-rendered video of clouds). The passengers are in a box with a video screen, just like a real plane. The trains *are* the planes. This is 100% achievable.

### 5. ATM10 Progression the Gate Map Under-Weights

**5.1 [KNOWN] The Ars Nouveau Enchanting Apparatus as a Gate**
You list HNN for hearts, MystAg for insanium, etc. The Arcane Core is an early-game gate that solves the "I have 30 enchanted books and nothing to do with them" problem. The Apparatus can pull enchants OFF items and onto books, then combine them. This is how you get an early-game "unbreakable" (Mending + Unbreaking V) diamond pick before you have a single Apotheosis gem. Your QoL staging has no mention of an early enchanting rework that removes the RNG. This is that rework. A CC turtle can automate the Apparatus (pull book, place item, place book, provide source, extract) long before RS2 is online, creating a "starter station" that proves the concept with zero bridges.

**5.2 [KNOWN] Productive Bees: The "Bee Cage" Shuffle**
Your bee pipeline is `dispense caged bee â squash`. The "dispense caged bee" step is a player-only action (or a deployer of some kind). The bees in a Breeding Chamber *produce* offspring as an item in the output slot. That item is a `caged bee`. If you can PULL that cage from the breeding chamber (an `inventory` peripheral push/pull), you've closed the loop. Your CC apiary wing doesn't need a deployer at all if the Breeding Chamber output can be pulled into a hopper that faces... another Breeding Chamber. Test this loop first: `Pull caged bee from Breeding Chamber output` â `Does a hopper placed against a new Breeding Chamber accept that caged bee item into its "parent" slot?` If yes, bees are a closed CC system and your gene-pool can run perpetually without a single deployer, from product bees alone.

**5.3 [KNOWN] The Occultism "Iesnium Anvil"**
You mention Occultism for miner spirits, but the Iesnium Anvil is a mid-game unbreakable setup *for your tools*. It adds an indestructibility enchant. Combined with an Ars Nouveau book, this makes a permanent soul-bound, unbreakable tool that is repaired for free. This negates the need for a Silent Gear repair kit infrastructure mentioned in Section 5 of your doc. Your armament plan has an "endless quiver" but doesn't aim for "endless pickaxe" for the commune. A permanent, soul-bound, unbreakable pick for every member, issued from the quartermaster depot using the spirit anvil, is the true endgame commune goal.