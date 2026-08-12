# Paperclip Transit Authority — the ATM10 gimmick charter (2026-08-12)

Pack tradition: every pack gets one big funny centerpiece (Neutral Pack
= the Doofenshmirtz tower; earlier packs = a zoo). ATM10's is a FULLY
FUNCTIONING AIRPORT + TRAIN STATION. Design law: the gimmick is not
decorative — it IS the commune's physical logistics layer wearing a
uniform. Corp fiction: the conglomerate acquisition included a
regional transit authority.

## Verified capabilities this rides on (jar-checked 2026-08-12)

- Create 6.0.10: trains + native CC peripherals (Station peripheral
  with programmable schedules, Display Link, sequenced gearshift etc.)
  — PENDING: verify which peripherals survive in ATM10's build (JEI).
- create-aeronautics-bundled 1.3.0 + createthrusters + toolgun +
  transmission linkage: real flying contraptions. Prior art:
  autopilot.lua flew a Sable airship in the Neutral Pack;
  planning/aeronautics.md holds the flight-stack research (physics
  assembler, propeller bearings, Linked Typewriter helm = movement-key
  hijack to redstone link frequencies, docking connectors).
- Create packages/postboxes: real freight items — baggage claim is a
  functioning carousel and the airport doubles as the freight hub.
- toms-peripherals tm_gpu: departure boards (amber-on-black, flight
  rows, BOARDING/DELAYED states). The screen's load-bearing moment.
- AP Chat Box: cross-dimension gate announcements ("final boarding
  call, flight PC-101 to THE NETHER") delivered in actual chat.
- AP Player Detector: boarding logic at gates; optional zero-function
  security checkpoint that detects you and displays CLEARED.
- AP Inventory Manager + memory cards: ARRIVALS HALL = quartermaster
  depot — land, walk the gate, get re-kitted to your loadout spec.
- create_hypertube: terminal transit / the budget airline joke.

## Phased build

1. **Grand Central first** (trains are proven tech): one mainline,
   2-3 wing stations, CC dispatch (demand-scheduled freight +
   passenger), display-link or tm_gpu departure board, package
   postboxes as the baggage/freight spine.
2. **Airport shell + boards + announcements** (pure build + CC, zero
   flight risk): terminal, gates, carousel, quartermaster arrivals.
3. **Scheduled flights** — gated on the aeronautics autonomy test:
   can CC drive the Linked Typewriter helm via redstone links (the
   ground test the Neutral Pack never ran)? If yes: autopilot v2 flies
   scheduled routes between campus and outposts. If no: flights are
   player-piloted with CC handling boards/announcements/docking
   clearance — still reads as a real airport.

## Open engineering questions (first sessions)

- Create train Station peripheral survey in ATM10 (JEI + wrap test).
- Aeronautics CC->redstone-link helm ground test (decides phase 3).
- tm_gpu board perf at departure-board size (small screen, low sync
  rate — should be trivial vs the nocboard budget).
- Where the mainline runs (needs the campus siting decision first).
