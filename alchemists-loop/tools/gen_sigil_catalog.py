#!/usr/bin/env python3
"""Генератор каталога карт «Аркана Сигилов» (подпроект A).

Читает игровые данные клиента и детерминированно раскладывает 100 карт по
4 комплектам стихий. Пишет discovery-server/server/data/sigil_catalog.json —
закоммиченный артефакт, который сервер раздаёт через GET /api/sigil/catalog.

    python tools/gen_sigil_catalog.py             # записать каталог
    python tools/gen_sigil_catalog.py --check     # сверить, exit 1 при дрейфе
    python tools/gen_sigil_catalog.py --out P     # записать в P (тесты)

Раскладка (ruling R1 плана подпроекта A):
  * категория предмета = CATEGORY_OF с подъёмом по цепочке "g";
  * комплект Земли = 25 самых мелких по слою «земля»;
  * (всего предметов - 100) самых глубоких «земля» исключаются из каталога;
  * оставшаяся «земля» раздаётся огню/воде/воздуху по близости к предкам
    (вес 0.5**(dist-1)), порядок fire -> water -> air;
  * редкость внутри комплекта — по глубине: 12 common, 7 rare, 4 epic,
    2 legendary (R2);
  * seed карты = sha256("sigil-card#<id>")[:12] — без соли игрока (R5),
    поэтому картинка карты одинакова у всех игроков.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
CLIENT_DIR = TOOLS_DIR.parent
REPO_DIR = CLIENT_DIR.parent
MAIN_GD = CLIENT_DIR / "main.gd"
MODES_GD = CLIENT_DIR / "game" / "data" / "modes.gd"
CATALOG_PATH = REPO_DIR / "discovery-server" / "server" / "data" / "sigil_catalog.json"

SET_ORDER = ["fire", "water", "air", "earth"]
SET_SIZE = 25
CAT_TO_SET = {"огонь": "fire", "вода": "water", "воздух": "air", "земля": "earth"}
SET_TO_CAT = {v: k for k, v in CAT_TO_SET.items()}
BASE_ORDER = ["fire", "water", "earth", "air"]

# 12 + 7 + 4 + 2 = 25 (R2). Порядок — от глубоких к мелким.
RARITY_PLAN = [("legendary", 2), ("epic", 4), ("rare", 7), ("common", 12)]
ETHER_BY_RARITY = {"common": 50, "rare": 150, "epic": 400, "legendary": 800}
QTY_BY_RARITY = {
    "common": (6, 14), "rare": (8, 20), "epic": (12, 30), "legendary": (18, 45),
}
# -1 = «3 или 4 по seed % 2» (R4)
INGREDIENTS_BY_RARITY = {"common": 3, "rare": 3, "epic": -1, "legendary": 4}
STAGE_BY_RARITY = {
    "common": "nigredo", "rare": "albedo",
    "epic": "citrinitas", "legendary": "rubedo",
}
# Список для citrinitas — допущение генератора (R3): lore-спека §6 его не
# определяет. Подпроект C сверяет пары process/stage со своей таблицей.
PROCESS_BY_STAGE = {
    "nigredo": ["calcinatio", "putrefactio", "distillatio"],
    "albedo": ["distillatio", "sublimatio", "coniunctio"],
    "citrinitas": ["sublimatio", "coniunctio", "distillatio"],
    "rubedo": ["coniunctio", "calcinatio", "sublimatio"],
}
OBJECT_TYPES = ["object", "abstraction", "planet", "creature", "relic"]
SEED_PREFIX = "sigil-card#"
SEED_HEX = 12       # 48 бит
VERSION_HEX = 16

_ITEM_LINE = re.compile(r'^\t"([a-z_]+)":\s*\{(.*)\},?\s*$')
_RECIPE_LINE = re.compile(
    r'^\t\{"a":\s*"([a-z_]+)",\s*"b":\s*"([a-z_]+)",\s*"out":\s*"([a-z_]+)"\},?\s*$'
)
_PAIR = re.compile(r'"([a-z_]+)":\s*"([^"]+)"')
_NAME = re.compile(r'"name":\s*"([^"]+)"')
_PARENT = re.compile(r'"g":\s*"([a-z_]+)"')
_SET_ENTRY = re.compile(r'\{"cat":\s*"([^"]+)",\s*"title":\s*"([^"]+)"')


def _block(text: str, start: str, end: str) -> str:
    """Тело литерала между `start` и первой отдельной строкой `end`."""
    i = text.index(start)
    j = text.index("\n" + end, i)
    return text[i + len(start):j]


def parse_items(path: Path) -> dict:
    block = _block(path.read_text(encoding="utf-8"), "var ITEMS := {", "}")
    out: dict = {}
    for line in block.splitlines():
        m = _ITEM_LINE.match(line)
        if not m:
            continue
        body = m.group(2)
        name_m = _NAME.search(body)
        if not name_m:
            raise SystemExit(f"ITEMS: у «{m.group(1)}» нет поля name")
        par_m = _PARENT.search(body)
        out[m.group(1)] = {
            "name": name_m.group(1),
            "parent": par_m.group(1) if par_m else "",
        }
    if len(out) < len(SET_ORDER) * SET_SIZE:
        raise SystemExit(
            f"ITEMS: нужно минимум {len(SET_ORDER) * SET_SIZE}, найдено {len(out)}")
    return out


def parse_recipes(path: Path) -> list:
    block = _block(path.read_text(encoding="utf-8"), "var RECIPES := [", "]")
    out: list = []
    for line in block.splitlines():
        m = _RECIPE_LINE.match(line)
        if m:
            out.append((m.group(1), m.group(2), m.group(3)))
    if not out:
        raise SystemExit("RECIPES: не разобрано ни одного рецепта")
    return out


def parse_categories(path: Path) -> dict:
    block = _block(path.read_text(encoding="utf-8"), "const CATEGORY_OF := {", "}")
    return {k: v for k, v in _PAIR.findall(block)}


def parse_set_titles(path: Path) -> dict:
    block = _block(path.read_text(encoding="utf-8"), "const CATEGORY_SETS := [", "]")
    return {cat: title for cat, title in _SET_ENTRY.findall(block)}


def compute_layers(item_ids: list, producers: dict) -> dict:
    """Слой = 0 для первостихий, иначе 1 + max(слои ингредиентов)."""
    layers: dict = {}

    def depth(i: str, stack: tuple) -> int:
        if i in layers:
            return layers[i]
        if i in stack:
            return 0
        pairs = producers.get(i)
        if not pairs:
            layers[i] = 0
            return 0
        d = 1 + max(
            max(depth(a, stack + (i,)), depth(b, stack + (i,))) for a, b in pairs
        )
        layers[i] = d
        return d

    for i in item_ids:
        depth(i, ())
    return layers


def resolve_categories(item_ids: list, parents: dict, cat_of: dict) -> dict:
    """Категория предмета: своя либо ближайшего предка по цепочке "g"."""
    out: dict = {}
    for i in item_ids:
        cur = i
        seen: set = set()
        cat = ""
        while cur and cur not in seen:
            seen.add(cur)
            if cur in cat_of:
                cat = cat_of[cur]
                break
            cur = parents.get(cur, "")
        if cat not in CAT_TO_SET:
            raise SystemExit(f"не удалось определить категорию «{i}»")
        out[i] = cat
    return out


def ancestors(item_id: str, producers: dict) -> set:
    out: set = set()
    stack = [p for pair in producers.get(item_id, []) for p in pair]
    while stack:
        cur = stack.pop()
        if cur in out or cur == item_id:
            continue
        out.add(cur)
        stack.extend(p for pair in producers.get(cur, []) for p in pair)
    return out


def affinity_weights(item_id: str, producers: dict, cats: dict) -> dict:
    """Близость к категориям: чем ближе предок, тем больше вес (0.5**(dist-1))."""
    w: dict = {}
    visited = {item_id}
    frontier = [p for pair in producers.get(item_id, []) for p in pair]
    dist = 1
    while frontier:
        nxt: list = []
        for p in frontier:
            if p in visited:
                continue
            visited.add(p)
            cat = cats.get(p, "")
            if cat:
                w[cat] = w.get(cat, 0.0) + 0.5 ** (dist - 1)
            nxt.extend(q for pair in producers.get(p, []) for q in pair)
        frontier = nxt
        dist += 1
    return w


def assign_sets(item_ids: list, producers: dict, layers: dict, cats: dict) -> tuple:
    exclude_count = len(item_ids) - len(SET_ORDER) * SET_SIZE
    if exclude_count < 0:
        raise SystemExit(
            f"предметов {len(item_ids)} — меньше каталога на {abs(exclude_count)}")

    def by_depth(i: str) -> tuple:
        return (layers.get(i, 0), i)

    earth_all = sorted((i for i in item_ids if cats[i] == "земля"), key=by_depth)
    if len(earth_all) - SET_SIZE < exclude_count:
        raise SystemExit(
            f"«земля» даёт {len(earth_all) - SET_SIZE} излишка, нужно {exclude_count}")
    sets: dict = {"earth": earth_all[:SET_SIZE]}
    excluded = earth_all[len(earth_all) - exclude_count:] if exclude_count else []
    skip = set(excluded)
    pool = [i for i in earth_all[SET_SIZE:] if i not in skip]

    weights = {i: affinity_weights(i, producers, cats) for i in pool}
    for s in ("fire", "water", "air"):
        members = sorted((i for i in item_ids if cats[i] == SET_TO_CAT[s]), key=by_depth)
        if len(members) > SET_SIZE:
            raise SystemExit(f"{s}: своих предметов {len(members)} > {SET_SIZE}")
        cat = SET_TO_CAT[s]
        while len(members) < SET_SIZE:
            if not pool:
                raise SystemExit(f"{s}: не хватило заимствованных карт")
            pool.sort(key=lambda i: (-weights[i].get(cat, 0.0), -layers.get(i, 0), i))
            members.append(pool.pop(0))
        sets[s] = members
    if pool:
        raise SystemExit(f"осталось {len(pool)} нераспределённых заимствований")
    return sets, sorted(excluded)


def assign_rarities(members: list, layers: dict) -> dict:
    """12 мелких common … 2 самых глубоких legendary (R2)."""
    ordered = sorted(members, key=lambda i: (layers.get(i, 0), i))
    out: dict = {}
    cursor = 0
    for rarity, count in reversed(RARITY_PLAN):
        for i in ordered[cursor:cursor + count]:
            out[i] = rarity
        cursor += count
    if cursor != len(ordered):
        raise SystemExit(f"раскладка редкостей покрыла {cursor} из {len(ordered)}")
    return out


def ingredients_for(item_id: str, n: int, producers: dict, layers: dict, items: dict) -> list:
    """Ближайшие предки по графу; не хватает — добираем первостихиями (R4)."""
    anc = sorted(ancestors(item_id, producers), key=lambda x: (-layers.get(x, 0), x))
    picked = anc[:n]
    for base in BASE_ORDER:
        if len(picked) >= n:
            break
        if base != item_id and base not in picked:
            picked.append(base)
    picked = picked[:n]
    if len(picked) != n:
        raise SystemExit(f"«{item_id}»: не набралось {n} ингредиентов")
    for iid in picked:
        if iid not in items:
            raise SystemExit(f"«{item_id}»: ингредиент «{iid}» не найден в ITEMS")
    return picked


def card_seed(item_id: str) -> int:
    return int(
        hashlib.sha256((SEED_PREFIX + item_id).encode("utf-8")).hexdigest()[:SEED_HEX], 16)


def build_card(item_id: str, set_id: str, rarity: str, name: str, seed: int,
               producers: dict, layers: dict, items: dict) -> dict:
    n = INGREDIENTS_BY_RARITY[rarity]
    if n < 0:
        n = 3 if seed % 2 == 0 else 4
    stage = STAGE_BY_RARITY[rarity]
    processes = PROCESS_BY_STAGE[stage]
    rng = random.Random(seed)
    lo, hi = QTY_BY_RARITY[rarity]
    return {
        "ether_cost": ETHER_BY_RARITY[rarity],
        "fallback_name": name,
        "id": item_id,
        "object_type": OBJECT_TYPES[seed % len(OBJECT_TYPES)],
        "process": processes[seed % len(processes)],
        "rarity": rarity,
        "recipe": [
            {"item_id": iid, "qty": rng.randint(lo, hi)}
            for iid in ingredients_for(item_id, n, producers, layers, items)
        ],
        "seed": seed,
        "set": set_id,
        "stage": stage,
    }


def catalog_version(cards: list) -> str:
    blob = json.dumps(cards, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:VERSION_HEX]


def check_invariants(catalog: dict, excluded: list, items: dict) -> None:
    cards = catalog["cards"]
    if len(cards) != len(SET_ORDER) * SET_SIZE:
        raise SystemExit(f"карт {len(cards)}, нужно {len(SET_ORDER) * SET_SIZE}")
    ids = [c["id"] for c in cards]
    if len(set(ids)) != len(ids):
        raise SystemExit("в каталоге есть дубли card id")
    if set(ids) & set(excluded):
        raise SystemExit("исключённый предмет попал в каталог")
    by_id = {c["id"]: c for c in cards}
    want = dict(RARITY_PLAN)
    for s in catalog["sets"]:
        if len(s["card_ids"]) != SET_SIZE:
            raise SystemExit(
                f"в комплекте {s['id']} {len(s['card_ids'])} карт, нужно {SET_SIZE}")
        counts: dict = {}
        for cid in s["card_ids"]:
            card = by_id[cid]
            if card["set"] != s["id"]:
                raise SystemExit(f"карта «{cid}» приписана не к своему комплекту")
            counts[card["rarity"]] = counts.get(card["rarity"], 0) + 1
        if counts != want:
            raise SystemExit(f"комплект {s['id']}: редкости {counts}, нужно {want}")
    for iid in ids:
        if iid not in items:
            raise SystemExit(f"карта «{iid}» отсутствует в ITEMS")
        card = by_id[iid]
        if card["stage"] != STAGE_BY_RARITY[card["rarity"]]:
            raise SystemExit(f"«{iid}»: stage не соответствует rarity")
        if card["ether_cost"] != ETHER_BY_RARITY[card["rarity"]]:
            raise SystemExit(f"«{iid}»: ether_cost не соответствует rarity")
        if not 0 < card["seed"] < 2 ** 48:
            raise SystemExit(f"«{iid}»: seed вне 48 бит")
        if not 3 <= len(card["recipe"]) <= 4:
            raise SystemExit(f"«{iid}»: ингредиентов {len(card['recipe'])}, нужно 3..4")
        seen: set = set()
        for ing in card["recipe"]:
            if ing["item_id"] in seen or ing["item_id"] == iid:
                raise SystemExit(f"«{iid}»: некорректный набор ингредиентов")
            seen.add(ing["item_id"])
            if ing["item_id"] not in items:
                raise SystemExit(f"«{iid}»: ингредиент «{ing['item_id']}» не в ITEMS")
            lo, hi = QTY_BY_RARITY[card["rarity"]]
            if not lo <= ing["qty"] <= hi:
                raise SystemExit(f"«{iid}»: qty {ing['qty']} вне {lo}..{hi}")


def build_catalog() -> dict:
    items = parse_items(MAIN_GD)
    recipes = parse_recipes(MAIN_GD)
    cat_of = parse_categories(MODES_GD)
    titles = parse_set_titles(MODES_GD)
    for cat in CAT_TO_SET:
        if cat not in titles:
            raise SystemExit(f"CATEGORY_SETS: нет заголовка для «{cat}»")
    item_ids = sorted(items)
    parents = {i: d["parent"] for i, d in items.items() if d["parent"]}
    producers: dict = {}
    for a, b, out in recipes:
        producers.setdefault(out, []).append((a, b))
    layers = compute_layers(item_ids, producers)
    cats = resolve_categories(item_ids, parents, cat_of)
    sets, excluded = assign_sets(item_ids, producers, layers, cats)

    cards: list = []
    set_entries: list = []
    for set_id in SET_ORDER:
        members = sets[set_id]
        rarities = assign_rarities(members, layers)
        for iid in members:
            cards.append(build_card(
                iid, set_id, rarities[iid], items[iid]["name"], card_seed(iid),
                producers, layers, items))
        ordered = sorted(members, key=lambda i: (layers.get(i, 0), i))
        set_entries.append({
            "card_ids": ordered,
            "id": set_id,
            "title": titles[SET_TO_CAT[set_id]],
        })
    cards.sort(key=lambda c: c["id"])
    catalog = {
        "cards": cards,
        "excluded": excluded,
        "sets": set_entries,
        "version": catalog_version(cards),
    }
    check_invariants(catalog, excluded, items)
    return catalog


def render(catalog: dict) -> str:
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Генератор каталога карт Аркана Сигилов.")
    ap.add_argument("--check", action="store_true", help="сверить файл, не записывая")
    ap.add_argument("--out", default=str(CATALOG_PATH), help="куда писать JSON")
    args = ap.parse_args(argv)
    catalog = build_catalog()
    text = render(catalog)
    out = Path(args.out)
    if args.check:
        current = out.read_text(encoding="utf-8") if out.exists() else ""
        if current != text:
            print(f"DRIFT: {out} не совпадает с выводом генератора", file=sys.stderr)
            return 1
        print(f"OK: {out} — {len(catalog['cards'])} карт, version={catalog['version']}")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    print(f"WROTE: {out} — {len(catalog['cards'])} карт, version={catalog['version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
