# minecraft-warehouse-os → **PaperclipOS**

> ⚠️ This is a silly Minecraft thing. It is not serious software. If you are a
> recruiter, please see literally anything else. If you are one of my friends
> from the server: no, you can't have admin on the warehouse computer.

A [CC: Tweaked](https://tweaked.cc) toolkit for a modded Minecraft server
(1.21.1 NeoForge) that started as "reimplement AE2 out of spite" and turned
into a whole factory OS — a serving engine, a renewable-resource fleet, its
own economy, and a pile of on-theme toys. Almost all of it is pure in-game Lua;
nothing here needs the companion Java mod to run.

Boot `menu` for the launcher. Deploy with `update` (below).

## The stack

**Storage & autocrafting**
- `warehouse.lua` — indexed storage, RS-style grid UI, touch storefront, and a
  **continuous-batching craft scheduler** across a turtle pool (priority
  preemption, backpressure, in-flight dedup, p50/p99 + goodput metrics via
  `serve`, cache-hit-rate, auto-stocker with `stock`).
- `scheduler.lua` — the job scheduler (admission control, lease-free priority queue).
- `plancache.lua` — RadixAttention-style resolved-recipe DAG cache; EMC-aware
  (picks the cheapest recipe). `planner.lua` — the backtracking planner.
- `recipedb.lua` / `recipes.lua` — recipe database (loads from `data/`, streamed
  from GitHub into RAM to dodge the 1 MB disk cap) + CLI lookup.
- `machine.lua` — mod-agnostic machine-tending driver (auto-feed/drain any
  processing machine into the network).

**Economy & analytics**
- `tools/emc.py` → `data/emc.txt` — intrinsic item value solved as a fixpoint
  over the recipe graph (20k+ items priced).
- `transmute.lua` — conservation-honest Equivalent Exchange (burn surplus → EMC → make).
- `exchange.lua` — the Paperclip Exchange, a live EMC stock ticker.
- `tools/factory_plan.py` → `planning/factory_plan.md` — recursive BOM for a
  target machine set (raw materials + machine-gated automation targets).

**Fleet & building**
- `fleet.lua` — lease-based fault-tolerant work allocator (no double-assign,
  dead-worker reclaim, resume).
- `harvest.lua` — regrowth-aware GeOre harvesting scheduler (renewable, no mining).
- `schematic.lua` / `builder.lua` / `buildrun.lua` — generate & build structures
  with a turtle (box/tower/cylinder/**evilhq**), network-refill via ender chest.
- `autopilot.lua` — PID flight controller for a Sable / Create Aeronautics ship.

**Network & comms**
- `starlink.lua` — wireless mesh link-layer with real RTT.
- `melink.lua` — link every ME system on the server into one EMC-valued market.
- `remote.lua` — pocket-computer network console.
- `bridge.lua` — cross-layer comms (snapshot world state / run committed commands).
- `pa.lua` + `music.lua` — PA announcer with chiptune stingers.

**Toys & OS**
- `menu.lua` — PaperclipOS launcher. `attract.lua` — screensaver. `oracle.lua` —
  the AI Oracle. `vault.lua` — password door. `conway.lua` — Game of Life.
  `marquee.lua` — scrolling signage.

**Ops**
- `update.lua` — pull everything in `manifest.txt` from the repo's raw URLs.
- `report.lua` — upload program output to pastebin. `seed.lua` — one-trip bootstrap.
- `tests/` — headless suites run with `lua54` (12 suites, all green).
- `datacenter/` (a.k.a. **Paperclip**) — optional Java mod: item-delivery + GPU
  peripherals (GT-1/RTX-4/B800) + cluster primitives. Not required by any Lua above.

## Deploying in-game

```
pastebin get <code> update      -- once
update https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/
menu install                    -- boot into PaperclipOS
reboot
```

## Roadmap

Machine-driven production wired into the auto-stocker, GPU-accelerated planning,
a natural-language front door, and an orbital datacenter (hovering, for the
server's sake). None of this is necessary. All of it is happening.
