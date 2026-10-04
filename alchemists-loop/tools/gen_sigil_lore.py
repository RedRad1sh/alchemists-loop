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


def write_elements(path: Path) -> None:
    """Write the curated inflections; never guess Russian cases from card IDs."""
    source = TOOLS_DIR / "sigil_elements_source.json"
    if check_elements(source):
        raise SystemExit("invalid canonical element data")
    payload = json.loads(source.read_text(encoding="utf-8"))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8", newline="\n")
    print(f"WROTE: {path}")


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



FRAGMENT_SLOTS = ["actions", "conditions", "results", "symbols", "warnings", "titles", "effects"]
# ===== Курируемые данные фрагментов (генерируются, не редактируются вручную) =====


C1 = {
    "nigredo": ["calcinatio", "putrefactio", "distillatio"],
    "albedo": ["sublimatio", "distillatio", "coniunctio"],
    "rubedo": ["coniunctio", "calcinatio"],
    "citrinitas": ["sublimatio", "coniunctio", "distillatio"],
}
ALL_STAGES = list(C1.keys())

# Варианты обстоятельств по слотам: (text, vessel_tag)
VARIANTS = {
    "actions": [
        ("в тигель и держи в огне всю ночь", "тигель"),
        ("в реторту и оставь под луной до утра", "реторта"),
        ("в алембик и перегоняй трижды", "алембик"),
        ("в глиняный горшок, закопав в тёплую золу", "горшок"),
        ("в стеклянную колбу, подвесив над слабым огнём", "колба"),
        ("в тигель, накрыв влажной тканью до рассвета", "тигель"),
    ],
    "conditions": [
        ("под светом полной луны", ""),
        ("в жаркой печи, раскалённой до бела", ""),
        ("при ровном пламени свечи, без сквозняков", ""),
        ("в холодном погребе, во тьме и тишине", ""),
        ("под первыми лучами солнца на востоке", ""),
        ("в грозу, когда воздух пахнет озоном", ""),
    ],
    "results": [
        ("поверхность покрывается белым налётом", ""),
        ("жидкость мутнеет и густеет на глазах", ""),
        ("из сосуда поднимается тонкий золотистый пар", ""),
        ("на дне остаётся тёмный осадок", ""),
        ("вещество вспыхивает и гаснет, оставляя пепел", ""),
        ("появляются мерцающие искры, вьющиеся кверху", ""),
    ],
    "symbols": [
        ("в этом скрыт знак змеи, кусающей собственный хвост", ""),
        ("то, что видишь, — отражение внутренней работы", ""),
        ("алхимик узнаёт в этом лик своего труда", ""),
        ("так рождается единство противоположностей", ""),
        ("это печать превращения, выжженная в материи", ""),
        ("символ этот старше камней и мудрее книг", ""),
    ],
    "warnings": [
        ("берегись: пары ядовиты, работай на ветру", ""),
        ("не вдыхай дым — он оставляет горький привкус", ""),
        ("держись подальше от открытого пламени", ""),
        ("если жидкость зашипит, немедленно отойди", ""),
        ("не касайся голыми руками, пока не остынет", ""),
        ("сосуд может треснуть — работай вдали от глаз", ""),
    ],
    "titles": [
        ("{process} {symbol} — {stage}", ""),
        ("{symbol} {stage}: путь {process}", ""),
        ("{process} под знаком {symbol}", ""),
        ("{target} {stage} — {process}", ""),
        ("врата {stage} через {process}", ""),
        ("{process} и {symbol} в час {stage}", ""),
    ],
    "effects": [
        ("крафт идёт ровнее", ""),
        ("материал служит дольше", ""),
        ("действие усиливается", ""),
        ("прилив сил у верстака", ""),
        ("результат стабильнее", ""),
        ("дорога к цели короче", ""),
    ],
}

