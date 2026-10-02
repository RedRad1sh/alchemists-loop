extends RefCounted
class_name Pages
# Страницы-вкладки (R12): лаборатория, мир, инструменты и компактные режимы.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _spring_clock := 0.0
var _mode_tabs: Dictionary = {}
var _tools_flow: HFlowContainer = null
var _tools_sub: VBoxContainer = null
var _tools_sel := ""
var _tools_hint: Label = null
var _mode_pages: Dictionary = {}
var _mode_chips: Dictionary = {}
var _hint_btn: Button
var _hint_id := ""
var _bench_target := ""
var _bench_on := false
var _bench_clock := 0.0
var _bench_busy := false
# анти-спам кнопок траты: key → msec последнего разрешённого тапа (_spend_gate)
var _spend_guard_ms: Dictionary = {}
var _bench_rows: VBoxContainer
var _bench_toggle_btn: Button
var _bench_info: Label
var _bench_page_labels = null
var _spring_toggle_btn: Button
var _spring_info: Label
var _spring_pick_btn: Dictionary = {}

# Эксперимент (v1: two reagents; hash/API version leaves room for 3–4).
var _experiment_a := ""
var _experiment_b := ""
var _experiment_a_pick: OptionButton = null
var _experiment_b_pick: OptionButton = null
var _experiment_info: Label = null
var _experiment_button: Button = null
var _experiment_preview: Label = null
var _experiment_confirm: ConfirmationDialog = null

# Большая экспериментальная локация: поле, выдвижная панель реагентов и котёл.
var _experiment_field: Control = null
var _experiment_center: CenterContainer = null
var _experiment_cauldron: CauldronView = null
var _experiment_cauldron_title: Label = null
var _experiment_cauldron_frame: PanelContainer = null
var _experiment_drawer: PanelContainer = null
var _experiment_drawer_button: Button = null
var _experiment_drawer_label: Label = null
var _experiment_reagent_search: LineEdit = null
var _experiment_filter_buttons: Dictionary = {}
var _experiment_filter := "recent"
var _experiment_drawer_empty: Label = null
var _experiment_reopen_button: Button = null
var _experiment_reagent_grid: GridContainer = null
var _experiment_picker_scroll: ScrollContainer = null
var _experiment_picker_title: Label = null
var _experiment_picker_count: Label = null
var _experiment_picker_hint: Label = null
var _experiment_hint_ids: Array[String] = []
var _experiment_recent_ids: Array[String] = []
var _experiment_side_drawer := false
var _experiment_play_right := 0.0
var _experiment_status: Label = null
var _experiment_recipe_line: Label = null
var _experiment_clear_button: Button = null
var _experiment_tokens: Array = []
var _experiment_cauldron_items: Array[String] = []
var _experiment_drag_token: ElementOrb = null
var _experiment_drag_source := ""
var _experiment_token_seq := 0
var _experiment_position_rng := RandomNumberGenerator.new()
var _experiment_drawer_signature := ""

func _init(game: Game) -> void:
	g = game

func _add_lab_reagent_cell(item_id: String) -> void:
	if g._inv_grid == null or g._engine._item_orbs.has(item_id):
		return
	var cell := Button.new()
	cell.name = "LabReagentCell_%s" % item_id
	cell.custom_minimum_size = Vector2(0, 48)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.focus_mode = Control.FOCUS_NONE
	cell.tooltip_text = g._online._item_name(item_id)
	var cell_style := StyleBoxFlat.new()
	cell_style.bg_color = Color(0.06, 0.12, 0.18, 0.78)
	cell_style.border_color = Color(0.20, 0.34, 0.42, 0.72)
	cell_style.set_border_width_all(1)
	cell_style.set_corner_radius_all(12)
	var cell_hover: StyleBoxFlat = cell_style.duplicate()
	cell_hover.bg_color = Color(0.12, 0.23, 0.29, 0.90)
	cell.add_theme_stylebox_override("normal", cell_style)
	cell.add_theme_stylebox_override("hover", cell_hover)
	cell.add_theme_stylebox_override("pressed", cell_hover)
	cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var cell_content := VBoxContainer.new()
	cell_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cell_content.alignment = BoxContainer.ALIGNMENT_CENTER
	cell_content.add_theme_constant_override("separation", 1)
	cell_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(cell_content)
	var orb := g._make_orb(item_id, 28)
	orb.count = 0
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.tapped.connect(g._engine._on_item_tapped.bind(item_id))
	orb.drag_started.connect(g._engine._on_orb_drag_started.bind(item_id))
	orb.drag_ended.connect(g._engine._on_orb_drag_ended.bind(item_id))
	cell_content.add_child(orb)
	var name_label := g._label(g._online._item_name(item_id), 11)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell_content.add_child(name_label)
	# Tap по подписи или свободному месту ячейки остаётся таким же действием,
	# как tap по орбу; drag продолжает идти через сам ElementOrb.
	cell.pressed.connect(func() -> void:
		g._engine._on_item_tapped(orb, item_id)
	)
	g._inv_grid.add_child(cell)
	g._engine._item_orbs[item_id] = orb
	g._engine._item_cells[item_id] = cell


func _build_lab(page: VBoxContainer) -> void:
	# панель котла
	var brew_panel := PanelContainer.new()
	brew_panel.add_theme_stylebox_override("panel",
		g._panel_style(Color(0.07, 0.10, 0.15, 0.85), 18))
	page.add_child(brew_panel)
	var bp := VBoxContainer.new()
	bp.add_theme_constant_override("separation", 6)
	brew_panel.add_child(bp)

	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	bp.add_child(mid)

	g._engine._slot_a = g._make_slot("A")
	mid.add_child(g._engine._slot_a)

	g._engine._cauldron = CauldronView.new()
	g._engine._cauldron.custom_minimum_size = Vector2(256, 210)
	g._engine._cauldron.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(g._engine._cauldron)

	g._engine._slot_b = g._make_slot("B")
	mid.add_child(g._engine._slot_b)

	var hint_line := g._label("Источники и «ВАРИТЬ» закреплены внизу экрана — при прокрутке они остаются на месте.", 12)
	hint_line.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
	bp.add_child(hint_line)

	# Родник живёт в лаборатории: это постоянная часть петли, а не отдельный чип.
	var spring_title := g._label("Родник", 16)
	spring_title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
	page.add_child(spring_title)
	var spring_box := VBoxContainer.new()
	spring_box.add_theme_constant_override("separation", 6)
	page.add_child(spring_box)
	_build_spring_page(spring_box)

	# автоварка: рецепты прямо в лаборатории (Светик теперь в углу вверху справа — контент на всю ширину)
	var book_head := HBoxContainer.new()
	book_head.add_theme_constant_override("separation", 6)
	page.add_child(book_head)
	var book_title := g._label("Книга рецептов — Производство считает длинные маршруты", 16)
	book_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book_head.add_child(book_title)
	var book_note := g._label("Бесплатное раскрытие результата убрано: неизвестные пары проверяются в Эксперименте, известные маршруты запускаются здесь.", 12)
	book_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	book_note.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	page.add_child(book_note)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск вещества по названию…"
	search.custom_minimum_size = Vector2(0, 40)
	search.add_theme_font_size_override("font_size", 15)
	search.clear_button_enabled = true
	search.text_changed.connect(g._online._on_search_changed)
	page.add_child(search)
	g._engine._search_box = search
	g._engine._book_stats = g._label("", 13)
	page.add_child(g._engine._book_stats)
	var auto_scroll := ScrollContainer.new()
	auto_scroll.custom_minimum_size = Vector2(0, 290)
	auto_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var book_margin := MarginContainer.new()
	book_margin.add_theme_constant_override("margin_right", 14)
	page.add_child(book_margin)
	book_margin.add_child(auto_scroll)
	g._engine._book_list = VBoxContainer.new()
	g._engine._book_list.add_theme_constant_override("separation", 6)
	g._engine._book_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_scroll.add_child(g._engine._book_list)

	# инвентарь
	page.add_child(g._label("Вещества — перетащи в лунки (A/B) у котла", 16))
	g._inv_grid = GridContainer.new()
	var grid := g._inv_grid
	# Та же компактная ячейка, что и в Эксперименте: знак + имя,
	# touch-зона 48 px, без россыпи огромных орбов.
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	# Добавляем только элементы, которые игрок уже открыл (есть в inventory)
	for raw_id in g.ITEMS:
		var item_id := String(raw_id)
		if g._engine.inventory.has(item_id):
			_add_lab_reagent_cell(item_id)

	# отступ под закреплённую панель «ВАРИТЬ»
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 150)
	page.add_child(bottom_pad)


