#!/usr/bin/env python3
"""Раннер РЕАЛЬНЫХ кадров UI игры — визуальный регресс для приёмки.

Почему не tools/ui-preview: там кадры рисует PIL «из токенов» и они не связаны
с кодом игры. Этот инструмент запускает саму игру (Godot + xvfb) и снимает
вьюпорт тем же харнесом, что описан в README (`--selftest --demo --shot=`).

Использование (из корня репозитория):
  python3 alchemists-loop/tools/shots.py run <label>        # снять кадры
  python3 alchemists-loop/tools/shots.py run baseline        # эталон ДО
  python3 alchemists-loop/tools/shots.py run current         # кадры ПОСЛЕ правок
  python3 alchemists-loop/tools/shots.py compare baseline current
  python3 alchemists-loop/tools/shots.py list

Результат run:  alchemists-loop/previews/shots/<label>/<сцена>.png
Результат compare: docs/ui-ux/shots-diff/<base>_vs_<new>/{<сцена>.png, report.md}
(каталоги артефактов в .gitignore — в репозиторий не попадают).

Требования: Godot 4.7.x (из $GODOT или PATH), xvfb-run (если нет $DISPLAY).
Для compare нужен Pillow (`pip install pillow`), без него — понятная подсказка.

Снимки детерминированы насколько это возможно: режим `--selftest` изолирует
сейвы в ST-файлы, выключает сеть и первый privacy-dialog (см. README).
Флаг `--plain` снимает без selftest — на твоём локальном сейве (если consent
уже дан, диалога не будет).
"""
from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent   # корень репо
PROJECT = ROOT / "alchemists-loop"                             # каталог project.godot
SHOTS = PROJECT / "previews" / "shots"
DIFFS = ROOT / "docs" / "ui-ux" / "shots-diff"

# Одна сцена = один кадр. Табы: 0 Эксперимент · 1 Лаборатория · 2 Мир ·
# 3 Дом · 4 Рейтинг · 5 Инструменты. Action-сцены открывают модалку в _ready.
SCENARIOS: dict[str, list[str]] = {
    "tab0_experiment": ["--tab=0"],
    "tab1_lab": ["--tab=1"],
    "tab2_world": ["--tab=2"],
    "tab3_house": ["--tab=3"],
    "tab4_rating": ["--tab=4"],
    "tab5_tools": ["--tab=5"],
    "modal_upgrades": ["--action=upgrades"],
    "modal_quests": ["--action=quests"],
    "modal_decor": ["--action=decor"],
    "modal_companion": ["--action=companion"],
}

SHOT_TIMEOUT_S = 240


def find_godot() -> str:
    godot = os.environ.get("GODOT", "")
    if godot:
        return godot
    for name in ("godot", "godot4", "godot-headless"):
        import shutil
        found = shutil.which(name)
        if found:
            return found
    sys.stderr.write(
        "shots: Godot не найден. Задайте GODOT=/путь/к/godot_4.7.x\n"
        "(скачать: https://github.com/godotengine/godot/releases — Godot_v4.7.x-stable_linux.x86_64.zip)\n"
    )
    raise SystemExit(127)


def xvfb_prefix() -> list[str]:
    if os.environ.get("DISPLAY"):
        return []
    import shutil
    if not shutil.which("xvfb-run"):
        sys.stderr.write(
            "shots: нет $DISPLAY и не найден xvfb-run — установи xvfb\n"
            "(Debian/Ubuntu: sudo apt-get install xvfb) либо запусти из графической сессии.\n"
        )
        raise SystemExit(127)
    # 540x960 — основной форм-фактор игры (portrait).
    return ["xvfb-run", "-a", "-s", "-screen 0 540x960x24"]


def run_scenarios(label: str, only: list[str] | None, plain: bool) -> int:
    names = only or list(SCENARIOS)
    unknown = [n for n in names if n not in SCENARIOS]
    if unknown:
        sys.stderr.write(f"shots: неизвестные сцены: {', '.join(unknown)} (см. list)\n")
        return 2
    godot = find_godot()
    prefix = xvfb_prefix()
    out_dir = SHOTS / label
    out_dir.mkdir(parents=True, exist_ok=True)

    fails = []
    for name in names:
        out_png = (out_dir / f"{name}.png").resolve()
        if out_png.exists():
            out_png.unlink()
        args = [godot, "--path", str(PROJECT), "--"]
        if not plain:
            args.append("--selftest")   # изолированные ST-сейвы, без сети и privacy-dialog
        args += ["--demo", f"--shot={out_png}", *SCENARIOS[name]]
        cmd = prefix + args
        print(f"[shot] {name} …", flush=True)
        try:
            proc = subprocess.run(
                cmd, cwd=str(PROJECT), capture_output=True, text=True,
                timeout=SHOT_TIMEOUT_S,
            )
        except subprocess.TimeoutExpired:
            print(f"[FAIL] {name}: таймаут {SHOT_TIMEOUT_S}s")
            fails.append(name)
            continue
        tail = (proc.stdout + proc.stderr).strip().splitlines()
        if proc.returncode == 0 and out_png.exists() and out_png.stat().st_size > 0:
            size_kb = out_png.stat().st_size // 1024
            print(f"[ OK ] {name} -> {out_png.relative_to(ROOT)} ({size_kb} KB)")
        else:
            print(f"[FAIL] {name}: exit={proc.returncode}, файла нет")
            for line in tail[-15:]:
                print("       |", line)
            fails.append(name)

    print(f"\nshots[{label}]: {len(names) - len(fails)}/{len(names)} ок")
    if fails:
        print("упали: " + ", ".join(fails))
        return 1
    print(f"сравни: python3 alchemists-loop/tools/shots.py compare <baseline> {label}")
    return 0


