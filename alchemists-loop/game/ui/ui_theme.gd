class_name UITheme
extends RefCounted
# Владелец путей и кэша текстур темы. UITheme не знает про UIStyle:
# токены остаются в UIStyle, здесь только материал.
# Каждый nine() создаёт новый StyleBoxTexture (их мутируют вызывающие),
# текстура берётся из кэша и общая.

const DIR := "res://assets/ui/theme/"

static var _tex_cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var path := DIR + name + ".png"
		_tex_cache[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex_cache[name] as Texture2D


static func nine(name: String, m: Vector4, content: Vector4 = Vector4.ZERO,
		mod: Color = Color.WHITE) -> StyleBoxTexture:
	var t := tex(name)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = m.x
	sb.texture_margin_top = m.y
	sb.texture_margin_right = m.z
	sb.texture_margin_bottom = m.w
	if content != Vector4.ZERO:
		sb.content_margin_left = content.x
		sb.content_margin_top = content.y
		sb.content_margin_right = content.z
		sb.content_margin_bottom = content.w
	sb.modulate_color = mod
	return sb


## normal/hover/pressed одной текстуры. Нажатие сдвигает контент на 1 px вниз
## (у StyleBoxTexture нет texture_offset); hover светлее, pressed темнее.
## Нет текстуры — пустой словарь, как null у nine(): вызывающий обязан проверить.
static func nine_hv(name: String, m: Vector4, content: Vector4,
		hover: float = 1.28, press: float = 0.82) -> Dictionary:
	if tex(name) == null:
		return {}
	var down := Vector4(content.x, content.y - 1.0, content.z, content.w + 1.0)
	return {
		"normal": nine(name, m, content),
		"hover": nine(name, m, content, Color(hover, hover, hover, 1.0)),
		"pressed": nine(name, m, down, Color(press, press, press, 1.0)),
	}
