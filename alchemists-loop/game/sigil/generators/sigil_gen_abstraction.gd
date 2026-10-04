extends SigilIconGenerator
class_name SigilGenAbstraction

## Алхимическая абстракция: единый обод, геометрическое ядро и узлы-глифы.
## На маленьких размерах мелкие глифы заменяются точками.

const FORMS = [
	"mandala",
	"sigil_stack",
	"lattice",
	"eye",
	"transmutation",
	"conjunction"
]


func type_name() -> StringName:
	return &"abstraction"


func description() -> String:
	return "Алхимические печати из глифов, орбит и геометрических связей"


func draw_icon(
	ci: CanvasItem,
	rect: Rect2,
	rng: SigilRng,
	ctx: Dictionary
) -> void:
	var s: float = minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return

	var c: Vector2 = rect.position + rect.size * 0.5
	var r: float = s * 0.43
	var w: float = maxf(s * 0.014, 1.0)
	var detailed: bool = s >= 96.0

	var ink: Color = palette(ctx, "ink", Color(0.92, 0.88, 0.78))
	var hue: float = rng.randf_range(0.08, 0.14)
	var accent: Color = palette(
		ctx,
		"accent",
		Color.from_hsv(hue, 0.65, 0.96)
	)

	var form: String = str(ctx.get("form", ""))
	if not FORMS.has(form):
		var form_index: int = rng.randi_range(0, FORMS.size() - 1)
		form = str(FORMS[form_index])

	var pool: PackedStringArray = PackedStringArray(
		SigilGlyphs.by_category("spirit")
	)
	if pool.is_empty():
		pool = PackedStringArray(SigilGlyphs.names())

	# Один центральный и один повторяющийся глиф:
	# повторение создаёт орнамент, а не случайный набор символов.
	var main_glyph: String = _ab_pick_glyph(pool, rng)
	var orbit_glyph: String = _ab_pick_glyph(pool, rng)
	var phase: float = -PI * 0.5 + rng.randf_range(-0.16, 0.16)

	var core_radius: float = r * 0.20
	var core_size: float = s * 0.14

	_ab_frame(ci, c, r, ink, accent, w, detailed)

	match form:
		"transmutation", "lattice":
			# Шесть вершин с шагом 2 дают два треугольника.
			# Пять или семь — непрерывную звёздчатую решётку.
			var vertex_count: int = 6

			if form == "lattice":
				vertex_count = 5
				if rng.randi_range(0, 1) == 1:
					vertex_count = 7
				core_radius = r * 0.16
				core_size = s * 0.11

			var vertices: PackedVector2Array = _ab_polygon(
				c, r * 0.65, vertex_count, phase
			)

			_ab_ring(
				ci, c, r * 0.73,
				_ab_fade(ink, 0.22), w * 0.5
			)

			if form == "lattice":
				_ab_outline(
					ci, vertices,
					_ab_fade(ink, 0.35), w * 0.6
				)

			for star_i in range(vertex_count):
				var edge_color: Color = _ab_fade(ink, 0.78)
				if star_i % 2 == 0:
					edge_color = _ab_fade(accent, 0.90)

				ci.draw_line(
					vertices[star_i],
					vertices[(star_i + 2) % vertex_count],
					edge_color,
					w * 0.9,
					true
				)

				var star_dir: Vector2 = (
					vertices[star_i] - c
				).normalized()
				var star_node: Vector2 = c + star_dir * r * 0.76

				ci.draw_line(
					vertices[star_i],
					star_node,
					_ab_fade(ink, 0.35),
					w * 0.55,
					true
				)
				ci.draw_circle(vertices[star_i], w * 0.85, edge_color)

				if detailed:
					_ab_glyph(
						ci, orbit_glyph, star_node, s * 0.09,
						star_dir.angle() + PI * 0.5,
						ink, w * 0.65
					)
				else:
					ci.draw_circle(star_node, w * 0.85, accent)

		"mandala":
			var petal_count: int = rng.randi_range(3, 5) * 2

			_ab_ring(
				ci, c, r * 0.73,
				_ab_fade(ink, 0.30), w * 0.55
			)

			for petal_i in range(petal_count):
				var petal_angle: float = (
					phase + TAU * float(petal_i) / float(petal_count)
				)
				var petal_dir: Vector2 = Vector2(
					cos(petal_angle), sin(petal_angle)
				)
				var petal_node: Vector2 = c + petal_dir * r * 0.76
				var petal_points: PackedVector2Array = _ab_ellipse(
					c + petal_dir * r * 0.45,
					r * 0.21,
					r * 0.075,
					petal_angle,
					24
				)

				ci.draw_line(
					c + petal_dir * r * 0.23,
					petal_node,
					_ab_fade(ink, 0.28),
					w * 0.5,
					true
				)
				_ab_outline(
					ci, petal_points,
					_ab_fade(accent, 0.70), w * 0.75
				)

				if detailed:
					_ab_glyph(
						ci, orbit_glyph, petal_node, s * 0.09,
						petal_angle + PI * 0.5,
						ink, w * 0.65
					)
				else:
					ci.draw_circle(petal_node, w * 0.9, accent)

		"sigil_stack":
			# Разомкнутые кольца с разными фазами — подобие астролябии.
			var ring_count: int = rng.randi_range(3, 4)

			for ring_i in range(ring_count):
				var ring_t: float = (
					float(ring_i) / float(maxi(ring_count - 1, 1))
				)
				var ring_radius: float = r * (0.31 + 0.41 * ring_t)
				var ring_start: float = phase + float(ring_i) * 0.75
				var ring_color: Color = _ab_fade(ink, 0.72)

				if ring_i % 2 == 1:
					ring_color = _ab_fade(accent, 0.82)

				ci.draw_arc(
					c, ring_radius,
					ring_start + 0.16,
					ring_start + PI - 0.16,
					36, ring_color, w * 0.75, true
				)
				ci.draw_arc(
					c, ring_radius,
					ring_start + PI + 0.16,
					ring_start + TAU - 0.16,
					36, ring_color, w * 0.75, true
				)

				for end_i in range(2):
					var end_angle: float = (
						ring_start + 0.16 + PI * float(end_i)
					)
					var end_point: Vector2 = c + Vector2(
						cos(end_angle), sin(end_angle)
					) * ring_radius

					ci.draw_circle(end_point, w * 0.95, ring_color)

		"conjunction":
			# Соединение противоположностей: две пересекающиеся сферы.
			var conjunction_angle: float = phase + PI * 0.5
			var conjunction_axis: Vector2 = Vector2(
				cos(conjunction_angle), sin(conjunction_angle)
			)
			var conjunction_normal: Vector2 = Vector2(
				-conjunction_axis.y, conjunction_axis.x
			)

			_ab_ring(
				ci, c - conjunction_axis * r * 0.22,
				r * 0.45, _ab_fade(ink, 0.80), w * 0.85
			)
			_ab_ring(
				ci, c + conjunction_axis * r * 0.22,
				r * 0.45, _ab_fade(accent, 0.85), w * 0.85
			)

			var sun_position: Vector2 = c - conjunction_axis * r * 0.46
			var moon_position: Vector2 = c + conjunction_axis * r * 0.46

			_ab_ring(ci, sun_position, r * 0.075, ink, w * 0.65)
			ci.draw_circle(sun_position, w * 0.75, accent)
			_ab_ring(ci, moon_position, r * 0.075, accent, w * 0.65)

			for conjunction_i in range(2):
				var polarity: float = -1.0 + 2.0 * float(conjunction_i)
				var conjunction_node: Vector2 = (
					c + conjunction_normal * r * 0.73 * polarity
				)

				ci.draw_line(
					c + conjunction_normal * r * 0.40 * polarity,
					conjunction_node,
					_ab_fade(ink, 0.42),
					w * 0.6,
					true
				)

				if detailed:
					_ab_glyph(
						ci, orbit_glyph, conjunction_node,
						s * 0.09, 0.0, ink, w * 0.65
					)
				else:
					ci.draw_circle(conjunction_node, w, accent)

		"eye":
			_ab_eye(ci, c, r, phase + PI * 0.5, ink, accent, w)

	# Центральная зона остаётся свободной от соединительных линий.
	if form != "eye":
		_ab_ring(
			ci, c, core_radius,
			_ab_fade(ink, 0.65), w * 0.7
		)
		_ab_glyph(
			ci, main_glyph, c, core_size,
			0.0, accent, w
		)


