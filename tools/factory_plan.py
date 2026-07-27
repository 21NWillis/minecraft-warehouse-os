#!/usr/bin/env python3
"""Recursive bill-of-materials planner for a target set of machines/blocks.

Reads BOTH grid-crafting recipes and machine recipes (Mekanism/Create/AE2/...)
directly from the mod jars, then expands each target down to raw materials,
tagging every intermediate by HOW it is produced (hand-craft vs a specific
machine). Machine-produced nodes are the automation targets. Emits a
human-chaseable checklist: factory_plan.md.
"""
import json
import zipfile
from collections import defaultdict
from pathlib import Path

MODS = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/mods")
DATA = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/cc-scripts/data")
OUT = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/cc-scripts/planning/factory_plan.md")

# raw materials: the leaves of the tree. You mine/smelt/gather these (or the
# iron foundry outputs them). Never expanded further.
BASE = {
    "minecraft:iron_ingot", "minecraft:gold_ingot", "minecraft:copper_ingot",
    "minecraft:redstone", "minecraft:coal", "minecraft:charcoal",
    "minecraft:diamond", "minecraft:emerald", "minecraft:lapis_lazuli",
    "minecraft:quartz", "minecraft:glowstone_dust", "minecraft:glass",
    "minecraft:sand", "minecraft:gravel", "minecraft:flint", "minecraft:clay_ball",
    "minecraft:stone", "minecraft:cobblestone", "minecraft:deepslate",
    "minecraft:dirt", "minecraft:obsidian", "minecraft:string", "minecraft:leather",
    "minecraft:gunpowder", "minecraft:blaze_rod", "minecraft:blaze_powder",
    "minecraft:ender_pearl", "minecraft:bone", "minecraft:slime_ball",
    "minecraft:water_bucket", "minecraft:lava_bucket", "minecraft:bucket",
    "mekanism:ingot_osmium", "mekanism:ingot_tin", "mekanism:ingot_lead",
    "mekanism:ingot_uranium", "mekanism:fluorite_gem", "mekanism:salt",
    "minecraft:oak_log", "minecraft:oak_planks", "minecraft:stick",
    "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
    "create:andesite_alloy",  # cheap create base; treat as raw to keep tree sane
    "createmetallurgy:steel_ingot",  # own production chain; leaf for this plan
}

MACHINE_TYPES = {
    "mekanism:enriching": "Enrichment Chamber",
    "mekanism:crushing": "Crusher",
    "mekanism:smelting": "Energized Smelter",
    "mekanism:combining": "Combiner",
    "mekanism:purifying": "Purification Chamber",
    "mekanism:injecting": "Chemical Injection Chamber",
    "mekanism:metallurgic_infusing": "Metallurgic Infuser",
    "mekanism:compressing": "Osmium Compressor",
    "create:crushing": "Crushing Wheels",
    "create:milling": "Millstone",
    "create:pressing": "Mechanical Press",
    "create:mixing": "Mechanical Mixer",
    "create:item_application": "Manual/Deployer Application",
    "create:deploying": "Deployer",
    "create:filling": "Spout",
    "create:compacting": "Mechanical Press (compacting)",
    "appliedenergistics2:inscriber": "Inscriber",
    "mekanism:sawing": "Precision Sawmill",
}


def norm(s):
    return s if ":" in s else "minecraft:" + s


def load_tags():
    tags = {}
    for line in (DATA / "tags.txt").read_text(encoding="utf-8").splitlines():
        if line:
            parts = line.split("|")
            tags[parts[0][1:]] = parts[1:]
    return tags


def load_names():
    names = {}
    for line in (DATA / "names.txt").read_text(encoding="utf-8").splitlines():
        if "\t" in line:
            i, n = line.split("\t", 1)
            names[i] = n
    return names


def load_grid():
    grid = defaultdict(list)  # output -> list of (count, [ingredient tokens])
    for line in (DATA / "recipes.txt").read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        p = line.split("|")
        out, cnt = p[1], int(p[2])
        ings = [x for x in p[3:] if x]
        grid[out].append((cnt, ings))
    return grid


def ing_token(obj):
    """Normalize a machine-recipe input object to an item id or #tag, or None."""
    if obj is None:
        return None
    if isinstance(obj, str):
        return norm(obj)
    if isinstance(obj, dict):
        if "item" in obj:
            return norm(obj["item"])
        if "id" in obj:
            return norm(obj["id"])
        if "tag" in obj:
            return "#" + norm(obj["tag"])
    return None