func _build_experiment_location(page: VBoxContainer) -> void:
	_experiment_position_rng.randomize()
	# Эксперимент остаётся полем с главным объектом: список не резервирует
	# постоянную боковую колонку. По умолчанию выбор открыт как полупрозрачное
	# окно поверх поля — игрок видит котёл и уже добавленные орбы.
	page.add_theme_constant_override("separation", 8)
	# Канвас Эксперимента должен помещаться в viewport целиком: длинный
	# список реагентов прокручивается внутри своего окна, но само поле — нет.
	var page_margin := page.get_parent() as Control
	if page_margin != null:
		var page_scroll := page_margin.get_parent() as ScrollContainer
		if page_scroll != null:
			page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	page.add_child(title_row)
	var title := g._label("ЭКСПЕРИМЕНТ", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(title)


	_experiment_status = g._label("Выбери вещество: окно выбора останется прозрачным, чтобы видеть поле.", 13)
	_experiment_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_experiment_status.add_theme_color_override("font_color", Color(0.68, 0.82, 0.88))
	page.add_child(_experiment_status)

	var arena := PanelContainer.new()
	# Поле растягивается до доступной высоты страницы. Никакой постоянной
	# inventory-карточки и принудительной высоты, вызывающей прокрутку, больше нет.
	arena.custom_minimum_size = Vector2.ZERO
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.add_theme_stylebox_override("panel", g._panel_style(Color(0.035, 0.06, 0.10, 0.90), 22))
	page.add_child(arena)
	_experiment_field = Control.new()
	_experiment_field.custom_minimum_size = Vector2.ZERO
	_experiment_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_experiment_field.clip_contents = true
	arena.add_child(_experiment_field)

	var field_title := g._label("ПОЛЕ ЭКСПЕРИМЕНТА", 12)
	field_title.name = "ExperimentFieldTitle"
	field_title.position = Vector2(18, 14)
	field_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_title.add_theme_color_override("font_color", Color(0.45, 0.72, 0.78))
	_experiment_field.add_child(field_title)
	var field_hint := g._label("Котёл — место для смешения. Нажатие на ячейку сразу кладёт вещество на поле.", 12)
	field_hint.name = "ExperimentFieldHint"
	field_hint.position = Vector2(18, 38)
	field_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_hint.add_theme_color_override("font_color", Color(0.48, 0.56, 0.64))
	_experiment_field.add_child(field_hint)

	# Котёл — самостоятельное место для смешения без внешней карточки.
	# Он центрируется по всему полю, а не по месту, оставшемуся после списка.
	var center := CenterContainer.new()
	_experiment_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 76
	center.offset_bottom = -26
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_experiment_field.add_child(center)
	_experiment_cauldron_frame = PanelContainer.new()
	_experiment_cauldron_frame.custom_minimum_size = Vector2(232, 292)
	_experiment_cauldron_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_experiment_cauldron_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	center.add_child(_experiment_cauldron_frame)
	var cauldron_col := VBoxContainer.new()
	cauldron_col.alignment = BoxContainer.ALIGNMENT_CENTER
	cauldron_col.add_theme_constant_override("separation", 4)
	_experiment_cauldron_frame.add_child(cauldron_col)
	_experiment_cauldron_title = g._label("КОТЁЛ", 12)
	_experiment_cauldron_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_experiment_cauldron_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cauldron_col.add_child(_experiment_cauldron_title)
	_experiment_cauldron = CauldronView.new()
	_experiment_cauldron.custom_minimum_size = Vector2(218, 188)
	_experiment_cauldron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cauldron_col.add_child(_experiment_cauldron)
	_experiment_recipe_line = g._label("Свободен · перетащи реагенты сюда", 10)
	_experiment_recipe_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_experiment_recipe_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_experiment_recipe_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cauldron_col.add_child(_experiment_recipe_line)
	_experiment_clear_button = g._small_button("Очистить", Vector2(96, 38), 0)
	_experiment_clear_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_experiment_clear_button.add_theme_font_size_override("font_size", 12)
	# Кнопка выглядит компактно, но сохраняет touch-зону helper-а.
	_experiment_clear_button.pressed.connect(_experiment_clear_cauldron)
	cauldron_col.add_child(_experiment_clear_button)

	# Полноэкранный выбор вещества. Это не боковая панель: полупрозрачный
	# слой накрывает всё поле, а небольшие ячейки быстро просматриваются.
	# Временные орбы остаются под окном выбора: полупрозрачность слоя
	# позволяет их видеть, но ячейки и подписи всегда остаются сверху.
	_experiment_drawer = PanelContainer.new()
	_experiment_drawer.name = "ExperimentReagentPicker"
	_experiment_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_experiment_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_drawer.z_index = 2
	var picker_style := StyleBoxFlat.new()
	picker_style.bg_color = Color(0.025, 0.055, 0.09, 0.44)
	picker_style.border_color = Color(0.26, 0.62, 0.67, 0.82)
	picker_style.set_border_width_all(1)
	picker_style.set_corner_radius_all(18)
	picker_style.content_margin_left = 10.0
	picker_style.content_margin_right = 10.0
	picker_style.content_margin_top = 10.0
	picker_style.content_margin_bottom = 10.0
	_experiment_drawer.add_theme_stylebox_override("panel", picker_style)
	_experiment_field.add_child(_experiment_drawer)
	var drawer_col := VBoxContainer.new()
	drawer_col.add_theme_constant_override("separation", 6)
	drawer_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_experiment_drawer.add_child(drawer_col)

	var drawer_head := HBoxContainer.new()
	drawer_head.add_theme_constant_override("separation", 8)
	drawer_col.add_child(drawer_head)
	_experiment_drawer_label = g._label("ВЫБРАТЬ РЕАГЕНТ", 14)
	_experiment_drawer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experiment_drawer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if g._font_semi != null:
		_experiment_drawer_label.add_theme_font_override("font", g._font_semi)
	drawer_head.add_child(_experiment_drawer_label)
	_experiment_picker_count = g._label("", 11)
	_experiment_picker_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_experiment_picker_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drawer_head.add_child(_experiment_picker_count)
	_experiment_drawer_button = g._small_button("Закрыть", Vector2(86, 44), 0)
	_experiment_drawer_button.custom_minimum_size.y = 44.0
	_experiment_drawer_button.pressed.connect(_toggle_experiment_drawer)
	drawer_head.add_child(_experiment_drawer_button)

	_experiment_picker_hint = g._label("Нажми на ячейку — вещество сразу появится на поле. Добавляй нужное количество.", 11)
	_experiment_picker_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_experiment_picker_hint.add_theme_color_override("font_color", Color(0.72, 0.84, 0.88))
	drawer_col.add_child(_experiment_picker_hint)

	_experiment_reagent_search = LineEdit.new()
	_experiment_reagent_search.placeholder_text = "Найти вещество по имени, идентификатору или описанию…"
	_experiment_reagent_search.clear_button_enabled = true
	_experiment_reagent_search.custom_minimum_size = Vector2(0, 44)
	_experiment_reagent_search.add_theme_font_size_override("font_size", 14)
	_experiment_reagent_search.text_changed.connect(_on_experiment_search_changed)
	drawer_col.add_child(_experiment_reagent_search)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 5)
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_col.add_child(filter_row)
	for filter_spec in [
		{"key": "recent", "title": "Недавние", "width": 100.0},
		{"key": "hint", "title": "Светик", "width": 78.0},
		{"key": "elements", "title": "Стихии", "width": 82.0},
		{"key": "all", "title": "Все", "width": 56.0},
	]:
		var filter_button := g._small_button(String(filter_spec["title"]), Vector2(float(filter_spec["width"]), 44), 0)
		filter_button.custom_minimum_size.y = 44.0
		filter_button.toggle_mode = true
		filter_button.add_theme_font_size_override("font_size", 12)
		filter_button.tooltip_text = {
			"recent": "Недавно использованные и базовые стихии",
			"hint": "Вещества из оплаченной подсказки Светика",
			"elements": "Четыре первостихии",
			"all": "Все открытые вещества",
		}.get(String(filter_spec["key"]), "")
		filter_button.pressed.connect(_set_experiment_filter.bind(String(filter_spec["key"])))
		filter_row.add_child(filter_button)
		_experiment_filter_buttons[String(filter_spec["key"])] = filter_button

	_experiment_picker_scroll = ScrollContainer.new()
	_experiment_picker_scroll.name = "ExperimentReagentList"
	_experiment_picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_experiment_picker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_experiment_picker_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experiment_picker_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_experiment_picker_scroll.custom_minimum_size = Vector2(0, 220)
	drawer_col.add_child(_experiment_picker_scroll)
	_experiment_reagent_grid = GridContainer.new()
	_experiment_reagent_grid.name = "ExperimentReagentCells"
	_experiment_reagent_grid.columns = 4
	_experiment_reagent_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experiment_reagent_grid.add_theme_constant_override("h_separation", 6)
	_experiment_reagent_grid.add_theme_constant_override("v_separation", 6)
	_experiment_picker_scroll.add_child(_experiment_reagent_grid)
	_experiment_drawer_empty = g._label("Ничего не найдено", 12)
	_experiment_drawer_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_experiment_drawer_empty.visible = false
	_experiment_drawer_empty.custom_minimum_size = Vector2(0, 24)
	drawer_col.add_child(_experiment_drawer_empty)

	# После закрытия остаётся одна компактная кнопка возврата. Она не занимает
	# поле постоянно и не перекрывает зону Светика в верхней части экрана.
	_experiment_reopen_button = g._small_button("Выбрать реагент", Vector2(158, 44), 1)
	_experiment_reopen_button.custom_minimum_size.y = 44.0
	_experiment_reopen_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_experiment_reopen_button.offset_left = -170
	_experiment_reopen_button.offset_right = -12
	_experiment_reopen_button.offset_top = -56
	_experiment_reopen_button.offset_bottom = -12
	_experiment_reopen_button.visible = false
	_experiment_reopen_button.pressed.connect(_toggle_experiment_drawer)
	_experiment_field.add_child(_experiment_reopen_button)

	_experiment_field.resized.connect(_fit_experiment_overlay)
	_refresh_experiment_location()
	call_deferred("_fit_experiment_overlay")


