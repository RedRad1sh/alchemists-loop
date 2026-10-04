class_name SigilFinishView
extends Control

enum Part { FOIL, SPARKLES }

const MOTION_MIN := 0.08
const SPEED_FOIL := 0.125  # Оборотов фазы в секунду: один проход за 8 с.
const SPEED_MOTES := 18.0  # Пикселей в секунду при ширине карточки 512.
const SPEED_SPARK := 3.4   # Радиан в секунду.
const TAU := 6.283185307179586

var part: int = Part.FOIL
var strength: float = 0.0
var phase: float = 0.0
var tint: Color = Color.WHITE
var art: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0
var card_size: Vector2 = Vector2(512, 1024)
var seed_value: int = 0

# animated — разрешено ли движение для этой редкости;
# live — нужно ли самостоятельно увеличивать время в игре.
var animated: bool = false
var live: bool = false

var _t: float = 0.0
var _generated: Array[ColorRect] = []
var _foil_mat: ShaderMaterial = null

var _glint_mats: Array[ShaderMaterial] = []
var _glint_offsets: Array[float] = []
var _glint_rates: Array[float] = []

var _mote_base: Array[Vector2] = []
var _mote_vel: Array[Vector2] = []
var _mote_radius: Array[float] = []
var _mote_alpha: Array[float] = []
var _mote_wobble: Array[float] = []


