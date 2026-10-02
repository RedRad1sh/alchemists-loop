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
