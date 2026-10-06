class_name SigilUI
extends Node
## Вынесенный сигильный UI из main.gd (рефакторинг godobject).
## Получает ссылку на главный Game (main.gd) и через неё работает с его полями/хелперами.
var main: Node = null

# --- состояние сигильного UI (переехало сюда из main.gd; остальные поля — через main.*) ---
var _sigil_coll: ColorRect = null  # модалка коллекции сигилов; != null ⇒ открыта
var _sigil_tab_content: Control = null  # контейнер активной вкладки модалки
var _sigil_tab: String = "crafts"  # активная вкладка: crafts | collection | sets
var _sigil_tab_btns: Array = []  # кнопки вкладок; подсветка активной в _sigil_show_tab
var _sigil_tab_seq := 0  # поколение вкладки: гасит корутины билдеров при переключении
var _sigil_book: BookPager = null      # книга-Аркан (страницы-вкладки)
var _sigil_pages: Dictionary = {}     # tab -> страница (VBoxContainer)
var _sigil_fullscreen: Control = null  # полноэкранный просмотр карты; != null ⇒ открыт
var _sigil_claim_layer: Control = null  # попап награды клейма майлстоуна; != null ⇒ открыт
var _sigil_set_screen: Control = null  # экран комплекта (Task 7b); != null ⇒ открыт
var _sigil_render_busy := false  # превью-рендер в полёте: у сервиса один SubViewport, фуллскрин ждёт (T5-M2)

var _sigil_craft_screen: Control = null
var _sigil_craft_data: Dictionary = {}
var _sigil_placed: Dictionary = {}  ## element_id -> placed_count
## Списанные ресурсы до ответа сервера: нужны, чтобы вернуть их при отказе.
var _sigil_pending_craft: Dictionary = {}
## Board подтвердил: все элементы на круге — запускаем крафт (списание+сервер).
var _sigil_craft_ritual: SigilCraftRitual = null
var _pending_craft_result: Dictionary = {}
var _popup_swipe_start := Vector2.ZERO

func _open_sigil_modal(start_tab: String = "crafts") -> void:
	if _sigil_coll != null or main._sigil == null:
		return
	Sfx.click()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 20
	_sigil_coll = dim
	add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_collection()
	)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(margin)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", main._panel_style(Color(0.055, 0.065, 0.10, 0.99), 18))
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Аркан — КНИГА (BookPager): вкладки стали страницами, переход — листание.
	var book := BookPager.new()
	book.name = "SigilBook"
	book.accent = Color(0.85, 0.72, 0.42)
	book.offset_left = 0
	book.offset_right = 0
	book.offset_top = 0
	book.offset_bottom = 0
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.close_requested.connect(_close_sigil_collection)
	book.page_requested.connect(func(to_i: int) -> void:
		_sigil_build_page(["crafts", "collection", "sets"][to_i]))
	book.flipped.connect(func(_a: int, _b: int) -> void: Sfx.click())
	vbox.add_child(book)
	_sigil_book = book
	_sigil_tab_btns = []

	# Страницы-вкладки: Крафты дня, Коллекция, Комплекты. Билдеры ожидают
	# VBoxContainer (content) — страницы делаем VBoxContainer.
	var craft_page := VBoxContainer.new()
	var coll_page := VBoxContainer.new()
	var sets_page := VBoxContainer.new()
	craft_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coll_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sets_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sets_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.add_page("КРАФТЫ ДНЯ", craft_page)
	book.add_page("КОЛЛЕКЦИЯ", coll_page)
	book.add_page("КОМПЛЕКТЫ", sets_page)
	_sigil_pages = {"crafts": craft_page, "collection": coll_page, "sets": sets_page}
	# Отступы контента от рамки бумаги (корешок слева, тени) — иначе
	# содержимое вплотную к рамке.
	for p in [craft_page, coll_page, sets_page]:
		p.offset_left = 18.0
		p.offset_right = -14.0
		p.offset_top = 8.0
		p.offset_bottom = -12.0
	_sigil_tab_content = craft_page
	# Контент стартовой страницы строим сразу (книга ещё закрыта, но к первому
	# снимку листа страница обязана быть готова). Обложка и перелистывание — в
	# _open_sigil_book_and_show_tab: open_book() и go_to() оба владеют
	# busy/_shield, поэтому запускать их одновременно нельзя.
	_sigil_build_page(start_tab)
	_open_sigil_book_and_show_tab.call_deferred(start_tab)


## Открыть книгу Аркана (обложка откидывается) и показать стартовую страницу.
## Перелистывание — строго после open_book(): если запустить go_to() во время
## открытия, щит одного гаснет, пока второй ещё анимируется, и ввод попадает в
## книгу. Корутина — await в месте вызова.
func _open_sigil_book_and_show_tab(tab: String) -> void:
	await _open_sigil_book()
	_sigil_show_tab(tab)


## Открыть книгу Аркана (обложка откидывается). Корутина — await в месте вызова.
func _open_sigil_book() -> void:
	if _sigil_book != null and is_instance_valid(_sigil_book):
		await _sigil_book.open_book()


## Программный переход на вкладку: строит контент и листает книгу. Старое
## содержимое сносится целиком, билдер строит заново; поколение _sigil_tab_seq
## гасит корутины билдеров, чтобы предыдущая вкладка не достраивалась поверх
## новой после своего await.
func _sigil_show_tab(tab: String) -> void:
	if _sigil_coll == null:
		return
	_sigil_build_page(tab)
	if _sigil_book != null and is_instance_valid(_sigil_book):
		var idx: int = {"crafts": 0, "collection": 1, "sets": 2}[tab]
		_sigil_book.go_to(idx)


## Строит контент страницы-вкладки книги (без перелистывания).
## Вызывается из page_requested — до снимка листа, чтобы новая страница
## уже была отрендерена, когда лист откроет её.
func _sigil_build_page(tab: String) -> void:
	if _sigil_coll == null:
		return
	if tab != "crafts" and tab != "collection" and tab != "sets":
		tab = "crafts"
	var page: Control = _sigil_pages.get(tab)
	if page == null:
		return
	# Уже активная и построенная страница — не перестраиваем (page_requested
	# при программном go_to не должен дублировать контент).
	if tab == _sigil_tab and page.get_child_count() > 0:
		return
	# Сносим содержимое СТАРОЙ страницы (билдер асинхронный — мог оставить
	# статус-лейбл/демо-контент), затем строим новую.
	var prev: Control = _sigil_pages.get(_sigil_tab, page)
	if prev != page and prev != null:
		for c in prev.get_children():
			(c as Node).queue_free()
	_sigil_tab = tab
	_sigil_tab_seq += 1
	_sigil_tab_content = page
	for c in page.get_children():
		(c as Node).queue_free()
	match tab:
		"collection":
			_sigil_build_collection_tab(_sigil_tab_content)
		"sets":
			_sigil_build_sets_tab(_sigil_tab_content)
		_:
			_sigil_build_crafts_tab(_sigil_tab_content)


## Вкладка «Крафты дня»: бывшее тело _open_sigil_modal — загрузка и строки.
func _sigil_build_crafts_tab(container: Control) -> void:
	var seq := _sigil_tab_seq
	var dim := _sigil_coll
	var status: Label = main._label("Загружаю крафты…", 15)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	main._sigil.request_catalog()
	await _await_catalog(10.0)
	main._sigil.request_collection(main._online._device_id)
	main._sigil.request_daily(main._online._device_id)
	var loaded := await _await_daily_crafts(10.0)
	if seq != _sigil_tab_seq or _sigil_coll != dim or not is_instance_valid(container):
		return
	var crafts: Array = main._sigil._daily_crafts
	if not loaded or crafts.is_empty():
		status.text = "Сервер не ответил.\nКрафты появятся, когда вернётся связь."
		status.add_theme_color_override("font_color", Color(0.78, 0.58, 0.46))
		var retry: Button = main._small_button("Повторить", Vector2(180, 46), 2)
		retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		retry.pressed.connect(func():
			_close_sigil_collection()
			_open_sigil_modal.call_deferred()
		)
		container.add_child(retry)
		return
	status.queue_free()
	scroll.visible = true
	var rows: Array = []
	for craft in crafts:
		var row := _sigil_craft_row(craft)
		list.add_child(row)
		rows.append(row)
	# Список показываем сразу, картинки дорисовываем по одной: рендер круга
	# требует кадров, а ждать все три до первого пикселя — значит держать
	# игрока на пустом экране.
	for i in rows.size():
		_sigil_render_busy = true
		var tex: ImageTexture = await main._sigil.preview_texture(crafts[i])
		_sigil_render_busy = false
		if seq != _sigil_tab_seq or _sigil_coll != dim or tex == null:
			continue
		_sigil_fill_preview((rows[i] as Control).get_meta("preview"), tex)


