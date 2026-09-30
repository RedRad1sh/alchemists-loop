class_name SigilFluidBg
extends Control

## Слой 1 — фон. По умолчанию GPU-шейдер (domain warping).
## [member SigilOptions.fluid_cpu_fallback] включает _draw()-замену: меньше
## красоты, зато работает без шейдерной поддержки (например, часть web-экспортов).

var _rect: ColorRect
var _cpu_seed: int = 0
var _cpu_palette: SigilPalette


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
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)
	var sh := SigilAssets.shader_file("shaders/sigil_fluid_bg.gdshader")
	if sh == null:
		options.fluid_cpu_fallback = true
		queue_redraw()
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for k in palette.to_shader_uniforms():
		mat.set_shader_parameter(k, palette.to_shader_uniforms()[k])
	mat.set_shader_parameter("card_size", Vector2(options.card_size))
	mat.set_shader_parameter("phase", float(SigilRng.new(seed_value).fork("bg").randf() * 100.0))
	_rect.material = mat
	_rect.show()


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
