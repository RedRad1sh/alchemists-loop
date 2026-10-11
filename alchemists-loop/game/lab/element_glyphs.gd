class_name ElementGlyphs
# Векторные глифы элементов: простые формы из примитивов, без текстур и эмодзи.

const GLYPH_KEYS := ["fire","water","earth","air","steam","stone","clay","dust","spark","mist","brick",
	"sand","glass","plant","cloud","ice","mountain","mud","metal","life","smoke","lava",
	"sky","rain","storm","hail","snow","volcano","obsidian","magma","ash","gold","swamp",
	"fish","bird","beast","person","seed","grass","mushroom","lightning","tornado","tool",
	"tree","sun","crystal","sandstorm","forest","wood","flower","rainbow","desert","boat",
	"coal","wall","house","child"]

# Параметрические глифы (генерирует LLM вместе с веществом): «форма+число»,
# например star6, crystal5, ring3. Формы должны совпадать с серверным
# gen_llm.GLYPH_PARAM.
const PARAM_BASES := ["poly", "star", "burst", "ring", "cluster", "crystal", "blossom", "sigil", "spiral", "rays"]


static func has(glyph: String) -> bool:
	return glyph in GLYPH_KEYS or is_parametric(glyph)


static func is_parametric(glyph: String) -> bool:
	# «форма+число»: латинская основа из PARAM_BASES, затем хотя бы одна цифра
	if glyph.length() < 3:
		return false
	var i := 0
	while i < glyph.length() and glyph[i] >= "a" and glyph[i] <= "z":
		i += 1
	if i == 0 or i == glyph.length():
		return false
	if glyph.substr(0, i) not in PARAM_BASES:
		return false
	for j in range(i, glyph.length()):
		var ch := glyph[j]
		if ch < "0" or ch > "9":
			return false
	return true

static func draw(c: CanvasItem, glyph: String, center: Vector2, r: float, col: Color) -> void:
	match glyph:
		"fire": _flame(c, center, r, col)
		"water": _drop(c, center, r, col)
		"earth": _mountain(c, center, r, col)
		"air": _wind(c, center, r, col)
		"steam": _steam(c, center, r, col)
		"stone": _stone(c, center, r, col)
		"clay": _blob(c, center, r, col)
		"dust": _dust(c, center, r, col)
		"spark": _spark(c, center, r, col)
		"mist": _mist(c, center, r, col)
		"brick": _brick(c, center, r, col)
		"sand": _sand(c, center, r, col)
		"glass": _glass(c, center, r, col)
		"plant": _leaf(c, center, r, col)
		"cloud": _cloud(c, center, r, col)
		"ice": _ice(c, center, r, col)
		"mountain": _mountain2(c, center, r, col)
		"mud": _mud(c, center, r, col)
		"metal": _metal(c, center, r, col)
		"life": _life(c, center, r, col)
		"smoke": _smoke(c, center, r, col)
		"lava": _lava(c, center, r, col)
		"sky": _sky(c, center, r, col)
		"rain": _rain(c, center, r, col)
		"storm": _storm(c, center, r, col)
		"hail": _hail(c, center, r, col)
		"snow": _snow(c, center, r, col)
		"volcano": _volcano(c, center, r, col)
		"obsidian": _obsidian(c, center, r, col)
		"magma": _magma(c, center, r, col)
		"ash": _ash(c, center, r, col)
		"gold": _gold(c, center, r, col)
		"swamp": _swamp(c, center, r, col)
		"fish": _fish(c, center, r, col)
		"bird": _bird(c, center, r, col)
		"beast": _beast(c, center, r, col)
		"person": _person(c, center, r, col)
		"seed": _seed(c, center, r, col)
		"grass": _grass(c, center, r, col)
		"mushroom": _mushroom(c, center, r, col)
		"lightning": _bolt(c, center, r, col)
		"tornado": _tornado(c, center, r, col)
		"tool": _tool(c, center, r, col)
		"tree": _tree(c, center, r, col)
		"sun": _sun(c, center, r, col)
		"crystal": _crystal(c, center, r, col)
		"sandstorm": _sandstorm(c, center, r, col)
		"forest": _forest(c, center, r, col)
		"wood": _wood(c, center, r, col)
		"flower": _flower(c, center, r, col)
		"rainbow": _rainbow(c, center, r, col)
		"desert": _desert(c, center, r, col)
		"boat": _boat(c, center, r, col)
		"coal": _coal(c, center, r, col)
		"wall": _wall(c, center, r, col)
		"house": _house(c, center, r, col)
		"child": _child(c, center, r, col)
		_:
			if is_parametric(glyph):
				_parametric(c, glyph, center, r, col)
			else:
				_proc(c, glyph, center, r, col)