func _ab_frame(
	ci: CanvasItem,
	c: Vector2,
	r: float,
	ink: Color,
	accent: Color,
	w: float,
	detailed: bool
) -> void:
	_ab_ring(ci, c, r, _ab_fade(ink, 0.42), w * 0.65)
	_ab_ring(ci, c, r * 0.88, _ab_fade(ink, 0.22), w * 0.5)

	var tick_count: int = 16
	if detailed:
		tick_count = 32

	for tick_i in range(tick_count):
		var tick_angle: float = TAU * float(tick_i) / float(tick_count)
		var tick_dir: Vector2 = Vector2(cos(tick_angle), sin(tick_angle))
		var inner_radius: float = r * 0.94

		if tick_i % 4 == 0:
			inner_radius = r * 0.90

		ci.draw_line(
			c + tick_dir * inner_radius,
			c + tick_dir * r * 0.975,
			_ab_fade(ink, 0.45),
			w * 0.55,
			true
		)

	# Четыре опорных узла связывают мотив с ободом.
	for marker_i in range(4):
		var marker_angle: float = float(marker_i) * PI * 0.5
		var marker_dir: Vector2 = Vector2(
			cos(marker_angle), sin(marker_angle)
		)

		ci.draw_arc(
			c, r,
			marker_angle - 0.11,
			marker_angle + 0.11,
			10, _ab_fade(accent, 0.9), w * 0.85, true
		)
		ci.draw_line(
			c + marker_dir * r * 0.76,
			c + marker_dir * r * 0.87,
			_ab_fade(ink, 0.32),
			w * 0.55,
			true
		)
		ci.draw_circle(c + marker_dir * r * 0.85, w * 0.7, accent)


