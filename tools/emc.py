#!/usr/bin/env python3
"""Compute an EMC-style intrinsic value for every craftable item - the cheapest
raw-material cost to produce it - as a fixpoint over the recipe graph. This is
Equivalent Exchange / ProjectE's core (a whole magic mod) reduced to one solve.

It's a cheapest-cost over an AND-OR hypergraph: an item's value is the MIN over
its recipes (OR) of the SUM of ingredient values (AND), divided by yield. Raw
materials are seeded with base values; everything else relaxes down to a
fixpoint (values only decrease as cheaper production paths are found).

Exports emc.txt (id value) for the in-game transmutation script.
"""
from collections import defaultdict
from pathlib import Path

DATA = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/cc-scripts/data")
INF = float("inf")

# base EMC for raw materials (ProjectE-inspired). Leaves not listed default to 32.
BASE = {
    "minecraft:cobblestone": 1, "minecraft:stone": 1, "minecraft:dirt": 1,
    "minecraft:sand": 1, "minecraft:gravel": 4, "minecraft:netherrack": 1,
    "minecraft:flint": 4, "minecraft:clay_ball": 64, "minecraft:glass": 1,
    "minecraft:oak_log": 32, "minecraft:coal": 128, "minecraft:charcoal": 16,
    "minecraft:iron_ingot": 256, "minecraft:gold_ingot": 2048,
    "minecraft:copper_ingot": 85, "minecraft:redstone": 64,
    "minecraft:glowstone_dust": 384, "minecraft:quartz": 256,
    "minecraft:diamond": 8192, "minecraft:emerald": 16384,
    "minecraft:lapis_lazuli": 864, "minecraft:ender_pearl": 1024,
    "minecraft:blaze_rod": 1536, "minecraft:gunpowder": 192,
    "minecraft:string": 12, "minecraft:leather": 64, "minecraft:bone": 48,
    "minecraft:obsidian": 64, "minecraft:slime_ball": 128,
    "minecraft:nether_star": 24576,
    "mekanism:ingot_osmium": 256, "mekanism:ingot_tin": 256,
    "mekanism:ingot_lead": 256, "createmetallurgy:steel_ingot": 512,
}
DEFAULT_RAW = 32


def load():
    recipes = defaultdict(list)  # out -> [(count, [tokens])]
    for line in (DATA / "recipes.txt").read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        p = line.split("|")
        out, cnt = p[1], int(p[2])
        ings = [x for x in p[3:] if x]
        recipes[out].append((cnt, ings))
    tags = {}
    for line in (DATA / "tags.txt").read_text(encoding="utf-8").splitlines():
        if line:
            f = line.split("|")
            tags[f[0][1:]] = f[1:]
    return recipes, tags


def main():
    recipes, tags = load()

    # every item that appears anywhere
    items = set(recipes.keys())
    for rs in recipes.values():
        for _, ings in rs:
            for tok in ings:
                for o in tok.split(";"):
                    if o.startswith("#"):
                        items.update(tags.get(o[1:], []))
                    else:
                        items.add(o)

    emc = {}
    # seed raws (no recipe) with base values
    for it in items:
        if it not in recipes:
            emc[it] = BASE.get(it, DEFAULT_RAW)
    for k, v in BASE.items():
        emc[k] = v   # base overrides even if a recipe exists (raw is cheapest)

    def tok_val(tok):
        best = INF
        for o in tok.split(";"):
            if o.startswith("#"):
                for opt in tags.get(o[1:], []):
                    best = min(best, emc.get(opt, INF))
            else:
                best = min(best, emc.get(o, INF))
        return best

    # relax to fixpoint
    for _ in range(80):
        changed = 0
        for out, rs in recipes.items():
            if out in BASE:
                continue
            best = emc.get(out, INF)
            for cnt, ings in rs:
                total = 0.0
                ok = True
                for tok in ings:
                    v = tok_val(tok)
                    if v == INF:
                        ok = False
                        break
                    total += v
                if ok:
                    cand = total / cnt
                    if cand < best:
                        best = cand
            if best < emc.get(out, INF):
                emc[out] = best
                changed += 1
        if changed == 0:
            break

    priced = {k: v for k, v in emc.items() if v != INF}
    lines = [f"{k} {v:.2f}" for k, v in sorted(priced.items())]
    (DATA / "emc.txt").write_text("\n".join(lines), encoding="utf-8")

    print(f"priced {len(priced)} / {len(items)} items")
    for probe in ["minecraft:iron_ingot", "minecraft:iron_block", "minecraft:diamond",
                  "minecraft:piston", "minecraft:chest", "minecraft:hopper",
                  "minecraft:crafting_table", "minecraft:stick", "minecraft:torch",
                  "minecraft:furnace"]:
        v = priced.get(probe)
        print(f"  {probe:34s} {v if v is not None else 'unpriced'}")


if __name__ == "__main__":
    main()