# Базы по слотам: (text, stage|None, process[]|None, safety, weight)
BASES = {
    "actions": [
        ("Помести {source:acc} {variant} и наблюдай", None, None, "", 8),
        ("Смешай {source:acc} c {target:acc} {variant}", None, None, "", 7),
        ("Раствори {source:acc} в кислоте {variant}", "nigredo", ["putrefactio"], "", 6),
        ("Прогрей {source:acc} на огне до красноты {variant}", "nigredo", ["calcinatio"], "", 6),
        ("Собери росу с {target:gen} {variant}", "albedo", ["distillatio"], "", 6),
        ("Запечатай {source:acc} в глиняном сосуде {variant}", "nigredo", ["putrefactio"], "", 6),
        ("Растолки {source:acc} в ступке и просей {variant}", "nigredo", ["calcinatio"], "", 6),
        ("Соедини {source:acc} c {mercury:ins} {variant}", "albedo", ["coniunctio"], "volatile", 7),
        ("Возгони {source:acc}, собирая белый налёт {variant}", "albedo", ["sublimatio"], "", 6),
        ("Очисти {source:acc} через полотно {variant}", "nigredo", ["distillatio"], "", 5),
        ("Нагрей {source:acc} до появления золы {variant}", "nigredo", ["calcinatio"], "", 5),
        ("Разотри {source:acc} c {salt:ins} {variant}", "nigredo", ["putrefactio"], "", 6),
        ("Перегони {source:acc} и собери дистиллят {variant}", "albedo", ["distillatio"], "", 7),
        ("Соедини {source:acc} c {sulfur:ins} {variant}", "rubedo", ["coniunctio"], "", 6),
        ("Подвесь {source:acc} в марле над паром {variant}", "albedo", ["sublimatio"], "", 5),
        ("Запечатай {source:acc} и оставь бродить {variant}", "nigredo", ["putrefactio"], "", 5),
        ("Смешай {source:acc} c {lead:acc} {variant}", "rubedo", ["coniunctio"], "", 6),
        ("Возгони {source:acc} на водяной бане {variant}", "albedo", ["sublimatio"], "", 5),
        ("Осторожно нагрей {source:acc} c водой {variant}", "nigredo", ["distillatio"], "", 5),
        ("Соедини {source:acc} c {target:acc}, помешивая {variant}", "citrinitas", ["coniunctio"], "", 6),
    ],
    "conditions": [
        ("Прогревай {source:acc} {variant}", None, None, "", 7),
        ("Оставь {source:acc} {variant}", None, None, "", 6),
        ("Держи смесь {variant}, пока не пойдёт пар", "nigredo", ["distillatio"], "", 6),
        ("Выдержи {source:acc} {variant}, ровно до утра", None, None, "", 5),
        ("Пусть {source} {variant} и наберётся силы", None, None, "", 5),
        ("Держи {source:acc} {variant}, не открывая сосуда", None, None, "", 6),
        ("Нагревай до шипения {variant}", "nigredo", ["calcinatio"], "", 6),
        ("Остуди {source:acc} {variant}, затем вновь нагрей", None, None, "", 5),
        ("Выдержи {source:acc} в темноте {variant}", "nigredo", ["putrefactio"], "", 5),
        ("Пусть {source} стоит {variant} и вызревает", None, None, "", 5),
        ("Грей {source:acc} {variant}, помешивая лопаткой", None, None, "", 6),
        ("Оставь {source:acc} {variant}, накрыв крышкой", None, None, "", 5),
        ("Томи {source:acc} {variant} на малом огне", None, None, "", 6),
        ("Держи {source:acc} {variant}, пока не выпадет роса", "albedo", ["distillatio"], "", 5),
        ("Подержи {source:acc} {variant}, затем слей настой", None, None, "", 5),
        ("Оставь {source:acc} {variant}, чтобы осел осадок", "nigredo", ["putrefactio"], "", 5),
        ('Следи, чтобы {source} {variant} и не перегревался', None, None, '', 5),
    ],
    "results": [
        ("{source} обращается в {target:acc} {variant}", None, None, "", 7),
        ("появляется {target:acc} {variant}", None, None, "", 6),
        ("{source} растворяется, давая {target:acc} {variant}", None, None, "", 6),
        ("из {source:gen} выходит {target} {variant}", None, None, "", 6),
        ("{source} теряет прежний вид {variant}", None, None, "", 6),
        ("{source} становится {target:ins} {variant}", None, None, "", 6),
        ("в {source:prep} зарождается {target} {variant}", None, None, "", 5),
        ("{source} вспыхивает, оставляя {target:acc} {variant}", None, None, "", 5),
        ("остаётся лишь {target} из {source:gen} {variant}", None, None, "", 5),
        ("{source} и {target} соединяются {variant}", None, None, "", 6),
        ("{source} оседает, и над ним встаёт {target} {variant}", None, None, "", 5),
        ("{source} бледнеет, превращаясь в {target:acc} {variant}", None, None, "", 5),
        ("{source} отдаёт {target:acc} {variant}", None, None, "", 5),
        ("вместо {source:gen} остаётся {target} {variant}", None, None, "", 5),
        ("{source} затвердевает в {target:acc} {variant}", None, None, "", 5),
        ("{source} испаряется, и остаётся {target} {variant}", None, None, "", 5),
        ('{source} покрывается сетью трещин, {variant}', None, None, '', 5),
    ],
    "symbols": [
        ("Это {stage}: {symbol} {variant}", None, None, "", 7),
        ("Алхимик видит в этом {symbol} {variant}", None, None, "", 6),
        ("{variant} — знак {symbol} на пути {stage}", None, None, "", 6),
        ("Так {symbol} открывает врата {stage} {variant}", None, None, "", 6),
        ("В {source:prep} таится {symbol} {variant}", None, None, "", 6),
        ("{symbol} является в час {stage} {variant}", None, None, "", 6),
        ("Мастер узнаёт {symbol} среди {variant}", None, None, "", 6),
        ("{stage} несёт печать {symbol} {variant}", None, None, "", 6),
        ("{symbol} венчает труд {stage} {variant}", None, None, "", 6),
        ("В этом {variant} сокрыт {symbol} {stage}", None, None, "", 5),
        ("{symbol} повторяет путь {stage} {variant}", None, None, "", 5),
        ("Алхимик ставит {symbol} над {stage} {variant}", None, None, "", 5),
        ('{symbol} сплетается с {source:ins} {variant}', None, None, '', 5),
        ('{stage} рождает {symbol} из {source:gen} {variant}', None, None, '', 5),
        ('Мастер видит {symbol} над {target:ins} {variant}', None, None, '', 5),
        ('{symbol} скрыт в {source:prep}, {variant}', None, None, '', 5),
        ('{stage} и {symbol} — одно в час {variant}', None, None, '', 5),
    ],
    "warnings": [
        ("Если {source} коснётся {mercury:gen} — {variant}", "albedo", ["coniunctio"], "volatile", 6),
        ("Пары {source:gen} ядовиты: {variant}", None, None, "poison", 6),
        ("Не нагревай {source:acc} слишком сильно: {variant}", None, None, "poison", 6),
        ("Берегись: {source} летуч, и {variant}", None, None, "volatile", 5),
        ("{variant}: не вдыхай испарения {source:gen}", None, None, "poison", 5),
        ("Не смешивай {source:acc} c {mercury:acc}: {variant}", None, None, "poison", 6),
        ("{variant} — иначе {source} улетит с дымом", None, None, "volatile", 5),
        ("Держи {source:acc} подальше от огня: {variant}", None, None, "volatile", 5),
        ("{variant}: отойди, пока не остынет", None, None, "poison", 4),
        ("Если пойдёт едкий дым — {variant}", None, None, "poison", 5),
        ('{variant} — и {source} отравит смесь', None, None, 'poison', 5),
        ('Не смешивай {source:acc} c {target:acc} впопыхах: {variant}', None, None, 'poison', 5),
        ('{variant} — иначе пойдёт едкая гарь', None, None, 'poison', 5),
        ('Осторожно: {source} легко воспламеняется {variant}', None, None, 'volatile', 5),
        ('При {variant} держи лицо подальше от сосуда', None, None, 'poison', 5),
        ('{variant} — тяжёлые испарения стелются по полу', None, None, 'poison', 5),
        ('Если {variant} — немедленно гаси огонь', None, None, 'volatile', 5),
    ],
    "titles": [
        ("{process} {symbol} — {stage}", None, None, "", 7),
        ("{symbol} {stage}: путь {process}", None, None, "", 7),
        ("{process} под знаком {symbol}", None, None, "", 6),
        ("{target} {stage} — {process}", None, None, "", 6),
        ("врата {stage} через {process}", None, None, "", 6),
        ("{process} и {symbol} в час {stage}", None, None, "", 6),
        ("{source} ведёт к {stage} через {process}", None, None, "", 6),
        ("алхимия {process} и {stage}", None, None, "", 5),
        ("{stage} {process} — {symbol}", None, None, "", 5),
        ("{process} {stage}: рождение {target:gen}", None, None, "", 5),
        ('{source} и {process} — {stage}', None, None, '', 5),
        ('{process} {stage} — {symbol}', None, None, '', 5),
        ('{target} через {process} к {stage}', None, None, '', 5),
        ('{symbol} {stage}: {process}', None, None, '', 5),
        ('{process} волею {stage}', None, None, '', 5),
        ('{stage} под знаком {process}', None, None, '', 5),
        ('рождение {target:gen} в {process}', None, None, '', 5),
    ],
    "effects": [
        ("{variant} — и крафт идёт ровнее", None, None, "", 7),
        ("После этого {source} служит дольше {variant}", None, None, "", 6),
        ("{variant} усиливает действие {target:gen}", None, None, "", 6),
        ("Применённый {variant}, даёт прилив сил у верстака", None, None, "", 6),
        ("{variant} — и результат стабильнее", None, None, "", 5),
        ("{source} в деле ускоряет {target:gen} {variant}", None, None, "", 5),
        ("{variant} отворяет дорогу к {target:dat}", None, None, "", 5),
        ("С {source:ins} работа спорится {variant}", None, None, "", 5),
        ('{variant} — и работа ускоряется', None, None, '', 5),
        ('{source} даёт больше отдачи {variant}', None, None, '', 5),
        ('{variant} открывает скрытые свойства {target:gen}', None, None, '', 5),
        ('С этим {source:ins} верстак слушается {variant}', None, None, '', 5),
        ('{variant} — и результат тоньше', None, None, '', 5),
        ('{variant} упрощает {target:gen}', None, None, '', 5),
        ('{source} в деле бережёт силы {variant}', None, None, '', 5),
        ('{variant} — и путь к {target:dat} короче', None, None, '', 5),
        ('После {source:gen} дела спорятся {variant}', None, None, '', 5),
    ],
}

