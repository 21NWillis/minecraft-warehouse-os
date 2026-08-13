# Board synthesis — outside consult on the ATM10 plan (2026-08-12)

Two independent passes over the briefing + blueprint + station spec +
airport charter: DeepSeek V4 Pro (planning/consult_v4pro_raw.md) and
Kimi K3 (planning/consult_kimik3_raw.md). ~$0.40 total. House verdicts
below; raw reports keep their [DOCS]/[KNOWN]/[SPEC] tags.

## ADOPTED — spec/design changes

1. **HNN gets a station class** (Kimi #1, the find of the consult):
   Simulation Chambers + Loot Fabricators are plain inventories — a
   `hnn_fab` station turns "piglich hearts from electricity" into a
   literal RS craftable that craftd can order. REQUIRED spec change:
   add `staticSlots` to the recipe config — slots the dispatcher must
   NEVER pull (the data model / key item persists in the machine).
   Note: current station.lua collect() only pulls declared output
   slots, so we're accidentally safe today — staticSlots makes it
   safe on purpose (jam diagnostics + any future full-drain must
   honor it). Build order: drygmys first (passive hearts), HNN second
   (crafting-visible path); the leveled Deep Learner transfers.
2. **Jam vs starvation alert classes** (Kimi): Mekanism gas/chemical
   starvation looks identical to a stuck item. Watchdog upgrade:
   before flagging, diagnostic-scan the machine inventory — inputs
   present + no output = STARVED (class-wide alert, do NOT route
   around); inputs absent = JAM (machine-local, route around).
3. **`station doctor` self-test** (both consultants converged):
   at setup and on demand — push probe item, verify landing slot,
   verify pull, rednet-alert on drift. Side-config drift becomes an
   alert instead of a mystery. (doctor.ps1 heritage continues.)
4. **Poll-phase de-confliction** (Kimi): N stations at pollFast=0.25
   can breach the shared 10ms budget. Cheap fix adopted: hash-offset
   poll phase by station name; keep craftd-granted poll windows in
   reserve if the fleet grows past ~8.
5. **Special-machine list** (V4 Pro): PRC-class machines (gas/fluid
   inputs, container returns) can't be generic stations. Spec gains a
   `special` registry; PRC/bee-centrifuge-with-tank get bespoke
   firmware modules. Set parser must model container returns
   (bucket comes back) before PRC class ships.
6. **Quartermaster gets a UI** (V4 Pro): tm_keyboard terminal, named
   loadouts, manifest preview ("swapping Fortune V for Silk Touch?"),
   confirm, then execute. "The armory issued me a kit," not "a robot
   stuffed my pockets." + Kimi's two loadout killers: DEATH-RECOVERY
   kit (detector sees empty-inv respawn → auto-issue recovery kit,
   per-player spec file = free commune engagement) and MINING-DIM
   swap depot (fresh Vengeance picks + torches out, loot in — serves
   the one unautomatable progression step).
7. **Concierge must surface failures** (V4 Pro): every chat order
   wrapped; MISSING_ITEMS events answered in chat ("ERROR: missing
   17 piglich hearts"), never a silent fail. craftd exposes a
   status/missing query endpoint.
8. **Receipts + telemetry-priced Exchange** (Kimi): chat receipt per
   completed order ("PC-ORDER: 256x infused_alloy for Torgo — 41s —
   have a compliant day"); ticker prices driven by real
   getCraftingTasks throughput — volume, and DELISTED jokes for
   dead items.

## ADOPTED — airport upgrades

- **Departure board = autocrafting monitor in a trench coat** (Kimi):
  rows from live RS task IDs ("FLT PC-4821 · 64x SIGNALUM ·
  BOARDING"); station jams display as DELAYED with apology
  announcements. Ops visibility disguised as set dressing — the
  screen's party trick becomes the status page.
- **Baggage claim = the flush path** (Kimi): flushed partial sets
  ARE lost luggage; the error path becomes a tourist attraction.
- **Gate 0 = the Teleport Pad** (Kimi): the mining-dim commute lives
  in the terminal; the one destination we can't fly, ticketed anyway.
- **Overbooking theater** (V4 Pro): player-count at gate → STANDBY /
  DENIED BOARDING with randomized reasons; customer service desk
  rebooks. Security checkpoint gains a randomized 2-6s "additional
  screening" pause (Kimi).
- **Trains ARE the planes** (V4 Pro): flight tunnel + in-car display
  link showing altitude/airspeed/cloud loop on tm_gpu. Boarding a
  box with a fake window = exactly like real aviation.
- **Job-board carousel** (V4 Pro, PARKED — needs commune ratify):
  task system where accepting a job spits raw mats onto the belt,
  finished goods go on Departures. Physical-logistics minigame.

## VERIFY IN-GAME (added to first-session checklist)

- Mekanism 1.21 slot-targeted pushItems: does toSlot survive the
  wrapped side + side-config? (V4 Pro flags; our spec already passes
  toSlot — test decides if mitigation pipes are needed.)
- Bee cage closed loop (V4 Pro): can the Breeding Chamber's offspring
  cage be pulled AND inserted into another chamber's parent slot? If
  yes: apiary needs zero deployers, gene program fully CC-closed.
- Integrated Tunnels "Operator" + LaserIO as Java-side dispatch for
  SIMPLE classes (V4 Pro): if they load-balance Mekanism banks with
  side-configs, small stations get deleted and CC keeps only jam
  telemetry. Test before building station N>3. Kimi agrees from the
  other side: don't mass-produce stations before the duplicate-
  pattern parallelism test returns.
- Occultism Iesnium Anvil unbreakable tools (V4 Pro) — commune-wide
  "endless pickaxe" via quartermaster; check 1.21 behavior.
- Ars Nouveau early wins: Enchanting Apparatus as pre-RS enchant
  rework + starbuncle as zero-budget mover for 1-machine stations;
  spell turret as deployer stand-in (V4 Pro).
- EvilCraft Environmental Accumulator rain-clearing automation
  (V4 Pro) — NOC weather row + auto rain-nuke.
- Bee yield reality check (Kimi): ATM-bee comb rates are low; the
  bee wing needs PARALLEL centrifuge banks = the dispatcher
  architecture, not a bespoke rig. Size accordingly.

## REJECTED / already covered

- "You cannot define target slot for CC push" (V4 Pro 2.1): wrong as
  stated — CC pushItems has a toSlot arg and the spec/impl use it.
  The real question is whether Mekanism honors it (see VERIFY).
- Recipe claim-order determinism (Kimi): already deterministic —
  greedy in config order, and test 4 pins shared-ingredient claiming.
  ADD one test: interleaved sets from two recipes SHARING an input
  (test 5 currently uses disjoint recipes) — cheap, worth pinning.
- Boss-arena station class (Kimi): correct observation that the
  armament report and gate map point at the same build; deferred to
  post-star-planning, not a bring-up item.
