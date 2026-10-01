class_name UiIcon
extends RefCounted
## Векторные иконки сета «Atheneum» (assets/ui/icons, 24x24, stroke 2).
## Иконка — TextureRect с SVG-текстурой, цвет задаётся modulate (currentColor
## в SVG = белый, поэтому модуляция даёт точный токен-цвет).

const T := DesignTokens
const ICON_DIR := "res://assets/ui/icons/"

static func texture(name: String) -> Texture2D:
	var path := ICON_DIR + name + ".svg"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Иконка нужного размера и цвета. mouse_filter = IGNORE: иконка не крадёт тапы.
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

## Иконка по центру кнопки: кнопка очищается от глифа-текста и получает
## центрированную иконку (тач-зона кнопки не меняется).
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

## Пилюля-бейдж со счётчиком (вместо «▲1» в тексте кнопки).
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
		lbl.add_theme_stylebox_override("normal", UiStyle.badge())
		lbl.add_theme_font_size_override("font_size", 11)
		var f := UiTheme.font(2)
		if f != null:
			lbl.add_theme_font_override("font", f)
		lbl.add_theme_color_override("font_color", T.c(T.GOLD_INK))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lbl.offset_left = -6
		lbl.offset_top = -4
		lbl.offset_right = 22
		lbl.offset_bottom = 14
		btn.add_child(lbl)
	lbl.text = str(count)