## Вкладка «Коллекция»: сетка 4 колонки собранных карт, ниже — отдельная
## секция хроматики. Порядок ячеек — по каталогу: сеты в порядке catalog_sets,
## внутри сета — порядок card_ids; карты без сета — в конце.
func _sigil_build_collection_tab(container: Control) -> void:
	var seq := _sigil_tab_seq
	var dim := _sigil_coll
	var coll: Dictionary = main._sigil._server_collection
	var extras: Array = main._sigil.server_extras()
	if coll.is_empty() and extras.is_empty():
		var empty: Label = main._label("Пока пусто — крафты дня ждут", 16)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		container.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var grid := GridContainer.new()
	grid.name = "SigilCollGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)

	var ordered: Array = []
	var seen := {}
	for s in main._sigil.catalog_sets():
		for cid in (s as Dictionary).get("card_ids", []):
			var cs := str(cid)
			if seen.has(cs):
				continue
			seen[cs] = true
			if coll.has(cs) and not main._sigil.card(cs).is_empty():
				ordered.append(cs)
	for cid in coll:
		var cs := str(cid)
		if not seen.has(cs) and not main._sigil.card(cs).is_empty():
			ordered.append(cs)
	var pending: Array = []
	for cs in ordered:
		var cell := _sigil_collection_cell(_sigil_catalog_entry(cs, coll[cs]))
		grid.add_child(cell)
		pending.append([cell, {"card_id": cs}])

	if not extras.is_empty():
		var section := VBoxContainer.new()
		section.name = "SigilChromaSection"
		section.add_theme_constant_override("separation", 8)
		list.add_child(section)
		var st: Label = main._label("ХРОМАТИКА", 14)
		st.autowrap_mode = TextServer.AUTOWRAP_OFF
		st.add_theme_color_override("font_color", Color(1.0, 0.55, 0.12))
		section.add_child(st)
		var cgrid := GridContainer.new()
		cgrid.columns = 4
		cgrid.add_theme_constant_override("h_separation", 10)
		cgrid.add_theme_constant_override("v_separation", 10)
		section.add_child(cgrid)
		for x in extras:
			var xe := x as Dictionary
			var entry := {
				"card_id": "", "craft_id": str(xe.get("craft_id", "")),
				"rarity": str(xe.get("rarity", "chromatic")),
				"name": str(xe.get("llm_name", "")), "set": "",
				"set_title": "Вне комплектов",
				"first_at": str(xe.get("crafted_at", "")), "copies": 1,
				"seed": int(xe.get("seed", 0)),
				"lore": str(xe.get("lore", "")),
				# Ингредиенты хроматика (сервер хранит их при крафте) — тот же
				# SigilLore.generate, что у комплектных карт, работает от recipe.
				"recipe": xe.get("ingredients", []),
			}
			var ccell := _sigil_collection_cell(entry)
			cgrid.add_child(ccell)
			# Экстрас (хроматик): уникальная картинка по seed. Ключ дискового кэша
			# зависит от _cache_extra — ставим его по seed, чтобы разные хроматики
			# не коллизировали в один PNG (глобальный _cache_extra это ломал).
			var xseed := int(xe.get("seed", 0))
			if xseed != 0:
				main._sigil._cache_extra = "chromatic|object|%d" % xseed
			var cimg: Image = main._sigil._load_cached_image(str(xe.get("craft_id", "")))
			if cimg == null:
				cimg = await main._sigil.generate_card(
					str(xe.get("craft_id", "")), PackedStringArray(),
					&"chromatic", &"object", str(xe.get("llm_name", "")))
				if cimg != null:
					main._sigil._save_cached_image(str(xe.get("craft_id", "")), cimg)
					main._sigil._cache_extra = ""
			if cimg != null:
				_sigil_fill_preview(ccell.get_meta("preview"),
					ImageTexture.create_from_image(cimg))

	# Мини-арты дорисовываем по одному, как в списке крафтов: клетки и бейджи
	# видны сразу, картинки приходят кадром позже.
	for p in pending:
		_sigil_render_busy = true
		var tex: ImageTexture = await main._sigil.preview_texture(p[1])
		_sigil_render_busy = false
		if seq != _sigil_tab_seq or _sigil_coll != dim or tex == null:
			continue
		_sigil_fill_preview((p[0] as Control).get_meta("preview"), tex)


## Вкладка «Комплекты»: панель на каждый комплект каталога — титул из
## каталога, прогресс «N/25», ProgressBar и ряд точек-майлстоунов 3/6/13/25.
## Экран комплекта с сеткой карт и силуэтами — Task 7b.
func _sigil_build_sets_tab(container: Control) -> void:
	var sets: Array = main._sigil.catalog_sets()
	if sets.is_empty():
		var empty: Label = main._label("Комплекты появятся после загрузки каталога", 16)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		container.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s in sets:
		list.add_child(_sigil_set_panel(s as Dictionary))


## Панель комплекта: титул стихии, прогресс «N/25», ProgressBar и ряд из четырёх
## точек-майлстоунов. Титул и порядок — из catalog_sets(); собранные карты —
## пересечение _server_collection с card_ids сета (has_collected).
func _sigil_set_panel(set_def: Dictionary) -> Control:
	var set_id := str(set_def.get("id", ""))
	var accent := _sigil_set_accent(set_id)
	var panel := PanelContainer.new()
	# Имя уникально по сету: find_children ищет по wildcard, add_child
	# переименовывает одинаковые имена соседей.
	panel.name = "SigilSetPanel_" + set_id
	panel.set_meta("set_id", set_id)
	panel.add_theme_stylebox_override("panel", _sigil_row_style(accent, 0.0))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title: Label = main._label(str(set_def.get("title", "")), 17)
	title.name = "SigilSetTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)

	var collected := 0
	var ids = set_def.get("card_ids", [])
	if ids is Array:
		for cid in (ids as Array):
			if main._sigil.has_collected(str(cid)):
				collected += 1
	var count: Label = main._label("%d/%d" % [collected, main.SIGIL_SET_SIZE], 14)
	count.name = "SigilSetCount"
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_color_override("font_color", Color(0.72, 0.74, 0.80))
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)

	var bar := ProgressBar.new()
	bar.name = "SigilSetProgress"
	bar.max_value = float(main.SIGIL_SET_SIZE)
	bar.value = float(clampi(collected, 0, main.SIGIL_SET_SIZE))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.045, 0.07, 1.0)
	bar_bg.set_corner_radius_all(5)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(accent.r, accent.g, accent.b, 0.3)
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(accent.r, accent.g, accent.b, 0.85)
	bar_fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(bar)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 10)
	box.add_child(dots)
	var claimed: Array = main._sigil.claimed_tiers(set_id)
	for tier in [3, 6, 13, 25]:
		dots.add_child(_sigil_milestone_dot(set_id, tier, collected, claimed))
	# Тап по панели (вне точек-майлстоунов) открывает экран комплекта — точки
	# живут по своим координатам, чтобы клейм не спотыкался о навигацию.
	var dot_boxes: Array = []
	for c in dots.get_children():
		dot_boxes.append(c as Control)
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			var pos := (ev as InputEventMouseButton).global_position
			for db in dot_boxes:
				if db.get_global_rect().has_point(pos):
					return
			_open_sigil_set_screen(set_id)
	)
	return panel


