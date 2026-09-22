#!/usr/bin/env python3
"""
Подготовка UI-ассетов под стиль игры из Kenney UI Pack (CC0).

Kenney-кнопки/панели перекрашиваются в палитру игры:
  - фон         #0d1219 (тёмный сине-чёрный)
  - панель      #111824, рамка бирюзовая
  - primary     бирюзовый (кнопка «ВАРИТЬ» и основные CTA)
  - gold        янтарный (спец-кнопки: намёк/апгрейды)
  - secondary   тёмно-синий (мелкие кнопки)

Перекраска — «по зонам»: каждый исходный цвет Kenney-кнопки (тело, светлая и
тёмная кромки «глубины») заменяется на соответствующий цвет целевой палитры,
ближайший по RGB. Шейдинг (bevel) сохраняется.

Исходники: assets/ui/kenney_src/*.png (скопированы из Kenney UI Pack 2.0, CC0).
Результат: assets/ui/*.png
"""

import os
import shutil

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # alchemists-loop/
SRC = os.path.join(ROOT, "assets", "ui", "kenney_src")
DST = os.path.join(ROOT, "assets", "ui")

# ---- палитра игры ----
TEAL = {
    "body": (32, 164, 155),   # #20a49b
    "light": (76, 214, 202),  # #4cd6ca
    "dark": (24, 126, 119),   # #187e77
    "darker": (18, 96, 92),   # #12605c
}
GOLD = {
    "body": (232, 170, 26),   # #e8aa1a
    "light": (255, 214, 112), # #ffd670
    "dark": (188, 132, 18),   # #bc8412
    "darker": (150, 104, 14), # #96680e
}
NAVY = {
    "body": (40, 53, 73),     # #283549
    "light": (62, 80, 106),   # #3e506a
    "dark": (28, 38, 54),     # #1c2636
}

# ---- исходные цвета Kenney (по факту из PNG) ----
KENNEY_BLUE_BODY = (28, 159, 215)
KENNEY_BLUE_LIGHT = (54, 189, 247)
KENNEY_BLUE_DARK = (22, 125, 168)
KENNEY_BLUE_DARKER = (20, 101, 135)

KENNEY_YELLOW_BODY = (255, 204, 0)
KENNEY_YELLOW_LIGHT = (255, 234, 156)
KENNEY_YELLOW_DARK = (222, 163, 18)
KENNEY_YELLOW_DARKER = (180, 128, 0)

KENNEY_GREY_BODY = (218, 220, 231)
KENNEY_GREY_LIGHT = (255, 255, 255)
KENNEY_GREY_DARK = (152, 154, 175)

KENNEY_INPUT_BODY = (255, 255, 255)
KENNEY_INPUT_BORDER = (152, 154, 175)
KENNEY_INPUT_EDGE = (218, 220, 231)


def _remap(img: Image.Image, mapping: list[tuple[tuple, tuple]]) -> Image.Image:
    """Заменить исходные цвета на целевые (ближайший якорь по RGB)."""
    a = np.array(img.convert("RGBA")).astype(np.float32)
    srcs = np.array([m[0] for m in mapping], dtype=np.float32)
    tgts = np.array([m[1] for m in mapping], dtype=np.float32)

    rgb = a[..., :3].reshape(-1, 3)
    # расстояние до каждого якоря
    dist = ((rgb[:, None, :] - srcs[None, :, :]) ** 2).sum(axis=2)  # (N, K)
    idx = dist.argmin(axis=1)
    new_rgb = tgts[idx].reshape(a.shape[0], a.shape[1], 3)
    out = np.concatenate([new_rgb, a[..., 3:]], axis=2).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def make(src_name: str, out_name: str, mapping):
    im = Image.open(os.path.join(SRC, src_name))
    im = _remap(im, mapping)
    im.save(os.path.join(DST, out_name))
    print(f"  {out_name} <- {src_name}")


def main():
    os.makedirs(DST, exist_ok=True)

    teal_map = [
        (KENNEY_BLUE_BODY, TEAL["body"]),
        (KENNEY_BLUE_LIGHT, TEAL["light"]),
        (KENNEY_BLUE_DARK, TEAL["dark"]),
        (KENNEY_BLUE_DARKER, TEAL["darker"]),
    ]
    gold_map = [
        (KENNEY_YELLOW_BODY, GOLD["body"]),
        (KENNEY_YELLOW_LIGHT, GOLD["light"]),
        (KENNEY_YELLOW_DARK, GOLD["dark"]),
        (KENNEY_YELLOW_DARKER, GOLD["darker"]),
    ]
    navy_map = [
        (KENNEY_GREY_BODY, NAVY["body"]),
        (KENNEY_GREY_LIGHT, NAVY["light"]),
        (KENNEY_GREY_DARK, NAVY["dark"]),
    ]
    panel_map = [
        (KENNEY_INPUT_BODY, (17, 24, 36)),      # тёмный корпус панели
        (KENNEY_INPUT_BORDER, (56, 128, 122)),  # бирюзовая рамка
        (KENNEY_INPUT_EDGE, (40, 56, 80)),      # внутренний светлый кант
    ]

    make("btn_blue_rect_depth.png", "btn_primary.png", teal_map)
    make("btn_yellow_rect_depth.png", "btn_gold.png", gold_map)
    make("btn_grey_rect_flat.png", "btn_secondary.png", navy_map)
    make("btn_blue_round_depth.png", "btn_round.png", teal_map)
    make("input_outline_rectangle.png", "panel.png", panel_map)
    # разделитель: белый → бирюзовый
    make("divider.png", "divider.png", [(KENNEY_INPUT_BODY, (84, 176, 168))])

    print("готово")


if __name__ == "__main__":
    main()