func _set_experiment_rect(control: Control, rect: Rect2) -> void:
	if control == null:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _set_experiment_picker_field_chrome() -> void:
	# Когда список открыт, не оставляем под ним дублирующиеся подписи и
	# «Очистить»: сам котёл остаётся видимым, а поле не превращается в набор
	# полупрозрачных дубликатов подписей.
	var field_title := _experiment_field.get_node_or_null("ExperimentFieldTitle") as Control
	var field_hint := _experiment_field.get_node_or_null("ExperimentFieldHint") as Control
	var picker_open := _experiment_drawer != null and _experiment_drawer.visible
	if field_title != null:
		field_title.visible = not picker_open
	if field_hint != null:
		field_hint.visible = not picker_open
	if _experiment_cauldron_title != null:
		_experiment_cauldron_title.visible = not picker_open
	if _experiment_recipe_line != null:
		_experiment_recipe_line.visible = not picker_open
	if _experiment_clear_button != null:
		_experiment_clear_button.visible = not picker_open


func _fit_experiment_overlay() -> void:
	if _experiment_field == null or _experiment_field.size.x <= 0.0 or _experiment_field.size.y <= 0.0:
		return
	var field_size := _experiment_field.size
	if _experiment_reagent_grid != null:
		_experiment_reagent_grid.columns = 4 if field_size.x >= 420.0 else (3 if field_size.x >= 330.0 else 2)
	# Поле всегда занимает всю ширину. Старой боковой колонки больше нет:
	# выбор — отдельный полупрозрачный режим, а котёл остаётся по центру.
	_experiment_side_drawer = false
	_experiment_play_right = field_size.x
	_experiment_cauldron_frame.custom_minimum_size = Vector2(232, 292)
	_experiment_cauldron.custom_minimum_size = Vector2(218, 188)
	_set_experiment_rect(_experiment_drawer, Rect2(0.0, 0.0, field_size.x, field_size.y))
	var field_title := _experiment_field.get_node_or_null("ExperimentFieldTitle") as Control
	_set_experiment_rect(field_title, Rect2(18.0, 12.0, maxf(1.0, field_size.x - 36.0), 22.0))
	var field_hint := _experiment_field.get_node_or_null("ExperimentFieldHint") as Control
	_set_experiment_rect(field_hint, Rect2(18.0, 36.0, maxf(1.0, field_size.x - 36.0), 30.0))
	_set_experiment_rect(_experiment_center,
		Rect2(0.0, 72.0, field_size.x, maxf(1.0, field_size.y - 98.0)))
	_set_experiment_rect(_experiment_reopen_button,
		Rect2(maxf(12.0, field_size.x - 170.0), maxf(12.0, field_size.y - 56.0), 158.0, 44.0))
	if _experiment_drawer_button != null and _experiment_drawer.visible:
		_experiment_drawer_button.text = "Закрыть"
	_set_experiment_picker_field_chrome()


func _show_experiment_drawer() -> void:
	if _experiment_drawer == null or _experiment_drawer.visible:
		return
	_toggle_experiment_drawer()


func _toggle_experiment_drawer() -> void:
	if _experiment_drawer == null:
		return
	_experiment_drawer.visible = not _experiment_drawer.visible
	if _experiment_drawer_button != null:
		_experiment_drawer_button.text = "Закрыть"
	if _experiment_reopen_button != null:
		_experiment_reopen_button.visible = not _experiment_drawer.visible
	if _experiment_drawer.visible and _experiment_picker_scroll != null:
		_experiment_picker_scroll.scroll_vertical = 0
	_set_experiment_picker_field_chrome()
	Sfx.click()


func _experiment_normalize_search(value: String) -> String:
	return value.strip_edges().to_lower().replace("ё", "е")


func _experiment_search_aliases(item_id: String) -> String:
	# Небольшой слой семантических синонимов поверх имени/ID/описания.
	# Он нужен именно в picker: игрок может искать «пламя», а не помнить
	# внутренний slug fire.
	match item_id:
		"fire": return "пламя жар flame blaze"
		"water": return "влага жидкость liquid вода"
		"earth": return "почва грунт soil земля"
		"air": return "ветер breeze небо воздух"
		"steam": return "испарение vapor пар"
		"stone": return "порода rock камень"
		"clay": return "глина керамика clay"
		"dust": return "порошок пыль dust"
		"spark": return "искра огонек огонь spark"
		"mist": return "дымка туман mist"
		"plant": return "росток растение plant"
		"cloud": return "туча облако cloud"
		"ice": return "заморозка лёд лед ice"
		"life": return "жизнь живое life"
		"metal": return "руда металл metal"
		"lightning": return "разряд молния lightning"
		"sun": return "свет солнце sun"
		"forest": return "деревья лес forest"
		"house": return "жилище дом house"
	return ""


func _experiment_search_matches(item_id: String) -> bool:
	if _experiment_reagent_search == null:
		return true
	var query := _experiment_normalize_search(_experiment_reagent_search.text)
	if query == "":
		return true
	var spec: Dictionary = g.ITEMS.get(item_id, {})
	var category := String(Game.CATEGORY_OF.get(item_id, spec.get("category", "")))
	var haystack := _experiment_normalize_search("%s %s %s %s %s" % [
		g._online._item_name(item_id), item_id,
		String(spec.get("d", "")), category, _experiment_search_aliases(item_id)])
	for term in query.split(" ", false):
		if term != "" and not haystack.contains(term):
			return false
	return true


func _experiment_reagent_priority(item_id: String) -> int:
	# После платной подсказки Светика нужные два вещества всегда первыми;
	# затем идут недавно использованные, чтобы повторный поиск не начинался с нуля.
	if _experiment_hint_ids.has(item_id):
		return -100
	var recent := _experiment_recent_ids.find(item_id)
	return recent if recent >= 0 else 1000


func _experiment_reagent_ids(apply_filter := true) -> Array[String]:
	var ids: Array[String] = []
	var query_active := _experiment_reagent_search != null and _experiment_normalize_search(_experiment_reagent_search.text) != ""
	for raw_id in g._engine.inventory.keys():
		var item_id := String(raw_id)
		if int(g._engine.inventory.get(item_id, 0)) <= 0 or not g.ITEMS.has(item_id):
			continue
		# Поиск всегда имеет приоритет над фильтром: пользователь явно
		# попросил найти вещество и не должен угадывать, в какой вкладке оно.
		if apply_filter and not _experiment_search_matches(item_id):
			continue
		if apply_filter and not query_active:
			match _experiment_filter:
				"hint":
					if not _experiment_hint_ids.has(item_id):
						continue
				"elements":
					if not Game.BASE_IDS.has(item_id):
						continue
				"recent":
					if not _experiment_recent_ids.has(item_id) and not _experiment_hint_ids.has(item_id) and not Game.BASE_IDS.has(item_id):
						continue
		ids.append(item_id)
	var stable_order := _experiment_filter == "all" or query_active
	ids.sort_custom(func(a: String, b: String) -> bool:
		# Вкладка «Все» — это спокойный каталог: нажатие не должно
		# перебрасывать вещество в начало прямо под пальцем.
		if stable_order:
			return g._online._item_name(a) < g._online._item_name(b)
		var pa := _experiment_reagent_priority(a)
		var pb := _experiment_reagent_priority(b)
		if pa != pb:
			return pa < pb
		return g._online._item_name(a) < g._online._item_name(b)
	)
	return ids


