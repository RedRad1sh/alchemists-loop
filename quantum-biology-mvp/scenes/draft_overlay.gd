extends Control
# Оверлей «Выбери ген»: драбл из 3 кандидатов после каждого деления.

signal picked(id: String)

const RARITY_COLORS := [
	Color8(159, 184, 176),   # обычный
	Color8(88, 166, 255),    # редкий
	Color8(198, 120, 255),   # эпический
	Color8(255, 184, 84)     # легендарный
]

var _cards_box: HBoxContainer

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := Label.new()
	title.text = I18n.t("draft_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color8(240, 255, 250))
	col.add_child(title)

	var cap := Label.new()
	cap.text = I18n.t("draft_caption")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 17)
	cap.add_theme_color_override("font_color", Color8(150, 190, 180))
	col.add_child(cap)

	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 16)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_cards_box)

func open() -> void:
	# очистить старые карточки
	for c in _cards_box.get_children():
		c.queue_free()
	var cands: Array = GameState.make_candidates(3)
	for g in cands:
		_cards_box.add_child(_build_card(g))
	visible = true

static func icon_tex(id: String) -> Texture2D:
	var path := "res://assets/icons/" + id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _build_card(g: Dictionary) -> Button:
	var rar: int = int(g.get("rarity", 0))
	var txt := I18n.gene_text(g)
	var border: Color = RARITY_COLORS[mini(rar, 3)]

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(206, 396)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(18, 30, 34, 250)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color8(26, 42, 46, 255)
	sb_hover.border_color = border.lightened(0.25)
	var sb_down: StyleBoxFlat = sb.duplicate()
	sb_down.bg_color = Color8(34, 54, 58, 255)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_down)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# контент кладём внутрь кнопки (текст кнопки пустой)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14
	vb.offset_top = 12
	vb.offset_right = -14
	vb.offset_bottom = -10
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vb)

	var rar_lb := Label.new()
	rar_lb.text = I18n.t("r" + str(rar)).to_upper()
	rar_lb.add_theme_font_size_override("font_size", 14)
	rar_lb.add_theme_color_override("font_color", border.lightened(0.2))
	rar_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(rar_lb)

	# чип с иконкой гена (сгенерирована, лежит в assets/icons)
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(0, 108)
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	isb.border_color = Color(border.r, border.g, border.b, 0.55)
	isb.set_border_width_all(2)
	isb.set_corner_radius_all(14)
	isb.content_margin_left = 4
	isb.content_margin_right = 4
	isb.content_margin_top = 4
	isb.content_margin_bottom = 4
	icon_panel.add_theme_stylebox_override("panel", isb)
	var tex: Texture2D = icon_tex(g["id"])
	if tex != null:
		var tr_icon := TextureRect.new()
		tr_icon.texture = tex
		tr_icon.custom_minimum_size = Vector2(98, 98)
		tr_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_panel.add_child(tr_icon)
	vb.add_child(icon_panel)

	var name_lb := Label.new()
	name_lb.text = txt["name"]
	name_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lb.add_theme_font_size_override("font_size", 25)
	name_lb.add_theme_color_override("font_color", Color8(235, 250, 245))
	name_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lb)

	var line := ColorRect.new()
	line.color = border
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(line)

	var desc_lb := Label.new()
	desc_lb.text = txt["desc"]
	desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lb.add_theme_font_size_override("font_size", 16)
	desc_lb.add_theme_color_override("font_color", Color8(160, 190, 183))
	desc_lb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(desc_lb)

	btn.pressed.connect(func() -> void:
		visible = false
		picked.emit(g["id"]))
	return btn
