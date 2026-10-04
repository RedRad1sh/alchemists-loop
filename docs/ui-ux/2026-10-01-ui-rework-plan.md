# UI/UX-переработка «Alchemist's Loop» — план (design system v2 «Atheneum»)

> **⚠️ 2026-10-04: итерация-2 откачена.** Приёмка по мокам (`tools/ui-preview/`)
> не выдержала проверки реальной игрой: parse-ошибка `home.gd`, no-op чипы
> (styleBox на `Label`), глобальные побочные эффекты (safe-area/`UiStateTick`).
> В коде оставлены сет иконок, меню вкладок и иконки шапки. Дальше — только по
> реальным кадрам (`tools/shots.py`) и с selftest в CI:
> `docs/ui-ux/2026-10-04-ui-revert-notes.md`. Пункты этого плана читать как
> бэклог, а не как сделанное.

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** убрать «сырость» UI: единая тема/токены, векторный икон-сет, исправленная геометрия
шапки/вкладок/BrewBar/списков при нулевом риске для игровой логики и автотестов.

**Architecture:** изолированный слой `game/ui/` (токены + Theme-фабрика + иконки + компоненты)
подключается к существующему UI одной точкой входа `UiBootstrap.apply(game)`; все правки
существующих файлов — точечные замены стилевых фабрик (`_small_button`, `_round_brew_button`,
`_panel_style`) и геометрии, без изменения сигналов/логики/баланса. Каждое изменение —
самостоятельный реверсируемый коммит; приемка — интерактивное превью `tools/ui-preview/`.

**Tech Stack:** Godot 4.7 GDScript, `Theme`/`StyleBoxFlat`/`TextureRect+SVG`, HTML/CSS/JS для превью.

**Spec:** `docs/ui-ux/2026-10-01-ui-ux-analysis.md` (находки UX-01…UX-32, метрики §2).

## Global Constraints

- Не менять игровую логику, баланс (`game/data/*`), сейвы, аналитику, сеть, монетизацию.
- Не ломать `tests/selftest.gd` и сюиты: имена нод/вкладок и тексты, на которые есть проверки,
  не переименовывать (проверено: сюиты читают `_mode_chips`, `text` чипов, имена путей).
- Тач-таргеты ≥ 44×44; контраст текста ≥ 4.5:1 (WCAG AA); фокус видим всегда.
- Палитра и шкалы — только из `game/ui/design_tokens.gd`; хардкод `Color(...)` в новых файлах запрещён.
- Иконки — только SVG 24×24, stroke 2, `currentColor`, из `assets/ui/icons/`.
- Android portrait 540×960 — основной форм-фактор; safe-area через `DisplayServer`.

## Review Focus

1. Тач: палец 48 px попадает в кнопки шапки и BrewBar без промаха (ранее 36–42 px).
2. Читаемость: статус/подсказки не трункятся и не перекрываются пузырьком Светика.
3. Навигация: все 6 вкладок видимы целиком на 540 px; активная однозначна.
4. Модалки: главное действие одно и выделено; закрытие — крестик и тап вне карточки.
5. Реверсия: откат любого коммита правки не оставляет UI в неполитом состоянии.

---

## Фаза 0 — База знаний (готово)

- [x] Task 0.1: аналитика `docs/ui-ux/2026-10-01-ui-ux-analysis.md`
- [x] Task 0.2: план (этот документ)

## Фаза 1 — Дизайн-система (изолированно, новые файлы)

### Task 1: Токены
- [x] Create `game/ui/design_tokens.gd` — палитра (16 токенов), type-scale (7 ролей),
      spacing (4-px сетка), radius, elevation, hit-size, letter-spacing для капса.
- Test: `gdparse` чисто; значения контрастов из анализа воспроизводятся функцией `contrast()`.

