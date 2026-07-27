# minecraft-warehouse-os

> ⚠️ This is a silly Minecraft thing. It is not serious software. If you are a
> recruiter, please see literally anything else. If you are one of my friends
> from the server: no, you can't have admin on the warehouse computer.

Lua "operating system" for a [CC: Tweaked](https://tweaked.cc) computer that
runs the item warehouse on a friends' modded Minecraft server (1.21.1
NeoForge). It reads the drawer wall through a wired modem network and is
slowly reimplementing Applied Energistics 2 out of spite, one feature at a
time.

## What it does

- Indexes ~2,000 storage slots behind a Sophisticated Storage controller
- Touch-screen storefront UI on a monitor wall (tap an item, get a stack)
- On-screen QWERTY keyboard, because monitors don't have real ones
- Knows every crafting recipe in the modpack (23,765 of them) without being
  taught — `tools/compile_recipes.py` extracts them from the mod jars offline
- Batches inventory transfers into parallel coroutines so peripheral calls
  coalesce per server tick (this is the part where my day job leaks in)
- Built-in profiling (`stats`), because if a thing exists it can be profiled

## Files

| file | purpose |
| --- | --- |
| `warehouse.lua` | main program: index, storefront UI, terminal commands |
| `recipedb.lua` | loads the compiled recipe/tag/name database |
| `recipes.lua` | CLI recipe lookup (`recipes iron gear`) |
| `update.lua` | pulls everything in `manifest.txt` from this repo's raw URLs |
| `report.lua` | uploads a program's output to pastebin for debugging |
| `probe.lua` / `pixeltest.lua` | display capability probes |
| `data/` | compiled recipes, item tags, display names (~6 MB) |
| `tools/compile_recipes.py` | offline recipe compiler (run against the mods folder) |

## Deploying in-game

```
pastebin get <code> update      -- once
update https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/
warehouse install               -- auto-start on boot
reboot
```

## Roadmap

Turtle autocrafting pool designed like a continuous-batching inference
scheduler, pocket computer remote ordering, pixel-mode storefront via
CC: Graphics, metrics dashboards on an in-game TV, and eventually a
natural-language front door. None of this is necessary. All of it is
happening.