func _ab_eye(
	ci: CanvasItem,
	c: Vector2,
	r: float,
	tilt: float,
	ink: Color,
	accent: Color,
	w: float
) -> void:
	# Лучи находятся снаружи века, а не пересекают зрачок.
	for ray_i in range(16):
		var ray_angle: float = TAU * float(ray_i) / 16.0
		if absf(sin(ray_angle)) < 0.35:
			continue

		var ray_dir: Vector2 = Vector2(
			cos(ray_angle), sin(ray_angle)
		).rotated(tilt)
		var ray_end: float = r * 0.65
		if ray_i % 2 == 0:
			ray_end = r * 0.74

		ci.draw_line(
			c + ray_dir * r * 0.41,
			c + ray_dir * ray_end,
			_ab_fade(accent, 0.48),
			w * 0.6,
			true
		)

	var almond: PackedVector2Array = PackedVector2Array()

	for upper_i in range(25):
		var upper_t: float = float(upper_i) / 24.0
		var upper_point: Vector2 = Vector2(
			lerpf(-r * 0.70, r * 0.70, upper_t),
			-sin(upper_t * PI) * r * 0.30
		)
		almond.append(c + upper_point.rotated(tilt))

	for lower_i in range(1, 24):
		var lower_t: float = float(lower_i) / 24.0
		var lower_point: Vector2 = Vector2(
			lerpf(r * 0.70, -r * 0.70, lower_t),
			sin(lower_t * PI) * r * 0.30
		)
		almond.append(c + lower_point.rotated(tilt))

	_ab_outline(ci, almond, ink, w)
	_ab_ring(ci, c, r * 0.23, _ab_fade(ink, 0.80), w * 0.75)

	# Ромбовидный зрачок вместо обычной круглой точки.
	var pupil: PackedVector2Array = PackedVector2Array()
	pupil.append(c + Vector2(0.0, -r * 0.14).rotated(tilt))
	pupil.append(c + Vector2(r * 0.055, 0.0).rotated(tilt))
	pupil.append(c + Vector2(0.0, r * 0.14).rotated(tilt))
	pupil.append(c + Vector2(-r * 0.055, 0.0).rotated(tilt))

	ci.draw_colored_polygon(pupil, accent)
	ci.draw_circle(c, w * 0.65, ink)


func _ab_ring(
	ci: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	width: float
) -> void:
	ci.draw_arc(
		center, radius, 0.0, TAU,
		72, color, width, true
	)


func _ab_outline(
	ci: CanvasItem,
	points: PackedVector2Array,
	color: Color,
	width: float
) -> void:
	if points.size() < 2:
		return

	var closed_points: PackedVector2Array = points.duplicate()
	closed_points.append(closed_points[0])
	ci.draw_polyline(closed_points, color, width, true)


func _ab_polygon(
	center: Vector2,
	radius: float,
	count: int,
	phase: float
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()

	for point_i in range(count):
		var angle: float = phase + TAU * float(point_i) / float(count)
		points.append(
			center + Vector2(cos(angle), sin(angle)) * radius
		)

	return points


func _ab_ellipse(
	center: Vector2,
	rx: float,
	ry: float,
	tilt: float,
	segments: int
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()

	for point_i in range(segments):
		var angle: float = TAU * float(point_i) / float(segments)
		var point: Vector2 = Vector2(
			cos(angle) * rx,
			sin(angle) * ry
		)
		points.append(center + point.rotated(tilt))

	return points


func _ab_pick_glyph(pool: PackedStringArray, rng: SigilRng) -> String:
	if pool.is_empty():
		return ""

	var glyph_index: int = rng.randi_range(0, pool.size() - 1)
	return pool[glyph_index]


func _ab_glyph(
	ci: CanvasItem,
	glyph: String,
	position: Vector2,
	glyph_size: float,
	angle: float,
	color: Color,
	width: float
) -> void:
	if glyph.is_empty():
		_ab_ring(ci, position, glyph_size * 0.25, color, width)
		return

	SigilGlyphs.draw_glyph(
		ci, glyph, position, glyph_size,
		angle, color, width
	)


func _ab_fade(color: Color, opacity: float) -> Color:
	return Color(
		color.r,
		color.g,
		color.b,
		color.a * opacity
	)