## Экран комплекта (Task 7b): фуллскрин-слой над модалкой (z=30) с сеткой 25
## карт сета. Собранные карты каталога — мини-арт из превью-кэша и тап на
## фуллскрин карты; несобранные и неизвестные каталогу — СИЛУЭТ: тёмный
## контур круга + «???», без имени и без арта (спека: без спойлера).
## ✕ закрывает слой — вкладка «Комплекты» под ним остаётся как есть.
func _open_sigil_set_screen(set_id: String) -> void:
	if _sigil_set_screen != null or main._sigil == null or _sigil_coll == null:
		return
	var set_def: Dictionary = {}
	for s in main._sigil.catalog_sets():
		if str((s as Dictionary).get("id", "")) == set_id:
			set_def = s as Dictionary
			break
	if set_def.is_empty():
		return
	Sfx.click()
	var root := Control.new()
	root.name = "SigilSetScreen"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_set_screen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_set_screen()
	)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		main._panel_style(Color(0.055, 0.065, 0.10, 0.99), 18))
	margin.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var accent := _sigil_set_accent(set_id)
	var collected := 0
	var ids: Array = set_def.get("card_ids", [])
	for cid in ids:
		if main._sigil.has_collected(str(cid)):
			collected += 1

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var title: Label = main._label("%s · %d/%d" % [str(set_def.get("title", "")),
		collected, main.SIGIL_SET_SIZE], 20)
	title.name = "SigilSetScreenTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close_btn: Button = main._small_button("✕", Vector2(46, 40))
	close_btn.name = "SigilSetClose"
	close_btn.tooltip_text = "Закрыть"
	close_btn.pressed.connect(_close_sigil_set_screen)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "SigilSetGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var pending: Array = []
	for cid in ids:
		var cs := str(cid)
		var coll_entry: Dictionary = {}
		if main._sigil._server_collection.has(cs):
			coll_entry = main._sigil._server_collection[cs]
		var cell := _sigil_set_cell(cs, coll_entry)
		grid.add_child(cell)
		if not main._sigil.card(cs).is_empty() and main._sigil.has_collected(cs):
			pending.append([cell, {"card_id": cs}])
	# Мини-арты — из превью-кэша по одному, как в коллекции: сетка с силуэтами
	# видна сразу, картинки приходят кадром позже (рендер — только на промах).
	var scr := root
	for p in pending:
		_sigil_render_busy = true
		var tex: ImageTexture = await main._sigil.preview_texture(p[1])
		_sigil_render_busy = false
		if _sigil_set_screen != scr or not is_instance_valid(p[0]):
			continue
		if tex != null:
			_sigil_fill_preview((p[0] as Control).get_meta("preview"), tex)


## Закрыть экран комплекта: слой уходит, вкладка «Комплекты» под ним остаётся
## как есть (без перестройки — спека Task 7b: «возврат к вкладке»).
func _close_sigil_set_screen() -> void:
	if _sigil_set_screen == null:
		return
	var s := _sigil_set_screen
	_sigil_set_screen = null
	s.queue_free()
	Sfx.click()


## Ячейка сетки комплекта: собранная карта каталога — кнопка с мини-артом и
## тапом на фуллскрин карты; несобранная или неизвестная каталогу — силуэт:
## тёмный контур круга + «???», без имени и без арта (спека: без спойлера).
func _sigil_set_cell(card_id: String, coll_entry: Dictionary) -> Control:
	var card: Dictionary = main._sigil.card(card_id)
	if not card.is_empty() and main._sigil.has_collected(card_id):
		var entry := _sigil_catalog_entry(card_id, coll_entry)
		var accent: Color = main._rarity_color(str(entry.get("rarity", "common")))
		var btn := Button.new()
		btn.name = "SigilSetCell_" + card_id
		btn.custom_minimum_size = Vector2(0, 110)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_contents = true
		btn.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0))
		btn.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05))
		btn.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09))
		btn.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_open_sigil_fullscreen.bind(entry))
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(holder)
		# Button не контейнер: якоря — до ручных офсетов.
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.offset_left = 6
		holder.offset_top = 6
		holder.offset_right = -6
		holder.offset_bottom = -6
		var shot := _sigil_preview_slot(accent, 0)
		shot.custom_minimum_size = Vector2(0, 0)
		holder.add_child(shot)
		shot.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.set_meta("preview", shot)
		btn.set_meta("card_id", card_id)
		return btn
	var box := PanelContainer.new()
	box.name = "SigilSetCell_" + card_id
	box.custom_minimum_size = Vector2(0, 110)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.07, 1.0)
	sb.border_color = Color(0.42, 0.45, 0.52, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var ring := SigilSilhouette.new()
	ring.name = "SigilSilhouetteRing"
	ring.custom_minimum_size = Vector2(64, 64)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ring)
	var q: Label = main._label("???", 16)
	q.autowrap_mode = TextServer.AUTOWRAP_OFF
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_color_override("font_color", Color(0.45, 0.49, 0.58))
	vb.add_child(q)
	box.set_meta("card_id", card_id)
	return box


## Точка-майлстоун комплекта: claimed — приглушённая с отметкой; claimable
## (N >= порог и не claimed) — золотая, тап шлёт клейм; locked — тусклая.
func _sigil_milestone_dot(set_id: String, tier: int, collected: int,
		claimed: Array) -> Button:
	var is_claimed := claimed.has(tier)
	var is_claimable := not is_claimed and collected >= tier
	var state := "claimed" if is_claimed else ("claimable" if is_claimable else "locked")
	var dot := Button.new()
	dot.name = "SigilDot" + str(tier)
	dot.custom_minimum_size = Vector2(34, 34)
	dot.focus_mode = Control.FOCUS_NONE
	dot.set_meta("tier", tier)
	dot.set_meta("set_id", set_id)
	dot.set_meta("state", state)
	dot.disabled = not is_claimable
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.065, 0.10, 1.0)
	if is_claimable:
		sb.border_color = Color(0.90, 0.82, 0.56, 0.95)
		sb.set_border_width_all(2)
	else:
		sb.border_color = Color(0.42, 0.45, 0.52, 0.55 if is_claimed else 0.3)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(17)
	dot.add_theme_stylebox_override("normal", sb)
	dot.add_theme_stylebox_override("hover", sb)
	dot.add_theme_stylebox_override("pressed", sb)
	dot.add_theme_stylebox_override("disabled", sb)
	dot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var num := Label.new()
	num.text = str(tier)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_size_override("font_size", 12)
	num.autowrap_mode = TextServer.AUTOWRAP_OFF
	var fg := Color(0.90, 0.85, 0.62) if is_claimable else Color(0.55, 0.58, 0.66)
	num.add_theme_color_override("font_color", fg)
	dot.add_child(num)
	# Button не контейнер: якорь до ручных офсетов.
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	if is_claimable:
		dot.pressed.connect(_sigil_claim_milestone.bind(set_id, tier))
	if is_claimed:
		# Глиф «✓» вне шрифта Manrope: отметка рисуется, а не печатается.
		var mark := SigilMilestoneMark.new()
		mark.name = "SigilDotMark"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_child(mark)
		mark.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		mark.offset_left = -16.0
		mark.offset_top = 2.0
		mark.offset_right = -2.0
		mark.offset_bottom = 14.0
	return dot


## Тап по claimable-точке: клейм уходит на сервер, офлайн — в очередь Net.
func _sigil_claim_milestone(set_id: String, tier: int) -> void:
	Sfx.click()
	main._sigil.request_milestone_claim(main._online._device_id, set_id, tier)


## Тексты наград майлстоунов — дословно из брифа Task 7 (минус — U+2212).
func _sigil_milestone_reward_text(tier: int) -> String:
	match tier:
		3: return "+40 к капу эфира"
		6: return "−10% эфира крафтов комплекта"
		13: return "Верстак ×2 для стихии"
		25: return "Четвёртый слот дневного крафта"
		_: return ""


## Акцент стихии для панелей комплектов.
func _sigil_set_accent(set_id: String) -> Color:
	match set_id:
		"fire": return Color(0.98, 0.55, 0.32)
		"water": return Color(0.33, 0.68, 1.0)
		"air": return Color(0.55, 0.85, 0.92)
		"earth": return Color(0.82, 0.66, 0.42)
		_: return Color(0.62, 0.66, 0.72)


## Main-обработчик клейма майлстоуна (вторая подписка на sigil_milestone_result):
## ok && claimed — попап награды и refresh коллекции, чтобы флаги перерисовались.
## Офлайн-форма и ошибки ничего не делают — эффекты строго по серверу.
func _on_sigil_milestone_result(result: Dictionary) -> void:
	if not result.get("ok", false) or not result.get("claimed", false):
		return
	var tier := int(result.get("tier", 0))
	Sfx.achievement()
	_sigil_claim_popup(tier)
	main._sigil.request_collection(main._online._device_id)


## Попап «Награда получена»: слой поверх модалки (z=20) и фуллскрина (z=30),
## закрытие по OK или тапу по фону. Неизвестный тир награды попап не строит.
func _sigil_claim_popup(tier: int) -> void:
	var reward := _sigil_milestone_reward_text(tier)
	if reward == "" or _sigil_claim_layer != null:
		return
	Sfx.click()
	var root := Control.new()
	root.name = "SigilSetScreen"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_claim_layer = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_sigil_claim_popup()
	)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", main._panel_style(Color(0.05, 0.05, 0.08, 0.98), 12))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title: Label = main._label("Награда получена", 20)
	title.name = "SigilClaimTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.56))
	vbox.add_child(title)

	var body: Label = main._label(reward, 15)
	body.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	vbox.add_child(body)

	var ok_btn: Button = main._small_button("OK", Vector2(120, 40))
	ok_btn.name = "SigilClaimOk"
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.pressed.connect(_close_sigil_claim_popup)
	vbox.add_child(ok_btn)