PLACEHOLDER_RE = __import__("re").compile(r"\{([a-z_]+):(gen|dat|acc|ins|prep)\}")


# Слоты: имя файла -> (база, варианты-словарь) — соответствует FRAGMENT_SLOTS.
def _expand_slot(slot: str, bases: list, variants: list) -> list:
    """Разворачивает курируемые базы: text c {variant} x каждый вариант.

    Плейсхолдер {variant} заменяется готовым обстоятельством (сосуд/время).
    Остальные {source:case}/{target:case}/{element:case} остаются — их подставит
    движок lore.gd на этапе генерации описания.
    """
    out: list = []
    for base in bases:
        text, stage, processes, safety, weight = base
        stage_tags = [stage] if stage else ALL_STAGES
        process_tags = list(processes) if processes else []
        # если process не задан - берём все совместимые со стадией (C1)
        if not process_tags:
            for st in stage_tags:
                for pr in C1[st]:
                    if pr not in process_tags:
                        process_tags.append(pr)
        for vi, (variant_text, _vessel) in enumerate(variants):
            ftext = text.replace("{variant}", variant_text)
            # vessel-тег в теги (для проверки «тигель+алембик»)
            vessel_tag = _vessel if _vessel else ""
            fid = f"{slot}_{len(out)+1:03d}"
            out.append({
                "id": fid,
                "slot": slot,
                "text": ftext,
                "tags": {
                    "process": process_tags,
                    "stage": stage_tags,
                    "elements": [],  # движок сам решает по плейсхолдерам
                    "vessel": [vessel_tag] if vessel_tag else [],
                    "safety": safety,
                },
                "weight": weight,
            })
    return out


