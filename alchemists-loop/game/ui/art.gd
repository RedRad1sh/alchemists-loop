class_name Art
# Общие процедурные текстуры/градиенты для «мягкого» рендера (желе, свечения, блики).
# Создаются один раз и кэшируются — никаких файлов и внешних запросов.

static var _soft_tex: GradientTexture2D = null

static func soft() -> GradientTexture2D:
	# Радиальный градиент: белый центр -> прозрачные края (мягкий «шарик»).
	# draw_texture_rect + modulate превращает его в цветное желе/свечение.
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1.0),
			Color(1, 1, 1, 0.92),
			Color(1, 1, 1, 0.38),
			Color(1, 1, 1, 0.0)
		])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_soft_tex = t
	return _soft_tex

static func soft_circle(pos: Vector2, radius: float, color: Color) -> void:
	# Удобная обёртка для отрисовки в _draw через draw_texture_rect.
	# Работает только внутри CanvasItem._draw (получаем через draw_texture_rect).
	pass  # реализация в каждой ноде своя (нужен self), см. helper в нодах