def result_id(obj):
    if isinstance(obj, str):
        return norm(obj), 1
    if isinstance(obj, dict):
        rid = obj.get("id") or obj.get("item")
        if isinstance(rid, dict):
            rid = rid.get("id")
        return (norm(rid), int(obj.get("count", 1))) if rid else (None, 0)
    return None, 0


def load_machine():
    """output id -> list of {machine, count, inputs:[(token,count)], chemicals:[str]}"""
    machine = defaultdict(list)
    for jar in sorted(MODS.glob("*.jar")):
        try:
            z = zipfile.ZipFile(jar)
        except Exception:
            continue
        for n in z.namelist():
            p = n.split("/")
            if not (len(p) >= 4 and p[0] == "data" and p[2] in ("recipe", "recipes") and n.endswith(".json")):
                continue
            try:
                r = json.loads(z.read(n))
            except Exception:
                continue
            t = r.get("type")
            if t not in MACHINE_TYPES:
                continue
            # output
            out, cnt = None, 1
            if "output" in r:
                out, cnt = result_id(r["output"])
            elif "results" in r and r["results"]:
                # first non-byproduct (chance missing or == 1) result
                primary = next((x for x in r["results"] if x.get("chance", 1) >= 1), r["results"][0])
                out, cnt = result_id(primary)
            if not out:
                continue
            # item inputs (chemicals noted separately)
            inputs, chems = [], []
            for k in ("input", "main_input", "item_input", "extra_input"):
                if k in r:
                    tok = ing_token(r[k])
                    if tok:
                        c = r[k].get("count", 1) if isinstance(r[k], dict) else 1
                        inputs.append((tok, c))
            if "ingredients" in r:
                for ing in r["ingredients"]:
                    tok = ing_token(ing)
                    if tok:
                        inputs.append((tok, ing.get("count", 1) if isinstance(ing, dict) else 1))
            for k in ("chemical_input", "chemicalInput"):
                if k in r and isinstance(r[k], dict):
                    ch = r[k].get("chemical") or r[k].get("tag") or "chemical"
                    chems.append(ch.split(":")[-1])
            machine[out].append({"machine": MACHINE_TYPES[t], "count": cnt,
                                 "inputs": inputs, "chemicals": chems})
    return machine


class Planner:
    def __init__(self):
        self.tags = load_tags()
        self.names = load_names()
        self.grid = load_grid()
        self.machine = load_machine()
        self.raw = defaultdict(float)          # base material -> qty
        self.crafted = defaultdict(float)      # grid intermediate -> qty
        self.produced = defaultdict(float)     # machine output -> qty
        self.method = {}                       # item -> ("grid"|machine name)
        self.chem_needed = set()
        self.unresolved = defaultdict(float)

    def name(self, i):
        i = i.lstrip("#")
        return self.names.get(i, i.split(":")[-1].replace("_", " ").title())

    def options(self, tok):
        if tok.startswith("#"):
            return self.tags.get(tok[1:], [])
        return [tok]

    def pick(self, tok):
        opts = self.options(tok)
        if not opts:
            return None
        # prefer a base material, then a minecraft item, then anything craftable
        for o in opts:
            if o in BASE:
                return o
        for o in opts:
            if o.startswith("minecraft:"):
                return o
        for o in opts:
            if o in self.grid or o in self.machine:
                return o
        return opts[0]

    def grid_recipe(self, item):
        rs = self.grid.get(item)
        if not rs:
            return None
        # fewest distinct ingredients = simplest; deterministic
        return min(rs, key=lambda r: len(set(r[1])))

    def expand(self, item, qty, path):
        item = self.pick(item) if item.startswith("#") else item
        if item is None:
            return
        if item in BASE:
            self.raw[item] += qty
            return
        if item in path:  # cycle guard
            self.raw[item] += qty
            return
        gr = self.grid_recipe(item)
        mr = self.machine.get(item)
        if gr and not (mr and item.endswith(("_dust", "_ingot")) and item not in self.grid):
            cnt, ings = gr
            batches = qty / cnt
            self.crafted[item] += qty
            self.method[item] = "grid"
            need = defaultdict(float)
            for tok in ings:
                need[tok] += batches
            for tok, b in need.items():
                self.expand(tok, b, path | {item})
        elif mr:
            m = mr[0]
            batches = qty / m["count"]
            self.produced[item] += qty
            self.method[item] = m["machine"]
            for ch in m["chemicals"]:
                self.chem_needed.add(ch)
            for tok, c in m["inputs"]:
                self.expand(tok, batches * c, path | {item})
        else:
            self.unresolved[item] += qty

    def plan(self, targets):
        for item, qty in targets.items():
            self.expand(item, qty, frozenset())