static func _poly(c: CanvasItem, pts: Array, col: Color) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(p)
	c.draw_colored_polygon(arr, col)

static func _flame(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(0, -r * 0.85), o + Vector2(r * 0.5, r * 0.1),
		o + Vector2(r * 0.28, r * 0.75), o + Vector2(0, r * 0.5),
		o + Vector2(-r * 0.28, r * 0.75), o + Vector2(-r * 0.5, r * 0.1)], col)
	_poly(c, [o + Vector2(0, -r * 0.3), o + Vector2(r * 0.18, r * 0.25),
		o + Vector2(0, r * 0.45), o + Vector2(-r * 0.18, r * 0.25)], Color(col.r, col.g, col.b, 0.55))

static func _drop(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(0, -r * 0.85), o + Vector2(r * 0.5, r * 0.2),
		o + Vector2(r * 0.3, r * 0.75), o + Vector2(-r * 0.3, r * 0.75),
		o + Vector2(-r * 0.5, r * 0.2)], col)
	c.draw_circle(o + Vector2(-r * 0.2, r * 0.05), r * 0.14, Color(col.r, col.g, col.b, 0.6))

static func _mountain(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(0, -r * 0.8), o + Vector2(r * 0.55, r * 0.7),
		o + Vector2(-r * 0.55, r * 0.7)], col)
	_poly(c, [o + Vector2(0, -r * 0.8), o + Vector2(r * 0.55, r * 0.7),
		o + Vector2(0, r * 0.7)], Color(col.r, col.g, col.b, 0.5))

static func _wind(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var y := -r * 0.5 + float(i) * r * 0.5
		var pts := PackedVector2Array()
		var amp := r * (0.18 + 0.08 * float(i % 2))
		var n := 10
		for k in n:
			var t := float(k) / float(n - 1)
			pts.append(o + Vector2(-r * 0.85 + t * r * 1.7, y + sin(t * TAU + float(i) * 1.4) * amp))
		c.draw_polyline(pts, col, maxf(r * 0.13, 1.4))

static func _steam(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var x := -r * 0.5 + float(i) * r * 0.5
		var pts := PackedVector2Array()
		for k in 6:
			var t := float(k) / 5.0
			pts.append(o + Vector2(x + sin(t * TAU * 0.8 + float(i)) * r * 0.14, r * 0.7 - t * r * 1.5))
		c.draw_polyline(pts, col, maxf(r * 0.12, 1.2))

static func _stone(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts: Array = [o + Vector2(-r * 0.7, -r * 0.35), o + Vector2(-r * 0.45, -r * 0.7),
		o + Vector2(r * 0.4, -r * 0.65), o + Vector2(r * 0.7, -r * 0.2),
		o + Vector2(r * 0.5, r * 0.6), o + Vector2(-r * 0.55, r * 0.6)]
	_poly(c, pts, col)
	c.draw_circle(o + Vector2(-r * 0.2, -r * 0.25), r * 0.12, Color(col.r, col.g, col.b, 0.55))

static func _blob(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var a := TAU * float(k) / 12.0
		var rr := r * (0.75 + 0.22 * sin(a * 3.0 + 1.2))
		pts.append(o + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)

static func _dust(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.4
		var dd := r * 0.55
		c.draw_circle(o + Vector2(cos(a), sin(a)) * dd, r * (0.16 + 0.05 * float(i % 3)), col)

static func _spark(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts: Array = []
	for k in 8:
		var a := TAU * float(k) / 8.0
		var rr := r * (0.95 if k % 2 == 0 else 0.34)
		pts.append(o + Vector2(cos(a), sin(a)) * rr)
	_poly(c, pts, col)
	c.draw_circle(o, r * 0.18, Color(1, 1, 1, 0.5))

static func _mist(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 4:
		var y := -r * 0.55 + float(i) * r * 0.36
		c.draw_rect(Rect2(o + Vector2(-r * 0.7, y), Vector2(r * 1.4, r * 0.16)), col, true)
		c.draw_rect(Rect2(o + Vector2(-r * 0.4, y + r * 0.1), Vector2(r * 0.8, r * 0.1)),
			Color(col.r, col.g, col.b, 0.5), true)

static func _brick(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var w := r * 1.4
	var h := r * 0.75
	c.draw_rect(Rect2(o + Vector2(-w / 2, -h / 2), Vector2(w, h)), col, true)
	c.draw_rect(Rect2(o + Vector2(-w / 2, -h / 2), Vector2(w / 2, h)), Color(0, 0, 0, 0.18), true)

static func _sand(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(0, -r * 0.7), o + Vector2(r * 0.6, r * 0.5),
		o + Vector2(-r * 0.6, r * 0.5)])
	c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.55))
	for i in 4:
		var a := -0.5 + float(i) * 0.33
		var y := r * 0.2
		c.draw_circle(o + Vector2(a * r * 1.2, y), r * 0.09 + 0.04 * float(i % 2), col)

static func _glass(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(0, -r * 0.8), o + Vector2(r * 0.6, 0),
		o + Vector2(0, r * 0.8), o + Vector2(-r * 0.6, 0)])
	c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.45))
	c.draw_polyline(PackedVector2Array([o + Vector2(0, -r * 0.8), o + Vector2(0, r * 0.8)]),
		col, 1.6)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.6, 0), o + Vector2(r * 0.6, 0)]),
		col, 1.6)

