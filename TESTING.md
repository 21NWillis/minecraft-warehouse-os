# PaperclipOS ??? cold-start test playbook

None of this has run in-game yet; the logic is proven headless but every
peripheral touch is an assumption. Run these in order on a fresh computer and
paste Claude the pastebin codes ??? each step proves one layer.

## 0. Setup
A computer with: a **wired modem to the storage controller**, an **Advanced
Monitor** (optional), a **speaker** (optional), and ideally a **scratch
chest/barrel** on the network. Server must allow HTTP (default on).

## 1. Deploy
```
pastebin get <code> update
update https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/
```
Expect: every listed file downloads, `0 failed`. If it fails on space, the
server's `computer_space_limit` is still 1MB and wasn't raised ??? that's fine,
the big data streams from GitHub; only the ~40 scripts need to fit (~170 KB).

## 2. Diagnose ??? `doctor`
Checks every assumption (controller responds to `list()`/`pushItems`, monitor
size + pixel mode, speaker, wired vs wireless modem, recipe DB loads, EMC
streams, crafter turtles, disk) and uploads a report. **Send Claude the code.**
This tells us what's real before touching anything.

## 3. Functional smoke ??? `selftest`
Non-destructive: moves one real item out to the scratch chest and back (proves
transfers work bidirectionally ??? the thing most likely to surprise us on
Sophisticated Storage), plus recipe search + EMC. **Send the result.**

## 4. Warehouse
```
warehouse
```
- `grid` ??? type to search, click a row to pull a stack (needs an Advanced computer for mouse).
- `craft crafting_table 1` from just logs ??? exercises the planner end-to-end.
- `serve` ??? should show job latency, throughput, cache hit rate.
- `stats` ??? per-op p50/p99.
Report anything that errors or hangs.

## 5. Crafting pool (if testing autocraft)
Crafty turtle + full-block wired modem on the network, then on the turtle:
```
wget https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/crafter.lua startup.lua
reboot
```
Back at the warehouse: `crafters` should list it; `craft chest 4` should run.

## 6. The Java mod (separate, singleplayer first)
Drop `paperclip/build/libs/paperclip-0.1.0.jar` in a **singleplayer** Neutral
world. Confirm it loads, place a GPU (`gpu_gt1`), wrap it, and:
```lua
peripheral.find("gpu").bench(256)   -- microseconds; a Lua matmul takes minutes
```

## Known risks / most-likely breakages
- Peripheral **names** may differ from assumptions (auto-detect matches on
  substrings like "controller"; if it misses, paste `peripherals`).
- Sophisticated Storage controller may expose slots differently than expected.
- CC:Graphics pixel mode: `probe` / `pixeltest` confirm; UIs fall back to text.
- The mod is untested in-game ??? expect first-load mapping errors; paste them.

Paste codes/screenshots for anything that breaks and Claude fixes against reality.
