extends RefCounted
class_name BottomNav
# Нижний иконковый таб-бар (концепт concepts/ui-lab-main-paging.png):
# крупные иконки Atheneum + подписи, активный раздел — бирюза с подчёркиванием,
# бейджи точек внимания (социалка на «Мир»). Верхний TabBar прячется,
# а этот бар переключает тот же TabContainer — контракты тестов живут.

const NAV_H := 64

var g: Game
var bar: PanelContainer = null
var _items: Array = []  # {key, tab, btn, icon: TextureRect, label: Label, dot: Label}


func _specs() -> Array:
	return [
		{"key": "lab", "tab": Game.TAB_EXPERIMENT, "icon": "cauldron", "label": "Лаборатория"},
		{"key": "book", "tab": Game.TAB_LAB, "icon": "book", "label": "Гримуар"},
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
	var sb := UIStyle.box(Color(0.04, 0.06, 0.10, 0.98), UIStyle.LINE, 0, 1)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hbox)
	for spec in _specs():
		var btn := Button.new()
		btn.name = "Nav_" + String(spec["key"])
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = String(spec["label"])
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_child(vbox)
		var ic := CenterContainer.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(ic)
		var icon := UIIcon.make(String(spec["icon"]), 22, UIStyle.TEXT_DIM)
		ic.add_child(icon)
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
		dot.add_theme_color_override("font_color", UIStyle.DANGER)
		dot.visible = false
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -14
		dot.offset_top = 2
		btn.add_child(dot)
		var key := String(spec["key"])
		btn.pressed.connect(_on_pressed.bind(key))
		hbox.add_child(btn)
		_items.append({"key": key, "tab": int(spec["tab"]), "btn": btn,
				"icon": icon, "label": lb, "dot": dot})


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
		var col: Color = UIStyle.TEAL if active else UIStyle.TEXT_DIM
		(it["icon"] as TextureRect).modulate = col
		(it["label"] as Label).add_theme_color_override("font_color", col)


func refresh_badges() -> void:
	for it in _items:
		if it["key"] == "world":
			var pending: bool = g._social_btn != null and g._social_btn.text != "Друзья"
			(it["dot"] as Label).visible = pending