# Простая замкнутая «линза» без дублирующихся вершин — полигон всегда триангулируется.
static func _lens_shape(o: Vector2, r: float, half_h: float, x0: float, x1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 7
	for k in n + 1:
		var t := float(k) / float(n)
		pts.append(o + Vector2(lerpf(x0, x1, t), -sin(t * PI) * r * half_h))
	for k in range(n - 1, 0, -1):
		var t := float(k) / float(n)
		pts.append(o + Vector2(lerpf(x0, x1, t), sin(t * PI) * r * half_h))
	return pts

static func _leaf(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(_lens_shape(o, r, 0.30, -r * 0.7, r * 0.8), col)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.6, 0), o + Vector2(r * 0.75, 0)]),
		Color(col.r, col.g, col.b, 0.7), 1.8)

static func _dot(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o, r * 0.5, col)


# ---------- семантические глифы (по смыслу вещества) ----------

static func _cloud(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(-r * 0.4, r * 0.05), r * 0.3, col)
	c.draw_circle(o + Vector2(0, -r * 0.16), r * 0.38, col)
	c.draw_circle(o + Vector2(r * 0.4, r * 0.05), r * 0.3, col)
	c.draw_rect(Rect2(o + Vector2(-r * 0.7, 0), Vector2(r * 1.4, r * 0.3)), col, true)

static func _ice(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var full := PackedVector2Array()
	for k in 6:
		var a := TAU * float(k) / 6.0 - PI / 2.0
		full.append(o + Vector2(cos(a), sin(a)) * r * 0.9)
		var a2 := a + TAU / 12.0
		full.append(o + Vector2(cos(a2), sin(a2)) * r * 0.32)
	c.draw_colored_polygon(full, col)

static func _snow(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for k in 6:
		var a := TAU * float(k) / 6.0 - PI / 2.0
		var d := Vector2(cos(a), sin(a))
		var p := Vector2(-d.y, d.x)
		c.draw_line(o + d * r * 0.15, o + d * r * 0.85, col, maxf(r * 0.09, 1.2))
		var mid := o + d * r * 0.5
		c.draw_line(mid, mid + p * r * 0.16, col, maxf(r * 0.07, 1.0))
		c.draw_line(mid, mid - p * r * 0.16, col, maxf(r * 0.07, 1.0))

static func _mountain2(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.85, r * 0.75), o + Vector2(-r * 0.45, -r * 0.45),
		o + Vector2(-r * 0.08, r * 0.2), o + Vector2(r * 0.55, -r * 0.7),
		o + Vector2(r * 0.85, r * 0.75)], col)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.62, -r * 0.12), o + Vector2(-r * 0.28, -r * 0.12)]),
		Color(1, 1, 1, 0.65), 2.0)
	c.draw_polyline(PackedVector2Array([o + Vector2(r * 0.36, -r * 0.34), o + Vector2(r * 0.72, -r * 0.34)]),
		Color(1, 1, 1, 0.65), 2.0)

static func _mud(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(-r * 0.35, r * 0.3), r * 0.34, col)
	c.draw_circle(o + Vector2(r * 0.1, r * 0.35), r * 0.4, col)
	c.draw_circle(o + Vector2(r * 0.5, r * 0.2), r * 0.28, col)
	c.draw_circle(o + Vector2(-r * 0.1, r * 0.0), r * 0.15, Color(col.r, col.g, col.b, 0.5))

static func _metal(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.6, -r * 0.3), o + Vector2(r * 0.6, -r * 0.3),
		o + Vector2(r * 0.45, r * 0.4), o + Vector2(-r * 0.45, r * 0.4)], col)
	c.draw_rect(Rect2(o + Vector2(-r * 0.6, -r * 0.3), Vector2(r * 0.34, r * 0.16)),
		Color(1, 1, 1, 0.35), true)

static func _life(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(-r * 0.28, -r * 0.2), r * 0.38, col)
	c.draw_circle(o + Vector2(r * 0.28, -r * 0.2), r * 0.38, col)
	_poly(c, [o + Vector2(-r * 0.6, -r * 0.08), o + Vector2(r * 0.6, -r * 0.08),
		o + Vector2(0, r * 0.8)], col)

