class_name UiIcon
extends RefCounted
## Векторные иконки сета «Atheneum»: assets/ui/icons (24 px) и assets/ui/icons16
## (16 px — для меню вкладок). База белая: в Godot тонируется modulate,
## в веб-превью — CSS mask. Генератор: tools/make_icons.py.

const ICON_DIR := "res://assets/ui/icons/"
const ICON_DIR_16 := "res://assets/ui/icons16/"

static func texture(name: String, size16 := false) -> Texture2D:
	var path := (ICON_DIR_16 if size16 else ICON_DIR) + name + ".svg"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Иконка нужного размера и цвета. mouse_filter = IGNORE: не крадёт тапы.
static func make(name: String, size_px: int = 20, color: Color = Color(1, 1, 1)) -> TextureRect:
	var rect := TextureRect.new()
	var tex := texture(name)
	if tex != null:
		rect.texture = tex
	rect.custom_minimum_size = Vector2(size_px, size_px)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = color
	rect.name = "Icon_" + name
	return rect

## Иконка по центру кнопки: текст-глиф убирается, тач-зона кнопки не меняется.
static func into_button(btn: Button, name: String, size_px: int = 20,
		color: Color = Color(1, 1, 1)) -> void:
	if btn == null:
		return
	btn.text = ""
	var old := btn.get_node_or_null("IconCenter")
	if old != null:
		old.queue_free()
	var center := CenterContainer.new()
	center.name = "IconCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(make(name, size_px, color))
	btn.add_child(center)

## Пилюля-бейдж со счётчиком поверх кнопки (вместо «▲N» в тексте).
static func badge(btn: Button, count: int) -> void:
	if btn == null:
		return
	var existing := btn.get_node_or_null("CountBadge")
	if count <= 0:
		if existing != null:
			existing.queue_free()
		return
	var lbl: Label
	if existing != null:
		lbl = existing as Label
	else:
		lbl = Label.new()
		lbl.name = "CountBadge"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = DesignTokens.c(DesignTokens.GOLD)
		sb.set_corner_radius_all(DesignTokens.R_PILL)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		lbl.add_theme_stylebox_override("normal", sb)
		lbl.add_theme_font_size_override("font_size", 11)
		var f := UiTheme.font(2)
		if f != null:
			lbl.add_theme_font_override("font", f)
		lbl.add_theme_color_override("font_color", DesignTokens.c(DesignTokens.GOLD_INK))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lbl.offset_left = -6
		lbl.offset_top = -6
		lbl.offset_right = 24
		lbl.offset_bottom = 12
		btn.add_child(lbl)
	lbl.text = str(count)
