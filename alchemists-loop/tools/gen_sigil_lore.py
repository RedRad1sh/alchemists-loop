#!/usr/bin/env python3
"""Генератор lore-данных «Аркана Сигилов» (подпроект C).

Пишет закоммиченные артефакты в alchemists-loop/game/sigil/data/lore/:
  * elements.json — падежная таблица элементов (100 карт каталога +
    алхимические mercury/sulfur/salt/lead);
  * actions/conditions/results/symbols/warnings/titles/effects.json —
    7 слотов фрагментов (>=100 в каждом) для детерминированного
    lore-генератора описаний карт.

    python tools/gen_sigil_lore.py elements --check   # сверить таблицу
    python tools/gen_sigil_lore.py fragments --check  # сверить слоты
    python tools/gen_sigil_lore.py elements           # записать таблицу
    python tools/gen_sigil_lore.py fragments          # записать слоты

Движок (game/sigil/lore.gd, Task 3) читает JSON через SigilAssets.json_file
по требованию; инструмент — только для генерации/сверки артефактов.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
CLIENT_DIR = TOOLS_DIR.parent
REPO_DIR = CLIENT_DIR.parent
CATALOG_PATH = REPO_DIR / "discovery-server" / "server" / "data" / "sigil_catalog.json"
DATA_DIR = CLIENT_DIR / "game" / "sigil" / "data" / "lore"
ELEMENTS_PATH = DATA_DIR / "elements.json"

CASES = ["name", "gen", "dat", "acc", "ins", "prep", "adj"]
ALCHEMY_IDS = ["mercury", "sulfur", "salt", "lead"]


def catalog_card_ids() -> set:
    """Все 100 card_id из каталога сервера (источник правды)."""
    if not CATALOG_PATH.exists():
        raise SystemExit(f"каталог не найден: {CATALOG_PATH}")
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    return {str(c["id"]) for c in catalog["cards"]}


def load_elements(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("elements"), dict):
        raise SystemExit(f"{path}: ожидался объект {{version, elements}}")
    return data["elements"]


def check_elements(path: Path) -> int:
    """Сверка elements.json с каталогом и схемой. 0 — зелёно, 1 — дрейф."""
    want_ids = catalog_card_ids() | set(ALCHEMY_IDS)
    elems = load_elements(path)
    problems: list = []

    missing = sorted(want_ids - set(elems))
    if missing:
        problems.append(f"нет элементов: {', '.join(missing)}")
    for eid in sorted(set(elems) - want_ids):
        problems.append(f"лишний элемент: {eid}")
    for eid in sorted(want_ids & set(elems)):
        entry = elems[eid]
        if not isinstance(entry, dict):
            problems.append(f"{eid}: не объект")
            continue
        for case in CASES:
            val = entry.get(case, "")
            if not isinstance(val, str) or not val.strip():
                problems.append(f"{eid}: пустая форма {case}")

    if problems:
        print("FAIL:", path)
        for p in problems:
            print("  -", p)
        return 1
    print(f"OK — {len(elems)} элементов: {path}")
    return 0


def main(argv=None) -> int:
    # --check — флаг верхнего уровня (как в gen_sigil_catalog.py): в аргументах
    # подкоманд его нет, чтобы не ломать разбор store_true с add_subparsers.
    argv = list(argv) if argv is not None else sys.argv[1:]
    check = "--check" in argv
    argv = [a for a in argv if a != "--check"]
    ap = argparse.ArgumentParser(description="Генератор lore-данных Аркана Сигилов.")
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("elements", help="падежная таблица элементов")
    sub.add_parser("fragments", help="семь слотов фрагментов")
    args = ap.parse_args(argv)

    if args.command == "elements":
        # Запись реализуется в Step 2; пока --check — единственный режим.
        return check_elements(ELEMENTS_PATH)
    if args.command == "fragments":
        print("FAIL: подкоманда fragments ещё не реализована (Task 2)")
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