func _set_experiment_filter(filter_key: String) -> void:
	if filter_key == "hint" and _experiment_hint_ids.is_empty():
		_experiment_filter = "recent"
		_experiment_status.text = "Сначала купи подсказку Светика — тогда нужные вещества появятся здесь первыми."
	else:
		_experiment_filter = filter_key
	_refresh_experiment_drawer()


func _on_experiment_search_changed(_query: String) -> void:
	if _experiment_reagent_grid == null:
		return
	var scroll := _experiment_reagent_grid.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0
	_refresh_experiment_drawer()


func _remember_experiment_reagent(item_id: String) -> void:
	_experiment_recent_ids.erase(item_id)
	_experiment_recent_ids.push_front(item_id)
	while _experiment_recent_ids.size() > 5:
		_experiment_recent_ids.pop_back()


func _experiment_drawer_state_signature() -> String:
	var open_ids: Array[String] = []
	for raw_id in g._engine.inventory.keys():
		var item_id := String(raw_id)
		if int(g._engine.inventory.get(item_id, 0)) > 0 and g.ITEMS.has(item_id):
			open_ids.append(item_id)
	open_ids.sort()
	var query := _experiment_normalize_search(_experiment_reagent_search.text) if _experiment_reagent_search != null else ""
	# Recent order matters only for the dedicated «Недавние» filter. In «Все»
	# it is deliberately excluded so a tap never causes a jump.
	var recent := ",".join(_experiment_recent_ids) if _experiment_filter == "recent" else ""
	return "%s|%s|%s|%s|%s" % [
		_experiment_filter, query, ",".join(_experiment_hint_ids), ",".join(open_ids), recent]


func _refresh_experiment_drawer() -> void:
	if _experiment_reagent_grid == null:
		return
	if _experiment_filter == "hint" and _experiment_hint_ids.is_empty():
		_experiment_filter = "recent"
	var next_signature := _experiment_drawer_state_signature()
	if next_signature == _experiment_drawer_signature:
		return
	_experiment_drawer_signature = next_signature
	for child in _experiment_reagent_grid.get_children():
		_experiment_reagent_grid.remove_child(child)
		child.queue_free()
	if _experiment_filter == "hint" and _experiment_hint_ids.is_empty():
		_experiment_filter = "recent"
	var all_ids := _experiment_reagent_ids(false)
	var visible_ids := _experiment_reagent_ids(true)
	var query := _experiment_normalize_search(_experiment_reagent_search.text) if _experiment_reagent_search != null else ""
	for filter_key in _experiment_filter_buttons:
		var filter_button := _experiment_filter_buttons[filter_key] as Button
		filter_button.button_pressed = filter_key == _experiment_filter and query == ""
		filter_button.disabled = filter_key == "hint" and _experiment_hint_ids.is_empty()
	if _experiment_drawer_label != null:
		_experiment_drawer_label.text = "ВЫБРАТЬ РЕАГЕНТ"
	if _experiment_picker_count != null:
		_experiment_picker_count.text = "%d / %d" % [visible_ids.size(), all_ids.size()]
	if _experiment_picker_hint != null:
		_experiment_picker_hint.text = "Нажми на ячейку — вещество сразу появится на поле. Добавляй нужное количество."
	if _experiment_drawer_empty != null:
		_experiment_drawer_empty.visible = query != "" and visible_ids.is_empty()
	for item_id in visible_ids:
		var cell := Button.new()
		cell.name = "ReagentCell_%s" % item_id
		# Визуальная ячейка компактная, а вся её высота остаётся
		# интерактивной зоной доступного размера 48 px.
		cell.custom_minimum_size = Vector2(0, 48)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.focus_mode = Control.FOCUS_NONE
		cell.tooltip_text = g._online._item_name(item_id)
		var cell_style := StyleBoxFlat.new()
		cell_style.bg_color = Color(0.06, 0.12, 0.18, 0.58)
		cell_style.border_color = Color(0.20, 0.34, 0.42, 0.68)
		if _experiment_hint_ids.has(item_id):
			cell_style.bg_color = Color(0.18, 0.16, 0.10, 0.64)
			cell_style.border_color = Color(1.0, 0.79, 0.28, 0.94)
		cell_style.set_border_width_all(1)
		cell_style.set_corner_radius_all(12)
		var cell_hover: StyleBoxFlat = cell_style.duplicate()
		cell_hover.bg_color = Color(0.12, 0.23, 0.29, 0.76)
		cell.add_theme_stylebox_override("normal", cell_style)
		cell.add_theme_stylebox_override("hover", cell_hover)
		cell.add_theme_stylebox_override("pressed", cell_hover)
		cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		cell.pressed.connect(_select_experiment_item.bind(item_id))

		var cell_content := VBoxContainer.new()
		cell_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell_content.alignment = BoxContainer.ALIGNMENT_CENTER
		cell_content.add_theme_constant_override("separation", 1)
		cell_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cell_content)
		var orb := g._make_orb(item_id, 28)
		# Ячейка показывает только знак и имя; количество остаётся в запасе,
		# а не превращает компактный выбор в таблицу.
		orb.count = 0
		orb.interactive = false
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _experiment_hint_ids.has(item_id):
			orb.hint_pulse()
		cell_content.add_child(orb)
		var visible_name := g._online._item_name(item_id)
		if _experiment_hint_ids.has(item_id):
			visible_name = "★ " + visible_name
		var name_label := g._label(visible_name, 12)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell_content.add_child(name_label)
		_experiment_reagent_grid.add_child(cell)


func _experiment_reserved(item_id: String) -> int:
	var n := 0
	for token in _experiment_tokens:
		if is_instance_valid(token) and token.element_id == item_id:
			n += 1
	for in_cauldron in _experiment_cauldron_items:
		if in_cauldron == item_id:
			n += 1
	return n


func _experiment_can_take(item_id: String) -> bool:
	return int(g._engine.inventory.get(item_id, 0)) > _experiment_reserved(item_id)


func _select_experiment_item(item_id: String) -> void:
	# Выбор из полноэкранного списка сразу создаёт вещество на поле,
	# без отдельной кнопки подтверждения.
	_experiment_spawn_token(item_id)


func _on_experiment_source_tapped(_orb: ElementOrb, item_id: String) -> void:
	_select_experiment_item(item_id)


func _on_experiment_source_drag_started(_orb: ElementOrb, _at: Vector2, item_id: String) -> void:
	_experiment_drag_source = item_id
	_experiment_status.text = "Перенеси «%s» в котёл или отпусти на поле." % g._online._item_name(item_id)


func _on_experiment_source_drag_ended(_orb: ElementOrb, at: Vector2, item_id: String) -> void:
	if _experiment_drag_source != item_id:
		return
	_experiment_drag_source = ""
	if _experiment_cauldron_rect().has_point(at):
		_experiment_add_to_cauldron(item_id)
	else:
		_experiment_spawn_token(item_id)


func _experiment_field_local_rect(control: Control) -> Rect2:
	if control == null or _experiment_field == null:
		return Rect2()
	var rect := control.get_global_rect()
	var field_origin := _experiment_field.global_position
	rect.position -= field_origin
	return rect


func _experiment_position_taken(candidate: Rect2, token_size: float) -> bool:
	var padded := candidate.grow(10.0)
	var cauldron_rect := _experiment_field_local_rect(_experiment_cauldron).grow(18.0)
	if _experiment_cauldron != null and padded.intersects(cauldron_rect):
		return true
	for raw_token in _experiment_tokens:
		var token := raw_token as ElementOrb
		if not is_instance_valid(token):
			continue
		var token_rect := Rect2(token.position, Vector2(token_size, token_size)).grow(10.0)
		if padded.intersects(token_rect):
			return true
	# Верхняя часть окна занята заголовком, поиском и фильтрами. Не прячем
	# новое вещество под ними, даже если само окно остаётся полупрозрачным.
	if _experiment_drawer != null and _experiment_drawer.visible:
		var menu_head := Rect2(0.0, 0.0, _experiment_field.size.x, 214.0)
		if padded.intersects(menu_head):
			return true
		if _experiment_reagent_grid != null:
			for cell in _experiment_reagent_grid.get_children():
				var cell_control := cell as Control
				if cell_control != null and padded.intersects(_experiment_field_local_rect(cell_control).grow(6.0)):
					return true
	return false


