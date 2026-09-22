extends Control
# Оверлей «Геном»: список генов в порядке, перестановка стрелками/вперемешку.
# Любое изменение генома -> EventBus.genome_changed -> существо мутирует.

const RARITY_COLORS := [
	Color8(159, 184, 176),
	Color8(88, 166, 255),
	Color8(198, 120, 255),
	Color8(255, 184, 84)
]

var _rows_box: VBoxContainer
var _code_label: Label

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.06, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 26
	panel.offset_top = 110
	panel.offset_right = -26
	panel.offset_bottom = -90
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color8(15, 26, 30, 245)
	pbg.set_corner_radius_all(18)
	pbg.border_color = Color8(64, 190, 165, 90)
	pbg.set_border_width_all(2)
	pbg.content_margin_left = 18
	pbg.content_margin_right = 18
	pbg.content_margin_top = 16
	pbg.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", pbg)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var title := Label.new()
	title.text = I18n.t("genome_title")
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color8(235, 255, 248))
	col.add_child(title)

	var hint := Label.new()
	hint.text = I18n.t("genome_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color8(150, 190, 180))
	col.add_child(hint)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	col.add_child(code_row)

	_code_label = Label.new()
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_label.add_theme_font_size_override("font_size", 15)
	_code_label.add_theme_color_override("font_color", Color8(130, 220, 195))
	code_row.add_child(_code_label)

	var copy_btn := _small_btn(I18n.t("copy_code"), Vector2(150, 40))
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(GameState.dna_code())
		_code_label.text = I18n.t("copied"))
	code_row.add_child(copy_btn)

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 10)
	col.add_child(tool_row)

	var shuf_btn := _small_btn(I18n.t("shuffle"), Vector2(0, 42))
	shuf_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shuf_btn.pressed.connect(func() -> void:
		GameState.shuffle_genome()
		refresh()
		Sfx.morph())
	tool_row.add_child(shuf_btn)

	var close_btn := _small_btn(I18n.t("close"), Vector2(130, 42))
	close_btn.pressed.connect(func() -> void:
		visible = false)
	tool_row.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)

func _small_btn(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	if min_size.x > 0:
		b.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(30, 52, 56, 255)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color8(42, 70, 74, 255)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color8(220, 245, 238))
	return b

func refresh() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	_code_label.text = I18n.tf("dna", [GameState.dna_code()])
	var ids: Array = GameState.genome_ids
	if ids.is_empty():
		var empty := Label.new()
		empty.text = I18n.t("genome_hint")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color8(140, 170, 165))
		_rows_box.add_child(empty)
		return
	for i in ids.size():
		_rows_box.add_child(_build_row(i, String(ids[i]), ids.size()))

func _build_row(idx: int, id: String, total: int) -> HBoxContainer:
	var g: Dictionary = GameState.gene_by_id(id)
	var txt := I18n.gene_text(g)
	var rar := clampi(int(g.get("rarity", 0)), 0, 3)
	var col: Color = RARITY_COLORS[rar]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var chip := ColorRect.new()
	chip.color = col
	chip.custom_minimum_size = Vector2(16, 16)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)

	# мини-иконка гена (если сгенерирована)
	var tex: Texture2D = null
	var ipath := "res://assets/icons/" + id + ".png"
	if ResourceLoader.exists(ipath):
		tex = load(ipath)
	if tex != null:
		var mini := TextureRect.new()
		mini.texture = tex
		mini.custom_minimum_size = Vector2(34, 34)
		mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mini)

	var name_lb := Label.new()
	name_lb.text = txt["name"]
	name_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lb.add_theme_font_size_override("font_size", 18)
	name_lb.add_theme_color_override("font_color", Color8(225, 245, 240))
	name_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lb)

	var up := _small_btn("^", Vector2(46, 40))
	up.disabled = idx == 0
	up.pressed.connect(func() -> void:
		if GameState.move_gene(idx, -1):
			refresh()
			Sfx.morph())
	row.add_child(up)

	var down := _small_btn("v", Vector2(46, 40))
	down.disabled = idx == total - 1
	down.pressed.connect(func() -> void:
		if GameState.move_gene(idx, 1):
			refresh()
			Sfx.morph())
	row.add_child(down)

	return row

func open() -> void:
	refresh()
	visible = true
