extends Control
# Дух-компаньон «Светик»: набор спрайтов по настроению + уровню дружбы.
#
# Спрайты (res://game/spirits/*.png) — нарезки референса (uploads/slices/):
#   idle(2) обычное · laugh(1) смеётся · content(3) глазки закрыты, улыбается
#   curious(4) наклонился · sad(5) расстроен/потемнел · tremble(6) трясётся
#   sad_soft(10) слегка расстроен · charged(11) заряжен · neutral2(22) нейтральный
#   lv1(15)..lv4(13) — уровни дружбы (жёлтый → жёлтый+аура → розовая аура → красный)
#   levelup(0) — иконка перехода на новый уровень · room(16) — интерьер для диалога
#
# Механика: базовый спрайт = уровень дружбы (set_base); эмоции временно
# перекрывают его (set_sprite + секунды), затем возврат к базовому. set_shake
# включает дрожь (смещение позиции каждый кадр). Если спрайтов нет — процедурный
# фоллбэк «искра» с глазами, чтобы игра не осталась без духа.

signal tapped

const SPRITE_DIR := "res://game/spirits/"

const KEYS := ["idle", "laugh", "content", "curious", "sad", "tremble", "sad_soft",
	"charged", "neutral2", "lv1", "lv2", "lv3", "lv4", "levelup"]

var _sprites := {}
var _base_key := "idle"
var _override_key := ""
var _override_left := 0.0
var _shake := false
var _phase := 0.0
var _bob := 0.0
var _mood := "idle"
var _aura := Color(0, 0, 0, 0)
var _house := false

var _bubble: PanelContainer = null
var _bubble_label: Label = null
var _bubble_ttl := 0.0
var _bubble_allowed := true

var _hearts: Array = []  # [{pos, vel, life, max_life, size}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for key in KEYS:
		var img := Image.new()
		if img.load(SPRITE_DIR + key + ".png") == OK:
			_sprites[key] = ImageTexture.create_from_image(img)
	# Светик статичен в покое: не перерисовываем всю сцену на каждом кадре.
	# Процесс включается только для короткой реплики/реакции/дрожи.
	set_process(false)


func has_sprites() -> bool:
	return not _sprites.is_empty()


func sprite_tex(key: String) -> Texture2D:
	return _sprites.get(key)


func set_base(key: String) -> void:
	if _sprites.has(key):
		_base_key = key
		queue_redraw()


func set_sprite(key: String, seconds: float) -> void:
	if _sprites.has(key):
		_override_key = key
		_override_left = seconds
		if seconds > 0.0:
			set_process(true)
		queue_redraw()


func set_shake(on: bool) -> void:
	_shake = on
	if not on and _override_left < 0.0:
		_override_key = ""
		_override_left = 0.0
	set_process(on or _override_left > 0.0 or _bubble_ttl > 0.0)
	queue_redraw()


func set_aura(col: Color) -> void:
	_aura = col
	queue_redraw()


func set_house(on: bool) -> void:
	_house = on
	queue_redraw()


func mood_color() -> Color:
	match _mood:
		"happy":
			return Color(1.0, 0.85, 0.42)
		"sad":
			return Color(0.55, 0.72, 1.0)
		"amazed":
			return Color(0.55, 1.0, 0.92)
		_:
			return Color(1.0, 0.72, 0.36)


func set_bubble_allowed(allowed: bool) -> void:
	_bubble_allowed = allowed
	if not allowed:
		_bubble_ttl = 0.0
		if _bubble != null:
			_bubble.visible = false


func spawn_hearts(count: int = 3) -> void:
	var c := size * 0.5
	for i in count:
		var angle := randf_range(-PI * 0.6, -PI * 0.4)
		var speed := randf_range(40.0, 70.0)
		_hearts.append({
			"pos": Vector2(c.x + randf_range(-10, 10), c.y - 10),
			"vel": Vector2(cos(angle) * speed * 0.3, sin(angle) * speed),
			"life": 0.0,
			"max_life": randf_range(0.8, 1.2),
			"size": randf_range(6.0, 10.0),
		})
	set_process(true)
	queue_redraw()


func say(text: String, mood: String = "idle") -> void:
	if text.strip_edges() == "":
		return
	_mood = mood
	if not _bubble_allowed:
		if _bubble != null:
			_bubble.visible = false
		return
	if _bubble == null:
		_build_bubble()
	_bubble_label.text = text
	_bubble.reset_size()
	var ms := _bubble.get_combined_minimum_size()
	_bubble.size = Vector2(maxf(ms.x, 150.0), ms.y)
	_bubble.position = Vector2(size.x - _bubble.size.x, -_bubble.size.y - 10.0)
	_bubble.visible = true
	_bubble.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_bubble, "modulate", Color(1, 1, 1, 1), 0.18)
	_bubble_ttl = clampf(2.8 + text.length() * 0.045, 2.8, 7.5)
	set_process(true)


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.15, 0.96)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	add_child(_bubble)
	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.custom_minimum_size.x = 210.0
	_bubble_label.add_theme_font_size_override("font_size", 13)
	_bubble_label.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_bubble_label)


