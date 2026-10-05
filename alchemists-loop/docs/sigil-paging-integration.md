# BookPager — книга с перелистыванием (интеграция)

`BookPager` — отдельный класс-«книга» (`game/sigil/book_pager.gd`). Обложка
открывается при показе экрана, вкладки вверху страницы, переход между ними идёт
перелистыванием, а свайп от левого или правого края страницы листает так же.

Статус: класс лежит в репозитории и уже подключён — Аркан Сигилов открывается
книгой (`main.gd`: `_open_sigil_modal()` собирает страницы, `_sigil_show_tab()`
листает, `_open_sigil_book_and_show_tab()` дожидается открытия обложки). Ниже —
как переиспользовать книгу в `SigilCraftBoard`.

Перелистывание идёт так:

1. Страница снимается в текстуру.
2. Текстура становится «листом» с шейдером: он вращается вокруг корешка с перспективой и затемнением.
3. Под листом уже лежит следующая страница с падающей тенью.

Обложка рисуется в том же шейдере процедурно (кожа, золотая рамка, рунный круг
цвета акцента), без текстур. Положи `book_pager.gd` рядом с `SigilCraftBoard`. В
самом `SigilCraftBoard` нужны точечные правки, логику драга и дропа трогать не
надо.

## 1. Новые поля и константа

```gdscript
const INTRO_DELAY := BookPager.INTRO_TIME   # интро ждёт открытия книги

var _book: BookPager
var _page: Control
```

В четырёх `tween_interval` (шапка `0.12`, ячейки `0.1 + …`, орбы `0.25 + …`,
кнопка `0.3`) прибавь `INTRO_DELAY + …`. Иначе анимации появления отыграют,
пока обложка ещё закрыта.

## 2. В `_build`, сразу после фона `bg`

```gdscript
_book = BookPager.new()
_book.name = "Book"
_book.accent = _accent
_book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
_book.offset_left = 14.0
_book.offset_right = -14.0
_book.offset_top = 28.0
_book.offset_bottom = -28.0
_book.close_requested.connect(func() -> void: closed.emit())
_book.flipped.connect(func(_a: int, _b: int) -> void: Sfx.click())
add_child(_book)

_page = Control.new()
_page.name = "CraftPage"
_book.add_page("Круг", _page)
_book.add_page("Рецепт", _build_recipe_page(game))
_book.open_book()
```

## 3. Родители у существующих узлов

- `add_child(head)` меняется на `_page.add_child(head)`.
- `add_child(_board)` меняется на `_page.add_child(_board)`.
- `add_child(_craft_btn)` меняется на `_page.add_child(_craft_btn)`.
- Блок `close_btn` из шапки удали: «✕» теперь в книге.
- У кнопки `offset_left = 28` и `offset_right = -28` вместо 120.

## 4. `close()`

Вместо tween по `modulate:a` сделай так:

```gdscript
await _book.close_book()
queue_free()
```

## 5. Вторая страница-вкладка

Это пример, ключи `craft` подставь свои.

```gdscript
func _build_recipe_page(game: Node) -> Control:
	var page := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 24)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	page.add_child(col)
	var h := Label.new()
	h.text = str(craft.get("name", "Рецепт"))
	h.add_theme_font_size_override("font_size", 22)
	col.add_child(h)
	var ings: Array = craft.get("ingredients", [])
	for i in ings.size():
		var d := ing_item(ings, i)
		var row := HBoxContainer.new()
		var orb: ElementOrb = game._make_orb(d.id, 44)
		orb.interactive = false
		orb.custom_minimum_size = Vector2(44, 44)
		row.add_child(orb)
		var l := Label.new()
		l.text = "  ×%d" % d.qty
		row.add_child(l)
		col.add_child(row)
	return page
```

## Что нужно учесть

- **Размеры.** Геометрия доски рассчитана на страницу шириной около 640 px (орбы на радиусе 220 плюс размер орба дают примерно 500 px). Для этого в проекте нужна базовая портретная база вроде 720×1280 со stretch `canvas_items`. Если база меньше, радиусы надо масштабировать.
- **Свайп.** Он срабатывает только от края страницы (36 px), чтобы не конфликтовать с драгом орбов. Орбы, лежащие у самого края, могут случайно запустить листание.
- **Снимок страницы.** Лист берёт снимок экрана, поэтому при листании назад целевая страница на один кадр показывается целиком, это может дать лёгкое мерцание. Лечится кэшем снимков или отдельным `SubViewport` на страницу.
- **Открытие и перелистывание.** `open_book()` и `go_to()` оба владеют `busy`/`_shield`: перелистывание запускай только после завершения открытия (`await _book.open_book()`), иначе щит одного гаснет, пока второй ещё анимируется, и ввод попадает в книгу.
- **Окно с letterbox.** Если окно с letterbox-полями (stretch mode `keep`), в `_snapshot` может понадобиться поправка на смещение вьюпорта.

## Дальше

Первая версия — интеграция в `SigilCraftBoard` (шапка/доска/кнопка крафта
первой страницей, рецепт второй). Если понадобится, добавлю полноценный разворот
на два листа для планшетов и бумажные текстуры страниц.
