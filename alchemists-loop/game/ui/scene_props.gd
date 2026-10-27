extends RefCounted
class_name SceneProps
# Объекты сцены (перенос паттерна из PR #65): спрайт предмета + тёплый ореол +
# табличка-подпись. Светится только интерактивный предмет; панели, кнопки и текст
# ореола не получают (спека §4.3). Ореол — запечённый радиал, состояние — alpha
# слоя, поэтому пульсации нет и reduced-motion не нужен.

const SCENE_DIR := "res://assets/ui/scene/"
const GLOW_REST := 0.18
const GLOW_READY := 0.24
const GLOW_HOVER := 0.32
const GLOW_LOCKED := 0.0

const FALLBACK := {
	"fountain": "⛲",
	"workbench": "⚒",
	"retort": "⚗",
	"deck": "✦",
	"scroll": "✉",
}

static var _glow: ImageTexture = null


static func glow() -> ImageTexture:
	if _glow == null:
		_glow = _make_glow()
	return _glow


static func _make_glow() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(UIStyle.HIGHLIGHT, a * a * 0.9))
	return ImageTexture.create_from_image(img)


## Кнопка-объект: ореол позади спрайта, подпись на табличке под ним.
static func make_prop(icon: String, size_px: int, label_text: String) -> Button:
	var btn := Button.new()
	btn.name = "Prop_" + icon
	btn.custom_minimum_size = Vector2(size_px, size_px)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var halo := TextureRect.new()
	halo.name = "Glow"
	halo.texture = glow()
	halo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	halo.offset_left = -size_px * 0.3
	halo.offset_top = -size_px * 0.3
	halo.offset_right = size_px * 0.3
	halo.offset_bottom = size_px * 0.3
	halo.modulate = Color(1, 1, 1, GLOW_READY)
	btn.add_child(halo)
	btn.add_child(_sprite(icon, size_px))
	btn.add_child(_plaque(label_text))
	btn.set_meta("glow", halo)
	btn.mouse_entered.connect(_on_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_hover.bind(btn, false))
	return btn


static func _sprite(icon: String, size_px: int) -> Control:
	var path := SCENE_DIR + icon + ".svg"
	if ResourceLoader.exists(path):
		var spr := TextureRect.new()
		spr.name = "Sprite"
		spr.texture = load(path) as Texture2D
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return spr
	var l := Label.new()
	l.name = "Glyph"
	l.text = String(FALLBACK.get(icon, "?"))
	l.add_theme_font_size_override("font_size", int(size_px * 0.5))
	l.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l


static func _plaque(label_text: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = "Plaque"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	plate.offset_top = 6
	plate.offset_bottom = 34
	plate.add_theme_stylebox_override("panel",
			UIStyle.box(Color(0.11, 0.08, 0.06, 0.92), UIStyle.BRASS_DIM, 8, 1))
	var lb := Label.new()
	lb.text = label_text
	lb.name = "PlaqueText"
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", UIStyle.CREAM)
	plate.add_child(lb)
	return plate


static func _on_hover(btn: Button, over: bool) -> void:
	var halo := btn.get_meta("glow", null) as TextureRect
	if halo == null or bool(btn.get_meta("locked", false)):
		return
	halo.modulate.a = GLOW_HOVER if over else GLOW_READY


## Запертый предмет остаётся видимым силуэтом (peek): тап объясняет условие,
## а ореол гаснет — светится только то, чем можно действовать.
static func set_locked(btn: Button, locked: bool) -> void:
	if btn == null:
		return
	btn.set_meta("locked", locked)
	btn.modulate = Color(0.55, 0.5, 0.46, 0.6) if locked else Color.WHITE
	var halo := btn.get_meta("glow", null) as TextureRect
	if halo != null:
		halo.modulate = Color(1, 1, 1, GLOW_LOCKED if locked else GLOW_READY)
	btn.disabled = false
