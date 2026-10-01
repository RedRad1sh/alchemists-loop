#!/usr/bin/env python3
"""Генератор икон-сета UI «Atheneum».

Единая сетка 24x24, stroke 2, round cap/join, базовый цвет — белый: в Godot тонируется modulate (UiIcon.make), в веб-превью — CSS mask. Запуск:
    python3 tools/make_icons.py
Иконки пишутся в alchemists-loop/assets/ui/icons/*.svg (детерминированно).
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui" / "icons"

# name -> список элементов: ("p", d) | ("c", cx, cy, r) | ("dot", cx, cy, r)
ICONS = {
    "bolt": [("p", "M13 2 5 13h6l-1 9 8-11h-6z")],
    "star": [("p", "M12 3l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9L3.5 9.2l5.9-.8z")],
    "trend_up": [("p", "M3 17l6-6 4 4 7-7"), ("p", "M14 8h6v6")],
    "volume": [("p", "M4 10v4h3l4 4V6L7 10H4z"), ("p", "M16 9.5a4 4 0 0 1 0 5"), ("p", "M18.5 7a8 8 0 0 1 0 10")],
    "volume_off": [("p", "M4 10v4h3l4 4V6L7 10H4z"), ("p", "M16 10l5 5"), ("p", "M21 10l-5 5")],
    "book": [("p", "M4 19.5A2.5 2.5 0 0 1 6.5 17H20"), ("p", "M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z")],
    "user": [("c", 12, 8, 4), ("p", "M4 21c0-4 3.6-6 8-6s8 2 8 6")],
    "home": [("p", "M3 11l9-8 9 8"), ("p", "M5 10v10h14V10"), ("p", "M10 20v-6h4v6")],
    "bag": [("p", "M6 8h12l1 13H5z"), ("p", "M9 8V6a3 3 0 0 1 6 0v2")],
    "flask": [("p", "M10 3v6L4.5 19a2 2 0 0 0 1.8 3h11.4a2 2 0 0 0 1.8-3L14 9V3"), ("p", "M8.5 3h7"), ("p", "M7.5 15h9")],
    "cauldron": [("p", "M4 10h16"), ("p", "M5 10a7 7 0 0 0 14 0"), ("p", "M8 16.5 6.5 21"), ("p", "M16 16.5 17.5 21"), ("p", "M9.5 6.5c0-1.5 1-2 1-3.5"), ("p", "M13.5 6.5c0-1.5 1-2 1-3.5")],
    "globe": [("c", 12, 12, 9), ("p", "M3 12h18"), ("p", "M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18")],
    "trophy": [("p", "M8 4h8v5a4 4 0 0 1-8 0z"), ("p", "M8 5H5a3 3 0 0 0 3 4"), ("p", "M16 5h3a3 3 0 0 1-3 4"), ("p", "M12 13v4"), ("p", "M9 21h6"), ("p", "M10 17h4v4h-4z")],
    "sliders": [("p", "M3 7h8"), ("p", "M17 7h4"), ("p", "M3 17h4"), ("p", "M13 17h8"), ("c", 14, 7, 2.5), ("c", 10, 17, 2.5)],
    "repeat": [("p", "M17 2l4 4-4 4"), ("p", "M3 11V9a4 4 0 0 1 4-4h14"), ("p", "M7 22l-4-4 4-4"), ("p", "M21 13v2a4 4 0 0 1-4 4H3")],
    "x": [("p", "M6 6l12 12"), ("p", "M18 6 6 18")],
    "check": [("p", "M4 12.5l5 5L20 6.5")],
    "chevron_right": [("p", "M9 5l7 7-7 7")],
    "chevron_down": [("p", "M5 9l7 7 7-7")],
    "search": [("c", 11, 11, 7), ("p", "M20 20l-3.5-3.5")],
    "mail": [("p", "M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"), ("p", "M3 7l9 6 9-6")],
    "map": [("p", "M9 4l6 2 6-2v14l-6 2-6-2-6 2V6z"), ("p", "M9 4v14"), ("p", "M15 6v14")],
    "plus": [("p", "M12 5v14"), ("p", "M5 12h14")],
    "info": [("c", 12, 12, 9), ("p", "M12 11v5"), ("p", "M12 8h.01")],
    "lock": [("p", "M4 13a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"), ("p", "M8 11V8a4 4 0 0 1 8 0v3")],
    "fire": [("p", "M12 2s5 4.5 5 9a5 5 0 0 1-10 0c0-1.8.8-3.4 1.8-4.8.4 1 1 1.8 1.7 2.3C10.5 6.5 11 4 12 2z")],
    "drop": [("p", "M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z")],
    "clock": [("c", 12, 12, 9), ("p", "M12 7v5l3.5 2")],
    "gift": [("p", "M3 8h18v4H3z"), ("p", "M5 12v9h14v-9"), ("p", "M12 8v13"), ("p", "M12 8c-4 0-5-4-2.5-4S12 8 12 8z"), ("p", "M12 8c4 0 5-4 2.5-4S12 8 12 8z")],
    "dots": [("dot", 5, 12, 1.7), ("dot", 12, 12, 1.7), ("dot", 19, 12, 1.7)],
    "leaf": [("p", "M4 20C4 10 12 4 20 4c0 8-6 16-16 16z"), ("p", "M4 20c4-6 8-10 12-12")],
    "gem": [("p", "M7 3h10l4 6-9 12L3 9z"), ("p", "M3 9h18"), ("p", "M12 21 8 9l3-6"), ("p", "M12 21l4-12-3-6")],
    "stop": [("p", "M7 7h10v10H7z")],
    "settings": [("c", 12, 12, 3), ("p", "M12 2v3"), ("p", "M12 19v3"), ("p", "M2 12h3"), ("p", "M19 12h3"), ("p", "M4.9 4.9 7 7"), ("p", "M17 17l2.1 2.1"), ("p", "M19.1 4.9 17 7"), ("p", "M7 17l-2.1 2.1")],
    "wind": [("p", "M3 8h9a3 3 0 1 0-3-4"), ("p", "M3 12h13a3 3 0 1 1-3 4"), ("p", "M3 16h6")],
    "mountain": [("p", "M3 20l6-10 4 6 3-4 5 8z")],
    "play": [("p", "M8 5l11 7-11 7z")],
}

HEADER = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
          'viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" '
          'stroke-linecap="round" stroke-linejoin="round">')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, elems in sorted(ICONS.items()):
        body = []
        for e in elems:
            if e[0] == "p":
                body.append(f'  <path d="{e[1]}"/>')
            elif e[0] == "c":
                body.append(f'  <circle cx="{e[1]}" cy="{e[2]}" r="{e[3]}"/>')
            else:
                body.append(f'  <circle cx="{e[1]}" cy="{e[2]}" r="{e[3]}" '
                            f'fill="#FFFFFF" stroke="none"/>')
        svg = HEADER + "\n" + "\n".join(body) + "\n</svg>\n"
        (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")
    print(f"wrote {len(ICONS)} icons -> {OUT}")


if __name__ == "__main__":
    main()
