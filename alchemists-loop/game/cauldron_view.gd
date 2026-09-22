class_name CauldronView
extends Control
# Живой котёл: цвет жидкости = смесь выбранных ингредиентов, пламя при варке,
# пар и пузырьки, вспышка при результате. Всё рисуется кодом (Art.soft).

var liquid := Color(0.10, 0.16, 0.24, 0.96)
var liquid_target := liquid
var flame := 0.0          # 0..1 текущая интенсивность
var _flame_target := 0.0
var flash := 0.0          # вспышка результата
var flash_color := Color.WHITE
const DRAW_SIZE := Vector2(270.0, 242.0)
const INGREDIENT_PULSE_DURATION := 1.0

var _time := 0.0
var _redraw_clock := 0.0
var _draw_origin := Vector2.ZERO
var _draw_scale := 1.0
var _rng := RandomNumberGenerator.new()
var _bubbles: Array = []
var _steam: Array = []
# Яркая вспышка при добавлении вещества: частицы процедурные,
# поэтому эффект одинаково работает в Эксперименте и Лаборатории без новых рисунков.
var _ingredient_particles: Array = []
var _ingredient_pulse := 0.0
var _ingredient_color := Color(0.45, 0.85, 0.95)
var _juice_rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Размер задаёт родитель: Лаборатория может использовать большой котёл,
	# а Эксперимент — компактный drop target. Не перетираем внешний minimum.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(256, 210)
	# Покой котла статичен; анимация включается только при изменении смеси,
	# варке или вспышке результата.
	set_process(false)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rng.randomize()
	_juice_rng.randomize()
	for i in 5:
		_bubbles.append({
			"x": _rng.randf_range(-0.5, 0.5),
			"y": _rng.randf_range(0.2, 0.9),
			"r": _rng.randf_range(0.02, 0.05),
			"v": _rng.randf_range(0.5, 1.1)
		})
	for i in 3:
		_steam.append({
			"x": _rng.randf_range(-0.45, 0.45),
			"y": _rng.randf_range(-1.6, -0.4),
			"r": _rng.randf_range(0.05, 0.1),
			"v": _rng.randf_range(0.35, 0.8),
			"ph": _rng.randf_range(0.0, TAU)
		})

func set_mixture(a_col: Color, b_col: Color) -> void:
	# цвет зелья — смесь двух ингредиентов, чуть затемнённая
	var next_target := Color(0.10, 0.16, 0.24, 0.96)
	if a_col.a >= 0.01 or b_col.a >= 0.01:
		next_target = a_col.lerp(b_col, 0.5).darkened(0.15)
		next_target.a = 0.96
	if liquid_target.is_equal_approx(next_target):
		return
	liquid_target = next_target
	set_process(true)

func trigger_ingredient(col: Color) -> void:
	# Входящее вещество читается как всплеск: новый цвет, мягкая волна,
	# искры и короткая вибрация уже вызываются на уровне UI.
	_ingredient_color = col
	_ingredient_pulse = INGREDIENT_PULSE_DURATION
	flash = maxf(flash, 0.72)
	flash_color = col.lightened(0.18)
	var origin := Vector2(DRAW_SIZE.x * 0.5, 61.0)
	# 12 частиц достаточно для читаемого всплеска и заметно дешевле
	# двадцати мягких текстур на каждом кадре.
	for i in 12:
		var angle := _juice_rng.randf_range(-PI * 0.94, -PI * 0.06)
		var speed := _juice_rng.randf_range(34.0, 108.0)
		var particle_col := col.lightened(_juice_rng.randf_range(0.08, 0.38))
		particle_col.a = 1.0
		_ingredient_particles.append({
			"pos": origin + Vector2(_juice_rng.randf_range(-42.0, 42.0), _juice_rng.randf_range(-2.0, 7.0)),
			"vel": Vector2(cos(angle) * speed, sin(angle) * speed),
			"life": _juice_rng.randf_range(0.65, 1.15),
			"max_life": 1.15,
			"radius": _juice_rng.randf_range(3.0, 6.0),
			"color": particle_col,
			"gravity": _juice_rng.randf_range(48.0, 92.0),
		})
	while _ingredient_particles.size() > 24:
		_ingredient_particles.pop_front()
	set_process(true)
	queue_redraw()


func clear_mixture() -> void:
	var next_target := Color(0.10, 0.16, 0.24, 0.96)
	if liquid_target.is_equal_approx(next_target) and _ingredient_pulse <= 0.001 and _ingredient_particles.is_empty():
		return
	liquid_target = next_target
	set_process(true)