static func _smoke(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var t := float(k) / 11.0
		pts.append(o + Vector2(sin(t * PI * 2.2) * r * 0.42, r * 0.7 - t * r * 1.4))
	c.draw_polyline(pts, col, maxf(r * 0.14, 1.4))
	c.draw_circle(o + Vector2(0, -r * 0.55), r * 0.2, Color(col.r, col.g, col.b, 0.6))

static func _lava(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.6, r * 0.75), o + Vector2(r * 0.6, r * 0.75),
		o + Vector2(r * 0.35, -r * 0.1), o + Vector2(-r * 0.35, -r * 0.1)], col)
	_flame(c, o + Vector2(0, -r * 0.32), r * 0.5, Color(1.0, 0.82, 0.35, 0.95))

static func _sky(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, -r * 0.25), r * 0.42, col)
	c.draw_line(o + Vector2(-r * 0.75, r * 0.55), o + Vector2(r * 0.75, r * 0.55), col, maxf(r * 0.1, 1.4))
	c.draw_line(o + Vector2(-r * 0.5, r * 0.75), o + Vector2(r * 0.5, r * 0.75), col, maxf(r * 0.08, 1.2))

static func _bolt(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(r * 0.15, -r * 0.75), o + Vector2(-r * 0.3, r * 0.05),
		o + Vector2(-r * 0.02, r * 0.05), o + Vector2(-r * 0.15, r * 0.75),
		o + Vector2(r * 0.3, -r * 0.05), o + Vector2(r * 0.02, -r * 0.05)], col)

static func _rain(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_cloud(c, o + Vector2(0, -r * 0.15), r * 0.8, col)
	for i in 3:
		var x := -r * 0.4 + float(i) * r * 0.4
		c.draw_line(o + Vector2(x, r * 0.05), o + Vector2(x - r * 0.08, r * 0.6), col, maxf(r * 0.1, 1.3))

static func _storm(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_cloud(c, o + Vector2(0, -r * 0.15), r * 0.8, col)
	_bolt(c, o + Vector2(0, r * 0.2), r * 0.5, Color(1.0, 0.9, 0.3, 0.95))

static func _hail(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_cloud(c, o + Vector2(0, -r * 0.15), r * 0.8, col)
	for i in 3:
		var x := -r * 0.42 + float(i) * r * 0.42
		c.draw_circle(o + Vector2(x, r * 0.5), r * 0.12, Color(col.r, col.g, col.b, 0.95))

static func _volcano(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.8, r * 0.7), o + Vector2(-r * 0.35, -r * 0.3),
		o + Vector2(r * 0.35, -r * 0.3), o + Vector2(r * 0.8, r * 0.7)], col)
	c.draw_circle(o + Vector2(0, -r * 0.3), r * 0.2, Color(0, 0, 0, 0.25))
	_flame(c, o + Vector2(0, -r * 0.45), r * 0.42, Color(1.0, 0.68, 0.2, 0.95))

static func _obsidian(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.55, -r * 0.75), o + Vector2(r * 0.15, -r * 0.75),
		o + Vector2(r * 0.75, r * 0.15), o + Vector2(r * 0.35, r * 0.75),
		o + Vector2(-r * 0.65, r * 0.1)], col)
	c.draw_line(o + Vector2(-r * 0.25, -r * 0.4), o + Vector2(-r * 0.25, r * 0.3),
		Color(1, 1, 1, 0.35), 1.4)

static func _magma(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.6, -r * 0.55), o + Vector2(r * 0.6, -r * 0.55),
		o + Vector2(r * 0.7, r * 0.05), o + Vector2(-r * 0.7, r * 0.05)], col)
	_flame(c, o + Vector2(0, r * 0.35), r * 0.5, Color(1.0, 0.6, 0.2, 0.9))

