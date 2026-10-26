class_name UIBackdrop
extends Control
# Фон экрана: комната (Room) → тёплый тинт темы (Tint) → виньетка (Vignette).
# Один слой на хост. Тинт — прежний _bg_rect, поэтому home и UIFx.ambient_bg
# продолжают работать без смены типа.

const TINT_ALPHA := 0.45

var _room: TextureRect
var _tint: ColorRect
var _vignette: TextureRect


static func attach(host: Control) -> UIBackdrop:
	var existing := host.get_node_or_null("UIBackdrop") as UIBackdrop
	if existing != null:
		return existing
	var bd := UIBackdrop.new()
	bd.name = "UIBackdrop"
	host.add_child(bd)
	host.move_child(bd, 0)
	return bd


func _init() -> void:
	name = "UIBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room = _layer("Room", UITheme.tex("backdrop_room"), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	var ink := Color("14100e")
	_tint = ColorRect.new()
	_tint.name = "Tint"
	_tint.color = Color(ink.r, ink.g, ink.b, TINT_ALPHA)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tint)
	_vignette = _layer("Vignette", UITheme.tex("vignette"), TextureRect.STRETCH_SCALE)


func _layer(layer_name: String, tex: Texture2D, stretch: TextureRect.StretchMode) -> TextureRect:
	var r := TextureRect.new()
	r.name = layer_name
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = stretch
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	return r


func tint_rect() -> ColorRect:
	return _tint


func set_tint(c: Color) -> void:
	_tint.color = Color(c.r, c.g, c.b, TINT_ALPHA)
