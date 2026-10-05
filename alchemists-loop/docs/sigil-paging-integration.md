Я сделал `BookPager` — отдельный класс-«книгу». Обложка открывается при показе экрана, вкладки вверху страницы, переход между ними идёт перелистыванием, а свайп от левого или правого края страницы листает так же. Код не запускал, на Godot 4.x не проверял.



Перелистывание идёт так:

1\. Страница снимается в текстуру.

2\. Текстура становится «листом» с шейдером: он вращается вокруг корешка с перспективой и затемнением.

3\. Под листом уже лежит следующая страница с падающей тенью.



Обложка рисуется в том же шейдере процедурно (кожа, золотая рамка, рунный круг цвета акцента), без текстур.Положи `book\_pager.gd` рядом с `SigilCraftBoard`. В самом `SigilCraftBoard` нужны точечные правки, логику драга и дропа трогать не надо.



\*\*1. Новые поля и константа\*\*

```gdscript

const INTRO\_DELAY := BookPager.INTRO\_TIME   # интро ждёт открытия книги

var \_book: BookPager

var \_page: Control

```

В четырёх `tween\_interval` (шапка `0.12`, ячейки `0.1 + …`, орбы `0.25 + …`, кнопка `0.3`) прибавь `INTRO\_DELAY + …`. Иначе анимации появления отыграют, пока обложка ещё закрыта.



\*\*2. В `\_build`, сразу после фона `bg`\*\*

```gdscript

\_book = BookPager.new()

\_book.name = "Book"

\_book.accent = \_accent

\_book.set\_anchors\_and\_offsets\_preset(Control.PRESET\_FULL\_RECT)

\_book.offset\_left = 14.0

\_book.offset\_right = -14.0

\_book.offset\_top = 28.0

\_book.offset\_bottom = -28.0

\_book.close\_requested.connect(func() -> void: closed.emit())

\_book.flipped.connect(func(\_a: int, \_b: int) -> void: Sfx.click())

add\_child(\_book)

\_page = Control.new()

\_page.name = "CraftPage"

\_book.add\_page("Круг", \_page)

\_book.add\_page("Рецепт", \_build\_recipe\_page(game))

\_book.open\_book()

```



\*\*3. Родители у существующих узлов\*\*

\- `add\_child(head)` меняется на `\_page.add\_child(head)`.

\- `add\_child(\_board)` меняется на `\_page.add\_child(\_board)`.

\- `add\_child(\_craft\_btn)` меняется на `\_page.add\_child(\_craft\_btn)`.

\- Блок `close\_btn` из шапки удали: «✕» теперь в книге.

\- У кнопки `offset\_left = 28` и `offset\_right = -28` вместо 120.



\*\*4. `close()`.\*\* Вместо tween по `modulate:a` сделай так:

```gdscript

await \_book.close\_book()

queue\_free()

```



\*\*5. Вторая страница-вкладка.\*\* Это пример, ключи `craft` подставь свои.

```gdscript

func \_build\_recipe\_page(game: Node) -> Control:

&#x09;var page := MarginContainer.new()

&#x09;for side in \["left", "right", "top", "bottom"]:

&#x09;	page.add\_theme\_constant\_override("margin\_" + side, 24)

&#x09;var col := VBoxContainer.new()

&#x09;col.add\_theme\_constant\_override("separation", 14)

&#x09;page.add\_child(col)

&#x09;var h := Label.new()

&#x09;h.text = str(craft.get("name", "Рецепт"))

&#x09;h.add\_theme\_font\_size\_override("font\_size", 22)

&#x09;col.add\_child(h)

&#x09;var ings: Array = craft.get("ingredients", \[])

&#x09;for i in ings.size():

&#x09;	var d := ing\_item(ings, i)

&#x09;	var row := HBoxContainer.new()

&#x09;	var orb: ElementOrb = game.\_make\_orb(d.id, 44)

&#x09;	orb.interactive = false

&#x09;	orb.custom\_minimum\_size = Vector2(44, 44)

&#x09;	row.add\_child(orb)

&#x09;	var l := Label.new()

&#x09;	l.text = "  ×%d" % d.qty

&#x09;	row.add\_child(l)

&#x09;	col.add\_child(row)

&#x09;return page

```



Что нужно учесть:

\- \*\*Размеры.\*\* Геометрия доски рассчитана на страницу шириной около 640 px (орбы на радиусе 220 плюс размер орба дают примерно 500 px). Для этого в проекте нужна базовая портретная база вроде 720×1280 со stretch `canvas\_items`. Если база меньше, радиусы надо масштабировать.

\- \*\*Свайп.\*\* Он срабатывает только от края страницы (36 px), чтобы не конфликтовать с драгом орбов. Орбы, лежащие у самого края, могут случайно запустить листание.

\- \*\*Снимок страницы.\*\* Лист берёт снимок экрана, поэтому при листании назад целевая страница на один кадр показывается целиком, это может дать лёгкое мерцание. Лечится кэшем снимков или отдельным `SubViewport` на страницу.

\- \*\*Окно с letterbox.\*\* Если окно с letterbox-полями (stretch mode `keep`), в `\_snapshot` может понадобиться поправка на смещение вьюпорта.



Если хочешь, добавлю полноценный разворот на два листа для планшетов и бумажные текстуры страниц.

