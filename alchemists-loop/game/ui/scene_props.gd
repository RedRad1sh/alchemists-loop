extends RefCounted
class_name SceneProps
# Объекты сцены (перенос паттерна из PR #65): спрайт предмета + бледная обводка
# по его контуру. Светится только интерактивный предмет; панели, кнопки и текст
# обводки не получают (спека §4.3). Обводка — не пятно за картинкой и не рамка
# вокруг квадрата: шейдер рисует кольцо снаружи силуэта (alpha = 0 внутри
# предмета), поэтому предмет не выглядит наклеенным, а кликнуть по нему понятно.
# Отсюда требование к предмету: он обязан быть вырезкой с прозрачным фоном.
# Состояние — modulate узла обводки, поэтому пульсации нет и reduced-motion
# не нужен. В покое обводка бледная, на наведении разгорается.

const SCENE_DIR := "res://assets/ui/scene/"
const ROOM_DIR := "res://assets/ui/room/"
const OUTLINE_SHADER := ROOM_DIR + "prop_outline.gdshader"
const OUTLINE_REST := 0.42
const OUTLINE_HOVER := 0.95
const OUTLINE_PRESS := 1.0
const OUTLINE_LOCKED := 0.0
# В покое кольцо медленно дышит (доля приглушения яркости); на наведении — ровное.
const OUTLINE_BREATH := 0.45
# Наведение приподнимает предмет на пару процентов — картинка не перекрашивается.
const HOVER_SCALE := 1.035
const PRESS_SCALE := 0.985
# Толщина кольца на экране. Место под него — прозрачные поля самих вырезок.
const OUTLINE_SCREEN_PX := 2.5
const PRESS_TINT := Color(1.25, 1.18, 1.05, 1.0)

const FALLBACK := {
	"fountain": "⛲",
	"workbench": "⚒",
	"retort": "⚗",
	"deck": "✦",
	"scroll": "✉",
}


## Кнопка-объект: обводка позади спрайта.
static func make_prop(icon: String, size_px: int) -> Button:
	var btn := Button.new()
	btn.name = "Prop_" + icon
	btn.custom_minimum_size = Vector2(size_px, size_px)
	var tex := _svg(SCENE_DIR + icon + ".svg")
	_shell(btn, Vector2(size_px, size_px), tex)
	btn.add_child(_picture(tex, String(FALLBACK.get(icon, "?")), int(size_px * 0.5)))
	return btn


## Предмет из живописного набора комнаты: та же обводка, но спрайт — png-вырезка.
## Размер задаётся по картинке, а не квадратом.
## alpha_hit — ловить нажатие только по нарисованному предмету, а не по квадрату.
static func make_art_prop(art: String, px: Vector2, alpha_hit := false) -> Button:
	var btn: Button = AlphaHitButton.new() if alpha_hit else Button.new()
	btn.name = "Prop_" + art
	btn.custom_minimum_size = px
	var tex := _png(ROOM_DIR + art + ".png")
	if alpha_hit:
		(btn as AlphaHitButton).set_hit_texture(tex)
	_shell(btn, px, tex)
	btn.add_child(_picture(tex, "✦", 22))
	return btn


static func _shell(btn: Button, px: Vector2, tex: Texture2D) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	if tex == null:
		return
	# Единственный вид обводки — кольцо по альфе спрайта. Рамки по границе
	# квадратной тап-зоны здесь больше нет: владелец забраковал её («ореолы
	# квадратные, а не идут по контуру предмета»), поэтому предмет, который
	# нужно обвести, обязан быть вырезкой.
	var glow := make_outline(tex, px)
	# Слой ровно по rect спрайта: раздутый rect растягивал текстуру, и кольцо
	# выходило крупнее силуэта — обводка «отходила» от предмета.
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(glow)
	wire(btn, glow, true)