func _close_sigil_claim_popup() -> void:
	if _sigil_claim_layer == null:
		return
	var d := _sigil_claim_layer
	_sigil_claim_layer = null
	d.queue_free()
	Sfx.click()


## Ячейка коллекции: кнопка с плейсхолдером превью, бейдж «×N» в углу при
## копиях больше одной; тап открывает полноэкранный просмотр.
func _sigil_collection_cell(entry: Dictionary) -> Control:
	var rarity := str(entry.get("rarity", "common"))
	var accent: Color = main._rarity_color(rarity)
	var copies := int(entry.get("copies", 1))
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(0, 200)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.clip_contents = true
	cell.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0))
	cell.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05))
	cell.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09))
	cell.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0))
	cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cell.pressed.connect(_open_sigil_fullscreen.bind(entry))

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	# Button не контейнер: якоря — до ручных офсетов.
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.offset_left = 8
	holder.offset_top = 8
	holder.offset_right = -8
	holder.offset_bottom = -8

	var shot := _sigil_preview_slot(accent, 150)
	holder.add_child(shot)
	shot.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell.set_meta("preview", shot)

	if copies > 1:
		var badge := _sigil_badge("×%d" % copies, accent)
		holder.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		var bs: Vector2 = badge.get_combined_minimum_size()
		badge.offset_left = -(bs.x + 4)
		badge.offset_top = 4
		badge.offset_right = -2
		badge.offset_bottom = 4 + bs.y
	return cell


## Entry полноэкранного просмотра карты каталога: имя/редкость/сет берутся
## из каталога, дата и копии — из серверной записи коллекции.
func _sigil_catalog_entry(card_id: String, coll_entry: Dictionary) -> Dictionary:
	var card: Dictionary = main._sigil.card(card_id)
	if card.is_empty():
		return {}
	var set_title := ""
	for s in main._sigil.catalog_sets():
		if str((s as Dictionary).get("id", "")) == str(card.get("set", "")):
			set_title = str((s as Dictionary).get("title", ""))
			break
	return {
		"card_id": card_id,
		"craft_id": "",
		"rarity": str(card.get("rarity", "common")),
		"name": str(card.get("fallback_name", "")),
		"set": str(card.get("set", "")),
		"set_title": set_title,
		"first_at": str(coll_entry.get("first_at", "")),
		"copies": int(coll_entry.get("copies", 1)),
		# Task 5C: поля для lore-генератора и будущего подпроекта D.
		"process": str(card.get("process", "")),
		"stage": str(card.get("stage", "")),
		"seed": int(card.get("seed", 0)),
		"recipe": card.get("recipe", []),
	}


## ISO-дата получения → «ДД.ММ.ГГГГ»: первые 10 символов до «T»,
## компоненты в обратном порядке.
func _sigil_date_ru(iso: String) -> String:
	var day := iso.substr(0, 10).split("T")[0]
	var p := day.split("-")
	if p.size() == 3:
		return "%s.%s.%s" % [p[2], p[1], p[0]]
	return day


## Полноэкранный просмотр карты коллекции — паттерн _show_sigil_card:
## затемнение + центральная панель. Закрытие: кнопка, тап по фону, свайп
## длиннее 80 px в любую сторону. Под артом — пустой якорь для lore-блока
## подпроекта C.
func _open_sigil_fullscreen(entry: Dictionary) -> void:
	if entry.is_empty() or _sigil_fullscreen != null or main._sigil == null:
		return
	var rarity := str(entry.get("rarity", "common"))
	# Хроматик — своё «раскрытие карты» (торжественный звук вместо клика).
	if rarity == "chromatic":
		Sfx.ritual_reveal()
	else:
		Sfx.click()
	var accent: Color = main._rarity_color(rarity)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 30
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil_fullscreen = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", main._panel_style(Color(0.05, 0.05, 0.08, 0.98), 12))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	# Отступы объектов внутри попапа от краёв панели.
	vbox.add_theme_constant_override("margin_left", 14)
	vbox.add_theme_constant_override("margin_right", 14)
	vbox.add_theme_constant_override("margin_top", 14)
	vbox.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(vbox)

	var title_lbl: Label = main._label(str(entry.get("name", "")), 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(title_lbl)

	# Живая карточка: SubViewportContainer + SigilCard (анимированная аура,
	# искры/фольга — как в sigil_module_v2). _svc.preview_into подключает
	# вьюпорт сервиса; UPDATE_ALWAYS заставляет его жить (иначе статика).
	# Переворачиваемая карточка: лицо = живой рендер, оборот = лор.
	var card_flip := Control.new()
	card_flip.name = "SigilCardFlip"
	card_flip.custom_minimum_size = Vector2(405, 540)
	card_flip.size = Vector2(405, 540)
	card_flip.mouse_filter = Control.MOUSE_FILTER_STOP
	card_flip.pivot_offset = Vector2(202, 270)
	card_flip.set_meta("flipped", false)
	card_flip.set_meta("busy", false)
	vbox.add_child(card_flip)

	# Лицо: живой рендер карточки (аура/фольга/искры по редкости).
	# Лицо: живой рендер карточки (аура/фольга/искры по редкости).
	var face := _sigil_live_card(entry)
	face.name = "SigilFace"
	# Каскад появления: слои собираются из центра по одному. deferred —
	# чтобы вьюпорт успел разложить размеры до первого тика твина.
	if main._live_card_node != null and is_instance_valid(main._live_card_node):
		main._live_card_node.play_reveal.call_deferred()
	# SubViewportContainer нельзя растягивать preset-ом: он сам задаёт размер
	# вьюпорту. Фикс. размер 300x540, центрирование — через size_flags.
	face.size = Vector2(405, 540)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_flip.add_child(face)

	# Оборот: лор (скролл).
	var lore := ScrollContainer.new()
	lore.name = "SigilBack"
	lore.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lore.visible = false
	# Фон оборотной стороны, чтобы текст читался (не «прозрачная» карта).
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.07, 0.07, 0.11, 1.0)
	lsb.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(12)
	lore.add_theme_stylebox_override("panel", lsb)
	card_flip.add_child(lore)
	var lore_v := VBoxContainer.new()
	lore_v.add_theme_constant_override("separation", 12)
	lore_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Отступы текста от краёв оборотной стороны.
	lore_v.add_theme_constant_override("margin_left", 12)
	lore_v.add_theme_constant_override("margin_right", 12)
	lore_v.add_theme_constant_override("margin_top", 12)
	lore_v.add_theme_constant_override("margin_bottom", 12)
	lore.add_child(lore_v)
	# Лор: тот же детерминированный генератор, что у комплектных карт
	# (SigilLore.generate от (id, seed)). Хроматики получают seed и ингредиенты
	# с сервера — SigilLore даёт такой же структурированный текст {title,
	# description, effect_hint, warning}, как у комплектов, а не плоский
	# LLM-абзац. Серверный lore больше не используется как source — только
	# как fallback при пустом seed.
	var srv_lore := str(entry.get("lore", ""))
	# Процесс/стадия у внекомплектных — детерминированные от seed, иначе
	# SigilLore (тот же генератор, что у комплектных) не найдёт совместимых
	# слотов и вернёт пустоту.
	var ps_pairs := [
		["calcinatio", "nigredo"], ["putrefactio", "nigredo"],
		["sublimatio", "albedo"], ["coniunctio", "albedo"],
		["coniunctio", "rubedo"], ["calcinatio", "rubedo"],
		["sublimatio", "citrinitas"], ["coniunctio", "citrinitas"],
	]
	var _entry_seed := int(entry.get("seed", 0))
	var _ps: Array = ps_pairs[abs(_entry_seed) % ps_pairs.size()]
	# id для лора: у каталожных карт — card_id (craft_id пуст), у хроматиков —
	# craft_id (card_id пуст). Пустой craft_id НЕ должен маскировать card_id.
	var _lore_id := str(entry.get("craft_id", ""))
	if _lore_id == "":
		_lore_id = str(entry.get("card_id", ""))
	var card_lore := SigilLore.generate({
		"id": _lore_id,
		"process": str(entry.get("process", _ps[0])),
		"stage": str(entry.get("stage", _ps[1])),
		"seed": _entry_seed,
		"recipe": entry.get("recipe", []),
	})
	if card_lore.is_empty() and rarity == "chromatic":
		if srv_lore != "":
			card_lore = {
				"title": str(entry.get("name", "Внекомплектный сигил")),
				"description": srv_lore,
				"effect_hint": "Не влияет на комплекты; коллекционная ценность.",
				"warning": "",
			}
		else:
			card_lore = {
				"title": "Внекомплектный сигил",
				"description": "Эта карта не входит ни в один комплект стихий. "
					+ "Её создали из случайного сочетания ингредиентов — "
					+ "призма редкости, светящаяся вне обычных графов трансмутации.",
				"effect_hint": "Не влияет на комплекты; коллекционная ценность.",
				"warning": "",
			}
	if not card_lore.is_empty():
		var lt: Label = main._label(str(card_lore.get("title", "")), 16)
		lt.name = "SigilLoreTitle"
		if main._font_lore != null:
			lt.add_theme_font_override("font", main._font_lore)
		lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lt.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
		lore_v.add_child(lt)
		var ld: Label = main._label(str(card_lore.get("description", "")), 13)
		ld.name = "SigilLoreDesc"
		if main._font_lore != null:
			ld.add_theme_font_override("font", main._font_lore)
		ld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ld.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ld.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78))
		lore_v.add_child(ld)
		var le: Label = main._label(str(card_lore.get("effect_hint", "")), 12)
		le.name = "SigilLoreEffect"
		if main._font_lore != null:
			le.add_theme_font_override("font", main._font_lore)
		le.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		le.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		le.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
		lore_v.add_child(le)
		var lw: Label = main._label(str(card_lore.get("warning", "")), 12)
		lw.name = "SigilLoreWarn"
		if main._font_lore != null:
			lw.add_theme_font_override("font", main._font_lore)
		lw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lw.add_theme_color_override("font_color", Color(0.8, 0.45, 0.4))
		lore_v.add_child(lw)

	card_flip.gui_input.connect(_sigil_flip_card.bind(card_flip))
	# GIF-демо: авто-переворот через 2 с (после ритуала).
	if main._demo_harness != null and main._demo_harness._gif_dir != "":
		main._demo_flip_timer = {"card": card_flip, "at": Time.get_ticks_msec() + 2000}

	# Ритуал-оверлей ОТКЛЮЧЁН: его круг перекрывал живую SigilCard
	# (pivot в 0,0 → свечение уезжало в правый нижний угол). Живая карточка
	# в SubViewport уже анимируется (аура/фольга/искры) — ритуал не нужен.

	var rar_lbl: Label = main._label(_sigil_rarity_title(rarity), 14)
	rar_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rar_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(rar_lbl)

	var set_lbl: Label = main._label("Комплект: %s" % str(entry.get("set_title", "")), 13)
	set_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
	vbox.add_child(set_lbl)

	var got_lbl: Label = main._label("Получена: %s" % _sigil_date_ru(str(entry.get("first_at", ""))), 13)
	got_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	got_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	got_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.70))
	vbox.add_child(got_lbl)

	var copies_lbl: Label = main._label("копии: ×%d" % int(entry.get("copies", 1)), 13)
	copies_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	copies_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copies_lbl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	vbox.add_child(copies_lbl)

	var close_btn: Button = main._small_button("Закрыть", Vector2(88, 36))
	close_btn.name = "SigilFsClose"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_close_sigil_fullscreen)
	vbox.add_child(close_btn)

	# Тап по фону и свайп в любую сторону закрывают; состояние перетаскивания
	# живёт в meta у center, чтобы оба обработчика видели одно и то же.
	center.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				center.set_meta("drag", ev.position)
			elif center.has_meta("drag"):
				var from: Vector2 = center.get_meta("drag")
				center.remove_meta("drag")
				if (ev.position - from).length() <= 80.0:
					_close_sigil_fullscreen()
		elif ev is InputEventMouseMotion and center.has_meta("drag"):
			var from: Vector2 = center.get_meta("drag")
			if (ev.position - from).length() > 80.0:
				center.remove_meta("drag")
				_close_sigil_fullscreen()
	)
	panel.gui_input.connect(func(ev):
		# Свайп, начавшийся на самой карте, тоже закрывает: панель перехватывает
		# press (STOP) и держит mouse focus, поэтому drag-meta кормим и отсюда —
		# тем же значением, что и фон. Релиз без драга снимает meta: тап по карте
		# не закрывает и не оставляет «висячего» жеста для hover-движений.
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				center.set_meta("drag", ev.position)
			elif center.has_meta("drag"):
				center.remove_meta("drag")
		elif ev is InputEventMouseMotion and center.has_meta("drag"):
			var from: Vector2 = center.get_meta("drag")
			if (ev.position - from).length() > 80.0:
				center.remove_meta("drag")
				_close_sigil_fullscreen()
	)



