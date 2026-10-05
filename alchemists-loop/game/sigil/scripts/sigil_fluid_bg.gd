class_name SigilFluidBg
extends Control

## Слой 1 — фон. По умолчанию GPU-шейдер (domain warping).
## [member SigilOptions.fluid_cpu_fallback] включает _draw()-замену: меньше
## красоты, зато работает без шейдерной поддержки (например, часть web-экспортов).
##
## Живой режим: в статичном рендере (превью, кэш, Python-эталон) phase
## замораживается ровно на seed-значении. В игре (SubViewport с UPDATE_ALWAYS)
## phase медленно дрейфует — фон «течёт». Скорость берётся из палитры
## (warp), поэтому mythic дышит быстрее common.

var _rect: ColorRect
var _cpu_seed: int = 0
var _cpu_palette: SigilPalette

## Живой дрейф фазы. Выключен по умолчанию — включается снаружи через
## set_live(true), когда карточка кладётся в SubViewport с UPDATE_ALWAYS.
var live_mode := false
var _phase := 0.0
var _phase_speed := 0.05


func setup(options: SigilOptions, palette: SigilPalette, seed_value: int) -> void:
	_cpu_seed = seed_value
	_cpu_palette = palette
	if not options.fluid_enabled:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if options.fluid_cpu_fallback:
		if _rect != null:
			_rect.queue_free()
			_rect = null
		queue_redraw()
		return
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "FluidRect"
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)
		# Размер — прямо, как в SigilAuraView: PRESET_FULL_RECT ДО add_child
		# не растягивается (anchors считаются от 0x0-родителя, rect остаётся 2x
		# и паттерн шейдера уезжает в угол). После add_child родитель уже
		# имеет размер карточки — ставим его явно.
		_rect.position = Vector2.ZERO
		_rect.size = Vector2(options.card_size)
	var sh := SigilAssets.shader_file("shaders/sigil_fluid_bg_focus.gdshader")
	if sh == null:
		options.fluid_cpu_fallback = true
		queue_redraw()
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for k in palette.to_shader_uniforms():
		mat.set_shader_parameter(k, palette.to_shader_uniforms()[k])
	mat.set_shader_parameter("card_size", Vector2(options.card_size))
	# Фокус вокруг центра круга и внутренний кант по рамке (новый шейдер).
	var circle := options.circle_rect()
	mat.set_shader_parameter("focus_uv", Vector2(
		circle.get_center().x / maxf(float(options.card_size.x), 1.0),
		circle.get_center().y / maxf(float(options.card_size.y), 1.0)))
	mat.set_shader_parameter("focus_radius", circle.size.x * 0.5
		/ maxf(float(options.card_size.x), 1.0) * 2.4)
	mat.set_shader_parameter("rim_offset_px", options.frame_margin)
	mat.set_shader_parameter("rim_width_px", 7.0)
	mat.set_shader_parameter("rim_strength", 0.06)
	_phase = float(SigilRng.new(seed_value).fork("bg").randf() * 100.0)
	# Скорость дрейфа из палитры: warp 0.6 (common) → 1.25 (mythic).
	# 0.05 — базовый коэффициент, подобранный по ощущению «застывшая жидкость».
	_phase_speed = palette.warp * 0.05
	mat.set_shader_parameter("phase", _phase)
	_rect.material = mat
	_rect.show()


## Включить/выключить живой дрейф. Идемпотентно.
func set_live(v: bool) -> void:
	live_mode = v
	set_process(v)


func _process(delta: float) -> void:
	if not live_mode or _rect == null or _rect.material == null:
		return
	# Фаза в шейдере — это просто смещение по noise-полю; модуль 1000
	# не даёт float-точности уползти за часы открытой карточки.
	_phase = fposmod(_phase + delta * _phase_speed, 1000.0)
	(_rect.material as ShaderMaterial).set_shader_parameter("phase", _phase)


func _draw() -> void:
	if _cpu_palette == null:
		return
	var p := _cpu_palette
	var rng := SigilRng.new(_cpu_seed).fork("bg.cpu")
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), p.bg_deep, true)
	# «Чернила в воде»: слоистые полупрозрачные пятна.
	for i in 46:
		var t := rng.randf()
		var c := p.bg_deep.lerp(p.bg_mid, clampf(t * 1.6, 0.0, 1.0))
		c = c.lerp(p.bg_hot, clampf((t - 0.55) * 2.0, 0.0, 1.0))
		c.a = rng.randf_range(0.05, 0.16)
		var pos := Vector2(rng.randf_range(-0.1, 1.1) * w, rng.randf_range(-0.05, 1.05) * h)
		var rad := rng.randf_range(0.10, 0.45) * maxf(w, h)
		for k in 3:
			draw_circle(pos, rad * (1.0 - float(k) * 0.28), c, true, -1.0, true)
	# Мягкая виньетка, чтобы кольцо читалось.
	for i in 10:
		var a := 0.022 * (1.0 - float(i) / 10.0)
		draw_rect(Rect2(Vector2.ZERO, size).grow(-float(i) * 6.0), Color(0, 0, 0, a), false, 6.0)