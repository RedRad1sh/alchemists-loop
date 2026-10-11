class_name SigilFrameView
extends Control

## Слой 6 — рамка коллекционной карточки.
## Было: засечки и глифы всегда рисовались «вправо-вниз» от каждого угла,
## из-за чего у правого и нижнего краёв они вылезали наружу. Теперь каждый
## угол знает своё направление внутрь (sx, sy), всё рисуется строго внутри
## margin, а сама рамка — скошенный (фасками) металлический контур со светом
## из левого-верхнего угла, самоцветами в углах и на серединах сторон.
## Цвет металла и камней зависит от редкости (rarity); хроматик — радужный.
##
## Редкость: если у SigilOptions есть поле `rarity` — берётся оттуда,
## иначе задайте `frame.rarity = recipe.rarity` до вызова setup().

var frame_seed: int = 0
var style: int = 0
var margin: float = 16.0
var ink: Color = Color(0.9, 0.87, 0.78)
var glyphs_enabled: bool = true
var options: SigilOptions = null
var rarity: StringName = &"common"

var _metal := Color(0.88, 0.84, 0.74)
var _gem := Color(0.95, 0.88, 0.70)
var _rainbow := false
var _hue_shift := 0.0

const LIGHT_DIR := Vector2(-0.7071, -0.7071)
const CHAMFER_INNER := 0.586  # 2 - sqrt(2): как сдвигается фаска при сдвиге контура внутрь


func setup(p_options: SigilOptions, palette: SigilPalette, seed_value: int) -> void:
	options = p_options
	frame_seed = SigilRng.new(seed_value).fork("frame").next_u32()
	style = options.frame_style
	margin = options.frame_margin
	ink = palette.ink
	var r = options.get("rarity")
	if r != null and str(r) != "":
		rarity = StringName(str(r))
	_apply_rarity()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_rarity(value: StringName) -> void:
	rarity = value
	_apply_rarity()
	queue_redraw()


func _apply_rarity() -> void:
	_rainbow = false
	_hue_shift = float(frame_seed % 100) / 100.0
	match String(rarity):
		"uncommon":
			_metal = ink.lerp(Color(0.62, 0.86, 0.66), 0.5)
			_gem = Color(0.35, 0.85, 0.50)
		"rare":
			_metal = ink.lerp(Color(0.62, 0.78, 1.0), 0.55)
			_gem = Color(0.30, 0.62, 1.0)
		"epic":
			_metal = ink.lerp(Color(0.78, 0.62, 1.0), 0.55)
			_gem = Color(0.72, 0.34, 1.0)
		"legendary":
			_metal = Color(1.0, 0.82, 0.38)
			_gem = Color(1.0, 0.58, 0.18)
		"mythic":
			_metal = ink.lerp(Color(1.0, 0.45, 0.50), 0.55)
			_gem = Color(1.0, 0.22, 0.30)
		"chromatic":
			_rainbow = true
			_metal = Color(1.0, 0.85, 0.6)
			_gem = Color(1.0, 0.7, 0.3)
		_:
			_metal = ink
			_gem = Color(0.95, 0.88, 0.70)


# ---------- геометрия ----------

## Прямоугольник со скошенными (фаской) углами; замкнут повтором первой точки.
func _oct(r: Rect2, cut: float) -> PackedVector2Array:
	var c := maxf(cut, 2.0)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y0 + c),
		Vector2(x0 + c, y0)])


func _inset_oct(outer: Rect2, cut: float, d: float) -> PackedVector2Array:
	return _oct(outer.grow(-d), cut - CHAMFER_INNER * d)


