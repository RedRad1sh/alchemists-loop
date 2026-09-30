class_name SigilAuraView
extends Control

## Слой 2 — аура редкости. Аддитивный шейдер поверх фона, под кругом.
## В стилке pulse = 0 (детерминированно). Для живого пульса в игре
## анимируйте uniform вручную: get_shader_parameter/set_shader_parameter.

var _rect: ColorRect


func setup(options: SigilOptions, palette: SigilPalette, circle_center: Vector2,
		circle_radius: float, seed_value: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not options.aura_enabled or palette.aura_intensity <= 0.01:
		visible = false
		return
	visible = true
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "AuraRect"
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)
	var sh := SigilAssets.shader_file("shaders/sigil_aura.gdshader")
	if sh == null:
		visible = false
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh

	var uv_center := Vector2(circle_center.x / float(maxi(size.x, 1)),
		circle_center.y / float(maxi(size.y, 1)))
	# Радиус в UV-координатах с поправкой на соотношение сторон.
	var aspect := float(options.card_size.x) / float(maxi(options.card_size.y, 1))
	var r_uv_y := circle_radius / float(maxi(options.card_size.y, 1))
	var r_uv_x := r_uv_y * aspect
	var rng := SigilRng.new(seed_value).fork("aura")

	mat.set_shader_parameter("center_uv", uv_center)
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("ring_radius", r_uv_x)
	mat.set_shader_parameter("ring_width", 0.008 + float(palette.aura_layers) * 0.0016)
	mat.set_shader_parameter("halo_width", r_uv_x * rng.randf_range(0.55, 1.1))
	mat.set_shader_parameter("glow_color", palette.aura_color)
	mat.set_shader_parameter("intensity", palette.aura_intensity)
	mat.set_shader_parameter("pulse", palette.aura_pulse)
	mat.set_shader_parameter("sparkle", clampf(0.15 + float(palette.aura_layers) * 0.12, 0.0, 0.85))
	mat.set_shader_parameter("rays", float(layout_rays(options)))
	_rect.material = mat


func layout_rays(options: SigilOptions) -> int:
	return clampi(6 + options.ring_count * 2, 6, 24)
