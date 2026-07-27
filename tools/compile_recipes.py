#!/usr/bin/env python3
"""Compile crafting recipes, item tags, and display names from mod jars
into compact text files for the ComputerCraft warehouse system.

Output (to cc-scripts/data/):
  recipes.txt  S|output|count|i1|...|i9  (shaped, row-major 3x3, '' = empty)
               L|output|count|i1|...|iN  (shapeless)
               ingredients: item id, #tag, or opt1;opt2 alternatives
  tags.txt     #tag|item1|item2|...      (transitively resolved, used tags only)
  names.txt    id<TAB>Display Name       (from en_us lang files)
"""
import json
import sys
import zipfile
from pathlib import Path

MODS_DIR = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/mods")
OUT_DIR = Path("/mnt/d/corge/Instances/The Neutral Pack that does nothing/cc-scripts/data")

SHAPED_TYPES = {"minecraft:crafting_shaped", "crafting_shaped"}
SHAPELESS_TYPES = {"minecraft:crafting_shapeless", "crafting_shapeless"}


def norm_id(s):
    return s if ":" in s else "minecraft:" + s


def parse_ingredient(ing):
    """Return item id, '#tag', 'a;b;c' alternatives, or None."""
    if ing is None:
        return None
    if isinstance(ing, str):
        return "#" + norm_id(ing[1:]) if ing.startswith("#") else norm_id(ing)
    if isinstance(ing, list):
        opts = [parse_ingredient(o) for o in ing]
        opts = [o for o in opts if o]
        if not opts:
            return None
        return opts[0] if len(opts) == 1 else ";".join(opts)
    if isinstance(ing, dict):
        if "item" in ing:
            return norm_id(ing["item"])
        if "id" in ing:
            return norm_id(ing["id"])
        if "tag" in ing:
            return "#" + norm_id(ing["tag"])
    return None


def parse_result(res):
    if isinstance(res, str):
        return norm_id(res), 1
    if isinstance(res, dict):
        item = res.get("id") or res.get("item")
        if isinstance(item, dict):
            item = item.get("id")
        if item:
            return norm_id(item), int(res.get("count", 1))
    return None, 0


def parse_recipe(r):
    t = r.get("type")
    if t in SHAPED_TYPES:
        out, count = parse_result(r.get("result"))
        if not out:
            return None
        pattern = r.get("pattern", [])
        key = {k: parse_ingredient(v) for k, v in r.get("key", {}).items()}
        grid = [""] * 9
        for row_i, row in enumerate(pattern[:3]):
            for col_i, ch in enumerate(row[:3]):
                if ch != " ":
                    ing = key.get(ch)
                    if ing is None:
                        return None
                    grid[row_i * 3 + col_i] = ing
        return "|".join(["S", out, str(count)] + grid)
    if t in SHAPELESS_TYPES:
        out, count = parse_result(r.get("result"))
        if not out:
            return None
        ings = [parse_ingredient(i) for i in r.get("ingredients", [])]
        if not ings or any(i is None for i in ings) or len(ings) > 9:
            return None
        return "|".join(["L", out, str(count)] + ings)
    return None


def main():
    recipes = set()
    raw_tags = {}       # tag id -> list of values (may reference other tags)
    names = {}

    jars = sorted(MODS_DIR.glob("*.jar"))
    for jar in jars:
        try:
            z = zipfile.ZipFile(jar)
        except Exception:
            continue
        for n in z.namelist():
            parts = n.split("/")
            if not n.endswith(".json") or len(parts) < 4:
                continue
            if parts[0] == "data" and parts[2] in ("recipe", "recipes"):
                try:
                    line = parse_recipe(json.loads(z.read(n)))
                except Exception:
                    continue
                if line:
                    recipes.add(line)
            elif parts[0] == "data" and parts[2] == "tags" and parts[3] in ("item", "items"):
                tag_id = parts[1] + ":" + "/".join(parts[4:])[:-5]
                try:
                    data = json.loads(z.read(n))
                except Exception:
                    continue
                bucket = raw_tags.setdefault(tag_id, [])
                if data.get("replace"):
                    bucket.clear()
                for v in data.get("values", []):
                    if isinstance(v, dict):
                        v = v.get("id")
                    if isinstance(v, str):
                        bucket.append(v)
            elif parts[0] == "assets" and len(parts) == 4 and parts[2] == "lang" and parts[3] == "en_us.json":
                ns = parts[1]
                try:
                    lang = json.loads(z.read(n))
                except Exception:
                    continue
                for k, v in lang.items():
                    if not isinstance(v, str) or "%" in v:
                        continue
                    bits = k.split(".")
                    if len(bits) == 3 and bits[0] in ("item", "block"):
                        item_id = bits[1] + ":" + bits[2]
                        if bits[0] == "item" or item_id not in names:
                            names[item_id] = v

    def resolve_tag(tag, stack=None):
        stack = stack or set()
        if tag in stack:
            return []
        stack.add(tag)
        out = []
        for v in raw_tags.get(tag, []):
            if v.startswith("#"):
                out.extend(resolve_tag(norm_id(v[1:]), stack))
            else:
                out.append(norm_id(v))
        seen, uniq = set(), []
        for i in out:
            if i not in seen:
                seen.add(i)
                uniq.append(i)
        return uniq

    used_tags = set()
    for line in recipes:
        for field in line.split("|")[3:]:
            for opt in field.split(";"):
                if opt.startswith("#"):
                    used_tags.add(opt[1:])

    resolved = {}
    for tag in sorted(used_tags):
        items = resolve_tag(tag)
        items.sort(key=lambda i: (not i.startswith("minecraft:"), i))
        resolved[tag] = items

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    recipes_sorted = sorted(recipes, key=lambda l: l.split("|")[1])
    (OUT_DIR / "recipes.txt").write_text("\n".join(recipes_sorted), encoding="utf-8")
    (OUT_DIR / "tags.txt").write_text(
        "\n".join("#" + t + "|" + "|".join(items) for t, items in resolved.items()),
        encoding="utf-8")
    (OUT_DIR / "names.txt").write_text(
        "\n".join(f"{k}\t{v}" for k, v in sorted(names.items())), encoding="utf-8")

    outputs = {l.split("|")[1] for l in recipes}
    empty = sum(1 for items in resolved.values() if not items)
    for f in ("recipes.txt", "tags.txt", "names.txt"):
        size = (OUT_DIR / f).stat().st_size
        print(f"{f}: {size/1024:.0f} KB")
    print(f"{len(recipes)} recipes, {len(outputs)} distinct craftable items")
    print(f"{len(resolved)} tags used ({empty} resolved empty), {len(names)} display names")


if __name__ == "__main__":
    main()