func _experiment_token_position(_lane: int, token_size: float) -> Vector2:
	var w := _experiment_field.size.x
	var h := _experiment_field.size.y
	var min_x := 10.0
	var max_x := maxf(min_x, w - token_size - 10.0)
	var min_y := 82.0
	if _experiment_drawer != null and _experiment_drawer.visible:
		min_y = 216.0
	var max_y := maxf(min_y, h - token_size - 20.0)
	var candidate := Vector2(min_x, min_y)
	# Случайное место с несколькими попытками избежать котла, меню и
	# уже лежащих веществ. Если поле заполнено, последняя случайная точка
	# всё равно лучше, чем возвращение к фиксированной сетке.
	for _attempt in 80:
		candidate = Vector2(
			_experiment_position_rng.randf_range(min_x, max_x),
			_experiment_position_rng.randf_range(min_y, max_y))
		var candidate_rect := Rect2(candidate, Vector2(token_size, token_size))
		if not _experiment_position_taken(candidate_rect, token_size):
			return candidate
	return candidate


func _experiment_spawn_token(item_id: String) -> void:
	if not _experiment_can_take(item_id):
		_experiment_status.text = "В запасе нет свободной порции «%s»." % g._online._item_name(item_id)
		return
	if _experiment_field == null:
		return
	var token: ElementOrb = g._make_orb(item_id, 50)
	token.count = 1
	token.interactive = true
	token.size = Vector2(50, 50)
	# Окно выбора должно быть выше временных веществ: ячейки и подписи
	# не перекрываются добавленными орбами.
	token.z_index = 1
	token.name = "ВременныйРеагент_%d" % _experiment_token_seq
	_experiment_token_seq += 1
	token.tapped.connect(_on_experiment_token_tapped.bind(token))
	token.drag_started.connect(_on_experiment_token_drag_started)
	token.drag_ended.connect(_on_experiment_token_drag_ended)
	_experiment_field.add_child(token)
	_experiment_tokens.append(token)
	_remember_experiment_reagent(item_id)
	var lane := _experiment_tokens.size() - 1
	token.position = _experiment_token_position(lane, 50.0)
	token.scale = Vector2(0.74, 0.74)
	var appear := g.create_tween()
	appear.tween_property(token, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_experiment_status.text = "«%s» появился на поле. При желании перенеси его в котёл." % g._online._item_name(item_id)
	Sfx.click()
	# Содержимое каталога не изменилось: не пересобираем десятки ячеек
	# после каждого добавления и не двигаем выбранный элемент.


func _on_experiment_token_tapped(token: ElementOrb, _bound_token: ElementOrb) -> void:
	_experiment_add_token_to_cauldron(token)


func _on_experiment_token_drag_started(token: ElementOrb, _at: Vector2) -> void:
	_experiment_drag_token = token
	_experiment_status.text = "Несём «%s» к котлу…" % g._online._item_name(token.element_id)


func _on_experiment_token_drag_ended(token: ElementOrb, at: Vector2) -> void:
	if _experiment_drag_token == token:
		_experiment_drag_token = null
	if not is_instance_valid(token):
		return
	if _experiment_cauldron_rect().has_point(at):
		_experiment_add_token_to_cauldron(token)
	else:
		_experiment_status.text = "Реагент оставлен на поле — его можно перенести ещё раз."


func _experiment_cauldron_rect() -> Rect2:
	if _experiment_cauldron == null:
		return Rect2()
	return Rect2(_experiment_cauldron.global_position, _experiment_cauldron.size)


func _experiment_add_token_to_cauldron(token: ElementOrb) -> void:
	if not is_instance_valid(token) or not _experiment_tokens.has(token):
		return
	var item_id := token.element_id
	_experiment_tokens.erase(token)
	token.queue_free()
	_experiment_add_to_cauldron(item_id)


func _experiment_add_to_cauldron(item_id: String) -> void:
	if _experiment_cauldron_items.size() >= Game.EXPERIMENT_ARITY_MAX:
		_experiment_status.text = "Котёл готов. Дождись ответа или освободи его."
		return
	if not _experiment_can_take(item_id):
		_experiment_status.text = "Для этого реагента не хватает запаса."
		return
	_remember_experiment_reagent(item_id)
	_experiment_cauldron_items.append(item_id)
	_refresh_experiment_cauldron()
	if _experiment_cauldron != null:
		_experiment_cauldron.trigger_ingredient(g._item_colors.get(item_id, Color.WHITE))
	Input.vibrate_handheld(12)
	Sfx.bubble()
	if _experiment_cauldron_items.size() < Game.EXPERIMENT_ARITY_MAX:
		_experiment_status.text = "«%s» в котле. Можно добавить ещё вещества на поле." % g._online._item_name(item_id)
	elif _experiment_cauldron_items.size() == Game.EXPERIMENT_ARITY_MAX:
		_experiment_status.text = "Состав собран · Светик проверяет его у сервера."
		_experiment_launch_pair()


func _refresh_experiment_cauldron() -> void:
	if _experiment_cauldron == null:
		return
	if _experiment_reagent_search != null:
		_experiment_reagent_search.placeholder_text = "Найти вещество…"
	if _experiment_clear_button != null:
		_experiment_clear_button.disabled = _experiment_cauldron_items.is_empty()
	if _experiment_cauldron_items.is_empty():
		_experiment_cauldron.clear_mixture()
		_experiment_recipe_line.text = "Свободен · перетащи реагенты сюда"
	elif _experiment_cauldron_items.size() == 1:
		var first := _experiment_cauldron_items[0]
		_experiment_cauldron.set_mixture(g._item_colors.get(first, Color.WHITE), g._item_colors.get(first, Color.WHITE))
		_experiment_recipe_line.text = "В котле: %s" % g._online._item_name(first)
	else:
		var a := _experiment_cauldron_items[0]
		var b := _experiment_cauldron_items[1]
		_experiment_cauldron.set_mixture(g._item_colors.get(a, Color.WHITE), g._item_colors.get(b, Color.WHITE))
		_experiment_recipe_line.text = "%s + %s · проверяем…" % [g._online._item_name(a), g._online._item_name(b)]


func _experiment_clear_cauldron() -> void:
	if _experiment_cauldron_items.is_empty():
		return
	var returned := _experiment_cauldron_items.size()
	_experiment_cauldron_items.clear()
	_refresh_experiment_cauldron()
	_experiment_status.text = "Котёл очищен: %d реагент(а) снова доступны в выборе." % returned
	Sfx.click()


func _experiment_launch_pair() -> void:
	if _experiment_cauldron_items.size() < 2:
		return
	var a := _experiment_cauldron_items[0]
	var b := _experiment_cauldron_items[1]
	var check := g._engine._experiment_status(a, b)
	if not bool(check.get("ok", false)):
		var reason := String(check.get("reason", "Эта пара пока недоступна."))
		_experiment_hint_ids.clear()
		if _experiment_filter == "hint":
			_experiment_filter = "recent"
		_experiment_cauldron_items.clear()
		_refresh_experiment_cauldron()
		_experiment_status.text = reason + " Реагенты возвращены на панель."
		_experiment_recipe_line.text = "Котёл свободен · выбери другую пару"
		_refresh_experiment_drawer()
		return
	# Визуальное состояние очищается до сетевого вызова: сервер теперь владеет расходом и возвратом.
	_experiment_hint_ids.clear()
	if _experiment_filter == "hint":
		_experiment_filter = "recent"
	_experiment_cauldron_items.clear()
	_refresh_experiment_cauldron()
	var started := g._online._start_experiment(a, b)
	if started:
		_experiment_status.text = "Светик раздувает огонь… сервер проверяет эту пару."
	else:
		# Офлайн/отказ до списания: ничего не потеряно, вернём пару в котёл.
		_experiment_cauldron_items = [a, b]
		_refresh_experiment_cauldron()
	_refresh_experiment_drawer()


func _refresh_experiment_location() -> void:
	if _experiment_field == null:
		return
	_refresh_experiment_drawer()
	_refresh_experiment_cauldron()
	if _experiment_status != null and g._engine._experiment_pending_pair.size() == 2:
		_experiment_status.text = "Светик проверяет пару на сервере… реагенты пока зарезервированы."


func _build_world(page: VBoxContainer) -> void:
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(g._label("Мир живых открытий", 20))
	g._online._world_status = g._label("Связываемся с миром…", 14)
	g._online._world_status.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	page.add_child(g._online._world_status)
	var race_title := g._label("Гонка первооткрытий", 16)
	race_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	page.add_child(race_title)
	# Блок 5: цель дня — карточкой с иконкой кубка (награда видна в тексте цели).
	var challenge_card := PanelContainer.new()
	var ccsb := StyleBoxFlat.new()
	ccsb.bg_color = Color(0.12, 0.10, 0.05, 0.9)
	ccsb.set_corner_radius_all(12)
	ccsb.border_color = Color(0.47, 0.39, 0.16, 0.9)
	ccsb.set_border_width_all(1)
	ccsb.content_margin_left = 12
	ccsb.content_margin_right = 12
	ccsb.content_margin_top = 10
	ccsb.content_margin_bottom = 10
	challenge_card.add_theme_stylebox_override("panel", ccsb)
	page.add_child(challenge_card)
	var challenge_row := HBoxContainer.new()
	challenge_row.add_theme_constant_override("separation", 10)
	challenge_card.add_child(challenge_row)
	challenge_row.add_child(UiIcon.make("trophy", 20, Color(1.0, 0.85, 0.42)))
	g._online._challenge_avatar = g._make_avatar("", 20)
	g._online._challenge_avatar.visible = false
	challenge_row.add_child(g._online._challenge_avatar)
	g._online._challenge_label = g._label("Цель дня появится после связи с миром…", 13)
	g._online._challenge_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	g._online._challenge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	challenge_row.add_child(g._online._challenge_label)
	var feed_title := g._label("Свежие открытия", 16)
	feed_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.9))
	page.add_child(feed_title)
	g._feed_list = VBoxContainer.new()
	g._feed_list.add_theme_constant_override("separation", 3)
	page.add_child(g._feed_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	page.add_child(scroll)
	col.add_child(g._label("Зал славы", 18))
	g._online._hall_list = VBoxContainer.new()
	g._online._hall_list.add_theme_constant_override("separation", 4)
	col.add_child(g._online._hall_list)
	col.add_child(g._label("Топ длинных цепочек", 18))
	g._online._chains_list = VBoxContainer.new()
	g._online._chains_list.add_theme_constant_override("separation", 4)
	col.add_child(g._online._chains_list)
	# Социальные отголоски принадлежат Миру, а не отдельному инструменту.
	g._resonance._build_resonance_page(col)
	col.add_child(g._label("Все вещества", 18))
	g._online._world_search = LineEdit.new()
	g._online._world_search.placeholder_text = "Поиск по миру: имя, id, автор…"
	g._online._world_search.clear_button_enabled = true
	g._online._world_search.custom_minimum_size = Vector2(0, 40)
	g._online._world_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.05, 0.08, 0.12, 0.9)
	ssb.set_corner_radius_all(10)
	ssb.content_margin_left = 12
	ssb.content_margin_right = 12
	g._online._world_search.add_theme_stylebox_override("normal", ssb)
	g._online._world_search.text_changed.connect(g._online._on_world_search)
	g._online._world_search.text_submitted.connect(func(_t: String) -> void: g.get_viewport().gui_release_focus())
	col.add_child(g._online._world_search)
	g._online._world_grid = GridContainer.new()
	g._online._world_grid.columns = 1
	g._online._world_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g._online._world_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(g._online._world_grid)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 8)
	col.add_child(pager)
	g._online._world_prev = g._small_button("‹", Vector2(44, 44), 1)
	g._online._world_prev.pressed.connect(func() -> void: g._online._world_set_page(g._online._world_page - 1))
	pager.add_child(g._online._world_prev)
	g._online._world_page_label = g._label("", 13)
	g._online._world_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g._online._world_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(g._online._world_page_label)
	g._online._world_next = g._small_button("›", Vector2(44, 44), 1)
	g._online._world_next.pressed.connect(func() -> void: g._online._world_set_page(g._online._world_page + 1))
	pager.add_child(g._online._world_next)
	g._online._rebuild_world_grid()
	g._online._refresh_chains()
	g._online._update_event_ui()
	g._refetch_world()

