extends RefCounted
class_name BottomNav
# Нижний бар навигации (перенос из PR #65): верхний TabBar спрятан, разделы
# переключает этот бар — он двигает тот же TabContainer, поэтому контракты
# тестов (current_tab, страницы) не разъезжаются. Балка — деревянный 9-slice
# tab_rail; активный раздел отличается цветом и латунной полосой под иконкой,
# а не отдельной накладкой на каждую кнопку.

const NAV_H := 64

var g: Game
var bar: PanelContainer = null
var _items: Array = []


func _specs() -> Array:
	return [
		{"key": "lab", "tab": Game.TAB_EXPERIMENT, "icon": "cauldron", "label": "Стол"},
		{"key": "book", "tab": Game.TAB_LAB, "icon": "flask", "label": "Лаборатория"},
		{"key": "world", "tab": Game.TAB_WORLD, "icon": "globe", "label": "Мир"},
		{"key": "house", "tab": -1, "icon": "home", "label": "Дом"},
		{"key": "rating", "tab": Game.TAB_RATING, "icon": "trophy", "label": "Рейтинг"},
		{"key": "tools", "tab": Game.TAB_TOOLS, "icon": "sliders", "label": "Ещё"},
	]


func build(game: Game, parent: Control) -> void:
	g = game
	bar = PanelContainer.new()
	bar.name = "BottomNav"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -NAV_H
	bar.offset_bottom = 0
	var rail: StyleBox = UITheme.nine("tab_rail", Vector4(24, 10, 24, 10), Vector4(6, 6, 6, 6))
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
		var icon := UIIcon.make(String(spec["icon"]), 22, UIStyle.TEXT_DIM)
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
		var dot := Label.new()
		dot.name = "Dot"
		dot.text = "•"
		dot.add_theme_font_size_override("font_size", 18)
		dot.add_theme_color_override("font_color", UIStyle.RUBY)
		dot.visible = false
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -14
		dot.offset_top = 2
		btn.add_child(dot)
		btn.pressed.connect(_on_pressed.bind(key))
		hbox.add_child(btn)
		_items.append({"key": key, "tab": int(spec["tab"]), "btn": btn,
				"icon": icon, "mark": mark, "label": lb, "dot": dot})


func _on_pressed(key: String) -> void:
	Sfx.click()
	if key == "house":
		g._home._open_workshop()
		return
	for it in _items:
		if it["key"] == key:
			if g._tabs_ref != null:
				g._tabs_ref.current_tab = it["tab"]
			return


func refresh(active_tab: int) -> void:
	for it in _items:
		var active: bool = it["tab"] == active_tab
		var col: Color = UIStyle.BRASS_HI if active else UIStyle.TEXT_DIM
		(it["icon"] as TextureRect).modulate = col
		(it["label"] as Label).add_theme_color_override("font_color",
				UIStyle.CREAM if active else UIStyle.TEXT_DIM)
		(it["mark"] as ColorRect).color = UIStyle.BRASS if active else Color(0, 0, 0, 0)


func refresh_badges() -> void:
	for it in _items:
		if it["key"] == "world":
			# Бейдж — тот же счётчик, что рисует шапка; от текста кнопки он не
			# зависит, иначе перенос навигации в сцену сломал бы индикатор.
			(it["dot"] as Label).visible = g._social.total() > 0