def main():
    p = Planner()
    # ---- the target: an iron foundry + a starter "datacenter" of machines ----
    targets = {
        # iron foundry core (Mekanism ore doubling + smelting)
        "mekanism:enrichment_chamber": 2,
        "mekanism:energized_smelter": 2,
        "mekanism:metallurgic_infuser": 1,
        "mekanism:crusher": 1,
        # power + transport
        "mekanism:basic_energy_cube": 2,
        "mekanism:basic_universal_cable": 16,
        # create assist
        "create:mechanical_press": 1,
        "create:depot": 2,
        # storage / the "datacenter"
        "mekanism:basic_bin": 4,
        "mekanism:steel_casing": 4,
    }
    p.plan(targets)

    lines = []
    W = lines.append
    W("# Factory Plan — Iron Foundry + Starter Datacenter\n")
    W("Recursive bill of materials. Chase the numbers top-down: raw materials")
    W("are what you mine/smelt; machine outputs are what you must **automate**.\n")

    W("## Target machines (the datacenter)\n")
    for item, qty in sorted(targets.items()):
        tag = "" if (item in p.grid or item in p.machine) else "  ⚠ recipe not found — verify id"
        W(f"- [ ] {qty}× **{p.name(item)}** (`{item}`){tag}")
    W("")

    W("## Raw materials to gather / mine  (the shopping list)\n")
    for item, qty in sorted(p.raw.items(), key=lambda kv: -kv[1]):
        flag = "  🏭 **automate production**" if qty >= 64 else ""
        W(f"- [ ] {int(round(qty))}× {p.name(item)} (`{item}`){flag}")
    W("")

    if p.produced:
        W("## Machine-made intermediates  (build these machines first)\n")
        by_machine = defaultdict(list)
        for item, qty in p.produced.items():
            by_machine[p.method[item]].append((item, qty))
        for mach, items in sorted(by_machine.items()):
            W(f"### {mach}")
            for item, qty in sorted(items, key=lambda kv: -kv[1]):
                W(f"- [ ] {int(round(qty))}× {p.name(item)} (`{item}`)")
            W("")

    if p.chem_needed:
        W("## Chemicals/gases required (Mekanism infrastructure)\n")
        W("These need their own production (electrolyzer, etc.): "
          + ", ".join(sorted(p.chem_needed)) + "\n")

    W("## Hand-crafted intermediates\n")
    for item, qty in sorted(p.crafted.items(), key=lambda kv: -kv[1]):
        if item not in targets:
            W(f"- [ ] {int(round(qty))}× {p.name(item)} (`{item}`)")
    W("")

    if p.unresolved:
        W("## ⚠ Unresolved (no grid or machine recipe found — likely raw, or check id)\n")
        for item, qty in sorted(p.unresolved.items(), key=lambda kv: -kv[1]):
            W(f"- {int(round(qty))}× {p.name(item)} (`{item}`)")
        W("")

    W("## Automation recommendations\n")
    heavy = [(i, q) for i, q in p.raw.items() if q >= 64]
    if heavy:
        W("- **Bulk raw materials** (≥64) worth an automated source "
          "(Digital Miner / laser drill / Create farm):")
        for i, q in sorted(heavy, key=lambda kv: -kv[1]):
            W(f"  - {int(round(q))}× {p.name(i)}")
    machines_used = sorted(set(p.method[i] for i in p.produced))
    if machines_used:
        W(f"- **Bootstrap order**: build these machines first, since other "
          f"targets depend on their output — {', '.join(machines_used)}.")
        W("  Note the chicken-and-egg: the first control circuits / infused "
          "alloys are made by hand in the Metallurgic Infuser before you can "
          "automate the chain.")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT}")
    print(f"raw={len(p.raw)} crafted={len(p.crafted)} machine={len(p.produced)} "
          f"unresolved={len(p.unresolved)}")


if __name__ == "__main__":
    main()