func set_flame(v: float) -> void:
	var next_target := clampf(v, 0.0, 1.0)
	if absf(_flame_target - next_target) > 0.001:
		_flame_target = next_target
		set_process(true)

func trigger_flash(col: Color) -> void:
	flash = 1.0
	flash_color = col
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	_redraw_clock += delta
	liquid = liquid.lerp(liquid_target, minf(delta * 4.0, 1.0))
	flame = move_toward(flame, _flame_target, delta * 2.2)
	flash = maxf(flash - delta * 1.8, 0.0)
	_ingredient_pulse = maxf(_ingredient_pulse - delta * 1.45, 0.0)
	for i in range(_ingredient_particles.size() - 1, -1, -1):
		var p: Dictionary = _ingredient_particles[i]
		p["life"] = float(p["life"]) - delta
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		vel.y += float(p["gravity"]) * delta
		pos += vel * delta
		vel *= 0.985
		p["pos"] = pos
		p["vel"] = vel
		if float(p["life"]) <= 0.0:
			_ingredient_particles.remove_at(i)
	for b in _bubbles:
		b["y"] -= b["v"] * delta * (0.3 + flame * 2.2)
		b["x"] += sin(_time * 2.0 + b["y"] * 30.0) * delta * 0.2
		if b["y"] < 0.05:
			b["y"] = _rng.randf_range(0.85, 0.99)
			b["x"] = _rng.randf_range(-0.5, 0.5)
	for st in _steam:
		st["y"] -= st["v"] * delta * (0.4 + flame * 1.5)
		st["x"] += sin(_time * 1.5 + st["ph"]) * delta * 0.3
		if st["y"] < -2.2:
			st["y"] = _rng.randf_range(-0.9, -0.4)
	var liquid_settled := absf(liquid.r - liquid_target.r) < 0.002 and absf(liquid.g - liquid_target.g) < 0.002 and absf(liquid.b - liquid_target.b) < 0.002 and absf(liquid.a - liquid_target.a) < 0.002
	var settled := flame <= 0.001 and flash <= 0.001 and liquid_settled \
		and _ingredient_pulse <= 0.001 and _ingredient_particles.is_empty()
	if _redraw_clock >= 0.05 or settled:
		_redraw_clock = 0.0
		queue_redraw()
	if settled:
		set_process(false)

# ---------- отрисовка ----------