func _subdiv(pts: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		for j in n:
			out.append(pts[i].lerp(pts[i + 1], float(j) / float(n)))
	out.append(pts[pts.size() - 1])
	return out


# ---------- цвет ----------

func _rgba(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Тон металла в точке: свет сверху-слева, тень снизу-справа; хроматик — радуга по углу.
func _tone(p: Vector2, center: Vector2, a: float) -> Color:
	if _rainbow:
		var ang := atan2(p.y - center.y, p.x - center.x) / TAU + 0.5
		return Color.from_hsv(fposmod(ang + _hue_shift, 1.0), 0.50, 1.0, a)
	var d := (p - center).normalized()
	var t := d.dot(LIGHT_DIR)
	var base := _metal
	if t >= 0.0:
		return Color(lerpf(base.r, 1.0, t * 0.42), lerpf(base.g, 1.0, t * 0.42), lerpf(base.b, 1.0, t * 0.42), a)
	var k := -t * 0.38
	return Color(lerpf(base.r, 0.0, k), lerpf(base.g, 0.0, k), lerpf(base.b, 0.0, k), a)


func _gem_tone(p: Vector2, center: Vector2) -> Color:
	if _rainbow:
		var ang := atan2(p.y - center.y, p.x - center.x) / TAU + 0.5
		return Color.from_hsv(fposmod(ang + _hue_shift + 0.5, 1.0), 0.75, 1.0)
	return _gem


## Контур с плавным градиентом тона (по подразбитым сегментам).
func _stroke(pts: PackedVector2Array, center: Vector2, width: float, a: float) -> void:
	var dense := _subdiv(pts, 8)
	var cols := PackedColorArray()
	for i in dense.size():
		cols.append(_tone(dense[i], center, a))
	draw_polyline_colors(dense, cols, width, true)


# ---------- элементы ----------

func _draw_gem(p: Vector2, r: float, center: Vector2) -> void:
	var gc := _gem_tone(p, center)
	var outline := PackedVector2Array([
		p + Vector2(0, -r * 1.25), p + Vector2(r, 0), p + Vector2(0, r * 1.25), p + Vector2(-r, 0)])
	draw_colored_polygon(outline, Color(gc.r * 0.45, gc.g * 0.45, gc.b * 0.45, 1.0))
	var inner := PackedVector2Array([
		p + Vector2(0, -r * 0.82), p + Vector2(r * 0.64, 0), p + Vector2(0, r * 0.82), p + Vector2(-r * 0.64, 0)])
	draw_colored_polygon(inner, gc)
	draw_line(p + Vector2(0, -r * 0.82), p + Vector2(0, r * 0.82), Color(1, 1, 1, 0.22), 1.0, true)
	var rim := outline.duplicate()
	rim.append(outline[0])
	draw_polyline(rim, _tone(p, center, 0.95), 1.2, true)
	draw_circle(p + Vector2(-r * 0.22, -r * 0.4), maxf(r * 0.16, 0.8), Color(1, 1, 1, 0.85))


## Орнамент угла: самоцвет на фаске, усиленные «башмаки» вдоль краёв,
## изящные дуги внутрь и (опционально) глиф в их центре. (sx, sy) — направление внутрь.
func _draw_corner(c: Vector2, sx: float, sy: float, cut: float, center: Vector2,
		glyph: String, glyph_rot: float) -> void:
	var inward := Vector2(sx, sy)
	# Усиленные концы краёв.
	var cap := cut * 0.9
	var cap_col := _tone(c + inward * cut, center, 1.0)
	draw_line(c + Vector2(sx * cut, 0.0), c + Vector2(sx * (cut + cap), 0.0), cap_col, 4.6, true)
	draw_line(c + Vector2(0.0, sy * cut), c + Vector2(0.0, sy * (cut + cap)), cap_col, 4.6, true)
	# Самоцвет на середине фаски.
	_draw_gem(c + inward * cut * 0.5, clampf(cut * 0.34, 3.5, 6.0), center)
	# Дуги внутрь, обращённые к углу.
	var ac := c + inward * cut * 1.75
	var base_ang := atan2(-sy, -sx)
	var t := _tone(ac, center, 0.85)
	draw_arc(ac, cut * 1.05, base_ang - 1.0, base_ang + 1.0, 20, t, 1.5, true)
	draw_arc(ac, cut * 0.70, base_ang - 1.1, base_ang + 1.1, 16, _rgba(t, 0.5), 1.0, true)
	if glyph != "":
		SigilGlyphs.draw_glyph(self, glyph, ac, cut * 0.95, glyph_rot, _rgba(t, 0.55), 1.0)


## Орнамент середины стороны. n — нормаль внутрь, k — масштаб.
func _draw_edge_ornament(p: Vector2, n: Vector2, k: float, center: Vector2) -> void:
	var t := Vector2(-n.y, n.x)
	var plate := PackedVector2Array([
		p - n * 2.5 * k + t * 15.0 * k, p - n * 2.5 * k - t * 15.0 * k,
		p + n * 5.0 * k - t * 9.0 * k, p + n * 5.0 * k + t * 9.0 * k])
	draw_colored_polygon(plate, Color(_metal.r * 0.18, _metal.g * 0.18, _metal.b * 0.18, 0.96))
	var pr := plate.duplicate()
	pr.append(plate[0])
	draw_polyline(pr, _tone(p, center, 0.9), 1.2, true)
	for sgn in [-1.0, 1.0]:
		var a: Vector2 = p + t * sgn * 17.0 * k
		var b: Vector2 = p + t * sgn * 36.0 * k
		draw_line(a, b, _tone(b, center, 0.9), 3.4, true)
		draw_circle(b, 1.8 * k, _tone(b, center, 1.0))
	_draw_gem(p + n * 1.2 * k, 5.2 * k, center)


# ---------- отрисовка ----------

func _draw() -> void:
	var rng := SigilRng.new(0)
	rng.reseed(frame_seed)
	var m := clampf(margin, 4.0, minf(size.x, size.y) * 0.2)
	var outer := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
	if outer.size.x < 60.0 or outer.size.y < 60.0:
		return
	var center := outer.get_center()
	var cut := clampf(14.0 + float(style % 3) * 3.0 + rng.randf_range(0.0, 3.0),
		8.0, minf(outer.size.x, outer.size.y) * 0.16)

	# Свечение редких рамок — строго в пределах margin.
	if m >= 8.0 and (String(rarity) in ["epic", "legendary", "mythic", "chromatic"]):
		var gc := _gem_tone(center + Vector2(0, -outer.size.y * 0.5), center)
		for i in 3:
			draw_polyline(_oct(outer.grow(1.5 + float(i) * 1.6), cut + float(i)),
				_rgba(gc, 0.14 - float(i) * 0.04), 3.0, true)

	# Внутренняя тень вдоль рамки.
	for i in 6:
		var d := 2.0 + float(i) * 2.2
		draw_polyline(_inset_oct(outer, cut, d), Color(0, 0, 0, 0.22 * (1.0 - float(i) / 6.0)), 2.4, true)

	# Основной металлический контур и две тонкие линии внутри.
	_stroke(_oct(outer, cut), center, 3.4, 1.0)
	_stroke(_inset_oct(outer, cut, 4.6), center, 1.3, 0.75)
	if style % 2 == 1:
		_stroke(_inset_oct(outer, cut, 9.0), center, 0.9, 0.42)

	# Орнаменты: углы (TL, TR, BL, BR) — каждый смотрит внутрь рамки.
	var pool = []  # тип зависит от SigilGlyphs (Array или Packed) — оставляем Variant
	if glyphs_enabled:
		pool = SigilGlyphs.by_category("spirit")
		if pool.is_empty():
			pool = SigilGlyphs.names()
	var corners := [
		[outer.position, 1.0, 1.0],
		[Vector2(outer.end.x, outer.position.y), -1.0, 1.0],
		[Vector2(outer.position.x, outer.end.y), 1.0, -1.0],
		[outer.end, -1.0, -1.0]]
	for cd in corners:
		var gname := ""
		var grot := rng.randf_range(-0.15, 0.15)
		if not pool.is_empty():
			gname = pool[rng.randi_range(0, pool.size() - 1)]
		_draw_corner(cd[0], cd[1], cd[2], cut, center, gname, grot)

	# Середины сторон: верх и низ всегда, бока — со стиля 1.
	_draw_edge_ornament(Vector2(center.x, outer.position.y), Vector2(0, 1), 1.0, center)
	_draw_edge_ornament(Vector2(center.x, outer.end.y), Vector2(0, -1), 1.0, center)
	if style >= 1:
		_draw_edge_ornament(Vector2(outer.position.x, center.y), Vector2(1, 0), 0.75, center)
		_draw_edge_ornament(Vector2(outer.end.x, center.y), Vector2(-1, 0), 0.75, center)

	# Зоны карточки: арт и плашка названия.
	if options == null:
		return
	var ar := options.art_rect()
	draw_rect(ar, _rgba(_metal, 0.22), false, 1.0)
	for cd in corners:
		var ac: Vector2 = Vector2(ar.position.x if cd[1] > 0.0 else ar.end.x,
			ar.position.y if cd[2] > 0.0 else ar.end.y)
		var tc := _tone(ac, center, 0.85)
		draw_line(ac, ac + Vector2(cd[1] * 9.0, 0.0), tc, 1.6, true)
		draw_line(ac, ac + Vector2(0.0, cd[2] * 9.0), tc, 1.6, true)

	var tr := options.title_rect()
	draw_rect(tr, Color(0, 0, 0, 0.46), true)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, minf(tr.size.y * 0.5, 14.0))), Color(1, 1, 1, 0.04), true)
	draw_rect(tr, _rgba(_metal, 0.5), false, 1.0)
	draw_rect(tr.grow(-2.5), _rgba(_metal, 0.18), false, 1.0)
	var mid := tr.get_center()
	# Разделитель и ромб с «крыльями».
	draw_line(Vector2(tr.position.x, tr.position.y), Vector2(tr.end.x, tr.position.y),
		_tone(mid, center, 0.7), 1.2, true)
	var ds := 6.0
	draw_colored_polygon(PackedVector2Array([
		mid + Vector2(0, -ds), mid + Vector2(ds, 0), mid + Vector2(0, ds), mid + Vector2(-ds, 0)]),
		_rgba(_metal, 0.8))
	if tr.size.x > 140.0:
		for sgn in [-1.0, 1.0]:
			draw_line(mid + Vector2(sgn * 12.0, 0), mid + Vector2(sgn * 42.0, 0), _rgba(_metal, 0.5), 1.0, true)
			var end_p: Vector2 = mid + Vector2(sgn * 48.0, 0)
			draw_colored_polygon(PackedVector2Array([
				end_p + Vector2(0, -2.6), end_p + Vector2(2.6, 0),
				end_p + Vector2(0, 2.6), end_p + Vector2(-2.6, 0)]), _rgba(_metal, 0.7))
