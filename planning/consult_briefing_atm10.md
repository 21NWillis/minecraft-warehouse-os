# Consultant briefing — ATM10 commune bring-up (2026-08-12)

You are an outside consultant. The house model (Claude) holds doctrine
and commits; your job is ideas we're sleeping on, holes in the plans,
and better mechanisms. Attached: the translation blueprint
(atm10_translation.md), the dispatcher spec (atm10_station_spec.md),
and the transit-authority gimmick charter (atm10_airport.md).

## Who we are
A friend group ("the commune") starting All the Mods 10 (NeoForge
1.21.1, 501 mods, customized). One member (our operator) runs a
ComputerCraft-based automation stack, PaperclipOS — evil-corp
roleplay flavor, serious engineering underneath. Prior pack: we built
a full autocrafting OS from scratch (recipe DB, planner, dispatcher,
crafting cells) because that pack had no bridge between CC and the
storage mod. This pack HAS the bridge (Advanced Peripherals RS Bridge
vs Refined Storage 2.0.9), so the architecture inverts: RS solves BOM
and storage; CC does edge dispatch, telemetry, and human-facing magic.

## Hard constraints (do not propose against these)
- Server: computer_threads=1, ~10ms/tick Lua budget SHARED by every
  computer; 1MB disk per computer; HTTP to public hosts only. We do
  not admin the server.
- ATM10 law: allthemodium/vibranium/unobtainium ore drops for REAL
  PLAYER pickaxes only. No automation loophole exists; don't propose
  one. Automate around it (targeting, logistics, post-processing).
- RS2 autocrafting locks a task's external steps to one Autocrafter;
  no load balancing. Our station dispatchers exist because of this.
- EMC is a fiction (scoreboard/roleplay), not a mechanic. No ProjectE.

## What we already know (don't re-derive)
The attached docs contain: verified RS Bridge Lua API + landmines,
the ATM10 gate graph + degenerate-loop map (HNN, drygmys, ATM bees,
Occultism spirits, Apotheosis flywheels), the station.lua design
(implemented + headless-tested), QoL mod staging, and the airport
plan. Assume all of it.

## What we want from you (ranked output, please)
1. What is this plan SLEEPING ON? Mods or interactions in ATM10 we
   haven't weaponized — especially ones that compose with CC via
   plain inventories, redstone, or Advanced Peripherals.
2. Holes: where will the station/dispatcher design hurt in practice?
   (Mekanism side-config, machines with weird slot semantics, RS2
   behaviors we've mismodeled.)
3. The commune angle: multiplayer-facing systems that make 4-6 friends
   FEEL the infrastructure (we have: chat concierge, quartermaster
   loadout depots, prospecting heatmaps, transit authority).
4. The gimmick: sharpen the airport/train-station. What would make it
   funnier or more real?
5. Anything about ATM10 progression our gate map gets wrong or
   under-weights.

## Output discipline
Tag every mod-behavior claim [DOCS] (supported by the attached docs),
[KNOWN] (your training knowledge of the mod - version-sensitive,
we'll verify), or [SPEC] (speculation/idea). Version drift is real:
this is MC 1.21.1 and many mods rewrote their APIs. Concrete > vague;
mechanisms > vibes. Length: whatever the content deserves.