func _draw() -> void:
	# Рисуем в базовой системе координат и масштабируем по фактическому
	# Control. Поэтому маленький экспериментальный котёл действительно
	# становится маленьким, а не продолжает рисоваться за границы карточки.
	_draw_scale = minf(1.0, minf(size.x / DRAW_SIZE.x, size.y / DRAW_SIZE.y))
	_draw_scale = maxf(_draw_scale, 0.01)
	_draw_origin = (size - DRAW_SIZE * _draw_scale) * 0.5
	draw_set_transform(_draw_origin, 0.0, Vector2(_draw_scale, _draw_scale))
	var cx := DRAW_SIZE.x * 0.5
	var pot_y := 128.0
	var pot_r := 118.0
	var liquid_y := pot_y - 14.0

	# мягкая тень под котлом
	_soft(Vector2(cx, pot_y + 76), 130.0, Color(0, 0, 0, 0.22))

	# пламя под котлом (когда варим)
	if flame > 0.03:
		var fl := 1.0 + 0.14 * sin(_time * 11.0)
		_soft(Vector2(cx - 34, pot_y + 68), 26.0 * fl, Color(0.35, 0.55, 1.0, 0.28 * flame))
		_soft(Vector2(cx, pot_y + 76), 32.0 * fl, Color(0.2, 0.7, 1.0, 0.4 * flame))
		_soft(Vector2(cx + 38, pot_y + 66), 22.0 * fl, Color(0.35, 0.55, 1.0, 0.22 * flame))

	# корпус котла (овалы через масштаб)
	var iron := Color(0.075, 0.09, 0.12)
	_ellipse(cx, pot_y, pot_r, 0.62, iron)
	_ellipse(cx, pot_y - 10, pot_r * 0.97, 0.62, Color(0.11, 0.14, 0.18))
	# верхняя кромка
	_ellipse(cx, pot_y - 66, pot_r * 0.86, 0.30, Color(0.19, 0.24, 0.30))
	_ellipse(cx, pot_y - 64, pot_r * 0.84, 0.28, Color(0.09, 0.11, 0.15))
	# ушки-ручки
	draw_arc(Vector2(cx - pot_r * 0.92, pot_y - 40), 18.0, -1.2, 1.2, 16,
		Color(0.3, 0.36, 0.42, 0.8), 6.0)
	draw_arc(Vector2(cx + pot_r * 0.92, pot_y - 40), 18.0, PI - 1.2, PI + 1.2, 16,
		Color(0.3, 0.36, 0.42, 0.8), 6.0)

	# жидкость
	_soft(Vector2(cx, liquid_y), pot_r * 0.78, Color(liquid.r, liquid.g, liquid.b, 0.95))
	_soft(Vector2(cx, liquid_y + 6), pot_r * 0.7, Color(liquid.r * 0.5, liquid.g * 0.5, liquid.b * 0.5, 0.5))
	# поверхность жидкости (эллипс-«зеркало»)
	_ellipse(cx, liquid_y - pot_r * 0.46, pot_r * 0.8, 0.22,
		liquid.lightened(0.12))

	# пузырьки внутри
	for b in _bubbles:
		var bx: float = cx + float(b["x"]) * pot_r * 1.4
		var by: float = liquid_y + float(b["y"]) * pot_r * 0.5
		draw_circle(Vector2(bx, by), float(b["r"]) * pot_r, Color(1, 1, 1, 0.10 + 0.10 * flame))

	# блик на котле
	_soft(Vector2(cx - pot_r * 0.5, pot_y - 50), 30.0, Color(0.8, 0.9, 1.0, 0.07))
	# свет от зелья на стенках котла
	_soft(Vector2(cx, liquid_y - 4), pot_r * 0.55, Color(liquid.r, liquid.g, liquid.b, 0.16))

	# пар над котлом
	for st in _steam:
		var sx: float = cx + float(st["x"]) * pot_r * 1.5
		var sy: float = liquid_y + float(st["y"]) * pot_r
		var sa: float = (0.05 + 0.05 * flame) * (1.0 - clampf((-float(st["y"]) - 0.3) / 1.6, 0.0, 1.0) * 0.6)
		_soft(Vector2(sx, sy), float(st["r"]) * pot_r * 1.6, Color(0.8, 0.85, 0.9, sa))

	# Всплеск от входящего вещества: мягкая цветная волна без жёсткого
	# кольца, которое на маленьком котле выглядело неровно.
	if _ingredient_pulse > 0.02:
		var pulse_t := 1.0 - _ingredient_pulse / INGREDIENT_PULSE_DURATION
		var pulse_alpha := _ingredient_pulse / INGREDIENT_PULSE_DURATION
		var glow_col := _ingredient_color.lightened(0.16)
		draw_circle(Vector2(cx, liquid_y), 28.0 + pulse_t * 28.0,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.12 * pulse_alpha))
	for raw_particle in _ingredient_particles:
		var particle: Dictionary = raw_particle
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var pcol: Color = particle["color"]
		var alpha := 0.88 * life_ratio
		var ppos: Vector2 = particle["pos"]
		var pr: float = float(particle["radius"]) * (0.70 + 0.30 * life_ratio)
		_soft(ppos, pr * 2.4, Color(pcol.r, pcol.g, pcol.b, alpha * 0.22))
		draw_circle(ppos, pr, Color(pcol.r, pcol.g, pcol.b, alpha))
		draw_circle(ppos - Vector2(pr * 0.28, pr * 0.3), pr * 0.28, Color(1, 1, 1, alpha * 0.62))

	# вспышка результата
	if flash > 0.02:
		var fc := flash_color
		_soft(Vector2(cx, liquid_y), pot_r * (0.6 + flash * 0.9),
			Color(fc.r, fc.g, fc.b, 0.5 * flash))
		_soft(Vector2(cx, liquid_y), pot_r * (0.3 + flash * 0.5),
			Color(1, 1, 1, 0.7 * flash))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ellipse(cx: float, cy: float, r: float, sy: float, color: Color) -> void:
	# Восстанавливаем базовый transform после каждого эллипса, иначе
	# последующие glow/arc-операции потеряют компактный масштаб.
	draw_set_transform(_draw_origin + Vector2(cx * _draw_scale, cy * _draw_scale),
		0.0, Vector2(_draw_scale, _draw_scale * sy))
	draw_circle(Vector2.ZERO, r, color)
	draw_set_transform(_draw_origin, 0.0, Vector2(_draw_scale, _draw_scale))

func _soft(pos: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(Art.soft(),
		Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
		false, color)
