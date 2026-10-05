class_name SigilFrameView
extends Control

## Алхимическая рамка: двойной контур, срезанные углы, руны внутрь

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
	clip_contents = true
	queue_redraw()

func _ink(a: float) -> Color: return Color(ink.r, ink.g, ink.b, a * ink.a)

func _draw() -> void:
	if size.x < 40 or size.y < 40: return
	var rng := SigilRng.new(0); rng.reseed(frame_seed)
	
	# 1. Внешний прямоугольник СТРОГО внутри size
	var pad := clampf(margin, 6.0, min(size.x, size.y) * 0.2)
	var outer := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	if outer.size.x < 20 or outer.size.y < 20: return
	var inner := outer.grow(-5.0)
	# Амплитуда среза углов общая для всех контуров — фаски параллельны.
	var cut := clampf(min(outer.size.x, outer.size.y) * 0.08, 6.0, 18.0)

	# 2. Контуры — срезанные углы (октагон), не прямоугольник.
	draw_polyline(_cut_path(outer, cut), _ink(0.75), 1.7, true)
	draw_polyline(_cut_path(inner, cut), _ink(0.35), 0.9, true)
	if style % 2 == 1:
		draw_polyline(_cut_path(inner.grow(-4.0), cut), _ink(0.16), 0.7, true)

	# Свечение
	draw_polyline(_cut_path(outer.grow(1.5), cut + 1.5), _ink(0.07), 4.0, true)

	# 3. Углы - всегда ВНУТРЬ
	_draw_corners(outer, rng, cut)
	# 4. Середины сторон
	if style >= 1: _draw_mids(outer)
	# 5. Зоны art/title
	if options != null: _draw_zones(outer)

## Контур со срезанными углами: замкнутая полилиния восьмиугольника
## (прямоугольник за вычетом 45°-фасок по углам). Срез автоматически
## вписывается в короткую сторону, чтобы фаски не перекрывались.
static func _cut_path(r: Rect2, cut: float) -> PackedVector2Array:
	var c := minf(cut, minf(r.size.x, r.size.y) * 0.5 - 2.0)
	if c < 1.0:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
		Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
		Vector2(r.position.x + c, r.position.y),
	])

func _draw_corners(outer: Rect2, rng: SigilRng, cut: float) -> void:
	var tick := 13.0 + rng.randf_range(0, 5.0)
	var corners = [
		[outer.position, Vector2(1, 1)],
		[Vector2(outer.end.x, outer.position.y), Vector2(-1, 1)],
		[Vector2(outer.position.x, outer.end.y), Vector2(1, -1)],
		[outer.end, Vector2(-1, -1)],
	]
	var pool: Array = SigilGlyphs.by_category("spirit")
	if pool.is_empty(): pool = SigilGlyphs.names()

	for c in corners:
		# Орнамент якорится к середине фаски (угол срезан), а не к мнимому
		# прямому углу прямоугольника.
		var p: Vector2 = c[0] + c[1] * (cut * 0.5)
		var d: Vector2 = c[1]
		var h_end := p + Vector2(d.x * tick, 0)
		var v_end := p + Vector2(0, d.y * tick)
		# L-засечка
		draw_line(p, h_end, _ink(0.7), 1.3, true)
		draw_line(p, v_end, _ink(0.7), 1.3, true)
		# Поперечины
		draw_line(h_end + Vector2(0, -3), h_end + Vector2(0, 3), _ink(0.4), 0.8, true)
		draw_line(v_end + Vector2(-3, 0), v_end + Vector2(3, 0), _ink(0.4), 0.8, true)
		# Ромб в углу
		_draw_diamond(p, 3.2, _ink(0.9))
		# Диагональ
		var diag := p + d * tick * 0.65
		draw_line(p + d * 4.0, diag, _ink(0.25), 0.7, true)
		draw_circle(diag, 1.4, _ink(0.4))
		# Глиф - строго внутрь + проверка границ
		if glyphs_enabled and not pool.is_empty():
			var gsize := 15.0 + rng.randf_range(0, 4.0)
			var gpos := p + d * (tick + gsize * 0.6 + 4.0)
			if gpos.x > gsize and gpos.x < size.x - gsize and gpos.y > gsize and gpos.y < size.y - gsize:
				var g: String = pool[rng.randi_range(0, pool.size()-1)]
				SigilGlyphs.draw_glyph(self, g, gpos, gsize, rng.randf_range(-0.1, 0.1), _ink(0.38), 1.0)

func _draw_mids(outer: Rect2) -> void:
	var mids := [Vector2(outer.get_center().x, outer.position.y), Vector2(outer.get_center().x, outer.end.y), Vector2(outer.position.x, outer.get_center().y), Vector2(outer.end.x, outer.get_center().y)]
	for m in mids:
		_draw_diamond(m, 2.8, _ink(0.6))
		draw_circle(m, 1.0, _ink(0.8))

func _draw_zones(outer: Rect2) -> void:
	var content := outer.grow(-7.0)
	var ar := options.art_rect().intersection(content)
	var tr := options.title_rect().intersection(content)
	if ar.size.x > 4 and ar.size.y > 4:
		draw_rect(ar, _ink(0.12), false, 0.7)
	if tr.size.x < 4 or tr.size.y < 4: return
	
	draw_rect(tr, Color(0,0,0,0.32), true)
	draw_rect(tr, _ink(0.5), false, 1.0)
	draw_rect(tr.grow(-2.5), _ink(0.15), false, 0.6)
	
	# Разделитель с 3 ромбами
	var y := tr.position.y
	var cx := tr.get_center().x
	draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), _ink(0.55), 1.1, true)
	_draw_diamond(Vector2(tr.position.x + 9, y), 2.2, _ink(0.6))
	_draw_diamond(Vector2(cx, y), 2.8, _ink(0.8))
	_draw_diamond(Vector2(tr.end.x - 9, y), 2.2, _ink(0.6))

func _draw_diamond(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c+Vector2(0,-s), c+Vector2(s,0), c+Vector2(0,s), c+Vector2(-s,0)])
	draw_colored_polygon(pts, col)