# ---------- судьбоносные режимы-вкладки ----------

func _mode_hint(key: String) -> String:
	for m in Game.MODES:
		if String(m["key"]) == key:
			return String(m["hint"])
	return ""

# ---------- инструменты: единая вкладка-хаб (вместо растущих вкладок) ----------

func _build_tools_page(page: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	page.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	_tools_hint = g._label("Инструменты открываются вместе с новыми веществами. Сколько бы их ни стало — всё здесь, в одной вкладке.", 13)
	_tools_hint.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(_tools_hint)
	_tools_flow = HFlowContainer.new()
	_tools_flow.add_theme_constant_override("h_separation", 6)
	_tools_flow.add_theme_constant_override("v_separation", 6)
	col.add_child(_tools_flow)
	_tools_sub = VBoxContainer.new()
	_tools_sub.add_theme_constant_override("separation", 8)
	col.add_child(_tools_sub)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 150)
	col.add_child(bottom_pad)


func _ensure_modes() -> void:
	if _tools_flow == null:
		return
	var unlocked_keys := {}
	var selectable_keys := {}
	# чипы: по одному на режим, порядок из MODES; не хватает ширины — переносятся
	for m in Game.MODES:
		var key := String(m["key"])
		if not _mode_chips.has(key):
			var new_chip := g._small_button(String(m["title"]), Vector2(0, 40))
			new_chip.toggle_mode = true
			new_chip.pressed.connect(_select_mode.bind(key))
			new_chip.visible = not bool(m.get("hidden", false))
			_tools_flow.add_child(new_chip)
			_mode_chips[key] = new_chip
		var chip: Button = _mode_chips[key]
		var unlocked := g._engine._mode_unlocked(key)
		chip.disabled = not unlocked
		chip.tooltip_text = String(m["hint"]) if not unlocked else String(m["title"])
		if unlocked:
			unlocked_keys[key] = true
			if not bool(m.get("hidden", false)):
				selectable_keys[key] = true
	# содержимое разблокированных режимов строим лениво и кэшируем
	for key in unlocked_keys:
		if _mode_pages.has(key):
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		match String(key):
			"experiment":
				box.add_child(g._label("Эксперимент перенесён в основную вкладку — здесь он больше не дублируется.", 12))
			"spring":
				box.add_child(g._label("Родник перенесён в Лабораторию.", 12))
			"bench":
				_build_bench_page(box)
			"resonance":
				box.add_child(g._label("Отголоски перенесены на страницу Мир.", 12))
			"retort":
				g._retort._build_retort_page(box)
			"letters":
				g._riddles._build_letters_page(box)
				# Атлас остаётся доступен, но живёт в том же экране, что и письма Светика.
				g._riddles._build_atlas_page(box)
			"atlas":
				g._riddles._build_atlas_page(box)
			"circle":
				g._retention._build_circle_page(box)
			"week":
				g._retention._build_week_page(box)
		_tools_sub.add_child(box)
		box.visible = false
		_mode_pages[key] = box
		_mode_tabs[key] = box  # обратная совместимость (selftest/диагностика)
	# если выбранного нет или он закрылся — берём первый разблокированный
	if _tools_sel == "" or not selectable_keys.has(_tools_sel):
		_tools_sel = ""
		for m in Game.MODES:
			var k2 := String(m["key"])
			if selectable_keys.has(k2):
				_tools_sel = k2
				break
	_apply_tools_selection()


func _apply_tools_selection() -> void:
	for k in _mode_pages:
		(_mode_pages[k] as Control).visible = (k == _tools_sel)
	for k in _mode_chips:
		var chip: Button = _mode_chips[k]
		var unlocked := g._engine._mode_unlocked(String(k))
		chip.button_pressed = (k == _tools_sel) and unlocked
	_refresh_mode_pages()


func _select_mode(key: String) -> void:
	if not g._engine._mode_unlocked(key):
		g._online._set_status(_mode_hint(key))
		Sfx.error()
		return
	_tools_sel = key
	_apply_tools_selection()
	if key == "resonance":
		g._resonance._fetch_echoes()
	if key == "letters":
		g._riddles._fetch_letters()
		g._riddles._fetch_atlas()
	Sfx.click()

func _build_experiment_page(container: VBoxContainer) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 8)
	container.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	col.add_child(g._label(_mode_hint("experiment"), 15))
	var desc := g._label("Открытия и производство разделены: здесь можно проверить неизвестную пару, а длинный известный маршрут запускается в книге как Производство.", 12)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
	col.add_child(desc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_experiment_a_pick = OptionButton.new()
	_experiment_a_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experiment_a_pick.item_selected.connect(_on_experiment_pick_a)
	row.add_child(_experiment_a_pick)
	row.add_child(g._label("+", 20))
	_experiment_b_pick = OptionButton.new()
	_experiment_b_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_experiment_b_pick.item_selected.connect(_on_experiment_pick_b)
	row.add_child(_experiment_b_pick)
	_experiment_button = g._round_brew_button("Проверить сочетание")
	_experiment_button.custom_minimum_size = Vector2(210, 42)
	_experiment_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_experiment_button.pressed.connect(_submit_experiment)
	col.add_child(_experiment_button)
	_experiment_info = g._label("", 13)
	_experiment_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_experiment_info)
	_experiment_preview = g._label("Результат не задаёт статы или цену: технические свойства назначаются сервером по валидатору.", 11)
	_experiment_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_experiment_preview.add_theme_color_override("font_color", Color(0.55, 0.66, 0.72))
	col.add_child(_experiment_preview)
	_experiment_confirm = ConfirmationDialog.new()
	_experiment_confirm.title = "Подтвердить Эксперимент"
	_experiment_confirm.ok_button_text = "Экспериментировать"
	_experiment_confirm.cancel_button_text = "Отмена"
	_experiment_confirm.confirmed.connect(_confirm_experiment)
	g.add_child(_experiment_confirm)
	_refresh_experiment_page()