## Слой-обводка по альфе текстуры: бледный в покое, с медленным дыханием.
static func make_outline(tex: Texture2D, px: Vector2) -> TextureRect:
	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = load(OUTLINE_SHADER) as Shader
	mat.set_shader_parameter("outline_color", Color(UIStyle.HIGHLIGHT, 1.0))
	# Толщина в пикселях текстуры, которые на экране сжаты: ~2.5 px экрана.
	mat.set_shader_parameter("thickness", OUTLINE_SCREEN_PX * float(tex.get_width()) / maxf(px.x, 1.0))
	mat.set_shader_parameter("breath", OUTLINE_BREATH)
	# Разная фаза — предметы дышат не в унисон, как мигалка.
	mat.set_shader_parameter("phase", float(abs(tex.resource_path.hash()) % 628) / 100.0)
	glow.material = mat
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1, 1, 1, OUTLINE_REST)
	return glow


## Наведение/нажатие кнопки управляют обводкой; lift — приподнимать сам предмет
## (котёл не приподнимается: поверх него рисуется живое варево).
static func wire(btn: Button, glow: Control, lift: bool) -> void:
	btn.set_meta("glow", glow)
	btn.set_meta("lift", lift)
	btn.mouse_entered.connect(_on_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_hover.bind(btn, false))
	btn.button_down.connect(_on_press.bind(btn, true))
	btn.button_up.connect(_on_press.bind(btn, false))
	# Клик открывает экран поверх предмета — mouse_exited тогда не приходит,
	# и подсветка залипала бы до следующего наведения.
	btn.pressed.connect(release.bind(btn))
	btn.visibility_changed.connect(release.bind(btn))


static func release(btn: Button) -> void:
	btn.set_meta("hot", false)
	btn.set_meta("down", false)
	_paint(btn)


static func _png(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _svg(path: String) -> Texture2D:
	return _png(path)


## Картинка предмета поверх обводки; если ассета нет — глиф тем же размером.
static func _picture(tex: Texture2D, glyph: String, glyph_px: int) -> Control:
	if tex != null:
		var spr := TextureRect.new()
		spr.name = "Sprite"
		spr.texture = tex
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return spr
	var l := Label.new()
	l.name = "Glyph"
	l.text = glyph
	l.add_theme_font_size_override("font_size", glyph_px)
	l.add_theme_color_override("font_color", UIStyle.BRASS_HI)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l


static func _on_hover(btn: Button, over: bool) -> void:
	btn.set_meta("hot", over)
	_paint(btn)


static func _on_press(btn: Button, down: bool) -> void:
	btn.set_meta("down", down)
	_paint(btn)


## Одно место, где состояние кнопки-предмета превращается в вид обводки:
## покой — бледная и дышит, наведение — светлая и ровная, нажатие — ярче и теплее.
static func _paint(btn: Button) -> void:
	var glow := btn.get_meta("glow", null) as CanvasItem
	if glow == null or bool(btn.get_meta("locked", false)):
		return
	var hot := bool(btn.get_meta("hot", false))
	var down := bool(btn.get_meta("down", false)) and hot
	var a := OUTLINE_PRESS if down else (OUTLINE_HOVER if hot else OUTLINE_REST)
	glow.modulate = (PRESS_TINT if down else Color.WHITE)
	glow.modulate.a = a
	var mat := (glow as CanvasItem).material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("breath", 0.0 if hot else OUTLINE_BREATH)
	if bool(btn.get_meta("lift", false)):
		btn.pivot_offset = btn.size * Vector2(0.5, 0.9)
		var s := PRESS_SCALE if down else (HOVER_SCALE if hot else 1.0)
		if btn.is_inside_tree() and Juice.enabled:
			var tw := btn.create_tween()
			tw.tween_property(btn, "scale", Vector2(s, s), 0.09)
		else:
			btn.scale = Vector2(s, s)


## Запертый предмет остаётся видимым силуэтом (peek): тап объясняет условие,
## а обводка гаснет — светится только то, чем можно действовать.
static func set_locked(btn: Button, locked: bool) -> void:
	if btn == null:
		return
	btn.set_meta("locked", locked)
	btn.modulate = Color(0.55, 0.5, 0.46, 0.6) if locked else Color.WHITE
	var glow := btn.get_meta("glow", null) as Control
	if glow != null:
		glow.modulate = Color(1, 1, 1, OUTLINE_LOCKED if locked else OUTLINE_REST)
