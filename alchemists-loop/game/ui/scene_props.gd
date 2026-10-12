extends RefCounted
class_name SceneProps
# Объекты-сцены: спрайт с мягким золотым ореолом (стиль концептов
# concepts/ui-lab-*.png: желтоватое выделение у спрайтов и кнопок).
# SVG лежат в assets/ui/scene; пока редактор не импортировал их (headless
# selftest), кнопка показывает глиф-fallback и остаётся кликабельной.

const SCENE_DIR := "res://assets/ui/scene/"
const FALLBACK := {
	"fountain": "⛲",
	"workbench": "⚒",
	"retort": "⚗",
	"deck": "✦",
	"scroll": "✉",
	"tome": "❖",
}

static var _glow: ImageTexture = null


static func _make_glow() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.5
			img.set_pixel(x, y, Color(0.95, 0.78, 0.36, a))
	return ImageTexture.create_from_image(img)


static func glow() -> ImageTexture:
	if _glow == null:
		_glow = _make_glow()
	return _glow


## Кнопка-объект: ореолом служит золотое пятно позади, спрайт — SVG.
## Тач-зона = size_px, визуальный ореол чуть выходит за счёт glow-слоя.
static func make_prop(icon: String, size_px: int, tooltip: String) -> Button:
	var btn := Button.new()
	btn.name = "Prop_" + icon
	btn.custom_minimum_size = Vector2(size_px, size_px)
	btn.tooltip_text = tooltip
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var glowr := TextureRect.new()
	glowr.name = "Glow"
	glowr.texture = glow()
	glowr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glowr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	glowr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glowr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glowr.offset_left = -size_px * 0.25
	glowr.offset_top = -size_px * 0.25
	glowr.offset_right = size_px * 0.25
	glowr.offset_bottom = size_px * 0.25
	btn.add_child(glowr)
	# R17c: сгенерированные PNG-спрайты приоритетны; SVG — фолбэк,
	# пока не все устройства переведены на генерацию.
	var path := SCENE_DIR + icon + ".png"
	if not ResourceLoader.exists(path):
		path = SCENE_DIR + icon + ".svg"
	if ResourceLoader.exists(path):
		var spr := TextureRect.new()
		spr.name = "Sprite"
		spr.texture = load(path) as Texture2D
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(spr)
	else:
		var l := Label.new()
		l.name = "Glyph"
		l.text = FALLBACK.get(icon, "?")
		l.add_theme_font_size_override("font_size", int(size_px * 0.5))
		l.add_theme_color_override("font_color", UIStyle.GOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(l)
	return btn


## Заблокированный объект: силуэт-подглядывание (peek) по статье —
## виден, но приглушён; тултип объясняет условие.
static func set_locked(btn: Button, locked: bool) -> void:
	if btn == null:
		return
	btn.modulate = Color(0.55, 0.62, 0.7, 0.55) if locked else Color.WHITE
	btn.disabled = false  # тап по замку объясняет условие статус-строкой