def _all_fragments() -> dict:
    """Возвращает {slot: [фрагменты,...]} для всех 7 слотов."""
    return {
        "actions": _expand_slot("actions", BASES["actions"], VARIANTS["actions"]),
        "conditions": _expand_slot("conditions", BASES["conditions"], VARIANTS["conditions"]),
        "results": _expand_slot("results", BASES["results"], VARIANTS["results"]),
        "symbols": _expand_slot("symbols", BASES["symbols"], VARIANTS["symbols"]),
        "warnings": _expand_slot("warnings", BASES["warnings"], VARIANTS["warnings"]),
        "titles": _expand_slot("titles", BASES["titles"], VARIANTS["titles"]),
        "effects": _expand_slot("effects", BASES["effects"], VARIANTS["effects"]),
    }


def write_fragments(data_dir: Path) -> None:
    """Пишет 7 JSON-файлов фрагментов (артефакт)."""
    data_dir.mkdir(parents=True, exist_ok=True)
    frags = _all_fragments()
    for slot, items in frags.items():
        path = data_dir / f"{slot}.json"
        payload = {"version": 1, "fragments": items}
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8", newline="\n")
        print(f"WROTE: {path} — {len(items)} фрагментов")

def check_fragments(data_dir: Path) -> int:
    """Сверка семи слотов фрагментов. 0 — зелёно, 1 — дрейф."""
    elems = load_elements(ELEMENTS_PATH)
    if not elems:
        print("FAIL: нет элементов.json — сначала Task 1", file=sys.stderr)
        return 1
    problems: list = []
    canonical = _all_fragments()
    for slot in FRAGMENT_SLOTS:
        path = data_dir / f"{slot}.json"
        if not path.exists():
            problems.append(f"{slot}: файл не найден")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if data != {"version": 1, "fragments": canonical[slot]}:
            problems.append(f"{slot}: содержимое отличается от генератора")
        frags = data.get("fragments", [])
        if len(frags) < 100:
            problems.append(f"{slot}: фрагментов {len(frags)} < 100")
        for f in frags:
            if not isinstance(f, dict):
                problems.append(f"{slot}: фрагмент не объект")
                continue
            fid = str(f.get("id", ""))
            if f.get("slot") != slot:
                problems.append(f"{slot}/{fid}: slot не совпадает")
            if f.get("text") is None or not str(f["text"]).strip():
                problems.append(f"{slot}/{fid}: пустой text")
                continue
            text = str(f["text"])
            tags = f.get("tags")
            if not isinstance(tags, dict):
                problems.append(f"{slot}/{fid}: нет tags")
                continue
            w = f.get("weight")
            if not isinstance(w, int) or w < 1:
                problems.append(f"{slot}/{fid}: weight не int>=1")
            for ph in PLACEHOLDER_RE.findall(text):
                eid, case = ph
                # source/target — ролевые плейсхолдеры (движок подставляет
                # первый ингредиент и карту), их в elements.json нет — пропускаем.
                if eid in ("source", "target"):
                    continue
                if eid not in elems:
                    problems.append(f"{slot}/{fid}: плейсхолдер {{{eid}:{case}}} — нет в elements")
                if case not in ("gen","dat","acc","ins","prep"):
                    problems.append(f"{slot}/{fid}: падеж {case} вне набора")
            if "✦" in text or "⚡" in text:
                problems.append(f"{slot}/{fid}: символьная пыль в тексте")
    if problems:
        print("FAIL: слоты фрагментов")
        for p_ in problems:
            print("  -", p_)
        return 1
    print(f"OK — 7 слотов, все >=100 фрагментов: {data_dir}")
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
        if check:
            return check_elements(ELEMENTS_PATH)
        write_elements(ELEMENTS_PATH)
        return 0
    if args.command == "fragments":
        if check:
            return check_fragments(DATA_DIR)
        write_fragments(DATA_DIR)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
