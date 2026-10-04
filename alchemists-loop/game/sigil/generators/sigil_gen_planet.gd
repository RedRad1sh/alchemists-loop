extends SigilIconGenerator
class_name SigilGenPlanet

## Тип «planet» — пиксельная планета.
##
## Сфера строится аналитически (нормаль → освещение → fbm суши), а не набором
## кружков: на 32×32 это даёт узнаваемый шар с терминатором, кольцами и
## атмосферой. Порт идеи Pixel Planet Generator, но на своём коде и в едином
## стиле с кругом (пиксель 1:1, жёсткие края, палитра из ctx).

const SUBTYPES := ["terrestrial", "desert", "ice", "gas", "molten", "moon", "ocean"]


func type_name() -> StringName:
	return &"planet"


func description() -> String:
	return "Сфера с сушей, кольцами, атмосферой; подтипы из свойств рецепта"


func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	var g := grid_for_rect(rect, ctx, 34)
	var c := SigilPixelCanvas.new(g)
	var f := float(g)
	var cx := f * 0.5
	var cy := f * 0.5

	var subtype := str(ctx.get("planet_type", rng.pick(SUBTYPES)))
	var rings := int(ctx.get("rings", rng.randi_range(0, 2) if rng.chance(0.3) else 0))
	# Сфера ужимается, если вокруг неё будут кольца: иначе они уезжают за
	# край сетки и обрезаются, и планета остаётся без кольца вообще.
	var r := f * 0.44
	if rings > 0:
		r = f * 0.39 / (1.0 + 0.26 * float(rings - 1))
	var light := Vector3(rng.randf_range(-1.0, -0.25), rng.randf_range(-1.0, -0.2), 0.8).normalized()
	var octaves := rng.randi_range(3, 5)
	var seed_off := Vector2(rng.randf() * 100.0, rng.randf() * 100.0)
	var land_ratio := float(ctx.get("land_ratio", rng.randf_range(0.28, 0.62)))

	var deep := _color(ctx, "deep", Color(0.10, 0.26, 0.52))
	var shallow := _color(ctx, "shallow", deep.lerp(Color(0.35, 0.68, 0.85), 0.55))
	var land := _color(ctx, "land", Color(0.30, 0.45, 0.24))
	var high := _color(ctx, "high", land.lerp(Color(0.85, 0.86, 0.80), 0.45))
	var ice := _color(ctx, "ice", Color(0.92, 0.95, 0.98))
	var atmos := _color(ctx, "atmosphere", deep.lerp(Color(0.6, 0.8, 1.0), 0.6))
	var outline_col := _color(ctx, "outline", Color(0.05, 0.06, 0.10))

	match subtype:
		"desert":
			land = _color(ctx, "land", Color(0.72, 0.48, 0.22))
			high = land.lerp(Color(0.92, 0.78, 0.5), 0.4)
			deep = _color(ctx, "deep", Color(0.35, 0.18, 0.12))
			shallow = deep.lerp(Color(0.8, 0.5, 0.3), 0.5)
		"ice":
			land = _color(ctx, "land", Color(0.72, 0.84, 0.90))
			high = Color(0.97, 0.99, 1.0)
			deep = _color(ctx, "deep", Color(0.16, 0.32, 0.46))
		"gas":
			land = _color(ctx, "land", Color(0.72, 0.55, 0.32))
			high = Color(0.92, 0.82, 0.58)
			deep = _color(ctx, "deep", Color(0.42, 0.26, 0.14))
		"molten":
			land = _color(ctx, "land", Color(0.28, 0.10, 0.08))
			high = Color(1.0, 0.46, 0.10)
			deep = _color(ctx, "deep", Color(0.10, 0.04, 0.05))
			ice = Color(1.0, 0.72, 0.24)
		"moon":
			land = _color(ctx, "land", Color(0.45, 0.45, 0.48))
			high = Color(0.72, 0.72, 0.74)
			deep = _color(ctx, "deep", Color(0.24, 0.24, 0.27))
			shallow = land
		"ocean":
			land_ratio = rng.randf_range(0.04, 0.16)
		"terrestrial", "ocean":
			pass

	# Атмосфера — внешний ободок, рисуем ПОСЛЕ сферы (см. ниже).
	for y in g:
		for x in g:
			var dx := (float(x) + 0.5 - cx) / r
			var dy := (float(y) + 0.5 - cy) / r
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var z := sqrt(maxf(1.0 - d2, 0.0))
			var n := _fbm(Vector2(dx, dy) * 2.6 + seed_off, octaves)
			var n2 := _fbm(Vector2(dx, dy) * 6.1 + seed_off * 1.7, 3)
			var col := deep

			if subtype == "gas":
				# Полосы по широте + турбулентность.
				var band := sin((dy + n * 0.35) * 11.0) * 0.5 + 0.5
				col = deep.lerp(land, band * 0.75 + n2 * 0.2)
				col = col.lerp(high, clampf((n2 - 0.55) * 2.2, 0.0, 1.0) * 0.5)
			else:
				var h := n * 0.5 + 0.5
				if subtype == "moon":
					col = deep.lerp(land, h)
					col = col.lerp(high, clampf((n2 - 0.6) * 2.0, 0.0, 1.0) * 0.7)
					# Кратеры.
					if n2 > 0.78 and fmod(n2 * 97.0, 1.0) < 0.25:
						col = col.lerp(deep, 0.55)
				else:
					var sea := h > land_ratio
					if sea:
						col = deep.lerp(shallow, clampf((h - land_ratio) / 0.12, 0.0, 1.0))
					else:
						var elev := 1.0 - h / maxf(land_ratio, 0.001)
						col = land.lerp(high, clampf((elev - 0.35) * 1.6, 0.0, 1.0))
					# Полярные шапки.
					var lat := absf(dy)
					if lat > 0.74:
						col = col.lerp(ice, clampf((lat - 0.74) / 0.22, 0.0, 1.0))
					# Облака.
					if n2 > 0.72 and subtype != "ice":
						col = col.lerp(Color(1, 1, 1), clampf((n2 - 0.72) * 3.0, 0.0, 1.0) * 0.55)

			# Освещение: Lambert + лёгкий римский контровой терминатор.
			var nrm := Vector3(dx, dy, z)
			var lam := maxf(nrm.dot(light), 0.0)
			var term := smoothstep(-0.12, 0.30, nrm.dot(light))
			col = col.lerp(Color(0, 0, 0), (1.0 - term) * 0.55)
			col = col.lerp(Color(1, 1, 1), pow(lam, 3.0) * 0.22)
			c.set_px(x, y, col)

	# Атмосферный ободок: пиксели с d2 в (1.0, 1.25].
	for y in g:
		for x in g:
			var dx2 := (float(x) + 0.5 - cx) / r
			var dy2 := (float(y) + 0.5 - cy) / r
			var dd := dx2 * dx2 + dy2 * dy2
			if dd > 1.0 and dd < 1.22:
				var a := (1.0 - (dd - 1.0) / 0.22) * 0.55
				c.set_px(x, y, Color(atmos.r, atmos.g, atmos.b, a))

	# Кольца — рисуем ДО сферы, чтобы планета перекрывала заднюю дугу.
	if rings > 0:
		var ring_col := _color(ctx, "ring", land.lerp(ice, 0.6))
		ring_col.a = 0.85
		var tilt := rng.randf_range(0.18, 0.42)
		for k in rings:
			var rr := r * (1.28 + 0.26 * float(k))
			for i in g * 3:
				var t := TAU * float(i) / float(g * 3)
				var px := cx + cos(t) * rr
				var py := cy + sin(t) * rr * tilt
				var th := maxf(0.9, r * 0.055)
				for oy in range(int(ceilf(-th)), int(floorf(th)) + 1):
					var yy := int(floorf(py)) + oy
					var xx := int(floorf(px))
					if c.in_bounds(xx, yy):
						var ddx := float(xx) + 0.5 - px
						var ddy := float(yy) + 0.5 - py
						if ddx * ddx + ddy * ddy <= th * th:
							var shade := 0.75 + 0.25 * (oy / maxf(th, 0.001))
							c.set_px(xx, yy, Color(ring_col.r * shade, ring_col.g * shade,
								ring_col.b * shade, 0.9))

	c.outline(outline_col, true)
	c.draw(ci, rect)


