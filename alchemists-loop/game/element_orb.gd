class_name ElementOrb
extends Control
# Визуальный «орб» элемента: цветной шарик-желе + векторный глиф + счётчик.
# Поддерживает тап и drag&drop (мышь и тач — эмулируется в мышь).

signal tapped(orb)
signal drag_started(orb, at: Vector2)
signal drag_ended(orb, at: Vector2)

var element_id := ""
var orb_color := Color(0.45, 0.55, 0.65)
var count := 0
var discovered := true
var interactive := true
var glyph_id := ""
var glyph_key := ""

var _pressed := false
var _dragging := false
var _down := Vector2.ZERO
var _drop_done := false
var _bump_tween: Tween
var _shake_t := 0.0
var hint_t := 0.0

func setup(id: String, col: Color, is_discovered := true, glyph := "") -> void:
	element_id = id
	orb_color = col
	discovered = is_discovered
	glyph_id = id
	glyph_key = glyph
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive else Control.MOUSE_FILTER_STOP
	_sync_pivot()
	resized.connect(_sync_pivot)
	# В инвентаре может быть до 95 орбов. Не держим отдельный _process
	# на каждом из них: он нужен только во время shake/подсветки.
	set_process(false)

func _sync_pivot() -> void:
	pivot_offset = size * 0.5

func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t = maxf(_shake_t - delta * 6.0, 0.0)
		position.x += sin(_shake_t * 90.0) * 2.2 * _shake_t
		queue_redraw()
	if hint_t > 0.0:
		hint_t = maxf(hint_t - delta, 0.0)
		queue_redraw()
	if _shake_t <= 0.0 and hint_t <= 0.0:
		set_process(false)

func _bump(strength := 0.92) -> void:
	if not is_inside_tree():
		return
	if _bump_tween != null and _bump_tween.is_valid():
		_bump_tween.kill()
	_bump_tween = create_tween()
	_bump_tween.tween_property(self, "scale", Vector2(strength, strength), 0.07) \
		.set_trans(Tween.TRANS_QUAD)
	_bump_tween.tween_property(self, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shake() -> void:
	_shake_t = 1.0
	set_process(true)

# Мягкая подсказка: золотое кольцо вокруг орба, чтобы «намёк» читался визуально.
func hint_pulse() -> void:
	hint_t = 2.2
	set_process(true)
	queue_redraw()

# Публичный «отказ»: орб мотает головой и сжимается — видно, что тап дошёл,
# но действие сейчас недоступно.
func refuse() -> void:
	_shake()
	_bump(0.9)

func _input(event: InputEvent) -> void:
	# Пока тащим орб, фиксируем отпускание ГЛОБАЛЬНО: если курсор во время
	# переноса оказался над «поиском», полосой прокрутки или другим контролом,
	# тот перехватит release — и дроп зависнет. Здесь мы завершаем перенос сами.
	if _dragging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		_pressed = false
		_drop_done = true
		drag_ended.emit(self, get_global_mouse_position())


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drop_done = false
			_pressed = true
			_dragging = false
			_down = event.position
			_bump(0.93 if discovered else 0.97)
			if not discovered:
				_shake()
		else:
			if _drop_done:
				_drop_done = false
				return
			var was_dragging := _dragging
			_pressed = false
			_dragging = false
			# Восстанавливаем непрозрачность сразу при отпускании: иначе орб
			# оставался бледным (modulate 0.35) до следующего queue_redraw.
			modulate.a = 1.0
			queue_redraw()
			if was_dragging:
				drag_ended.emit(self, get_global_mouse_position())
			else:
				_bump()
				# «?» тоже шлёт тап: обработчик в main объяснит, что это туман
				tapped.emit(self)
	elif event is InputEventMouseMotion and _pressed:
		if not _dragging and _down.distance_to(event.position) > 22.0:
			_dragging = true
			drag_started.emit(self, get_global_mouse_position())
		if _dragging:
			queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var c := size * 0.5
	if not discovered:
		# тёмная ячейка «?»
		draw_circle(c, r, Color(0.10, 0.13, 0.17, 0.9))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(0.4, 0.45, 0.5, 0.25), 2.0)
		var f := get_theme_default_font()
		var ts := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var ascent_h := f.get_ascent(26)
		var descent_h := f.get_descent(26)
		draw_string(f, c + Vector2(-ts.x * 0.5, (ascent_h - descent_h) * 0.5), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.55, 0.62, 0.66, 0.55))
		return
	var col := orb_color
	if _dragging:
		modulate.a = 0.35
	else:
		modulate.a = 1.0
	# свечение (компактное, чтобы не «расплывалось»)
	_soft(c, r * 1.45, Color(col.r, col.g, col.b, 0.20))
	# тело
	draw_circle(c, r * 0.96, col.darkened(0.22))
	_soft(c, r * 0.95, Color(col.r, col.g, col.b, 0.95))
	_soft(c + Vector2(-r * 0.22, -r * 0.24), r * 0.55, Color(1, 1, 1, 0.25))
	_soft(c + Vector2(0, r * 0.3), r * 0.7, Color(0, 0, 0, 0.08))
	if hint_t > 0.0:
		var k := 0.5 + 0.5 * sin(hint_t * 9.0)
		draw_arc(c, r + 2.5, 0.0, TAU, 48, Color(1.0, 0.86, 0.35, 0.30 + 0.45 * k), 2.5)
	# глиф
	var gc := Color(1, 1, 1, 0.88)
	if orb_color.get_luminance() > 0.6:
		gc = Color(0.09, 0.12, 0.16, 0.85)
	ElementGlyphs.draw(self, glyph_key if glyph_key != "" else glyph_id, c, r * 0.52, gc)
	# счётчик: по центру бейджа, с учётом реальной ширины текста
	if count > 0:
		var f2 := get_theme_default_font()
		var txt := str(count)
		var fs := 15
		var ts2 := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		# радиус бейджа — по фактической ширине числа, чтобы «12» и «100» не вылезали
		var br := clampf(ts2.x * 0.5 + 4.5, r * 0.42, r * 0.70)
		var bc := Vector2(c.x + r * 0.70, c.y + r * 0.70)
		draw_circle(bc, br, Color(0.03, 0.05, 0.07, 0.92))
		draw_arc(bc, br, 0, TAU, 24, Color(1, 1, 1, 0.22), 1.5)
		var asc := f2.get_ascent(fs)
		var dsc := f2.get_descent(fs)
		draw_string(f2, bc + Vector2(-ts2.x * 0.5, (asc - dsc) * 0.5), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))

func _soft(pos: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(Art.soft(),
		Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)
