extends SigilIconGenerator
class_name SigilGenAbstraction

## Тип «abstraction» — чистая геометрия на глифах круга.
## Переиспользует [SigilGlyphs]: центральный объект буквально вырастает из
## символов кольца, поэтому абстракция не выглядит «приклеенной» к кругу.

const FORMS := ["mandala", "sigil_stack", "lattice", "eye"]


func type_name() -> StringName:
	return &"abstraction"


func description() -> String:
	return "Мандала из глифов и линий; форма из seed"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	var s := minf(rect.size.x, rect.size.y)
	var c := rect.position + rect.size * 0.5
	var ink := palette(ctx, "ink", Color(0.92, 0.88, 0.78))
	var accent := palette(ctx, "accent", Color.from_hsv(fposmod(rng.randf(), 1.0), 0.75, 0.95))
	var w := maxf(s * 0.020, 1.0)
	var r := s * 0.42
	var pool := SigilGlyphs.by_category("spirit")
	if pool.is_empty():
		pool = SigilGlyphs.names()

	match str(ctx.get("form", FORMS[rng.randi_range(0, FORMS.size() - 1)])):
		"mandala":
			var petals := rng.randi_range(5, 9)
			for i in petals:
				var a := TAU * float(i) / float(petals)
				var p := c + Vector2(cos(a), sin(a)) * r * 0.62
				ci.draw_line(c, p, Color(ink.r, ink.g, ink.b, 0.35), w * 0.7, true)
				var g: String = pool[rng.randi_range(0, pool.size() - 1)]
				SigilGlyphs.draw_glyph(ci, g, p, s * 0.20, a + PI * 0.5, ink, w * 0.8)
			ci.draw_arc(c, r * 0.92, 0.0, TAU, 64, Color(ink.r, ink.g, ink.b, 0.5), w * 0.8, true)
			ci.draw_arc(c, r * 0.34, 0.0, TAU, 48, accent, w, true)
		"sigil_stack":
			var n := rng.randi_range(2, 4)
			for i in n:
				var t := float(i) / float(maxi(n - 1, 1))
				var rr := r * (0.30 + t * 0.62)
				ci.draw_arc(c, rr, 0.0, TAU, 56, Color(ink.r, ink.g, ink.b, 0.35 + 0.2 * t), w * 0.7, true)
			var g2: String = pool[rng.randi_range(0, pool.size() - 1)]
			SigilGlyphs.draw_glyph(ci, g2, c, s * 0.42, rng.randf() * TAU, accent, w)
		"lattice":
			var n2 := rng.randi_range(5, 7)
			var pts := SigilGeometry.regular_polygon(c, r * 0.80, n2, rng.randf() * TAU)
			var skip := rng.randi_range(1, maxi(n2 / 2, 1))
			for i in pts.size():
				ci.draw_line(pts[i], pts[(i + skip) % pts.size()],
					Color(ink.r, ink.g, ink.b, 0.42), w * 0.7, true)
			ci.draw_polyline(SigilGeometry.closed(pts), Color(ink.r, ink.g, ink.b, 0.8), w, true)
			ci.draw_circle(c, r * 0.12, accent, true)
		_:
			# «Око»: almond + pupil + лучи. Самая узнаваемая форма абстракции.
			var almond := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				almond.append(c + Vector2(lerpf(-r, r, t), -sin(t * PI) * r * 0.46))
			for i in 17:
				var t2 := float(i) / 16.0
				almond.append(c + Vector2(lerpf(r, -r, t2), sin(t2 * PI) * r * 0.46))
			ci.draw_polyline(almond, ink, w, true)
			ci.draw_circle(c, r * 0.24, Color(ink.r, ink.g, ink.b, 0.9), true, -1.0, true)
			ci.draw_circle(c, r * 0.12, accent, true)
			for i in 12:
				var a := TAU * float(i) / 12.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.30,
					c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.34, 0.46),
					Color(accent.r, accent.g, accent.b, 0.5), w * 0.6, true)
