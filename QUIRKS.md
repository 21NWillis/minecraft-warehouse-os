# QUIRKS.md — things that bit us

The bite log. Every entry is a law paid for in lost time: symptom →
root cause → rule. Append when bitten; never delete (supersede with a
dated note instead). Agents: read this BEFORE deriving fresh — if your
clever plan contradicts a law here, the law wins until proven stale.
This file is the project's crash-proof memory — session memories and
drives die; the repo survives.

## Toolchain / Windows

- **PS5.1 `Set-Content -Encoding utf8` writes a BOM; CC Lua REJECTS
  BOM'd files** ("character isn't usable") — while headless lua54
  skips the BOM, so local tests stay green while the server breaks.
  Law: never write repo `.lua` via PowerShell string cmdlets; if
  bitten, strip `EF BB BF`.
- **PS5.1 chokes on non-ASCII in `.ps1` files** (em-dashes in a
  comment string = parser errors, 2026-08-05). Law: ASCII-only in
  PowerShell scripts.
- **git isn't on PATH in fresh shells.** Law: prepend
  `[Environment]::GetEnvironmentVariable("Path","Machine"/"User")`.
- **lua54 is not CC.** Headless-green proves logic, not runtime
  compatibility (encoding, missing CC APIs, event semantics). Field
  debug is always still owed.

## CC:Tweaked networking (the lost hour, 2026-08-04)

- **A wired network is ONLY cable+modem blocks, FACE-adjacent.**
  Diagonal runs look connected and are not (the bishop's move).
- **Peripherals never conduct through their body.** A computer,
  controller, or chest mid-span dead-ends the network; they hang OFF
  the net via an adjacent modem, they are never part of its spine.
- **Chat NEVER announces network formation** — only peripheral
  bindings. Silence can be success. Law: verify with `netprobe` /
  `getNamesRemote`, never by watching chat.
- **Wired names are PER-MODEM-BINDING, counter-assigned at
  activation.** Two modems touching one turtle bind it under two
  different names simultaneously (the turtle_4/turtle_8 incident).
  Law: announce ALL local names; resolvers pick the reachable one.
- **`rednet.broadcast` with no modem open fails silently** (craftd's
  0-cells mystery). Open every modem, wired included — rednet rides
  wired fine.
- **`peripheral.pushItems` only works within ONE wired network.** A
  computer bridging two nets sees all peripherals and can ferry
  nothing between them.
- **`rednet.receive` swallows non-rednet events.** Use a single
  event pump (`os.pullEvent` + timer) when chat/peripheral events
  matter too.

## Pack / mod behavior

- **The SS storage controller VOIDS automation inserts** once
  item-matching stacks cap (the emerald famine) — reads and pulls are
  fine. Law: controllers are PULL-ONLY; SFM store labels sit on plain
  barrels; return trays are linked chests, never inserts.
- **Owner-tracked interactive blocks (harvester pylons etc.) bind to
  their PLACER.** Turtle-placed = fake-player-owned = the user locked
  out of their own block; turtle dig repossesses. Law: hand-place
  every GUI/owner-tracked block, forever.
- **Blanket `turtle.refuel()` burns wooden items** — it ate its own
  reject-bin chests (15 fuel each). Refuel coal-by-name only.
- **Real inventories merge returned stacks into front slots** — a
  suck-and-drop-back kit protocol livelocks. Separate reject bin,
  direction-aware venting, end-of-kit flush.
- **MA flight augment DIES on ground contact.** Never land, never
  settle onto your own work — executor altitude floor exists for this.
- **Alt-tabbing can interrupt F8 flights.** Stay focused while armed.
- **EM Rail Ejector guns validate a 3x3x3 AIR volume** — an adjacent
  turtle fails the check by existing inside it. F8 places guns.
- **EMC IS FICTION.** ProjectE is not in the pack; EMC is the
  Exchange's scoreboard metric only. No transmutation, ever.
- **The pack author DELETES recipes** (wind_generator is gone
  entirely). Law: recipe-db audit (`data/recipes.txt`) before
  planning any build around a machine; never trust mod defaults.
- **The dealer always takes his cut** — wait, wrong repo.

## Lens / F8 executor (the six-flight debug arc, 2026-08-04)

- **`done++` without server verification = phantom completions**
  (flight 3's false 25/62 COMPLETE). Verify against server block
  state after a delay; count REVERTED and requeue.
- **Hotbar slot + aim set the same tick as the click** = the server
  processes last tick's hand/look. Sync one tick, then click.
- **Side-hovering put the eye at 3.37 vs the 3.5 reach filter — the
  face search could never succeed** (flight 4: zero placements, empty
  placelog). Law: turtle semantics — hover directly above, click
  straight down.
- **The executor placed a block under its own feet, settled 0.15 onto
  it, and the flight augment died at full altitude** (flight 5). Hover
  clearance + altitude floor are load-bearing numbers.
- **BuildOrder's layer re-sort interleaved distant columns at reach
  limit** (column ping-pong). Law: trust file order; generators own
  ordering AND sequential-support verification.
- **Weak retries orphan everything above a hole** (defer-after-2).
  Law: block-is-a-barrier — tight re-approach retries before defer.
- **Straight-line autopilot clips obstacles near the path** — the bay
  chest hit at 0.49 clearance including the half-to-arm diagonal
  (needed: 0.3 player + 0.44 chest = 0.74). Law: route legs keep
  >= 1.0 from known obstacles; pin it with segment-distance tests.

## craftd / planner

- **Missing-map not rolled back on abandoned recipe branches** = 2772
  phantom nuggets from ingot<->block<->nugget cycles. Snapshot/restore
  `missing` with `have`.
- **Name search resolves the wrong item** ("iron ingot" -> Cast Iron
  Ingot). Law: UI passes exact `id:` orders; what you click is what
  runs.
- **Cell slot math caps ring-recipe jobs**: 8 input slots x 64 runs =
  512 items, but free output slots = 7-8. Law: order in <= 256
  chunks; the surplus-retry path is a fallback, not a plan.
- **Chunk unloads wipe running turtles' state.** Every cell writes a
  `startup` file and self-resurrects.

## Process / collaboration

- **Operator checklists ("did you restart it?") disguise MY model
  uncertainty as user error.** The user is a software engineer. Law:
  state uncertainty explicitly, establish the mechanic, give system
  facts — they self-diagnose instantly.
- **The user cannot paste CC screen output. Ever.** Channels:
  Lens screenshots, pastebin uploads, telemetry files.
- **Restarts are expensive; the user hates them.** Runtime tunables
  over jar rebuilds; batch restart-worthy changes.
- **Session memory dies with drives** (hit-me, 2026-08). The repo is
  the only memory that survives. Doctrine, decisions, and bites live
  in committed files — this one included.


## Extreme Reactors 2 (the 7x7 shame, 2026-08-13)

- **BASIC tier multiblocks have HARD SIZE CAPS: reactor max 5x5x5,
  turbine max 5x5x10. Only Reinforced is size-unlimited.** An
  over-size Basic structure fails SILENTLY - no GUI, no chat message,
  no assembly error; the controller right-click does literally
  nothing. Claude spec'd a 7x7x5 Basic reactor from memory; the
  operator built it faithfully (twice audited it, vein-mined the
  interior to recount blocks) and burned an hour debugging a
  blueprint that was illegal at authoring time. Law: BEFORE speccing
  any multiblock, verify the tier's size cap against the mod page or
  in-game manual - and when a multiblock is silent (vs telling you
  what's wrong), suspect the SPEC first, the operator's assembly
  LAST. Corollary: Basic tier has no Computer Port either -
  Reinforced only.
