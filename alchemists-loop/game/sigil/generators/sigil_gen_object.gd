extends SigilIconGenerator
class_name SigilGenObject

## Тип «object» — предмет/артефакт.
##
## Раньше был векторным: сплошные заливки многоугольников. Среди соседей —
## пиксельных планет, существ и реликвий — он выбивался и читался как
## «нарисованный в пейнте». Теперь это тот же пиксельный холст и тот же
## проход подсветки, что у [SigilGenRelic], поэтому весь ряд читается как
## одна семья. Имена форм сохранены — старые рецепты продолжают работать.

const FORMS := ["vessel", "gem", "tablet", "idol", "orb", "relic"]


func type_name() -> StringName:
	return &"object"


func description() -> String:
	return "Пиксельный предмет: сосуд, самоцвет, скрижаль, идол, сфера, реликвия"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	var g := grid_for(rect, ctx, 34)
	var c := SigilPixelCanvas.new(g)
	var f := float(g)
	var cx := f * 0.5
	var cy := f * 0.5
	var r := f * 0.42

	var body := palette(ctx, "body", Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.7), rng.randf_range(0.5, 0.9)))
	var dark := body.lerp(Color(0, 0, 0), 0.55)
	var deep := body.lerp(Color(0.05, 0.06, 0.12), 0.72)
	var hi := body.lerp(Color(1, 1, 1), 0.62)
	var accent := palette(ctx, "accent", Color.from_hsv(fposmod(_hue_of(body) + 0.5, 1.0), 0.8, 0.95))

	match str(ctx.get("form", FORMS[rng.randi_range(0, FORMS.size() - 1)])):
		"vessel":
			_vessel(c, cx, cy, r, rng, body, deep, dark, hi, accent)
		"gem":
			_gem(c, cx, cy, r, rng, body, deep, dark, hi, accent)
		"tablet":
			_tablet(c, cx, cy, r, rng, body, deep, dark, hi, accent)
		"idol":
			_idol(c, cx, cy, r, rng, body, deep, dark, hi, accent)
		"orb":
			_orb(c, cx, cy, r, rng, body, deep, dark, hi, accent)
		_:
			_relic(c, cx, cy, r, rng, body, deep, dark, hi, accent)

	c.shade_highlight(Vector2(cx, cy), r, hi, 0.12, 0.55)
	c.outline(deep)
	c.draw(ci, rect)


func _hue_of(c: Color) -> float:
	return c.h