func _experiment_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw in g._engine.inventory.keys():
		var id := String(raw)
		if g.ITEMS.has(id) and int(g._engine.inventory.get(id, 0)) > 0:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return g._online._item_name(a) < g._online._item_name(b))
	return ids

func _fill_experiment_picker(picker: OptionButton, selected: String) -> String:
	if picker == null:
		return ""
	var ids := _experiment_ids()
	picker.clear()
	var chosen := selected
	for i in ids.size():
		var id := ids[i]
		picker.add_item(g._online._item_name(id))
		picker.set_item_metadata(i, id)
		if id == selected:
			picker.select(i)
	if chosen == "" or not ids.has(chosen):
		chosen = String(ids[0]) if not ids.is_empty() else ""
		if chosen != "":
			picker.select(ids.find(chosen))
	return chosen

func _on_experiment_pick_a(index: int) -> void:
	if _experiment_a_pick != null and index >= 0:
		_experiment_a = String(_experiment_a_pick.get_item_metadata(index))
	_refresh_experiment_page()

func _on_experiment_pick_b(index: int) -> void:
	if _experiment_b_pick != null and index >= 0:
		_experiment_b = String(_experiment_b_pick.get_item_metadata(index))
	_refresh_experiment_page()

func _submit_experiment() -> void:
	if _experiment_a == "" or _experiment_b == "":
		return
	var check := g._engine._experiment_status(_experiment_a, _experiment_b)
	if not bool(check.get("ok", false)):
		_refresh_experiment_page()
		return
	if _experiment_confirm == null:
		return
	_experiment_confirm.dialog_text = "Потратить %d ⚡ и по одному реагенту?\n\n%s + %s\n\nРезультат определит сервер; характеристики, стоимость и награды не задаются внешним генератором." % [
		Game.EXPERIMENT_COST, g._online._item_name(_experiment_a), g._online._item_name(_experiment_b)]
	_experiment_confirm.popup_centered(Vector2i(420, 0))

func _confirm_experiment() -> void:
	g._online._start_experiment(_experiment_a, _experiment_b)
	_refresh_experiment_page()

func _focus_experiment(a: String, b: String) -> void:
	_experiment_a = a
	_experiment_b = b
	# Неизвестные узлы всегда ведут в первичную пространственную локацию.
	if g._tabs_ref != null:
		g._tabs_ref.current_tab = 0
	_refresh_experiment_location()
	_refresh_experiment_page()

func _refresh_experiment_page() -> void:
	if _experiment_a_pick == null or _experiment_b_pick == null:
		return
	_experiment_a = _fill_experiment_picker(_experiment_a_pick, _experiment_a)
	_experiment_b = _fill_experiment_picker(_experiment_b_pick, _experiment_b)
	if _experiment_info == null:
		return
	if _experiment_a == "" or _experiment_b == "":
		_experiment_info.text = "Нужно открыть хотя бы два вещества."
		if _experiment_button != null:
			_experiment_button.disabled = true
		return
	var check := g._engine._experiment_status(_experiment_a, _experiment_b)
	var key := g._pair_key(_experiment_a, _experiment_b)
	var known := g._engine.known_recipes.has(key)
	var remaining := g._engine._experiment_remaining()
	var cooldown := g._engine._experiment_cooldown_remaining()
	var line := "Лимит: %d/%d сегодня · эфир: %d ⚡" % [remaining, Game.EXPERIMENT_DAILY_LIMIT, Game.EXPERIMENT_COST]
	if cooldown > 0.0:
		line += " · перерыв: %d с" % ceili(cooldown)
	if known:
		line += "\nПара уже изучена — используй Производство в книге рецептов."
	elif g._engine._rejected_pairs.has(key):
		line += "\nПара уже признана несочетаемой."
	else:
		line += "\nХэш пары: v1/%s · сначала проверится серверный кэш." % key
	_experiment_info.text = line + "\n" + String(check.get("reason", "Готово к эксперименту."))
	if _experiment_button != null:
		_experiment_button.disabled = not bool(check.get("ok", false)) or g._engine._experiment_pending_pair.size() > 0

func _build_spring_page(container: VBoxContainer) -> void:
	container.add_child(g._label(_mode_hint("spring"), 15))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	container.add_child(row)
	for item_id in Game.BASE_IDS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var orb := g._make_orb(item_id, 64)
		orb.tapped.connect(_on_spring_pick.bind(item_id))
		col.add_child(orb)
		var mark := g._label("", 15)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.custom_minimum_size = Vector2(64, 20)
		mark.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
		col.add_child(mark)
		row.add_child(col)
		_spring_pick_btn[item_id] = {"orb": orb, "mark": mark}
	_spring_toggle_btn = g._round_brew_button("Пустить родник")
	_spring_toggle_btn.custom_minimum_size = Vector2(184, 42)
	_spring_toggle_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spring_toggle_btn.pressed.connect(_toggle_spring)
	container.add_child(_spring_toggle_btn)
	_spring_info = g._label("", 14)
	container.add_child(_spring_info)

func _spend_gate(key: String, now_ms: int) -> bool:
	# True — трата разрешена (окно свободно) и ключ взведён; False — повторный тап
	# внутри SPEND_GUARD_MSEC. now_ms параметром, чтобы это было чисто тестируемо.
	# Взводится на входе, поэтому отказанного следующим гейтом тапа окно тоже
	# тратит 250 мс: это анти-спам очереди нажатий (тот же смысл, что
	# _collect_all_ms в core.gd), а не бухгалтерия списаний.
	var last := int(_spend_guard_ms.get(key, -Game.SPEND_GUARD_MSEC))
	if now_ms - last < Game.SPEND_GUARD_MSEC:
		return false
	_spend_guard_ms[key] = now_ms
	return true

func _hint() -> bool:
	# Единственная подсказка — платный голос Светика. Она показывает направление,
	# но никогда не раскрывает результат и не создаёт новую валюту.
	if not _spend_gate("hint", Time.get_ticks_msec()):
		return false
	if not g._spirit._companion_unlocked:
		g._engine.status_text = "Светик ещё не проснулся. Открой первую Искру — и он подскажет путь."
		Sfx.error()
		g._engine._refresh()
		return false
	if g._engine.brewing or g._engine._experiment_pending_pair.size() > 0:
		g._engine.status_text = "Светик подскажет после завершения текущей варки."
		Sfx.error()
		g._engine._refresh()
		return false
	var cand := _hint_candidates()
	if cand.is_empty():
		g._engine.status_text = "Светик не видит подходящей пары из твоих запасов — добавь вещества на стол."
		Sfx.error()
		g._engine._refresh()
		return false
	if g._engine._available_ether() < Game.HINT_COST:
		g._engine.status_text = "Светику нужен эфир: %d ⚡." % Game.HINT_COST
		Sfx.error()
		g._engine._refresh()
		return false
	var chosen: Dictionary = cand[randi() % cand.size()]
	var a := String(chosen.get("a", ""))
	var b := String(chosen.get("b", ""))
	_experiment_hint_ids.clear()
	_experiment_hint_ids.append(a)
	_experiment_hint_ids.append(b)
	_experiment_filter = "hint"
	g._engine._spend_ether(Game.HINT_COST)
	Analytics.track("hint_purchase", {"source": "svetik", "cost": Game.HINT_COST, "left": a, "right": b})
	g._engine.status_text = "Светик шепчет: попробуй «%s» + «%s». Результат откроешь сам." % [
		g._online._item_name(a), g._online._item_name(b)]
	g._spirit._companion_react("hint", "%s + %s" % [g._online._item_name(a), g._online._item_name(b)])
	_focus_experiment(a, b)
	var orb_a: ElementOrb = g._engine._item_orbs.get(a)
	if orb_a != null:
		orb_a.hint_pulse()
	var orb_b: ElementOrb = g._engine._item_orbs.get(b)
	if orb_b != null:
		orb_b.hint_pulse()
	Sfx.click()
	g._engine._refresh()
	g._saves._save_game()
	return true

