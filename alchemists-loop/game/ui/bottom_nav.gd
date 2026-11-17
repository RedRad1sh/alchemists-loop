extends RefCounted
class_name BottomNav

const Kit = preload("res://game/ui/menu_kit.gd")
const NAV_H := 90

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
	var s := game.size.x / 360.0
	bar.offset_top = -58 * s
	var rail := StyleBoxTexture.new()
	rail.texture = Kit.texture("09_bottom_dock_bar.png")
	rail.content_margin_left = 6 * s
	rail.content_margin_right = 8 * s
	rail.content_margin_top = 6 * s
	rail.content_margin_bottom = 4 * s
	bar.add_theme_stylebox_override("panel", rail)
	# Фиксированная нижняя панель: событие мира не должно ложиться на неё (док §7).
	bar.add_to_group("qte_exclusion")
	parent.add_child(bar)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", roundi(5 * s))
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hbox)
	for spec in _specs():
		var btn := Button.new()
		var key := String(spec["key"])
		btn.name = "Nav_" + key
		Kit.clear_button(btn)
		btn.custom_minimum_size = Vector2(74 * s if key == "lab" else 0.0, 39 * s)
		btn.size_flags_horizontal = Control.SIZE_FILL if key == "lab" else Control.SIZE_EXPAND_FILL
		var artwork: TextureRect
		var icon_host: Control = btn
		if key == "lab":
			btn.z_index = 1
			var shield := Control.new()
			shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(shield)
			shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			artwork = Kit.glow_artwork(shield, "11_bottom_cauldron_shield.png")
			icon_host = shield
		else:
			artwork = Kit.glow_artwork(btn, "10_bottom_tab_button.png")
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.tooltip_text = String(spec["label"])
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		# Button — не контейнер: без якорей VBox встаёт в левый верх ячейки и подпись
		# с иконкой липнут к левому краю вместо центра.
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_host.add_child(vbox)
		var ic := CenterContainer.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(ic)
		var icon := UIIcon.make(String(spec["icon"]), roundi((24 if key == "lab" else 19) * s), Color("e2bc80"))
		ic.add_child(icon)
		var mark_box := CenterContainer.new()
		mark_box.visible = false
		mark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(mark_box)
		var mark := ColorRect.new()
		mark.name = "Mark"
		mark.custom_minimum_size = Vector2(24, 3)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark_box.add_child(mark)
		btn.pressed.connect(_on_pressed.bind(key))
		if key == "lab":
			var slot := Control.new()
			slot.custom_minimum_size = Vector2(74, 39) * s
			slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hbox.add_child(slot)
			slot.add_child(btn)
			btn.custom_minimum_size = Vector2.ZERO
			btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			btn.offset_left = -32 * s
			btn.offset_right = 32 * s
			btn.offset_top = -73 * s
			btn.offset_bottom = 2 * s
		else:
			hbox.add_child(btn)
		if key == "friends":
			# Счётчик непрочитанного и заявок — бейдж на самой иконке; его
			# правит core._refresh_header через g._social_btn.
			var badge := Kit.wax_badge()
			btn.add_child(badge)
			# Правый верхний угол иконки: от центра ячейки, а не от её края.
			badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			badge.offset_left = 6
			badge.offset_right = 32
			badge.offset_top = 0
			badge.offset_bottom = 17
			g._social_btn = btn
		var item := {"key": key, "tab": int(spec["tab"]), "btn": btn,
				"icon": icon, "mark": mark, "artwork": artwork, "hover": false}
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
	(it["icon"] as TextureRect).modulate = Color("ffe5a3") if active else col
	var material := (it["artwork"] as TextureRect).material as ShaderMaterial
	material.set_shader_parameter("active_amount", 1.0 if active else 0.0)
	var mark := Color(0, 0, 0, 0)
	if active:
		mark = UIStyle.BRASS
	elif hot:
		mark = Color(UIStyle.BRASS, 0.45)
	(it["mark"] as ColorRect).color = mark