func grid_for_rect(rect: Rect2, ctx: Dictionary, fallback: int) -> int:
	var g := int(ctx.get("pixel_grid", 0))
	if g <= 0:
		g = clampi(int(floorf(minf(rect.size.x, rect.size.y) / 2.0)), 14, fallback)
	return clampi(g, 12, 80)


func _color(ctx: Dictionary, key: String, fallback: Color) -> Color:
	var p: Dictionary = ctx.get("icon_palette", {})
	return (p[key] as Color) if p.has(key) else fallback


func _fbm(p: Vector2, octaves: int) -> float:
	var v := 0.0
	var amp := 0.5
	var q := p
	for i in octaves:
		v += amp * _noise(q)
		q = q * 2.07 + Vector2(13.1, 7.3)
		amp *= 0.5
	return v


func _noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	# Сглаживание покомпонентное: скалярное «3 - 2f» по вектору не определено.
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	return lerpf(lerpf(_hash(i), _hash(i + Vector2(1, 0)), u.x),
		lerpf(_hash(i + Vector2(0, 1)), _hash(i + Vector2(1, 1)), u.x), u.y) * 2.0 - 1.0


func _hash(i: Vector2) -> float:
	var h := i.x * 374761393.0 + i.y * 668265263.0
	h = fmod(h * 1274126177.0, 2147483647.0)
	return absf(h) / 2147483647.0
