# craftd — the CC-native autocrafting platform (design)

Thesis (user's): the corp's moat is that recipedb already contains the
pack's ENTIRE recipe registry (~20k recipes) and planner already does
recursive craft planning. Everyone else hand-encodes patterns; we
compiled the game. ME shrinks to storage + viewing.

## Throughput truth (corrected: turtles are NOT slow)

  * turtle.craft(limit) crafts up to a full batch (64 results) in ONE
    action. With peripheral staging (9 pushItems, sub-tick main-thread
    calls) a cell cycles ~64 items / ~0.5s = ~100+ items/s PER CELL.
    A molecular assembler wall doesn't beat one shelf of turtles.
  * The REAL limiter on this server: the shared 10ms main-thread
    budget. Design rule: batch everything (full-stack pushItems, no
    per-item ops), event-driven dispatch (no polling loops), cache
    list() snapshots. Peripheral spam is the only way to lose.

## Three-tier execution model

  T1 HOT PATHS - Cyclic Crafting Machines, one per high-volume fixed
     recipe: SAIL, BEAM, PACKAGES, glass->panes. Recipe set once by
     hand; pipez ultimate streams inputs; crafts continuously with
     ZERO CC cost per craft. This is the "dump stacks into a crafter"
     firehose - the Dyson supply line runs entirely on T1.
  T2 GENERAL - craftd turtle cells: any of the 20k recipes on demand.
     Cell = crafty turtle + input chest + output chest. The warehouse
     computer (brain) plans via planner, stages exact ingredients via
     pushItems, orders turtle.craft, collects output. Container-item
     recipes (Master Infusion Crystal tier-ups) are cells where the
     catalyst simply lives aboard.
  T3 MACHINE CELLS - furnace banks (TIAB'd), Mek machines as CC
     peripherals: computer sequences inputs/outputs for smelting,
     enriching, chemical chains. reactor.lua's pattern generalized.

## Components (night-shift build order)

  1. craftcell.lua - cell firmware: rednet protocol paperclip.craft;
     receives {grid, count}; arranges slots; craft; deposits; reports.
  2. craftd.lua - dispatcher on the warehouse computer: order queue,
     planner integration, cell registry/assignment, ingredient
     staging from the ME/SS storage via wired peripherals, progress
     events.
     CELLS ARE GENERALISTS (user doctrine): every cell can run every
     recipe - it's a distributed system behind a load balancer, not a
     bank of specialists. Dispatcher = work queue + least-loaded
     assignment (scheduler.lua's lease pattern reused); adding
     throughput = placing another turtle, zero configuration. The
     only pinned cells are container-item catalysts (the crystal
     lives somewhere) and T1 hot paths, which exist purely to keep
     bulk volume off the main-thread budget.
  3. warehouse UI v2 (the "giga ass" remediation):
     - incremental fuzzy search (recipedb.search exists)
     - click-to-order on advanced computer + monitor (mouse events)
     - live order queue w/ per-step progress + ETA from planner
     - favorites row (sail/beam/package one-click)
     - pocket computer remote ordering over rednet
     - NOC ticker line: active orders + cells busy/idle
  4. Tests: mock cell + mock storage, staging/order lifecycle,
     container-item cell, multi-cell parallel dispatch, budget
     discipline (call-count assertions per order).

## Placement

Cell shelf inside the warehouse near the controller: 4-8 cells to
start (turtles are cheap; scale by adding turtles + chests). T1
crafter bank beside the conversion cluster, pipez-fed. All wired
modems to the warehouse computer.

## The horizon: the capability fabric (user doctrine, build toward)

craftd's brain must not know what a cell IS - only what it CAN DO.
Cells advertise capabilities ({craft}, {smelt}, {infuse}, {conduct},
{harvest}...); jobs declare a required capability plus input/output
contracts; the planner compiles goals into producer/consumer DAGs and
the dispatcher schedules onto whatever advertises the capability.
"Teaching the platform a new machine" = dropping a DRIVER module in
the repo - a small Lua file wrapping one weird peripheral (a Create
train station IS a CC peripheral: a conductor cell is just a driver
that schedules trains). Generalist behaviors (craft/smelt/move-items)
ship built in so the long tail needs no teaching at all.

The repo already rehearsed this pattern everywhere: builder, quarry,
survey, printfit all take injected ops tables - drivers by another
name. craftd v1 implements craft+smelt ONLY, but shapes the registry
and job schema open from day one, so the fabric grows by accretion,
never rewrite. (Yes, this is a warp scheduler with specialized
kernels; the lease queue is the atomic; a turtle eating its own
staging chest is warp divergence. The metaphor is load-bearing.)

## Mobile jobs: the datum closes the loop (user doctrine)

Stationary cells consume in place; MOBILE jobs (build, quarry, survey,
explore) are the same queue with one extra contract: the consumer
first paths to the GOLD DATUM, normalizes pose there, then executes
the job in datum-frame coordinates - exactly the launch convention
already decreed for humans, now a machine protocol. Every existing
program (printfit, quarry, survey, builder) becomes a job type the
moment it reads its target from a job payload instead of argv.
Spec/gen split heuristic: generalist by default; specialize ONLY
where hardware pins it (catalyst-holding cells, T1 crafter banks,
machine-adjacent cells, dock geometry).

## Fleet nursery (kills the floppy-boot chore)

Turtles can place turtles. A nursery station: one turtle with a stack
of blank crafty turtles + a disk drive holding the provisioning
floppy (provision.lua exists) + a fuel chest. It places a newborn on
the boot spot; newborn boots from floppy, self-installs from GitHub,
sucks fuel, registers with the dispatcher, flies to fleet parking;
nursery places the next. Fleet growth becomes a chest you refill.

## LLM-in-the-loop, correctly placed

Runtime needs no LLM: machine recipes are datapack JSONs like
everything else - compile Mekanism/furnace/etc. recipe types INTO
recipedb with capability tags, and the existing planner plans
THROUGH machines deterministically. The LLM's seat is the compiler:
authoring drivers and recipe importers from mod data dumps offline
(this is literally what tonight already was, eleven times).

## Verdict vs AE2 crafting

AE2 assemblers/patterns: skipped entirely. Storage bus + terminals
remain for storage UX. If someone wants "click in ME to craft," the
honest answer is the warehouse UI v2 on a monitor next to the ME
terminal - one block apart, and ours knows every recipe for free.