### Task 2: Икон-сет
- [x] Create `assets/ui/icons/*.svg` — 24 иконки, сетка 24, stroke 2, round cap/join, `currentColor`.
- [x] Create `game/ui/ui_icon.gd` — `UiIcon.make(name,size,color)` → `TextureRect` (SVG, модульт).
- Test: все SVG валидны (xml), единые атрибуты; `UiIcon` возвращает ноду с `stretch_mode=KEEP_ASPECT_CENTERED`.

### Task 3: Theme-фабрика
- [x] Create `game/ui/ui_theme.gd` — `UiTheme.build()` → `Theme`: Button (normal/hover/pressed/
      disabled/focus), TabContainer (pill-сегмент), LineEdit, ProgressBar, PanelContainer, Label-роли.
- [x] Create `game/ui/ui_style.gd` — фабрики StyleBoxFlat из токенов (card, input, chip, pill, bar).

## Фаза 2 — Подключение (минимальный диф существующих файлов)

### Task 4: Точка входа
- [x] Create `game/ui/ui_bootstrap.gd` — `apply(game)`: ставит Theme, чинит шапку (иконки вместо
      глифов, бейдж-компонент, 44 px), строку ресурсов (KPI-чип), выравнивает веса «Дом/Лавка».
- [x] Modify `main.gd::_build_ui()` — 2 строки: `UiBootstrap.apply(self)` после построения.

### Task 5: Стилевые фабрики через токены
- [x] Modify `main.gd::_small_button/_round_brew_button/_panel_style` — StyleBox из `UiStyle`
      (Kenney-текстуры остаются фолбэком при `UiTheme.enabled == false`).
- Test: `--selftest` зелёный (логика не тронута); превью «После» показывает новые кнопки.

## Фаза 3 — Геометрия и модули (изолированные фиксы)

### Task 6: BrewBar
- [x] Modify `main.gd::_build_brew_bar()` — «ВАРИТЬ» по центру ширины и в thumb-зоне, бейджи орбов
      пилюлей под орбом (не поверх), прогресс с подписью, «Стоп» резервирует место (без jump).
- [x] Modify `game/element_orb.gd` — бейдж количества: пилюля снизу по центру, кегль 11 SemiBold.

### Task 7: Вкладки и списки
- [x] Theme-скин вкладок: pill-сегмент, иконки, активная = accent-soft + accent-текст; отступы,
      чтобы 6 вкладок помещались на 540 px (кегль 13 SemiBold, `tab_hseparation 4`).
- [x] Modify `game/pages.gd` (picker реагентов): одна рамка вместо двойной, строка реагента
      72 px (описание не трункится), чипы-сегмент, поиск с иконкой и рамкой.

### Task 8: Дом и попапы
- [x] Modify `game/home.gd`: disabled-CTA → инфо-строка; выбор варианта → компактный сегмент.
- [x] Modify `main.gd::_build_popup()`: крестик 44 px, главное действие одно (accent), вторичное ghost.

## Фаза 4 — Приемка

### Task 9: Интерактивное превью
- [x] Create `tools/ui-preview/` — статический сайт: экраны «До/После» (540×960), лист иконок,
      токены, компоненты, чек-лист находок UX-01…UX-32 со статусом правки.
- [x] Сервер: `python3 -m http.server` (0.0.0.0) — live preview в браузере.
- Test: превью открывается, тумблер До/После переключает все экраны, иконки грузятся из репо.

## Фаза 5 — Дальше (бэклог, не в этой итерации)

- [ ] Task 10: нижняя tab-навигация (5+Ещё) вместо верхнего TabContainer (UX-09) — требует
      переноса BrewBar внутрь страницы «Лаборатория»; затронет `_on_tab_changed`/interstitial.
- [ ] Task 11: стек экранов вместо флагов `visible` (UX-27) + системная кнопка «назад».
- [ ] Task 12: дисплейный шрифт бренда (UX: §3.2) + letter-spacing капса во всех заголовках.
- [ ] Task 13: motion-пакет (game-feel): pressed-scale, tab-crossfade, skeleton-loading сетей.
- [ ] Task 14: safe-area inset из `DisplayServer.get_display_safe_area()` (UX-29).