def _load_png(path: pathlib.Path):
    try:
        from PIL import Image
    except ImportError:
        sys.stderr.write("compare: нужен Pillow — `pip install pillow`\n")
        raise SystemExit(127)
    return Image.open(path).convert("RGB")


def compare(base_label: str, new_label: str) -> int:
    base_dir, new_dir = SHOTS / base_label, SHOTS / new_label
    if not base_dir.is_dir() or not new_dir.is_dir():
        sys.stderr.write(f"compare: нет каталогов {base_dir} / {new_dir} — сначала run\n")
        return 2
    names = sorted({p.name for p in base_dir.glob("*.png")} & {p.name for p in new_dir.glob("*.png")})
    only_base = sorted({p.name for p in base_dir.glob("*.png")} - set(names))
    if not names:
        sys.stderr.write("compare: общих кадров нет\n")
        return 2
    out_dir = DIFFS / f"{base_label}_vs_{new_label}"
    out_dir.mkdir(parents=True, exist_ok=True)

    from PIL import Image, ImageChops, ImageDraw  # noqa: F401  (Pillow уже проверен точечно)

    rows = []
    for name in names:
        a, b = _load_png(base_dir / name), _load_png(new_dir / name)
        if a.size != b.size:
            rows.append((name, -1.0, "разный размер"))
            continue
        diff = ImageChops.difference(a, b)
        # пиксель считается изменившимся, если хотя бы в одном канале дельта > 16
        gray = diff.convert("L")
        mask = gray.point(lambda v: 255 if v > 16 else 0)
        changed = sum(mask.histogram()[255:])
        total = a.size[0] * a.size[1]
        pct = 100.0 * changed / total
        # подсветка диффа на тёмном фоне + подписи
        heat = diff.convert("L").point(lambda v: min(255, v * 4)).convert("RGB")
        w, h = a.size
        montage = Image.new("RGB", (w * 3 + 16, h + 18), (24, 24, 28))
        montage.paste(a, (0, 18))
        montage.paste(b, (w + 8, 18))
        montage.paste(heat, (w * 2 + 16, 18))
        d = ImageDraw.Draw(montage)
        d.text((4, 4), f"{name}  [base={base_label} | new={new_label} | diff x4]  changed={pct:.2f}%", fill=(230, 230, 230))
        montage.save(out_dir / name)
        rows.append((name, pct, "ok"))

    lines = [f"# Визуальный дифф `{base_label}` → `{new_label}`", ""]
    lines += ["| Сцена | Изменено пикселей | |", "|---|---:|---|"]
    for name, pct, note in sorted(rows, key=lambda r: -r[1]):
        lines.append(f"| {name} | {'—' if pct < 0 else f'{pct:.2f}%'}{'' if note == 'ok' else f' ({note})'} | |")
    lines += ["", "Кадры: base | new | diff×4 в каждом `<сцена>.png`.", "",
              "Порог: канал-дельта > 16. Ноль изменений на вкладке, которую не трогали, — зелёный знак.",
              "Для спорных кадров смотри сам montages; числа нужны для быстрой сортировки."]
    (out_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"compare: {len(rows)} сцен -> {out_dir.relative_to(ROOT)}/report.md")
    for name, pct, note in sorted(rows, key=lambda r: -r[1]):
        print(f"  {'—' if pct < 0 else format(pct, '.2f').rjust(6) + '%'}  {name}" + (f"  [{note}]" if note != "ok" else ""))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run", help="снять реальные кадры игры в previews/shots/<label>/")
    p_run.add_argument("label", help="метка набора: baseline / current / любая")
    p_run.add_argument("--only", help="только сцены через запятую (см. list)")
    p_run.add_argument("--plain", action="store_true",
                       help="без --selftest (снимок на локальном сейве вместо изолированного)")
    p_cmp = sub.add_parser("compare", help="side-by-side + % диффа между двумя наборами")
    p_cmp.add_argument("base")
    p_cmp.add_argument("new")
    sub.add_parser("list", help="показать сцены")

    args = ap.parse_args()
    if args.cmd == "run":
        only = [s.strip() for s in args.only.split(",")] if args.only else None
        return run_scenarios(args.label, only, args.plain)
    if args.cmd == "compare":
        return compare(args.base, args.new)
    for name, extra in SCENARIOS.items():
        print(f"{name:18s} {' '.join(extra)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
