class_name SigilFrameView
extends Control

## Слой 6 — рамка. Тонкая, алхимическая: двойной контур, угловые засечки,
## опциональные угловые глифы. Вариативность — от frame_seed.

var frame_seed: int = 0
var style: int = 0
var margin: float = 16.0
var ink: Color = Color(0.9, 0.87, 0.78)
var glyphs_enabled: bool = true
var options: SigilOptions = null


func setup(p_options: SigilOptions, palette: SigilPalette, seed_value: int) -> void:
	options = p_options
	frame_seed = SigilRng.new(seed_value).fork("frame").next_u32()
	style = options.frame_style
	margin = options.frame_margin
	ink = palette.ink
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var rng := SigilRng.new(0)
	rng.reseed(frame_seed)
	var w := maxf(ink.a, 0.5)
	var outer := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)

	draw_rect(outer, Color(ink.r, ink.g, ink.b, 0.55), false, maxf(1.2, w))
	draw_rect(outer.grow(-4.0), Color(ink.r, ink.g, ink.b, 0.30), false, maxf(0.8, w * 0.7))
	if style % 2 == 1:
		draw_rect(outer.grow(-9.0), Color(ink.r, ink.g, ink.b, 0.18), false, maxf(0.8, w * 0.6))

	# Угловые засечки.
	var tick := 10.0 + rng.randf_range(0.0, 8.0)
	var col := Color(ink.r, ink.g, ink.b, 0.65)
	for c in _corners(outer):
		draw_line(c, c + Vector2(tick, 0), col, maxf(1.0, w), true)
		draw_line(c, c + Vector2(0, tick), col, maxf(1.0, w), true)
		draw_line(c + Vector2(-tick * 0.5, 0), c + Vector2(0, -tick * 0.5),
			Color(ink.r, ink.g, ink.b, 0.3), maxf(0.8, w * 0.6), true)

	# Угловые глифы.
	if glyphs_enabled:
		var pool := SigilGlyphs.by_category("spirit")
		if pool.is_empty():
			pool = SigilGlyphs.names()
		if not pool.is_empty():
			var gsize := 20.0 + rng.randf_range(0.0, 8.0)
			for i in 4:
				var g: String = pool[rng.randi_range(0, pool.size() - 1)]
				SigilGlyphs.draw_glyph(self, g, _corners(outer)[i] + Vector2(gsize * 0.5 + 4.0, gsize * 0.5 + 4.0),
					gsize, rng.randf_range(-0.15, 0.15), Color(ink.r, ink.g, ink.b, 0.45), 1.0)

	# Верхняя/нижняя центральные отметки.
	if style >= 2:
		var mid_top := Vector2(size.x * 0.5, margin)
		var mid_bot := Vector2(size.x * 0.5, size.y - margin)
		draw_line(mid_top + Vector2(-6, 0), mid_top + Vector2(6, 0), col, 1.0, true)
		draw_line(mid_bot + Vector2(-6, 0), mid_bot + Vector2(6, 0), col, 1.0, true)

	# Зоны карточки: art_rect и title_rect.
	if options != null:
		var ar := options.art_rect()
		draw_rect(ar, Color(ink.r, ink.g, ink.b, 0.12), false, 0.8)
		var tr := options.title_rect()
		draw_rect(tr, Color(0, 0, 0, 0.34), true)
		draw_rect(tr, Color(ink.r, ink.g, ink.b, 0.45), false, 1.0)
		# Линия-разделитель между art и title.
		draw_line(Vector2(tr.position.x, tr.position.y),
			Vector2(tr.end.x, tr.position.y),
			Color(ink.r, ink.g, ink.b, 0.5), 1.0, true)
		# Ромб в центре title_rect.
		var tc := tr.get_center()
		var ds := 6.0
		var diamond := PackedVector2Array([
			tc + Vector2(0, -ds), tc + Vector2(ds, 0),
			tc + Vector2(0, ds), tc + Vector2(-ds, 0)])
		draw_colored_polygon(diamond, Color(ink.r, ink.g, ink.b, 0.55))


func _corners(outer: Rect2) -> Array:
	return [outer.position, Vector2(outer.end.x, outer.position.y),
		Vector2(outer.position.x, outer.end.y), outer.end]
