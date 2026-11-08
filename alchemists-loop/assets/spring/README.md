# Родник v2 — визуальные ассеты

## Что здесь лежит

```
assets/spring/
├── spring_l{1..6}_{steel,obsidian,crystal,gold}.png        # 24 формы
├── spring_l{1..6}_{steel,obsidian,crystal,gold}_water.png  # 24 слоя воды
└── spring_water.gdshader                                   # течение по слою воды
```

Пары `...png` / `..._water.png` нарисованы в одной системе координат: `_water`
содержит ровно те пиксели формы, которые в SVG были водой, всё остальное —
прозрачно. Поэтому слой воды — это `Sprite2D` **ребёнком того же `_fountain`**,
что и форма: течение физически не может уехать от струи, никакой второй
расстановки не требуется.

## Как экран выбирает пару

`game/lab/spring_screen.gd:_refresh()`:

```
total_level   = speed + volume + sources + offline          # 0…20
form_stage    = clampi(floori(total_level / 4.0), 0, 5)     # l1…l6
material_tier = max tier всех КУПЛЕННЫХ ступеней            # 0…4
stem          = "res://assets/spring/spring_l{stage+1}_{asset}"
```

`SPRING_TIER_ASSET = [steel, steel, obsidian, crystal, gold]` — два первых
уровня делят сталь, остальное по одному. Загружаются `stem + ".png"` и
`stem + "_water.png"`; отсутствие слоя воды экран переживает как
`_water.visible = false`, но `tests/suite_spring_v2.gd` проверяет все 24 пары.

## Параметры шейдера

| Параметр | Кто задаёт | Смысл |
|---|---|---|
| `flow_color` | `_item_colors[spring_source]` | поток окрашивается в цвет выбранной стихии |
| `flow_speed` | `clampf(6 / интервал, 0.6, 3.2)`, `0` если родник остановлен | быстрая вода течёт быстрее, остановленный родник стоит |
| `band_strength` | не трогаем (0.16) | яркость бегущих полос течения |

`WATER_BASE = (0.37, 0.81, 0.94)` — базовый цвет воды в PNG. Шейдер домножает
пиксель к целевому цвету, поэтому перекраска сохраняет затенение оригинала.

## Ограничения, которые уже стоили отладки

- В `.gdshader` нельзя `const X := v` (это GDScript) и нельзя `return` внутри
  `fragment()` — обе ошибки видны только в оконном запуске, headless их не
  компилирует. Проверка лежит в `tests/suite_spring_v2.gd`.
- Спрайты матовые, без запечённого свечения: блик и брызги даёт
  `GPUParticles2D` на экране, не пиксели картинки.

## Приёмка

Кадры снимаются оконным прогоном демо-стенда:

```
godot --path . -- --demo --action=spring --springlvl=2 --springsrc=fire \
      --shot=<абсолютный путь>/shot.png
```

`--springlvl=N` выставляет все четыре оси в N, `--springsrc=` добавляет
источник. geometry-дамп — `--geom`.