## Полный арт фуллскрина: для карты каталога — дисковый кэш по card_id, промах
## рендерится по карточному рецепту с полными опциями (как в get_card) и
## ложится в кэш; для extras — только дисковый кэш по craft_id, промах
## остаётся плейсхолдером. Рендер ждёт фоновые превью: у сервиса один
## SubViewport, параллельные рендеры портят картинки друг друга (хазард T5-M2).
func _sigil_fill_fullscreen_art(slot: Control, entry: Dictionary) -> void:
	var fs := _sigil_fullscreen
	var card_id := str(entry.get("card_id", ""))
	if card_id == "":
		var img0: Image = main._sigil._load_cached_image(str(entry.get("craft_id", "")))
		if img0 != null and _sigil_fullscreen == fs:
			_sigil_fill_preview(slot, ImageTexture.create_from_image(img0))
		return
	var img: Image = main._sigil._load_cached_image(card_id)
	if img == null:
		var waited := 0.0
		while _sigil_render_busy and waited < 1.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		if _sigil_fullscreen != fs or not is_instance_valid(slot):
			return
		var recipe: SigilRecipe = main._sigil.card_recipe_for({"card_id": card_id})
		img = await main._sigil._svc.render(recipe, main._sigil._options)
		if img != null and _sigil_fullscreen == fs:
			main._sigil._save_cached_image(card_id, img)
	if img == null or _sigil_fullscreen != fs or not is_instance_valid(slot):
		return
	_sigil_fill_preview(slot, ImageTexture.create_from_image(img))


func _close_sigil_fullscreen() -> void:
	if _sigil_fullscreen == null:
		return
	var fs := _sigil_fullscreen
	_sigil_fullscreen = null
	main._live_card_node = null
	fs.queue_free()
	Sfx.click()


## Ждать ежедневные крафты, но не вечно: офлайн не должен вешать меню.
## Settled-флаг гасит ожидание сразу после офлайн-ответа, не по полному таймауту.
func _await_daily_crafts(timeout: float) -> bool:
	# Ждём ОТВЕТА сервера (daily_settled), а не просто непустого кэша: иначе
	# экран строится из устаревшего sigil_daily_cache.json раньше, чем придёт
	# свежий оффер («превью хроматик, крафт обычка» после ротации).
	# Кэш — только офлайн-фолбэк по таймауту.
	var waited := 0.0
	while not main._sigil.daily_settled() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return not main._sigil._daily_crafts.is_empty()


## Ждать каталог карт: без него превью меню рисовало бы посоленный fallback
## вместо общей карты каталога. Тот же приём, что у _await_daily_crafts:
## settled-флаг выходит из ожидания сразу после офлайн-ответа.
func _await_catalog(timeout: float) -> bool:
	var waited := 0.0
	while main._sigil.catalog_size() == 0 and not main._sigil.catalog_settled() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return main._sigil.catalog_size() > 0


