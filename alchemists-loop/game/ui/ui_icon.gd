class_name UIIcon
extends RefCounted
# Набор векторных иконок «Atheneum» (из PR #32): assets/ui/icons — 24 px,
# assets/ui/icons16 — 16 px (меню вкладок). База белая: тонируется modulate.
# Тот же вид на любом DPI; шейдеров и текстурных атласов не требуют.

const ICON_DIR := "res://assets/ui/icons/"
const ICON_DIR_16 := "res://assets/ui/icons16/"


static func texture(icon: String, small: bool = false) -> Texture2D:
	var path := (ICON_DIR_16 if small else ICON_DIR) + icon + ".svg"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Иконка нужного размера и цвета. mouse_filter = IGNORE: не крадёт тапы.
static func make(icon: String, size_px: int = 20, color: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	var tex := texture(icon)
	if tex != null:
		rect.texture = tex
	rect.custom_minimum_size = Vector2(size_px, size_px)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = color
	rect.name = "Icon_" + icon
	return rect


## Иконка по центру кнопки: текст-глиф убирается, тач-зона не меняется.
## Если SVG ещё не импортирован (текстуры нет), текст остаётся как есть.
static func into_button(btn: Button, icon: String, size_px: int = 20,
		color: Color = UIStyle.TEXT) -> void:
	if btn == null:
		return
	var tex := texture(icon)
	if tex == null:
		return
	btn.text = ""
	var old := btn.get_node_or_null("IconCenter")
	if old != null:
		old.queue_free()
	var center := CenterContainer.new()
	center.name = "IconCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(make(icon, size_px, color))
	btn.add_child(center)