## Колба: узкое горло, раздутое брюхо, уровень жидкости, пробка, блик на стекле.
func _vessel(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	var neck := r * rng.randf_range(0.16, 0.24)
	var top := cy - r * 0.92
	var belly := cy + r * 0.88
	var by := cy + r * 0.28
	var br := r * 0.72

	c.fill_rect(int(cx - neck), int(top), int(cx + neck), int(by - br * 0.2), body.lerp(Color(1, 1, 1), 0.18))
	c.ellipse(cx, by, br, br, body.lerp(Color(1, 1, 1), 0.18))

	# Жидкость: нижняя часть брюха, ширина по эллиптическому сечению.
	var level := by - br * rng.randf_range(0.0, 0.5)
	for y in range(int(level), int(belly + br * 0.7)):
		var t := (float(y) + 0.5 - by) / br
		if absf(t) >= 1.0:
			continue
		var hw := br * sqrt(maxf(1.0 - t * t, 0.0))
		c.fill_rect(int(cx - hw), y, int(cx + hw), y, accent)
	# Мениск.
	c.fill_rect(int(cx - br * 0.55), int(level) - 1, int(cx + br * 0.55), int(level), hi)

	# Пробка.
	c.fill_rect(int(cx - neck * 1.35), int(top - r * 0.14), int(cx + neck * 1.35), int(top), dark)
	c.fill_rect(int(cx - neck * 1.35), int(top - r * 0.14), int(cx + neck * 1.35), int(top - r * 0.10), hi)
	# Блик на стекле.
	for y in range(int(top + r * 0.2), int(belly)):
		var yy := float(y) + 0.5
		if yy < by - br * 0.2:
			c.set_px(int(cx - neck * 0.62), y, hi)
		else:
			var tt := (yy - by) / br
			if absf(tt) < 1.0:
				c.set_px(int(cx - br * 0.62 * sqrt(maxf(1.0 - tt * tt, 0.0))), y, hi)


## Самоцвет огранкой «бриллиант»: площадка, корона, пояс, калетта.
## Объём несут чередующиеся по светлоте грани, а не общий градиент:
## мягкий блик поверх граней превращал камень в шар.
func _gem(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	var sides := rng.randi_range(6, 9)
	var y_tab := cy - r * 0.46
	var y_gir := cy
	var table := PackedVector2Array()
	var girdle := PackedVector2Array()
	for i in sides:
		var a := -PI * 0.5 + TAU * float(i) / float(sides)
		# Пояс и площадка сплющены снизу, иначе нижняя вершина многоугольника
		# выходит ниже калетты и низ камня срезается вместо острия.
		var pt := SigilGeometry.polar(Vector2(cx, y_tab), r * 0.46, a)
		table.append(Vector2(pt.x, minf(pt.y, y_tab)))
		var pg := SigilGeometry.polar(Vector2(cx, y_gir), r, a)
		girdle.append(Vector2(pg.x, minf(pg.y, y_gir)))
	var culet := Vector2(cx, cy + r * 0.94)
	c.fill_polygon(table, body.lerp(hi, 0.46))
	for i in sides:
		var j := (i + 1) % sides
		# Корона: чередующиеся светлая и тёмная трапеции.
		var crown := body.lerp(hi, 0.24) if i % 2 == 0 else body.lerp(deep, 0.30)
		c.fill_polygon(PackedVector2Array([table[i], table[j], girdle[j], girdle[i]]), crown)
		# Павильон: треугольники к острию.
		var pav := body.lerp(hi, 0.10) if i % 2 == 0 else body.lerp(deep, 0.46)
		c.fill_polygon(PackedVector2Array([girdle[i], girdle[j], culet]), pav)
		c.line(girdle[i].x, girdle[i].y, girdle[j].x, girdle[j].y, dark)
		c.line(table[i].x, table[i].y, girdle[i].x, girdle[i].y, body.lerp(deep, 0.55))
	# Искра на площадке.
	c.disc(cx - r * 0.16, y_tab - r * 0.02, r * 0.15, Color(1, 1, 1, 0.50), true)
	c.disc(cx - r * 0.16, y_tab - r * 0.02, r * 0.07, Color(1, 1, 1, 0.75), true)


## Скрижаль: плита с двойной рамкой и строки рун.
func _tablet(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	var hw := r * 0.62
	var hh := r * 0.92
	c.fill_rect(int(cx - hw), int(cy - hh), int(cx + hw), int(cy + hh), body)
	c.fill_rect(int(cx - hw), int(cy - hh), int(cx + hw), int(cy - hh + maxf(1.0, r * 0.09)), hi)
	c.fill_rect(int(cx - hw), int(cy + hh - maxf(1.0, r * 0.09)), int(cx + hw), int(cy + hh), dark)
	var inset := maxf(1.0, r * 0.13)
	c.fill_rect(int(cx - hw + inset), int(cy - hh + inset), int(cx + hw - inset), int(cy + hh - inset), deep)
	c.fill_rect(int(cx - hw + inset), int(cy - hh + inset), int(cx + hw - inset),
		int(cy - hh + inset * 1.8), body.lerp(hi, 0.3))
	# Руны: строки разной длины + центральный знак.
	var lines := rng.randi_range(3, 4)
	for i in lines:
		var y := cy - hh * 0.5 + float(i) * (hh * 0.9) / float(lines)
		var w := hw * rng.randf_range(0.45, 0.75)
		c.fill_rect(int(cx - w), int(y), int(cx + w), int(y + maxf(1.0, r * 0.07)), hi)
	# Знак в верхней трети.
	var mark := rng.randi_range(0, 2)
	if mark == 0:
		c.ring(cx, cy - hh * 0.55, r * 0.16, maxf(1.0, r * 0.06), accent)
	elif mark == 1:
		for i in 3:
			c.line(cx, cy - hh * 0.55 - r * 0.16, cx + cos(PI * 0.5 + TAU * float(i) / 3.0) * r * 0.18,
				cy - hh * 0.55 + sin(PI * 0.5 + TAU * float(i) / 3.0) * r * 0.18, accent)
	else:
		c.disc(cx, cy - hh * 0.55, r * 0.12, accent)


## Идол: стойкая фигура с рогами и подставкой.
func _idol(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	var head_y := cy - r * 0.62
	var head_r := r * 0.24
	c.ellipse(cx, head_y, head_r, head_r * 1.1, body)
	c.ellipse(cx, cy + r * 0.34, r * 0.34, r * 0.52, body)
	c.ellipse(cx, cy + r * 0.34, r * 0.20, r * 0.40, body.lerp(hi, 0.22))
	c.fill_rect(int(cx - r * 0.52), int(cy + r * 0.80), int(cx + r * 0.52), int(cy + r * 0.92), dark)
	# Тень на дальней стороне фигуры.
	c.ellipse(cx + r * 0.10, cy + r * 0.34, r * 0.26, r * 0.44, deep)
	c.ellipse(cx, cy + r * 0.34, r * 0.34, r * 0.52, body)
	c.ellipse(cx - r * 0.04, cy + r * 0.34, r * 0.22, r * 0.40, body.lerp(hi, 0.22))
	# Руки.
	c.line(cx - r * 0.28, cy - r * 0.12, cx - r * 0.58, cy + r * 0.26, body)
	c.line(cx + r * 0.28, cy - r * 0.12, cx + r * 0.58, cy + r * 0.26, body)
	# Рога.
	for s in [-1.0, 1.0]:
		c.line(cx + s * head_r * 0.85, head_y - head_r * 0.6,
			cx + s * head_r * 1.35, head_y - head_r * 1.15, accent)
	# Глаза.
	c.set_px(int(cx - head_r * 0.42), int(head_y), accent)
	c.set_px(int(cx + head_r * 0.42), int(head_y), accent)
	c.line(cx, head_y - head_r * 0.4, cx, head_y + head_r * 0.4, dark)


## Сфера: градиент, меридианы, блик, тень снизу.
func _orb(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	var lx := rng.randf_range(-1.0, -0.4)
	var ly := rng.randf_range(-1.0, -0.3)
	var ll := sqrt(lx * lx + ly * ly)
	if ll < 0.0001:
		ll = 1.0
	lx /= ll
	ly /= ll
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			var dx := (float(x) + 0.5 - cx) / r
			var dy := (float(y) + 0.5 - cy) / r
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var z := sqrt(maxf(1.0 - d2, 0.0))
			var lam := maxf(0.0, dx * lx + dy * ly + z * 0.75)
			# У терминатора уходим в deep — иначе край сферы сливается с фоном.
			c.set_px(x, y, body.lerp(dark, clampf(lam * 1.3, 0.0, 1.0) * 0.55)
				.lerp(deep, clampf(1.0 - lam * 2.0, 0.0, 1.0)))
	# Меридианы и экватор.
	for i in 3:
		var t := float(i - 1) * 0.42
		var w := r * 0.6 * (1.0 - absf(t) * 0.6)
		for y in range(int(cy - r), int(cy + r) + 1):
			var yy := (float(y) + 0.5 - cy) / r
			if absf(yy) < 1.0:
				c.set_px(int(cx + w * sqrt(maxf(1.0 - yy * yy, 0.0)) * (1.0 if i == 1 else 0.55)),
					y, body.lerp(dark, 0.55))
	for x in range(int(cx - r), int(cx + r) + 1):
		var xx := (float(x) + 0.5 - cx) / r
		if absf(xx) <= 1.0:
			c.set_px(x, int(cy + r * 0.12 * (1.0 - xx * xx)), body.lerp(dark, 0.5))
	# Спекуляр.
	c.disc(cx + lx * r * 0.42, cy + ly * r * 0.42, r * 0.16, Color(1, 1, 1, 0.75), true)
	c.disc(cx + lx * r * 0.40, cy + ly * r * 0.40, r * 0.07, Color(1, 1, 1, 0.95))


## Реликвия: кольца, спицы, самоцвет в центре.
func _relic(c: SigilPixelCanvas, cx: float, cy: float, r: float, rng: SigilRng,
		body: Color, deep: Color, dark: Color, hi: Color, accent: Color) -> void:
	c.ring(cx, cy, r * 0.92, maxf(1.0, r * 0.10), body)
	c.ring(cx, cy, r * 0.60, maxf(1.0, r * 0.06), deep)
	var spokes := rng.randi_range(6, 9)
	for i in spokes:
		var a := TAU * float(i) / float(spokes) + rng.randf_range(-0.1, 0.1)
		c.line(cx + cos(a) * r * 0.30, cy + sin(a) * r * 0.30,
			cx + cos(a) * r * 0.88, cy + sin(a) * r * 0.88, body.lerp(dark, 0.35))
	c.disc(cx, cy, r * 0.24, accent)
	c.ring(cx, cy, r * 0.24, maxf(1.0, r * 0.05), hi)
	c.ring(cx, cy, r * 1.0, maxf(1.0, r * 0.04), body.lerp(hi, 0.3))