## Строка крафта: слева круг, справа всё, что нужно для решения.
func _sigil_craft_row(craft: Dictionary) -> Control:
	var rarity := str(craft.get("rarity", "common"))
	var is_chromatic := bool(craft.get("is_chromatic", false))
	var ether_cost: int = main._sigil.craft_ether_cost(craft)
	var rc: Color = main._rarity_color(rarity)
	var accent: Color = Color(1.0, 0.55, 0.12) if is_chromatic else rc
	var shortages := _sigil_shortages(craft)
	var can_afford: bool = shortages.is_empty() and main._engine.ether >= ether_cost
	var n_ing := int((craft.get("ingredients", []) as Array).size())
	var title := _sigil_craft_title(craft)
	# Высота по содержимому: Button не контейнер и сам её не посчитает.
	var row_h := 107 + 21 * n_ing
	if not shortages.is_empty():
		row_h += 24
		if _sigil_shortage_text(shortages).length() > 48:
			row_h += 18
	if title.length() > 24:
		row_h += 24

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, maxi(176, row_h))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	btn.add_theme_stylebox_override("normal", _sigil_row_style(accent, 0.0, is_chromatic))
	btn.add_theme_stylebox_override("hover", _sigil_row_style(accent, 0.05, is_chromatic))
	btn.add_theme_stylebox_override("pressed", _sigil_row_style(accent, 0.09, is_chromatic))
	btn.add_theme_stylebox_override("disabled", _sigil_row_style(accent, 0.0, is_chromatic))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if can_afford:
		btn.pressed.connect(_open_sigil_craft.bind(craft))
	else:
		btn.disabled = true
		btn.modulate = Color(0.68, 0.68, 0.74, 0.92)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	# Button не контейнер: без якорей HBox остался бы нулевого размера.
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_top = 10
	row.offset_right = -14
	row.offset_bottom = -10

	var shot := _sigil_preview_slot(accent, 148)
	row.add_child(shot)
	btn.set_meta("preview", shot)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_lbl: Label = main._label(title, 18)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(name_lbl)

	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 8)
	info.add_child(badge_row)
	badge_row.add_child(_sigil_badge(_sigil_rarity_title(rarity), rc))
	if is_chromatic and rarity != "chromatic":
		badge_row.add_child(_sigil_badge("ХРОМА", Color(1.0, 0.55, 0.12)))

	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		info.add_child(_sigil_need_row(str(d.get("item_id", "")), int(d.get("qty", 0))))

	var price: Label = main._label("%d эфира" % ether_cost, 15)
	price.autowrap_mode = TextServer.AUTOWRAP_OFF
	price.add_theme_color_override("font_color",
		Color(0.62, 0.85, 0.66) if main._engine.ether >= ether_cost else Color(0.92, 0.48, 0.42))
	info.add_child(price)

	if not shortages.is_empty():
		var miss: Label = main._label(_sigil_shortage_text(shortages), 12)
		miss.add_theme_color_override("font_color", Color(0.92, 0.56, 0.46))
		miss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(miss)
	return btn


## Плейсхолдер превью: рамка в цвет редкости, картинка встанет сюда позже.
## Переворот карточки: лицо <-> оборот (лор) через scale.x-схлоп.
## Эмуляция тапа (для демо/GIF): один левый клик.
func _tap_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev



func _sigil_flip_card(ev: InputEvent, card_flip: Control) -> void:
	if not is_instance_valid(card_flip):
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if card_flip.get_meta("busy", false):
		return
	card_flip.set_meta("busy", true)
	var flipped: bool = card_flip.get_meta("flipped", false)
	var face := card_flip.get_node_or_null("SigilFace")
	var back := card_flip.get_node_or_null("SigilBack")
	# Настоящий переворот: двухстадийный scale.x-схлоп (без ломки layout,
	# pivot по центру; старый твин убиваем, чтобы не конкурировали).
	var tw := create_tween()
	card_flip.pivot_offset = card_flip.size / 2.0
	tw.tween_property(card_flip, "scale:x", 0.0, 0.18) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if face != null:
			face.visible = flipped
		if back != null:
			back.visible = not flipped
		card_flip.set_meta("flipped", not flipped)
		Sfx.click())
	tw.tween_property(card_flip, "scale:x", 1.0, 0.18) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		card_flip.set_meta("busy", false))




## Живая карточка для фуллскрина: SubViewportContainer поверх вьюпорта
## SigilRenderService, UPDATE_ALWAYS — чтобы аура/фольга/искры жили.
## Редкость/seed берутся из entry, поэтому свечения совпадают с редкостью.
func _sigil_live_card(entry: Dictionary) -> Control:
	# Свой SubViewport, а не общий вьюпорт SigilRenderService: общий занят
	# статичными рендерами (UPDATE_DISABLED) и не может быть переподключён.
	var recipe: SigilRecipe = main._sigil.card_recipe_for(entry)
	var rarity := str(entry.get("rarity", recipe.rarity))
	var prism_eff := ""
	# Хроматики — космос/призма поверх (Prism-эффекты card_beatify).
	if rarity == "chromatic":
		var effs := ["galaxy", "oil_slick", "textured_foil",
			"shattered_glass", "laser_refraction", "glitch"]
		prism_eff = effs[recipe.compute_seed() % effs.size()]
	var opts := SigilOptions.make({
		"card_size": Vector2i(405, 540),
		"show_name": true,
		"show_frame": true,
		"show_icon": true,
		"render_scale": 1,
		"prism_effect": prism_eff,
		"prism_phase": -1.0,
	})
	var box := SubViewportContainer.new()
	box.custom_minimum_size = Vector2(405, 540)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	box.stretch = true
	var vp := SubViewport.new()
	vp.name = "LiveCardViewport"
	vp.size = Vector2i(405, 540)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	# UPDATE_ALWAYS — чтобы аура/фольга/искры анимировались каждый кадр.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(vp)
	var card := SigilCard.new()
	card.name = "LiveCard"
	vp.add_child(card)
	card.setup(recipe, opts)
	card.set_live(true)
	# Живой режим: параллакс/дыхание иконки/каскад. Только для игровой
	# карточки в SubViewport, статичный рендер не трогаем.
	card.live_mode = true
	main._live_card_node = card
	return box


## Превью круга БЕЗ рамки (для крафт-экрана): просто текстурный холст.
func _sigil_preview_slot(accent: Color, side: int, border: bool = true) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(side, side)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.07, 1.0) if border else Color(0, 0, 0, 0)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55) if border else Color(0, 0, 0, 0)
	sb.set_border_width_all(1) if border else sb.set_border_width_all(0)
	sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rect)
	box.set_meta("rect", rect)
	var ph: Label = main._label("…", 28)
	ph.name = "Ph"
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ph)
	return box


func _sigil_fill_preview(box: Control, tex: ImageTexture) -> void:
	if box == null or not is_instance_valid(box):
		return
	var rect: TextureRect = box.get_meta("rect")
	rect.texture = tex
	var ph := box.get_node_or_null("Ph")
	if ph != null:
		ph.visible = false


func _sigil_row_style(accent: Color, lift: float, is_chromatic: bool = false) -> StyleBox:
	var sb := StyleBoxFlat.new()
	if is_chromatic:
		# Хроматик выделяется: тёплый фон и золотая рамка потолще.
		sb.bg_color = Color(0.16 + lift, 0.11 + lift, 0.06 + lift, 1.0)
		sb.border_color = Color(1.0, 0.72, 0.25, 0.95)
		sb.set_border_width_all(2)
		sb.border_width_left = 5
		# Лёгкое свечение: внешний контур рамки (имитация ореола).
		sb.shadow_color = Color(1.0, 0.6, 0.15, 0.35)
		sb.shadow_size = 6
	else:
		sb.bg_color = Color(0.075 + accent.r * 0.10 + lift, 0.085 + accent.g * 0.10 + lift,
			0.12 + accent.b * 0.10 + lift, 1.0)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.45 + lift)
		sb.set_border_width_all(1)
		sb.border_width_left = 4
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _sigil_badge(text: String, col: Color) -> Control:
	var b := PanelContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	b.add_theme_stylebox_override("panel", sb)
	var l: Label = main._label(text, 11)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_color", col)
	b.add_child(l)
	return b


## Строка ингредиента: сколько есть и сколько нужно.
func _sigil_need_row(elem_id: String, needed: int) -> Control:
	var have := int(main._engine.inventory.get(elem_id, 0))
	var enough := have >= needed
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = _element_color(elem_id)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var nm: Label = main._label(main._online._item_name(elem_id), 13)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	row.add_child(nm)
	var qty: Label = main._label("%d / %d" % [have, needed], 13)
	qty.autowrap_mode = TextServer.AUTOWRAP_OFF
	qty.add_theme_color_override("font_color",
		Color(0.55, 0.86, 0.58) if enough else Color(0.93, 0.50, 0.44))
	row.add_child(qty)
	return row


func _sigil_shortage_text(shortages: Array) -> String:
	return "Не хватает: " + ", ".join(shortages)


func _sigil_shortages(craft: Dictionary) -> Array:
	var out: Array = []
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		var needed := int(d.get("qty", 0))
		var have := int(main._engine.inventory.get(elem_id, 0))
		if have < needed:
			out.append("%s (%d/%d)" % [main._online._item_name(elem_id), have, needed])
	return out


## Название крафта: LLM-имя, если сервер его прислал, иначе нейтральное.
func _sigil_craft_title(craft: Dictionary) -> String:
	var llm_name := str(craft.get("llm_name", ""))
	if llm_name != "":
		return llm_name
	var fb := str(craft.get("fallback_name", ""))
	if fb != "":
		return fb
	return "Сигил «%s»" % _sigil_rarity_title(str(craft.get("rarity", "common"))).capitalize()