static func _ash(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 5:
		var x := -r * 0.6 + float(i) * r * 0.3
		var y := r * 0.5 - float(posmod(i * 7, 5)) * r * 0.18
		c.draw_circle(o + Vector2(x, y), r * (0.1 + 0.03 * float(i % 3)),
			Color(col.r, col.g, col.b, 0.55 + 0.12 * float(i % 3)))

static func _gold(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o, r * 0.7, col)
	c.draw_circle(o, r * 0.45, Color(col.r, col.g, col.b, 0.55))
	c.draw_circle(o, r * 0.2, Color(1, 1, 1, 0.35))

static func _swamp(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_line(o + Vector2(-r * 0.4, r * 0.2), o + Vector2(-r * 0.4, -r * 0.6), col, maxf(r * 0.1, 1.4))
	c.draw_line(o + Vector2(r * 0.15, r * 0.25), o + Vector2(r * 0.15, -r * 0.45), col, maxf(r * 0.1, 1.4))
	_leaf(c, o + Vector2(-r * 0.4, -r * 0.6), r * 0.4, col)
	c.draw_line(o + Vector2(-r * 0.7, r * 0.62), o + Vector2(r * 0.7, r * 0.62), col, maxf(r * 0.08, 1.2))

static func _fish(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(-r * 0.55, 0), o + Vector2(-r * 0.05, -r * 0.4),
		o + Vector2(r * 0.4, -r * 0.35), o + Vector2(r * 0.7, 0),
		o + Vector2(r * 0.4, r * 0.35), o + Vector2(-r * 0.05, r * 0.4)])
	c.draw_colored_polygon(pts, col)
	_poly(c, [o + Vector2(-r * 0.5, 0), o + Vector2(-r * 0.85, -r * 0.35),
		o + Vector2(-r * 0.85, r * 0.35)], Color(col.r, col.g, col.b, 0.7))
	c.draw_circle(o + Vector2(r * 0.35, -r * 0.15), r * 0.08, Color(0, 0, 0, 0.4))

static func _bird(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, r * 0.1), r * 0.38, col)
	c.draw_circle(o + Vector2(r * 0.35, -r * 0.35), r * 0.24, col)
	_poly(c, [o + Vector2(r * 0.55, -r * 0.4), o + Vector2(r * 0.78, -r * 0.3),
		o + Vector2(r * 0.55, -r * 0.24)], col)
	_poly(c, [o + Vector2(-r * 0.1, -r * 0.2), o + Vector2(-r * 0.55, -r * 0.6),
		o + Vector2(-r * 0.2, r * 0.05)], Color(col.r, col.g, col.b, 0.8))

static func _beast(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, r * 0.4), r * 0.3, col)
	c.draw_circle(o + Vector2(-r * 0.4, -r * 0.2), r * 0.13, col)
	c.draw_circle(o + Vector2(0, -r * 0.35), r * 0.13, col)
	c.draw_circle(o + Vector2(r * 0.4, -r * 0.2), r * 0.13, col)

static func _person(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, -r * 0.35), r * 0.27, col)
	_poly(c, [o + Vector2(-r * 0.55, r * 0.75), o + Vector2(-r * 0.45, r * 0.15),
		o + Vector2(r * 0.45, r * 0.15), o + Vector2(r * 0.55, r * 0.75)], col)

static func _seed(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, r * 0.25), r * 0.32, col)
	c.draw_line(o + Vector2(0, r * 0.2), o + Vector2(0, -r * 0.4), col, maxf(r * 0.08, 1.2))
	_leaf(c, o + Vector2(0, -r * 0.42), r * 0.35, col)

static func _grass(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var x := -r * 0.45 + float(i) * r * 0.45
		var tilt := 0.0 if i == 1 else (0.2 if i == 0 else -0.2)
		var pts := PackedVector2Array([o + Vector2(x, r * 0.6), o + Vector2(x, -r * 0.15),
			o + Vector2(x + tilt * r, -r * 0.6)])
		c.draw_polyline(pts, col, maxf(r * 0.1, 1.3))

static func _mushroom(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var cap := PackedVector2Array()
	for k in 11:
		var t := float(k) / 10.0
		cap.append(o + Vector2(-r * 0.55 + t * r * 1.1, -sin(t * PI) * r * 0.5 - r * 0.1))
	c.draw_colored_polygon(cap, col)
	c.draw_rect(Rect2(o + Vector2(-r * 0.14, -r * 0.1), Vector2(r * 0.28, r * 0.6)),
		Color(col.r, col.g, col.b, 0.9), true)
	c.draw_circle(o + Vector2(-r * 0.2, -r * 0.35), r * 0.06, Color(1, 1, 1, 0.5))
	c.draw_circle(o + Vector2(r * 0.15, -r * 0.5), r * 0.05, Color(1, 1, 1, 0.5))

static func _tornado(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.55, -r * 0.7), o + Vector2(-r * 0.1, r * 0.7),
		o + Vector2(r * 0.1, r * 0.7), o + Vector2(r * 0.55, -r * 0.7)], col)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.55, -r * 0.7),
		o + Vector2(0, -r * 0.35), o + Vector2(r * 0.55, -r * 0.7)]), col, maxf(r * 0.1, 1.4))

