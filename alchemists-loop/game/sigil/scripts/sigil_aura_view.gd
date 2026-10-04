class_name SigilAuraView
extends Control

## Слой 2 — аура редкости. Аддитивный шейдер поверх фона, под кругом.
## В стилке pulse = 0 (детерминированно). Для живого пульса в игре
## анимируйте uniform вручную: get_shader_parameter/set_shader_parameter.

var _rect: ColorRect
var _t := 0.0
var _base_pulse := 0.0
## Число слоёв ауры из палитры. Кэшируется здесь, потому что _process
## не имеет доступа к palette (setup его не сохраняет).
var _aura_layers := 0


func _process(delta: float) -> void:
	# Живое «дыхание» ауры для открытой карточки: равномерно колеблем pulse.
	if _rect == null or _rect.material == null:
		return
	_t += delta
	# Амплитуда растёт с редкостью: common пульсирует едва, legendary/mythic —
	# заметно. 0.24 — базовый шум, +0.20 на пике слоёв ауры.
	var amp := 0.24 + 0.20 * clampf(float(_aura_layers) / 5.0, 0.0, 1.0)
	var p := _base_pulse + amp * (0.5 + 0.5 * sin(_t * 2.4))
	(_rect.material as ShaderMaterial).set_shader_parameter("pulse", p)


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
		add_child(_rect)
	# Размер прямо, без anchors: PRESET_FULL_RECT ДО add_child не растягивается
	# (anchors от 0x0-родителя), rect оставался 2x и свечение уезжало в угол.
	_rect.position = Vector2.ZERO
	_rect.size = Vector2(options.card_size)
	var sh := SigilAssets.shader_file("shaders/sigil_aura.gdshader")
	if sh == null:
		visible = false
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh

	# UV считаем от геометрии карточки (options.card_size), а НЕ от size узла:
	# в момент setup размер узла ещё не разложен контейнером (0x0), и center_uv
	# уезжал в правый нижний угол (пятно света в углу вместо кольца вокруг круга).
	var uv_center := Vector2(circle_center.x / float(maxi(options.card_size.x, 1)),
		circle_center.y / float(maxi(options.card_size.y, 1)))
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
	_base_pulse = palette.aura_pulse
	_aura_layers = palette.aura_layers
	set_process(true)
	mat.set_shader_parameter("sparkle", clampf(0.15 + float(palette.aura_layers) * 0.12, 0.0, 0.85))
	mat.set_shader_parameter("rays", float(layout_rays(options)))
	_rect.position = Vector2.ZERO
	_rect.size = Vector2(options.card_size)
	_rect.material = mat


func layout_rays(options: SigilOptions) -> int:
	return clampi(6 + options.ring_count * 2, 6, 24)