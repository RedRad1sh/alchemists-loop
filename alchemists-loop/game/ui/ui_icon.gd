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
		color: Color = UIStyle.BRASS_HI) -> void:
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
	var rect := make(icon, size_px, color)
	center.add_child(rect)
	btn.add_child(center)
	# Наведение: иконка чуть светлеет и подрастает — одного осветления плашки
	# на тёмной латуни не видно.
	center.pivot_offset = btn.custom_minimum_size * 0.5
	if not btn.mouse_entered.is_connected(_hover):
		btn.mouse_entered.connect(_hover.bind(btn, true))
		btn.mouse_exited.connect(_hover.bind(btn, false))
	btn.set_meta("icon_color", color)


static func _hover(btn: Button, over: bool) -> void:
	var center := btn.get_node_or_null("IconCenter") as Control
	if center == null:
		return
	center.pivot_offset = btn.size * 0.5
	center.scale = Vector2(1.12, 1.12) if over and not btn.disabled else Vector2.ONE
	var base: Color = btn.get_meta("icon_color", Color.WHITE)
	for c in center.get_children():
		(c as CanvasItem).modulate = base.lightened(0.25) if over and not btn.disabled else base
