# Paperclip

A tiny NeoForge 1.21.1 QoL mod for the warehouse OS. Adds one block: the
**Paperclip Terminal** (crafted from iron, redstone, and an ender pearl),
which is a 9-slot inventory + a `paperclip` peripheral for CC: Tweaked.

Design rule: **not a cheat mod.** It only moves items that physically exist
and reports observable facts. No item creation, no reading player
inventories, no teleporting anything.

## Peripheral API

Delivery & chat:

| function | what it does |
| --- | --- |
| `players()` | list of online player names |
| `give(player)` | moves the terminal's 9-slot inventory into that player's inventory; returns items moved, leftovers stay |
| `notify(player, msg)` | chat message to one player (rate-limited 1/s) |
| `broadcast(msg)` | chat message to everyone (rate-limited 1/s) |

Server health:

| function | what it does |
| --- | --- |
| `mspt()` / `tps()` | live server tick health, for dashboards |

Cluster primitives — **shared across every terminal on the server**, persisted
with the world. This is the distributed-systems toolkit: shared memory,
atomics, and work queues for fleets of computers.

| function | what it does |
| --- | --- |
| `get(key)` / `set(key, value)` / `del(key)` | shared KV store (4096 keys, 16KB values) |
| `incr(key, [delta])` | atomic counter, returns new value |
| `cas(key, expected, value)` | compare-and-swap; pass nil expected to acquire a lock |
| `push(queue, value)` / `pop(queue)` / `qsize(queue)` | named FIFO work queues (4096 entries) |

Example — two computers splitting work off one queue:

```lua
local dc = peripheral.find("paperclip")
-- producer
dc.push("jobs", textutils.serialize({ craft = "minecraft:piston", count = 64 }))
-- worker (any number of these, anywhere on the server)
local job = dc.pop("jobs")
if job then handle(textutils.unserialize(job)) end
```

## Building

Requires JDK 21 and Gradle 8.8+ (`winget install EclipseAdoptium.Temurin.21.JDK`,
then a Gradle install or `gradle wrapper` once to make it self-contained).

```
gradle build
```

Jar lands in `build/libs/paperclip-0.1.0.jar`. Test in a singleplayer world
on the client instance first, then hand the jar to the server admin. Needs to
be installed on both server and clients.

First-build note: written against NeoForge 21.1.95 + CC: Tweaked 1.120.0 API;
if the compiler objects to a mapping or API name, paste the errors upstream
and they will be fixed - that is expected first-compile friction for a
hand-rolled mod, not something wrong with your setup.