func _process(delta: float) -> void:
	var needs_redraw := false
	if _shake:
		_phase += delta
		_bob = sin(_phase * 1.7) * 2.5
		needs_redraw = true
	if _override_left > 0.0:
		_override_left -= delta
		if _override_left <= 0.0:
			_override_key = ""
			needs_redraw = true
	if _bubble_ttl > 0.0:
		_bubble_ttl -= delta
		if _bubble_ttl <= 0.0 and _bubble != null:
			_bubble.visible = false
	# Animate hearts
	var alive_hearts := []
	for h in _hearts:
		h["life"] += delta
		if h["life"] < h["max_life"]:
			h["pos"] += h["vel"] * delta
			h["vel"].y -= 20.0 * delta  # gravity
			alive_hearts.append(h)
			needs_redraw = true
	_hearts = alive_hearts
	if needs_redraw:
		queue_redraw()
	if not _shake and _override_left <= 0.0 and _bubble_ttl <= 0.0 and _hearts.is_empty():
		set_process(false)

func _current_texture() -> Texture2D:
	if _override_key != "" and _sprites.has(_override_key):
		return _sprites[_override_key]
	if _sprites.has(_base_key):
		return _sprites[_base_key]
	return null


func _draw() -> void:
	var shake_off := Vector2.ZERO
	if _shake:
		shake_off = Vector2(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5))
	var c := size * 0.5 + shake_off
	var breath := 1.0 + 0.035 * sin(_phase * 2.1)
	var gcol := _aura if _aura.a > 0.0 else mood_color()
	if _house:
		_draw_house(c)
	var r := 30.0 * breath
	for i in range(4, 0, -1):
		draw_circle(Vector2(c.x, c.y + _bob), r * (0.45 + 0.13 * i), Color(gcol, 0.05 * i))
	var tex := _current_texture()
	if tex != null:
		var sc := minf(68.0 / tex.get_width(), 62.0 / tex.get_height()) * breath
		var w := tex.get_width() * sc
		var h := tex.get_height() * sc
		draw_texture_rect(tex, Rect2(c.x - w * 0.5, c.y - h * 0.5 + _bob, w, h), false)
	else:
		_draw_fallback(c, breath)
	draw_circle(Vector2(c.x, c.y + _bob), 15.0 * breath, Color(1, 1, 1, 0.04))
	# Draw hearts
	for h in _hearts:
		var t: float = h["life"] / h["max_life"]
		var alpha: float = 1.0 - t
		var sz: float = h["size"] * (1.0 - t * 0.3)
		_draw_heart(h["pos"], sz, Color(1.0, 0.4, 0.5, alpha))


func _draw_heart(pos: Vector2, sz: float, col: Color) -> void:
	var half := sz * 0.5
	var top := PackedVector2Array([
		pos + Vector2(0, -half * 0.3),
		pos + Vector2(-half, -half),
		pos + Vector2(-half * 0.3, -half * 0.2),
		pos + Vector2(0, half * 0.5),
		pos + Vector2(half * 0.3, -half * 0.2),
		pos + Vector2(half, -half),
	])
	draw_colored_polygon(top, col)


func _draw_house(c: Vector2) -> void:
	var hy := size.y - 6.0
	var hw := 52.0
	# стена
	draw_rect(Rect2(c.x - hw * 0.5, hy - 34.0, hw, 34.0), Color(0.32, 0.21, 0.14, 0.92))
	# крыша
	var roof := PackedVector2Array([
		Vector2(c.x - hw * 0.5 - 7.0, hy - 34.0),
		Vector2(c.x + hw * 0.5 + 7.0, hy - 34.0),
		Vector2(c.x, hy - 56.0),
	])
	draw_colored_polygon(roof, Color(0.55, 0.32, 0.18, 0.95))
	# дверь
	draw_rect(Rect2(c.x - 7.0, hy - 17.0, 14.0, 17.0), Color(1.0, 0.85, 0.5, 0.9))
	# окошко
	draw_rect(Rect2(c.x + 10.0, hy - 28.0, 10.0, 10.0), Color(0.9, 0.8, 0.5, 0.85))


func _draw_fallback(c: Vector2, breath: float) -> void:
	var col := mood_color()
	var flame := PackedVector2Array([
		Vector2(c.x, c.y - 26 * breath), Vector2(c.x + 14 * breath, c.y + 3 * breath),
		Vector2(c.x + 5 * breath, c.y + 4 * breath), Vector2(c.x + 3 * breath, c.y + 22 * breath),
		Vector2(c.x, c.y + 14 * breath), Vector2(c.x - 3 * breath, c.y + 22 * breath),
		Vector2(c.x - 5 * breath, c.y + 4 * breath), Vector2(c.x - 14 * breath, c.y + 3 * breath),
	])
	draw_colored_polygon(flame, Color(col, 0.95))
	draw_circle(Vector2(c.x, c.y + 1 * breath), 8.0 * breath, Color(1.0, 0.98, 0.9, 0.9))
	draw_circle(Vector2(c.x - 3, c.y), 1.6, Color(0.1, 0.1, 0.14))
	draw_circle(Vector2(c.x + 3, c.y), 1.6, Color(0.1, 0.1, 0.14))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()
		spawn_hearts(3)
		accept_event()