func _sigil_rarity_title(rarity: String) -> String:
	match rarity:
		"common": return "ОБЫЧНЫЙ"
		"uncommon": return "НЕОБЫЧНЫЙ"
		"rare": return "РЕДКИЙ"
		"epic": return "ЭПИЧЕСКИЙ"
		"legendary": return "ЛЕГЕНДАРНЫЙ"
		"chromatic": return "ХРОМАТИЧЕСКИЙ"
		"mythic": return "МИФИЧЕСКИЙ"
		_: return rarity.to_upper()


func _open_sigil_craft(craft: Dictionary) -> void:
	# Экран крафта — весь в SigilCraftBoard (game/sigil/sigil_craft_board.gd):
	# вёрстка, ячейки-фантомы, drag&drop, кнопка. Здесь только подключение.
	if _sigil_craft_screen != null:
		_close_sigil_craft_screen()
	Sfx.click()
	_sigil_craft_data = craft
	_sigil_placed = {}
	var board := SigilCraftBoard.new()
	board.name = "SigilCraftBoard"
	_sigil_craft_screen = board
	add_child(board)
	board.show_craft(craft, self)
	board.confirmed.connect(_on_sigil_board_confirmed)
	board.closed.connect(_close_sigil_craft_screen)



func _show_sigil_craft_ritual(rarity: String) -> void:
	print("RITUAL: show, rarity=", rarity)
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		_sigil_craft_ritual.queue_free()
		
	var strength := 0.7
	match rarity:
		"epic": strength = 0.85
		"legendary": strength = 1.0
		"mythic", "chromatic": strength = 1.2
		
	var r := SigilCraftRitual.new()
	r.accent = main._rarity_color(rarity)
	r.strength = strength
	
	# КЛЮЧЕВОЕ: Подключаем сигнал показа карты и автозакрытие
	r.on_card_reveal.connect(_on_ritual_card_reveal)
	r.on_complete.connect(_close_sigil_craft_ritual)
	
	_sigil_craft_ritual = r
	add_child(r)
	
func _on_ritual_card_reveal(rect: Rect2, payload: Variant) -> void:
	print("RITUAL: card reveal signal received")
	if payload != null:
		var p := payload as Dictionary
		_show_pending_craft_card(p.get("craft_id", ""), p.get("rarity", "common"), p.get("llm_name", ""))
	elif not _pending_craft_result.is_empty():
		# Фоллбэк, если сервер не успел
		_show_pending_craft_card(_pending_craft_result.get("craft_id", ""), _pending_craft_result.get("rarity", "common"), _pending_craft_result.get("llm_name", ""))


func _close_sigil_craft_ritual() -> void:
	print("RITUAL: close (карточка пришла или таймаут)")
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		_sigil_craft_ritual.queue_free()
	_sigil_craft_ritual = null


func _on_sigil_board_confirmed(craft: Dictionary) -> void:
	# Атомарный крафт: ресурсы списываются сразу (спека: карточка уже у игрока)
	var ether_cost: int = main._sigil.craft_ether_cost(craft)
	main._engine.ether = max(0, main._engine.ether - ether_cost)
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		var needed := int(d.get("qty", 0))
		var have := int(main._engine.inventory.get(elem_id, 0))
		main._engine.inventory[elem_id] = max(0, have - needed)
	main._saves._save_game()
	Sfx.craft_start()
	var craft_id := str(craft.get("id", ""))
	_sigil_pending_craft = craft.duplicate(true)
	main._sigil.craft_card(main._online._device_id, craft_id)
	# Торжественный ритуал трансмутации (окно крафта закрывается, ритуал поверх).
	_close_sigil_craft_screen()
	_show_sigil_craft_ritual(str(craft.get("rarity", "common")))


## Сервер подтвердил крафт: показываем готовую карточку.
func _on_sigil_craft_completed(craft_id: String, rarity: String, llm_name: String) -> void:
	# Сохраняем результат
	_pending_craft_result = {"craft_id": craft_id, "rarity": rarity, "llm_name": llm_name}
	
	if _sigil_craft_ritual != null and is_instance_valid(_sigil_craft_ritual):
		# Отдаём данные ритуалу. 
		# Если он ещё не дошёл до фазы удержания (4.85с), он подождёт.
		# Если уже ждёт — немедленно начнёт вспышку и эмитнет on_card_reveal.
		_sigil_craft_ritual.deliver_result(_pending_craft_result)
	else:
		# Ритуала нет (или уже закрылся), показываем сразу
		_show_pending_craft_card(craft_id, rarity, llm_name)
		_pending_craft_result = {}


## Рендер и показ карточки (после ритуала или сразу, если ритуала нет).
func _show_pending_craft_card(craft_id: String, rarity: String, llm_name: String) -> void:
	var craft: Dictionary = {"id": craft_id, "rarity": rarity, "llm_name": llm_name,
		"ingredients": []}
	for c in main._sigil._daily_crafts:
		if str((c as Dictionary).get("id", "")) == craft_id:
			craft = c
			break
	# Хроматик: показываем ТУ ЖЕ живую карточку, что и в коллекции
	# (с Prism-эффектом, анимированная) — не статичный PNG.
	if rarity == "chromatic":
		var entry := {
			"card_id": "", "craft_id": craft_id,
			"rarity": "chromatic",
			"name": llm_name if llm_name != "" else str(craft.get("fallback_name", "")),
			"set": "", "set_title": "Вне комплектов",
			"first_at": "", "copies": 1,
			# Seed и лор — из ответа крафта (сервер — источник правды), а не из
			# _daily_crafts: клиентский daily мог устареть (кэш/старый оффер),
			# тогда seed=0 -> все хроматики рендерились бы одной картинкой.
			"seed": main._sigil._last_craft_seed if main._sigil._last_craft_seed != 0 \
				else int(craft.get("seed", 0)),
			"lore": main._sigil._last_craft_lore if main._sigil._last_craft_lore != "" \
				else str(craft.get("lore", "")),
		}
		_open_sigil_fullscreen(entry)
		return
	var img: Image = await main._sigil.get_card(craft_id, SigilManager.craft_ingredients(craft),
		StringName(rarity), &"object", _sigil_craft_title(craft))
	if img == null:
		return
	main._show_sigil_card(ImageTexture.create_from_image(img), craft_id,
		_sigil_craft_title(craft), rarity)


## Сервер отказал: возвращаем списанное, иначе ресурсы сгорают молча.
func _on_sigil_craft_failed(err: String) -> void:
	_close_sigil_craft_ritual()
	var craft := _sigil_pending_craft
	_sigil_pending_craft = {}
	if craft.is_empty():
		return
	# Возврат — по той же скидочной цене, что и списание (ruling T4-fix):
	# «−10% стоимости эфира крафтов этого комплекта» покрывает весь ether-учёт.
	main._engine.ether += main._sigil.craft_ether_cost(craft)
	for ing in craft.get("ingredients", []):
		var d := ing as Dictionary
		var elem_id := str(d.get("item_id", ""))
		main._engine.inventory[elem_id] = int(main._engine.inventory.get(elem_id, 0)) + int(d.get("qty", 0))
	main._saves._save_game()
	main._engine._refresh()
	main._engine.status_text = "Крафт не прошёл (%s) — ресурсы возвращены." % err
	Sfx.error()

func _close_sigil_craft_screen() -> void:
	if _sigil_craft_screen == null:
		return
	var d := _sigil_craft_screen
	_sigil_craft_screen = null
	_sigil_craft_data = {}
	_sigil_placed = {}
	d.queue_free()
	Sfx.click()

func _btn_style(col: Color) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _element_color(elem_id: String) -> Color:
	return main._item_colors.get(elem_id, Color(0.62, 0.66, 0.72))

func _close_sigil_collection() -> void:
	if _sigil_coll == null:
		return
	var d := _sigil_coll
	_sigil_coll = null
	d.queue_free()
	_sigil_tab_content = null
	_sigil_tab_btns = []
	_sigil_book = null
	_sigil_pages = {}
	Sfx.click()

func _sigil_thumb(item: Dictionary) -> Control:
	var id := str(item["id"])
	var rar := str(item["rarity"])
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.custom_minimum_size = Vector2(100, 133)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 1)
	sb.border_color = main._rarity_color(rar)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var rect := TextureRect.new()
	rect.texture = item["texture"]
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rect)
	b.pressed.connect(func():
		main._show_sigil_card(item["texture"], id, main._online._item_name(id), rar)
	)
	cell.add_child(b)
	var name_lbl: Label = main._label(main._online._item_name(id), 10)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", main._rarity_color(rar))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	cell.add_child(name_lbl)
	return cell


