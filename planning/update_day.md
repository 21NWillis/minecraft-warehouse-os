# UPDATE DAY — the hour-one runbook

For the pack update that adds Advanced Peripherals + the paperclip mod
(+ whatever else Errot ships). Written 2026-08-08 while waiting, so
that when it lands we execute instead of deliberate. Order matters:
verify -> re-index -> integrate -> then play.

## Step 0 — trust nothing, verify the drop (10 min)

- [ ] CurseForge updates the instance; note the pack version.
- [ ] JEI existence checks (fastest source of truth): search
      `ME Bridge`, `Chat Box`, `Player Detector`, `Energy Detector`
      (Advanced Peripherals), and every paperclip-mod block we expect
      (GPU block, B800, singularity pricing). What's actually present
      beats what was promised — write the diff in this file.
- [ ] Check the changelog for REMOVALS too. The pack author deleted
      the wind generator recipe last time; assume nothing survived.
- [ ] `update` on the NOC computer (deploys latest OS), then `doctor`
      + `selftest` — confirm the old world still works before wiring
      anything new.

## Step 1 — re-index the world (recipes changed under us)

- [ ] Re-export the recipe dump and rebuild recipedb (~20k recipes;
      the new mods' recipes join the planner's pattern library).
- [ ] Planner smoke test: plan a known-old item (solar generator) and
      a known-new item (anything AP) — both must resolve.
- [ ] Re-verify the load-bearing recipes this base's plans lean on:
      sail (3 copper + 2 lapis + 4 panes), pitiful_generator chain,
      metallurgic infuser chain, gas-burning generator chain. Any
      drift invalidates datacenter_floor.md numbers - fix there.

## Step 2 — craftd goes ME-native (the pre-armed push)

craftd's Advanced Peripherals integration shipped ahead of the update
(commit bce3575, "pre-armed"). Now it goes live:

- [ ] Place an ME Bridge on the warehouse network spine; wired modem;
      note the peripheral name into craftd.cfg.
- [ ] Live-fire the integration tests against the real bridge.
- [ ] STORAGE DOCTRINE v2 (runbook phase 9, now unlocked): CC reads
      ME cells directly -> cells become primary storage, the barrel
      priority dance becomes optional, grid/nocboard/Lens/curator all
      read the whole network. Revisit warehouse.lua's storage layer.
- [ ] Chat Box: fleet speaks in chat (job done/stuck/fuel alerts).
      Keep it terse - one line per event, no spam. Player Detector in
      the NOC for presence-aware dashboards.

## Step 3 — paperclip mod bring-up (our own hardware)

- [ ] Place one of each new block; confirm textures/GUIs/recipes.
- [ ] GPU blocks + cluster primitives: whatever the mod's actual API
      turned out to be, probe it from CC and write the peripheral
      surface into a new planning note (nanolm-on-hardware starts as
      a survey, not a plan).
- [ ] B800 pricing / Block of Singularities: check the Exchange
      board picks it up (fe81d49 wired the pricing).

## Step 4 — claims and chunks

- [ ] If the claim/force-load bump landed: claim the deck chunks +
      sun wing, force-load the campus core, printer row, and deck.
      (Strainers and bays only tick loaded - this is production.)

## Step 5 — THEN the Datacenter Floor (unchanged by all of the above)

Resume planning/datacenter_floor.md exactly as written - none of it
depended on the update:

1. Shard 1 deck tile: anchor obsidian at (-376, 257, -1872), F8
   shard1_deck.json (512 obsidian, order staged since 08-05).
2. Cable spine drop + modem stubs.
3. pitiful_generator + metallurgic infuser (first power, no copper).
4. Bays 10-12 (copper/lapis) -> sail line unblocked.
5. Ethylene from seed surplus; solar row on the sun wing.
6. Gun row 1. The casino skyline begins.

## Non-goals for hour one

- No warehouse.lua rewrite live on update day - doctrine v2 is a
  planned change with tests, not a day-one improvisation.
- No GPU-block automation until the peripheral surface is probed and
  documented.
- Nothing built west. West is still banned. West is always banned.