static func _tool(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_line(o + Vector2(-r * 0.2, r * 0.6), o + Vector2(r * 0.15, -r * 0.5), col, maxf(r * 0.12, 1.6))
	c.draw_rect(Rect2(o + Vector2(-r * 0.1, -r * 0.75), Vector2(r * 0.7, r * 0.35)), col, true)

static func _tree(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(o + Vector2(-r * 0.1, -r * 0.1), Vector2(r * 0.2, r * 0.7)),
		Color(col.r, col.g, col.b, 0.85), true)
	c.draw_circle(o + Vector2(0, -r * 0.35), r * 0.45, col)

static func _sun(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o, r * 0.45, col)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(o + d * r * 0.55, o + d * r * 0.9, col, maxf(r * 0.09, 1.3))

static func _crystal(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_gem(c, o, r, col)

static func _sandstorm(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_wind(c, o, r * 0.8, col)
	for i in 4:
		var x := -r * 0.6 + float(i) * r * 0.4
		c.draw_circle(o + Vector2(x, r * 0.4 + 0.1 * r * float(i % 2)), r * 0.08,
			Color(col.r, col.g, col.b, 0.85))

static func _forest(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_tree(c, o + Vector2(-r * 0.3, r * 0.05), r * 0.6, col)
	_tree(c, o + Vector2(r * 0.3, r * 0.05), r * 0.6, col)

static func _wood(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(o + Vector2(-r * 0.7, -r * 0.35), Vector2(r * 1.4, r * 0.7)), col, true)
	c.draw_circle(o + Vector2(r * 0.4, 0), r * 0.2, Color(col.r, col.g, col.b, 0.5))
	c.draw_circle(o + Vector2(r * 0.4, 0), r * 0.08, Color(0, 0, 0, 0.2))
	c.draw_line(o + Vector2(-r * 0.7, -r * 0.35), o + Vector2(-r * 0.7, r * 0.35),
		Color(1, 1, 1, 0.25), 1.5)

static func _flower(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for k in 5:
		var a := TAU * float(k) / 5.0
		var d := Vector2(cos(a), sin(a))
		c.draw_circle(o + d * r * 0.4, r * 0.26, col)
	c.draw_circle(o, r * 0.2, Color(1.0, 0.9, 0.4, 0.95))

static func _rainbow(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var rr := r * (0.85 - 0.24 * float(i))
		c.draw_arc(o + Vector2(0, r * 0.5), rr, PI, TAU, 20, col, maxf(r * 0.11, 1.3))

static func _desert(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(r * 0.4, -r * 0.35), r * 0.22, col)
	var pts := PackedVector2Array()
	for k in 11:
		var t := float(k) / 10.0
		pts.append(o + Vector2(-r * 0.8 + t * r * 1.6, r * 0.6 - sin(t * PI) * r * 0.5))
	c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.8))

static func _boat(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.7, r * 0.3), o + Vector2(r * 0.7, r * 0.3),
		o + Vector2(r * 0.4, r * 0.7), o + Vector2(-r * 0.4, r * 0.7)], col)
	c.draw_line(o + Vector2(0, r * 0.3), o + Vector2(0, -r * 0.7), col, maxf(r * 0.08, 1.2))
	_poly(c, [o + Vector2(r * 0.05, -r * 0.65), o + Vector2(r * 0.55, -r * 0.1),
		o + Vector2(r * 0.05, -r * 0.1)], Color(col.r, col.g, col.b, 0.85))

static func _coal(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	_poly(c, [o + Vector2(-r * 0.6, -r * 0.2), o + Vector2(-r * 0.2, -r * 0.6),
		o + Vector2(r * 0.4, -r * 0.55), o + Vector2(r * 0.65, 0),
		o + Vector2(r * 0.25, r * 0.65), o + Vector2(-r * 0.5, r * 0.5)], col)
	c.draw_circle(o + Vector2(-r * 0.1, -r * 0.15), r * 0.12, Color(1, 1, 1, 0.2))

static func _wall(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var w := r * 1.3
	var h := r * 0.8
	c.draw_rect(Rect2(o + Vector2(-w / 2, -h / 2), Vector2(w, h)), col, true)
	c.draw_line(o + Vector2(-w / 2, 0), o + Vector2(w / 2, 0), Color(0, 0, 0, 0.25), 1.6)
	c.draw_line(o + Vector2(0, -h / 2), o + Vector2(0, 0), Color(0, 0, 0, 0.25), 1.6)
	c.draw_line(o + Vector2(-w / 4, 0), o + Vector2(-w / 4, h / 2), Color(0, 0, 0, 0.25), 1.6)
	c.draw_line(o + Vector2(w / 4, 0), o + Vector2(w / 4, h / 2), Color(0, 0, 0, 0.25), 1.6)

static func _house(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(o + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.7)), col, true)
	_poly(c, [o + Vector2(-r * 0.7, -r * 0.1), o + Vector2(r * 0.7, -r * 0.1),
		o + Vector2(0, -r * 0.75)], Color(col.r, col.g, col.b, 0.8))
	c.draw_rect(Rect2(o + Vector2(-r * 0.18, r * 0.2), Vector2(r * 0.3, r * 0.4)),
		Color(1, 1, 1, 0.35), true)

static func _child(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(0, -r * 0.4), r * 0.36, col)
	_poly(c, [o + Vector2(-r * 0.4, r * 0.7), o + Vector2(-r * 0.35, r * 0.2),
		o + Vector2(r * 0.35, r * 0.2), o + Vector2(r * 0.4, r * 0.7)], col)


# ---------- процедурные эмблемы для новых веществ (по стабильному хешу id) ----------
# Каждая из форм — простой примитив; «семейство» выбирает хеш id, поэтому у одного
# id форма всегда одинаковая между запусками.

static func _parametric(c: CanvasItem, g: String, o: Vector2, r: float, col: Color) -> void:
	var i := 0
	while i < g.length() and g[i] >= "a" and g[i] <= "z":
		i += 1
	var base := g.substr(0, i)
	var n := 6
	var ns := g.substr(i)
	if ns != "":
		n = clampi(int(ns), 2, 12)
	match base:
		"poly": _g_polygon(c, o, r, col, n)
		"star": _g_star(c, o, r, col, n)
		"burst": _g_burst(c, o, r, col, n)
		"ring": _g_ring(c, o, r, col, n)
		"cluster": _g_cluster(c, o, r, col, n)
		"crystal": _g_crystal(c, o, r, col, n)
		"blossom": _g_blossom(c, o, r, col, n)
		"sigil": _g_sigil(c, o, r, col, n)
		"spiral": _g_spiral(c, o, r, col, n)
		"rays": _g_rays(c, o, r, col, n)
		_: _proc(c, g, o, r, col)


static func _g_polygon(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	var pts := PackedVector2Array()
	for k in n:
		var a := -PI / 2.0 + TAU * float(k) / float(n)
		pts.append(o + Vector2(cos(a), sin(a)) * r * 0.82)
	c.draw_colored_polygon(pts, col)
	var inner := PackedVector2Array()
	for k in n:
		var a := -PI / 2.0 + TAU * (float(k) + 0.5) / float(n)
		inner.append(o + Vector2(cos(a), sin(a)) * r * 0.4)
	c.draw_polyline(inner, Color(col.r, col.g, col.b, 0.45), 1.3)


static func _g_star(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	var pts := PackedVector2Array()
	for k in n * 2:
		var a := -PI / 2.0 + TAU * float(k) / float(n * 2)
		var rr := r * (0.85 if k % 2 == 0 else 0.34)
		pts.append(o + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)
	c.draw_circle(o, r * 0.12, Color(col.r, col.g, col.b, 0.5))


static func _g_burst(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	for k in n:
		var a := TAU * float(k) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal() * r * 0.09
		var p1 := o + dir * r * 0.3
		var p2 := o + dir * r * 0.85
		c.draw_colored_polygon(PackedVector2Array([p1 + side, p1 - side, p2]), col)
	c.draw_circle(o, r * 0.18, Color(col.r, col.g, col.b, 0.7))


static func _g_ring(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	var steps := maxi(n - 1, 1)
	for i in n:
		var t := float(i) / float(steps)
		var rr := r * (0.85 - 0.62 * t)
		c.draw_arc(o, rr, 0.0, TAU, 28, col, maxf(1.1, r * 0.12), true)
	c.draw_circle(o, r * 0.1, Color(col.r, col.g, col.b, 0.7))


static func _g_cluster(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	var cr := r * (0.34 if n <= 4 else 0.24)
	for k in n:
		var a := TAU * float(k) / float(n) + PI / float(n)
		c.draw_circle(o + Vector2(cos(a), sin(a)) * r * 0.46, cr, col)
	c.draw_circle(o, r * 0.2, Color(col.r, col.g, col.b, 0.6))


static func _g_crystal(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	for k in n:
		var a := -PI / 2.0 + TAU * float(k) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal() * r * 0.2
		c.draw_colored_polygon(PackedVector2Array([o + side, o - side, o + dir * r * 0.85]), col)
	c.draw_circle(o, r * 0.12, Color(col.r, col.g, col.b, 0.6))


static func _g_blossom(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	for k in n:
		var a := TAU * float(k) / float(n)
		c.draw_circle(o + Vector2(cos(a), sin(a)) * r * 0.5, r * 0.28, col)
	c.draw_circle(o, r * 0.16, Color(col.r, col.g, col.b, 0.65))


static func _g_sigil(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	for k in n:
		var a := TAU * float(k) / float(n)
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(o - dir * r * 0.75, o + dir * r * 0.75, col, maxf(1.2, r * 0.14))
	c.draw_arc(o, r * 0.6, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 1.2, true)
	c.draw_circle(o, r * 0.14, Color(col.r, col.g, col.b, 0.6))


static func _g_spiral(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	var pts := PackedVector2Array()
	var steps := 24
	var turns := float(n) * PI
	for k in steps + 1:
		var t := float(k) / float(steps)
		var a := t * turns
		var rr := r * (0.14 + 0.7 * t)
		pts.append(o + Vector2(cos(a), sin(a)) * rr)
	c.draw_polyline(pts, col, maxf(1.2, r * 0.14))
	c.draw_circle(o, r * 0.1, Color(col.r, col.g, col.b, 0.6))


static func _g_rays(c: CanvasItem, o: Vector2, r: float, col: Color, n: int) -> void:
	for k in n:
		var a := TAU * float(k) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal() * r * 0.055
		var p1 := o + dir * r * 0.55
		var p2 := o + dir * r * 0.88
		c.draw_colored_polygon(PackedVector2Array([p1 + side, p1 - side, p2]), col)
	c.draw_arc(o, r * 0.55, 0.0, TAU, 24, col, maxf(1.2, r * 0.12), true)


static func _proc(c: CanvasItem, id: String, o: Vector2, r: float, col: Color) -> void:
	var h := id.hash()
	var form := posmod(h, 6)
	var rot := float(posmod(h >> 3, 360))
	var sy := 1.0 + 0.2 * (float(posmod(h >> 5, 10)) - 5.0) / 5.0  # лёгкое сплющивание
	c.draw_set_transform(o, deg_to_rad(rot), Vector2(1.0, sy))
	match form:
		0: _gem(c, Vector2.ZERO, r, col)                # кристалл/ромб
		1: _sparkle(c, Vector2.ZERO, r, col)            # звезда-искра
		2: _orb3(c, Vector2.ZERO, r, col)               # клубок/кластер
		3: _leafblade(c, Vector2.ZERO, r, col)          # лезвие/лист
		4: _polyrock(c, Vector2.ZERO, r, col)           # камень-многоугольник
		5: _wave(c, Vector2.ZERO, r, col)               # волна/струя
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _gem(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(0, -r * 0.8), o + Vector2(r * 0.55, 0),
		o + Vector2(0, r * 0.8), o + Vector2(-r * 0.55, 0)])
	c.draw_colored_polygon(pts, col)
	c.draw_polyline(PackedVector2Array([o + Vector2(0, -r * 0.8), o + Vector2(0, r * 0.8)]),
		Color(col.r, col.g, col.b, 0.4), 1.4)

static func _sparkle(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := TAU * float(k) / 10.0
		var rr := r * (0.9 if k % 2 == 0 else 0.3)
		pts.append(o + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)
	c.draw_circle(o, r * 0.14, Color(col.r, col.g, col.b, 0.5))

static func _orb3(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_circle(o + Vector2(-r * 0.32, r * 0.1), r * 0.44, col)
	c.draw_circle(o + Vector2(r * 0.34, r * 0.14), r * 0.4, col)
	c.draw_circle(o + Vector2(0, -r * 0.42), r * 0.34, col)
	c.draw_circle(o + Vector2(0, 0), r * 0.18, Color(col.r, col.g, col.b, 0.55))

static func _leafblade(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	c.draw_colored_polygon(_lens_shape(o, r, 0.40, -r * 0.75, r * 0.75), col)
	c.draw_polyline(PackedVector2Array([o + Vector2(-r * 0.6, 0), o + Vector2(r * 0.72, 0)]),
		Color(col.r, col.g, col.b, 0.6), 1.6)

static func _polyrock(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(-r * 0.7, -r * 0.4), o + Vector2(-r * 0.4, -r * 0.7),
		o + Vector2(r * 0.45, -r * 0.6), o + Vector2(r * 0.7, r * 0.15),
		o + Vector2(r * 0.2, r * 0.7), o + Vector2(-r * 0.6, r * 0.5)])
	c.draw_colored_polygon(pts, col)
	c.draw_circle(o + Vector2(-r * 0.15, -r * 0.2), r * 0.12, Color(col.r, col.g, col.b, 0.5))

static func _wave(c: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	for i in 3:
		var y := -r * 0.45 + float(i) * r * 0.45
		var pts := PackedVector2Array()
		for k in 9:
			var t := float(k) / 8.0
			pts.append(o + Vector2(-r * 0.7 + t * r * 1.4,
				y + sin(t * PI + float(i) * 1.1) * r * 0.16))
		c.draw_polyline(pts, col, maxf(r * 0.12, 1.4))
	c.draw_circle(o + Vector2(-r * 0.4, -r * 0.5), r * 0.12,
		Color(col.r, col.g, col.b, 0.6))