func _on_popup_card_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_popup_swipe_start = mb.position
			elif UiGestures.swipe_closes(mb.position - _popup_swipe_start):
				main._hide_popup()
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_popup_swipe_start = st.position
		elif UiGestures.swipe_closes(st.position - _popup_swipe_start):
			main._hide_popup()
	# touch-ветка — guarded-untested: headless-прогон не эмулирует ScreenTouch;
	# предикат общий и покрыт кейсом swipe-предиката.

func _on_brew_btn_pressed() -> void:
	main._engine._brew()

func _handle_tilde(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var ke := event as InputEventKey
	if not ke.pressed or ke.keycode != KEY_QUOTELEFT:
		return false
	if main._admin != null:
		main._admin.toggle()
		Sfx.click()
	return true

# Предикат ESC и сам уход собраны в одну булеву функцию: «потреблять или нет»
# наблюдаемо из selftest (наблюдаемость самого set_input_as_handled в headless
# проверить нечем — это оставленный, осознанный зазор в одну строку).
func _handle_esc(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var ke := event as InputEventKey
	if not ke.pressed or ke.keycode != KEY_ESCAPE:
		return false
	return _close_top_modal()

# Порядок elif-веток = порядок наложения (z): сначала модальные окна поверх
# всего (autovark/consent, магазин декора z=100), затем попапы по убыванию z.
# Возвращает true, если что-то закрыто/потреблено — только тогда Esc считается
# обработанным; иначе событие уходит дальше (обычный выход из игры).
func _close_top_modal() -> bool:
	if _sigil_fullscreen != null:
		_close_sigil_fullscreen()
		return true
	if _sigil_set_screen != null:
		_close_sigil_set_screen()
		return true
	if _sigil_craft_screen != null:
		_close_sigil_craft_screen()
		return true
	if _sigil_coll != null:
		_close_sigil_collection()
		return true
	if main._admin != null and main._admin.is_visible():
		main._admin.close()
		Sfx.click()
		return true
	if main._engine._auto:
		main._engine._auto_cancel = true
		main._engine.status_text = "Автоварка: остановлю после текущего шага…"
		return true
	if main._shop != null and main._shop._consent_popup != null and main._shop._consent_popup.visible:
		# Не даём обойти первый consent через Esc: один из двух режимов
		# должен быть выбран явно.
		return true
	elif main._home != null and main._home._decor_popup != null and main._home._decor_popup.visible:
		# Магазин декора — modal surface с z=100 (home.gd), выше shop/hub/discovery.
		main._home._close_decor_popup()
		return true
	elif main._shop != null and main._shop._popup != null and main._shop._popup.visible:
		main._shop.close()
		return true
	elif main._popup.visible:
		main._hide_popup()
		return true
	elif main._confirm.visible:
		main._hide_confirm()
		return true
	elif main._saves._return_popup.visible:
		main._saves._close_return_popup()
		return true
	elif main._hub._settings_popup.visible:
		main._hub._settings_dim.visible = false
		main._hub._settings_popup.visible = false
		Sfx.click()
		return true
	elif main._hub._craftable_popup.visible:
		main._hub._craftable_dim.visible = false
		main._hub._craftable_popup.visible = false
		Sfx.click()
		return true
	elif main._retort._retort_popup.visible:
		main._retort._retort_dim.visible = false
		main._retort._retort_popup.visible = false
		Sfx.click()
		return true
	elif main._hub._journal_popup.visible:
		main._hub._journal_dim.visible = false
		main._hub._journal_popup.visible = false
		Sfx.click()
		return true
	elif main._hub._prestige_popup.visible:
		main._hub._prestige_dim.visible = false
		main._hub._prestige_popup.visible = false
		Sfx.click()
		return true
	elif main._progress_ui._prog_popup.visible:
		main._progress_ui._prog_dim.visible = false
		main._progress_ui._prog_popup.visible = false
		Sfx.click()
		return true
	elif main._hub._profile_popup.visible:
		main._hub._profile_dim.visible = false
		main._hub._profile_popup.visible = false
		Sfx.click()
		return true
	elif main._hub._up_popup.visible:
		main._hub._up_dim.visible = false
		main._hub._up_popup.visible = false
		Sfx.click()
		return true
	elif main._spirit._companion_dlg != null and main._spirit._companion_dlg.visible:
		main._spirit._companion_close_dialog()
		return true
	elif main._home != null and main._home._color_picker != null and main._home._color_picker.visible:
		# Отмена палитры с откатом живого предпросмотра (кнопки Cancel у пикера нет).
		main._home._cancel_color_picker()
		return true
	elif main._home != null and main._home._house_popup != null and main._home._house_popup.visible:
		# Палитра и гостевой домик — самые нижние по z и одновременно видны
		# быть не могут, порядок этих двух веток не важен.
		main._home._close_house_popup()
		return true
	return false

# Read-only перечисление ровно тех поверхностей, что закрывает
# _close_top_modal(): interstitial не должен появляться поверх открытого модала,
# во время автоварки (_engine._auto — верхняя ветка того же порядка), ручной
# варки (_engine.brewing: core.gd:14, true в :695, false в :711/:765) и
# ручного крафта на верстаке (_pages._bench_busy — core.gd трактует её занятой
# вместе с варкой: :407, :666, :1208, :1371). Церемония открытия идёт внутри
# _popup и покрыта модальной веткой ниже. Каждая поверхность защищена
# проверкой на
# null по образцу уже существующих строк предиката: tab_changed эмитится
# синхронно во время построения вкладок, когда часть попапов ещё null
# (сам показ при этом гейтится _ui_ready в _on_tab_changed).
# Предикат из tests/suite_journal_misc.gd переиспользовать нельзя (он тестовый),
# поэтому у продакшена свой, проверяемый из selftest напрямую.
func _modal_open_for_ads() -> bool:
	if main._admin != null and main._admin.is_visible():
		return true
	if main._engine._auto:
		return true
	if main._engine.brewing:
		return true
	if main._pages != null and main._pages._bench_busy:
		return true
	if main._shop != null and main._shop._consent_popup != null and main._shop._consent_popup.visible:
		return true
	if main._home != null and main._home._decor_popup != null and main._home._decor_popup.visible:
		return true
	if main._shop != null and main._shop._popup != null and main._shop._popup.visible:
		return true
	if main._popup != null and main._popup.visible:
		return true
	if main._confirm != null and main._confirm.visible:
		return true
	if main._saves._return_popup != null and main._saves._return_popup.visible:
		return true
	if main._hub._settings_popup != null and main._hub._settings_popup.visible:
		return true
	if main._hub._craftable_popup != null and main._hub._craftable_popup.visible:
		return true
	if main._retort._retort_popup != null and main._retort._retort_popup.visible:
		return true
	if main._hub._journal_popup != null and main._hub._journal_popup.visible:
		return true
	if main._hub._prestige_popup != null and main._hub._prestige_popup.visible:
		return true
	if main._progress_ui._prog_popup != null and main._progress_ui._prog_popup.visible:
		return true
	if main._hub._profile_popup != null and main._hub._profile_popup.visible:
		return true
	if main._hub._up_popup != null and main._hub._up_popup.visible:
		return true
	if main._spirit._companion_dlg != null and main._spirit._companion_dlg.visible:
		return true
	if main._home != null and main._home._color_picker != null and main._home._color_picker.visible:
		return true
	if main._home != null and main._home._house_popup != null and main._home._house_popup.visible:
		return true
	return false




# ---------- Рисованные глифы (переехали из main.gd вместе с сигильным UI) ----------

## Рисованная галочка для claimed-точек майлстоунов: глиф «✓» вне шрифта
## Manrope, поэтому отметка рисуется двумя линиями в _draw.
class SigilMilestoneMark:
	extends Control

	func _draw() -> void:
		var c := Color(0.90, 0.82, 0.56)
		var w := 2.0
		draw_line(Vector2(size.x * 0.16, size.y * 0.52),
			Vector2(size.x * 0.42, size.y * 0.78), c, w)
		draw_line(Vector2(size.x * 0.42, size.y * 0.78),
			Vector2(size.x * 0.86, size.y * 0.22), c, w)


## Силуэт несобранной карты комплекта (Task 7b): тёмный контур круга без
## заливки — игрок не получает ни имени, ни арта, ни намёка на сид карты.
class SigilSilhouette:
	extends Control

	func _draw() -> void:
		var c := Color(0.28, 0.32, 0.40)
		var w := 2.0
		var r := (minf(size.x, size.y) - 8.0) * 0.5
		if r <= 0.0:
			return
		draw_arc(size * 0.5, r, 0.0, TAU, 48, c, w, true)