func _hint_candidates() -> Array:
	# приоритет: неопробованные пары из открытых веществ (локальные + серверные)
	var res: Array = []
	var seen := {}
	var ids: Array = g._engine.inventory.keys()
	for r in g.RECIPES:
		var a := String(r["a"])
		var b := String(r["b"])
		if g._engine.known_recipes.has(g._pair_key(a, b)) or g._engine._rejected_pairs.has(g._pair_key(a, b)):
			continue
		if g._online._has_ingredients(a, b):
			res.append(r)
			seen[g._pair_key(a, b)] = true
	# Серверные пары и самосочетания тоже остаются честными кандидатами: подсказка
	# никогда не ведёт в уже известный рецепт и не предлагает недостающий запас.
	for raw_a in ids:
		for raw_b in ids:
			var a := String(raw_a)
			var b := String(raw_b)
			var key := g._pair_key(a, b)
			if seen.has(key) or g._engine.known_recipes.has(key) or g._engine._rejected_pairs.has(key):
				continue
			if g._online._has_ingredients(a, b):
				res.append({"a": a, "b": b, "out": "?"})
				seen[key] = true
	return res

func _build_bench_page(container: VBoxContainer) -> void:
	container.add_child(g._label(_mode_hint("bench"), 15))
	var bench_poster := "Подмастерье: варит выбранное вещество каждые %d с, копит до %d шт. и останавливается. Эфир списывается по обычной цене варки; скидка чертежа применяется." % [int(Game.BENCH_INTERVAL), Game.BENCH_LIMIT]
	container.add_child(g._label(bench_poster, 12))
	if _bench_page_labels == null:
		_bench_page_labels = []
	(_bench_page_labels as Array).append(bench_poster)
	_bench_info = g._label("", 14)
	container.add_child(_bench_info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)
	_bench_rows = VBoxContainer.new()
	_bench_rows.add_theme_constant_override("separation", 6)
	_bench_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bench_rows)
	_bench_toggle_btn = g._round_brew_button("Включить верстак")
	_bench_toggle_btn.custom_minimum_size = Vector2(184, 42)
	_bench_toggle_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bench_toggle_btn.pressed.connect(_toggle_bench)
	container.add_child(_bench_toggle_btn)
	_rebuild_bench_rows()

func _bench_candidates() -> Array:
	var res: Array = []
	var seen := {}
	for r in g.RECIPES:
		var out := String(r["out"])
		if seen.has(out):
			continue
		if not g._engine.known_recipes.has(g._pair_key(String(r["a"]), String(r["b"]))):
			continue
		seen[out] = true
		res.append(out)
	res.sort_custom(func(x: String, y: String) -> bool:
		var lx := g._engine._layer_of(x)
		var ly := g._engine._layer_of(y)
		if lx != ly:
			return lx < ly
		return x < y)
	return res

func _rebuild_bench_rows() -> void:
	if _bench_rows == null:
		return
	for child in _bench_rows.get_children():
		_bench_rows.remove_child(child)
		child.queue_free()
	for raw in _bench_candidates():
		var out := String(raw)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected := out == _bench_target
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.20, 0.22, 0.95) if selected else Color(0.08, 0.11, 0.16, 0.9)
		sb.set_corner_radius_all(12)
		sb.border_color = Color(0.35, 0.85, 0.8, 0.55) if selected else Color(0.3, 0.4, 0.5, 0.3)
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_on_bench_pick.bind(out))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		hb.add_child(g._engine._mini_orb(out, 34))
		var nm := g._label(g._online._item_name(out), 15)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nm)
		if selected:
			var mk := g._label("выбрано", 12)
			mk.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
			mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(mk)
		_bench_rows.add_child(b)

func _on_bench_pick(item_id: String) -> void:
	_bench_target = item_id
	_bench_clock = 0.0
	Sfx.click()
	_rebuild_bench_rows()
	g._engine._refresh()
	g._saves._save_game()

func _toggle_bench() -> void:
	if _bench_target == "":
		g._engine.status_text = "Сначала выбери на Верстаке, что варить."
		Sfx.error()
		g._engine._refresh()
		return
	_bench_on = not _bench_on
	_bench_clock = 0.0
	Sfx.click()
	g._engine._refresh()
	g._saves._save_game()

func _experiment_tick() -> void:
	if _experiment_drag_token == null or not is_instance_valid(_experiment_drag_token) or _experiment_field == null:
		return
	var field_point := _experiment_field.get_global_transform_with_canvas().affine_inverse() * g.get_global_mouse_position()
	var pos: Vector2 = field_point - _experiment_drag_token.size * 0.5
	var play_right := _experiment_play_right if _experiment_play_right > 0.0 else _experiment_field.size.x
	var max_x: float = maxf(16.0, play_right - _experiment_drag_token.size.x - 16.0)
	var play_bottom := _experiment_field.size.y - 18.0
	var max_y: float = maxf(74.0, play_bottom - _experiment_drag_token.size.y)
	_experiment_drag_token.position = Vector2(clampf(pos.x, 16.0, max_x), clampf(pos.y, 70.0, max_y))


func _bench_tick(delta: float) -> void:
	if not g._engine._mode_unlocked("bench") or not _bench_on or _bench_target == "":
		return
	if _bench_busy or g._engine._auto:
		return
	_bench_clock += delta
	if _bench_clock < Game.BENCH_INTERVAL:
		return
	_bench_clock = 0.0
	if int(g._engine.inventory.get(_bench_target, 0)) >= Game.BENCH_LIMIT:
		g._engine.status_text = "Верстак: «%s» уже накоплен до лимита %d — выбери другое вещество." % [g._online._item_name(_bench_target), Game.BENCH_LIMIT]
		g._engine._refresh()
		return
	var plan := g._guild._plan_craft(_bench_target)
	if not bool(plan.get("ok", false)):
		g._engine.status_text = "Верстак ждёт: %s" % String(plan.get("reason", "нет подходящего рецепта"))
		g._engine._refresh()
		return
	# Верстак тоже работает по этапам: нехватка полной стоимости не блокирует
	# первый доступный шаг. Следующий тик продолжит маршрут.
	g._engine._run_bench_plan(_bench_target, plan)

func _unrevealed_recipe_candidates() -> Array:
	var res: Array = []
	for r in g.RECIPES:
		var a := String(r["a"])
		var b := String(r["b"])
		if g._engine.known_recipes.has(g._pair_key(a, b)) or g._engine._rejected_pairs.has(g._pair_key(a, b)):
			continue
		if g._engine.inventory.has(a) and g._engine.inventory.has(b):
			res.append(r)
	return res

func _on_spring_pick(_orb: ElementOrb, item_id: String) -> void:
	g._engine.spring_source = item_id
	Sfx.click()
	g._engine._refresh()
	g._saves._save_game()

func _toggle_spring() -> void:
	g._engine.spring_on = not g._engine.spring_on
	_spring_clock = 0.0
	Sfx.click()
	g._engine._refresh()
	g._saves._save_game()

func _refresh_mode_pages() -> void:
	_refresh_experiment_location()
	_refresh_experiment_page()
	if _spring_info != null:
		var spring_ready := g._engine._mode_unlocked("spring")
		var base_name := g._online._item_name(g._engine.spring_source)
		_spring_info.text = ("Каждые %d с: +1 «%s» — базовая стихия, без трат эфира." % [int(Game.SPRING_INTERVAL), base_name]) if spring_ready else "Родник откроется после открытия Ростка."
		if _spring_toggle_btn != null:
			_spring_toggle_btn.disabled = not spring_ready
			_spring_toggle_btn.text = "Остановить родник" if g._engine.spring_on else "Пустить родник"
	for raw in _spring_pick_btn:
		var id2 := String(raw)
		var entry: Dictionary = _spring_pick_btn[id2]
		(entry["mark"] as Label).text = "▼" if id2 == g._engine.spring_source else ""
		(entry["orb"] as ElementOrb).queue_redraw()
	if _bench_info != null:
		var cand := _bench_candidates()
		var tgt := "не выбран"
		if _bench_target != "":
			tgt = g._online._item_name(_bench_target)
		var state := "варится сам" if _bench_on else "на паузе"
		_bench_info.text = "Подмастерье: %s · «%s» · рецептов доступно: %d" % [state, tgt, cand.size()]
		if _bench_toggle_btn != null:
			_bench_toggle_btn.text = "Остановить верстак" if _bench_on else "Включить верстак"
		if _bench_rows != null and _bench_rows.get_child_count() != cand.size():
			_rebuild_bench_rows()
	g._retort._refresh_retort_page()
	g._riddles._refresh_letters_page()
	g._riddles._refresh_atlas_page()