func setup(p_part: int, options: SigilOptions, palette: SigilPalette,
		p_seed: int, p_center: Vector2, p_radius: float,
		p_live: bool = false) -> void:
	_clear_generated()

	part = p_part
	seed_value = p_seed # В исходном коде здесь было seed_value = seed_value.
	strength = clampf(palette.aura_pulse, 0.0, 1.0)
	phase = SigilRng.new(p_seed).fork("finish").randf()
	tint = palette.aura_color if part == Part.FOIL else palette.ink
	art = options.art_rect()
	center = p_center
	radius = p_radius
	card_size = Vector2(options.card_size)

	_t = 0.0
	animated = strength >= MOTION_MIN
	live = p_live
	visible = strength > 0.001 and (
		part == Part.FOIL or strength >= 0.25
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if visible:
		if part == Part.FOIL:
			_make_foil()
			_make_motes()
		else:
			_make_glints()

	set_process(live and animated and visible)
	set_motion_time(0.0)
	queue_redraw()


func set_live_mode(p_live: bool) -> void:
	live = p_live
	set_process(live and animated and visible)


## Установить конкретный воспроизводимый кадр, в секундах.
## Для PNG: set_motion_time(0.0).
func set_motion_time(seconds: float) -> void:
	_t = maxf(0.0, seconds)

	if _foil_mat != null:
		var foil_phase := phase
		if animated:
			foil_phase = fposmod(phase + _t * SPEED_FOIL, 1.0)
		_foil_mat.set_shader_parameter("phase", foil_phase)

	for i in range(_glint_mats.size()):
		var wave := 0.5 + 0.5 * sin(
			_t * SPEED_SPARK * _glint_rates[i] + _glint_offsets[i]
		)
		var intensity := 0.35 + 0.65 * pow(wave, 4.0)
		_glint_mats[i].set_shader_parameter("intensity", intensity)

	if part == Part.FOIL and animated:
		queue_redraw()


func motion_phase() -> float:
	return _t


func _process(delta: float) -> void:
	if is_visible_in_tree():
		set_motion_time(_t + delta)


func _make_foil() -> void:
	var sh: Shader = SigilAssets.shader_file("shaders/sigil_foil.gdshader")
	if sh == null:
		push_warning("Missing shaders/sigil_foil.gdshader")
		return

	_foil_mat = ShaderMaterial.new()
	_foil_mat.shader = sh
	_foil_mat.set_shader_parameter("strength", strength)
	_foil_mat.set_shader_parameter("phase", phase)
	_foil_mat.set_shader_parameter("rect_size", art.size)
	_foil_mat.set_shader_parameter("tint", tint)

	var rect := ColorRect.new()
	rect.name = "Foil"
	rect.position = art.position
	rect.size = art.size
	rect.color = Color.WHITE
	rect.material = _foil_mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	_generated.append(rect)


func _make_glints() -> void:
	var sh: Shader = SigilAssets.shader_file("shaders/sigil_sparkle.gdshader")
	if sh == null:
		push_warning("Missing shaders/sigil_sparkle.gdshader")
		return

	var rng := SigilRng.new(seed_value).fork("sparkle")
	var k := maxf(card_size.x, 1.0) / 512.0
	var count := int(2.0 + 10.0 * strength)

	for i in range(count):
		var angle := rng.randf() * TAU
		var distance := radius * (0.20 + 0.72 * rng.randf())
		var pos := center + Vector2(cos(angle), sin(angle)) * distance
		var side := (32.0 + 22.0 * strength) \
			* (0.80 + 0.40 * rng.randf()) * k
		var offset := rng.randf() * TAU
		var rate := 0.70 + 0.60 * rng.randf()

		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("strength", strength)
		mat.set_shader_parameter(
			"glow_color", Color.WHITE.lerp(tint, 0.30)
		)

		var rect := ColorRect.new()
		rect.name = "Glint_%d" % i
		rect.color = Color.WHITE
		rect.position = pos - Vector2(side, side) * 0.5
		rect.size = Vector2(side, side)
		rect.material = mat
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

		_generated.append(rect)
		_glint_mats.append(mat)
		_glint_offsets.append(offset)
		_glint_rates.append(rate)


## Генерируем параметры один раз, а не пересоздаём RNG на каждом кадре.
func _make_motes() -> void:
	var rng := SigilRng.new(seed_value).fork("motes")
	var k := maxf(card_size.x, 1.0) / 512.0
	var count := int(18.0 + 65.0 * strength)

	for i in range(count):
		var x := rng.randf()
		var y := rng.randf()
		var r := (0.70 + rng.randf() * (0.55 + 0.90 * strength)) * k
		var alpha := 0.11 + rng.randf() * (0.08 + 0.16 * strength)

		# Скорость храним в долях art_rect за секунду.
		var vy := -(0.60 + 0.40 * rng.randf()) \
			* SPEED_MOTES * k / maxf(art.size.y, 1.0)
		var vx := (1.0 + 2.0 * rng.randf()) \
			* k / maxf(art.size.x, 1.0)
		var wobble := rng.randf() * TAU

		_mote_base.append(Vector2(x, y))
		_mote_vel.append(Vector2(vx, vy))
		_mote_radius.append(r)
		_mote_alpha.append(alpha)
		_mote_wobble.append(wobble)


func _draw() -> void:
	if part != Part.FOIL or strength <= 0.001:
		return

	for i in range(_mote_base.size()):
		var p := _mote_base[i]

		if animated:
			p.x = fposmod(
				p.x + _mote_vel[i].x * _t
				+ 0.006 * (
					sin(_mote_wobble[i] + _t * 0.85)
					- sin(_mote_wobble[i])
				),
				1.0
			)
			p.y = fposmod(p.y + _mote_vel[i].y * _t, 1.0)

		# Частица гаснет перед переходом через край art_rect.
		var fade := smoothstep(0.0, 0.06, p.x) \
			* smoothstep(0.0, 0.06, 1.0 - p.x) \
			* smoothstep(0.0, 0.06, p.y) \
			* smoothstep(0.0, 0.06, 1.0 - p.y)

		var alpha := _mote_alpha[i] * fade
		if alpha < 0.005:
			continue

		draw_circle(
			art.position + Vector2(p.x * art.size.x, p.y * art.size.y),
			_mote_radius[i],
			Color(tint.r, tint.g, tint.b, alpha)
		)


func _clear_generated() -> void:
	for rect in _generated:
		if is_instance_valid(rect):
			if rect.get_parent() == self:
				remove_child(rect)
			rect.queue_free()

	_generated.clear()
	_foil_mat = null
	_glint_mats.clear()
	_glint_offsets.clear()
	_glint_rates.clear()
	_mote_base.clear()
	_mote_vel.clear()
	_mote_radius.clear()
	_mote_alpha.clear()
	_mote_wobble.clear()