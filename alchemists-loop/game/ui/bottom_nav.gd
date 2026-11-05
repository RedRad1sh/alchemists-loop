extends RefCounted
class_name BottomNav
# Нижний бар навигации (перенос из PR #65): верхний TabBar спрятан, разделы
# переключает этот бар — он двигает тот же TabContainer, поэтому контракты
# тестов (current_tab, страницы) не разъезжаются. Балка — деревянный 9-slice
# tab_rail; активный раздел отличается цветом и латунной полосой под иконкой,
# а не отдельной накладкой на каждую кнопку.

const NAV_H := 70

var g: Game
var bar: PanelContainer = null
var _items: Array = []


const HOVER_ICON := Color(0.98, 0.90, 0.72)


# Правило навигации: всё, что открывается снизу, живёт в одной общей панели
# между шапкой и баром (комната за ней притушена); шапка открывает полноэкранные
# экраны и модалки поверх всего. Доска — только на стене комнаты, Аркан — в шапке.
# tab = -1: пункт открывает свою панель, а не страницу вкладок.
func _specs() -> Array:
	return [
		{"key": "lab", "tab": Game.TAB_EXPERIMENT, "icon": "gi_cauldron", "label": "Стол"},
		{"key": "world", "tab": Game.TAB_WORLD, "icon": "gi_world", "label": "Мир"},
		{"key": "friends", "tab": -1, "icon": "gi_friends", "label": "Друзья"},
		{"key": "rating", "tab": Game.TAB_RATING, "icon": "gi_rating", "label": "Рейтинг"},
		{"key": "tools", "tab": Game.TAB_TOOLS, "icon": "gi_more", "label": "Ещё"},
	]


func build(game: Game, parent: Control) -> void:
	g = game
	bar = PanelContainer.new()
	bar.name = "BottomNav"
	# Бар выше экрана механики (z=16): раздел меняется тапом, а не через «В комнату».
	bar.z_index = 17
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -NAV_H
	bar.offset_bottom = 0
	# Рейка во всю ширину без торцов: заглушки с заклёпками у краёв экрана
	# выглядели обрубками (претензия владельца к бокам бара).
	# Верх контента 15 px: иконки не прилипают к латунной рейке.
	var rail: StyleBox = UITheme.nine("tab_rail", Vector4(8, 12, 8, 8), Vector4(6, 15, 6, 4))
	if rail == null:
		rail = UIStyle.box(Color(0.09, 0.06, 0.04, 0.98), UIStyle.LINE, 0, 1)
	bar.add_theme_stylebox_override("panel", rail)
	# Фиксированная нижняя панель: событие мира не должно ложиться на неё (док §7).
	bar.add_to_group("qte_exclusion")
	parent.add_child(bar)
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hbox)
	for spec in _specs():
		var btn := Button.new()
		var key := String(spec["key"])
		btn.name = "Nav_" + key
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = String(spec["label"])
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		# Button — не контейнер: без якорей VBox встаёт в левый верх ячейки и подпись
		# с иконкой липнут к левому краю вместо центра.
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(vbox)
		var ic := CenterContainer.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(ic)
		var icon := UIIcon.make(String(spec["icon"]), 26, UIStyle.TEXT_DIM)
		ic.add_child(icon)
		var mark_box := CenterContainer.new()
		mark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(mark_box)
		var mark := ColorRect.new()
		mark.name = "Mark"
		mark.custom_minimum_size = Vector2(24, 3)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark_box.add_child(mark)
		var lb := Label.new()
		lb.text = String(spec["label"])
		lb.add_theme_font_size_override("font_size", 11)
		lb.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lb)
		btn.pressed.connect(_on_pressed.bind(key))
		hbox.add_child(btn)
		if key == "friends":
			# Счётчик непрочитанного и заявок — бейдж на самой иконке; его
			# правит core._refresh_header через g._social_btn.
			var badge := UIStyle.count_badge()
			btn.add_child(badge)
			# Правый верхний угол иконки: от центра ячейки, а не от её края.
			badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			badge.offset_left = 6
			badge.offset_right = 32
			badge.offset_top = 0
			badge.offset_bottom = 17
			g._social_btn = btn
		var item := {"key": key, "tab": int(spec["tab"]), "btn": btn,
				"icon": icon, "mark": mark, "label": lb, "hover": false}
		btn.mouse_entered.connect(_on_hover.bind(item, true))
		btn.mouse_exited.connect(_on_hover.bind(item, false))
		_items.append(item)


func _on_hover(item: Dictionary, over: bool) -> void:
	item["hover"] = over
	_paint(item, g._tabs_ref.current_tab if g._tabs_ref != null else -1)


func _on_pressed(key: String) -> void:
	Sfx.click()
	for it in _items:
		it["hover"] = false
	# Экран механики — не модалка: он не переживает смену раздела, иначе висел бы
	# окном поверх уже другой вкладки.
	if g._screens != null and g._screens.is_open():
		g._screens.close()
	if key == "friends":
		g._open_social()
		_repaint()
		return
	# Друзья делят ту же панель, что и вкладки: переход на вкладку её закрывает.
	if g._social_ui != null and g._social_ui.is_open():
		g._social_ui.close()
	for it in _items:
		if it["key"] == key:
			if g._tabs_ref != null:
				g._tabs_ref.current_tab = it["tab"]
			return


func refresh(active_tab: int) -> void:
	for it in _items:
		_paint(it, active_tab)


func _repaint() -> void:
	refresh(g._tabs_ref.current_tab if g._tabs_ref != null else -1)


## Активен открытый раздел: панель друзей перекрывает вкладку, поэтому, пока
## она открыта, подсвечены «Друзья», а не вкладка под ней.
func _is_active(it: Dictionary, active_tab: int) -> bool:
	var social_open: bool = g._social_ui != null and g._social_ui.is_open()
	if it["key"] == "friends":
		return social_open
	return not social_open and int(it["tab"]) >= 0 and it["tab"] == active_tab


func _paint(it: Dictionary, active_tab: int) -> void:
	var active := _is_active(it, active_tab)
	var hot: bool = bool(it.get("hover", false)) and not active
	var col: Color = UIStyle.BRASS_HI if active else (HOVER_ICON if hot else UIStyle.TEXT_DIM)
	(it["icon"] as TextureRect).modulate = col
	(it["label"] as Label).add_theme_color_override("font_color",
			UIStyle.CREAM if active or hot else UIStyle.TEXT_DIM)
	var mark := Color(0, 0, 0, 0)
	if active:
		mark = UIStyle.BRASS
	elif hot:
		mark = Color(UIStyle.BRASS, 0.45)
	(it["mark"] as ColorRect).color = mark
