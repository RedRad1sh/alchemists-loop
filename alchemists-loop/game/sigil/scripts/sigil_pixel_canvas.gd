class_name SigilPixelCanvas
extends RefCounted

## Пиксельный холст для генераторов центрального объекта.
## Пиксели склеиваются в горизонтальные отрезки при выводе — на карточке
## 32×32 это 1024 draw_rect'ов превращаются в ~150.

var grid: int = 32
var _px: Dictionary = {}   # Vector2i -> Color


func _init(p_grid: int = 32) -> void:
	grid = maxi(p_grid, 4)


func clear() -> void:
	_px.clear()


func set_px(x: int, y: int, c: Color) -> void:
	## Пиксель ставится по правилу «поверх» (source-over), а не затирается.
	## Из-за перезаписи полупрозрачные слои (атмосфера, блики, кольца) стирали
	## то, что под ними, и объект вырождался в одно пятно.
	if c.a <= 0.0:
		return
	var key := Vector2i(x, y)
	if c.a >= 0.999 or not _px.has(key):
		_px[key] = c
		return
	var d: Color = _px[key]
	_px[key] = Color(
		lerpf(d.r, c.r, c.a),
		lerpf(d.g, c.g, c.a),
		lerpf(d.b, c.b, c.a),
		maxf(d.a, c.a))


func get_px(x: int, y: int) -> Color:
	return _px.get(Vector2i(x, y), Color(0, 0, 0, 0))


func has_px(x: int, y: int) -> bool:
	return _px.has(Vector2i(x, y))


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < grid and y < grid


func fill_rect(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			set_px(x, y, c)


func disc(cx: float, cy: float, r: float, c: Color, feather: bool = false) -> void:
	var r2 := r * r
	for y in range(floori(cy - r) - 1, ceili(cy + r) + 2):
		for x in range(floori(cx - r) - 1, ceili(cx + r) + 2):
			var d2 := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length_squared()
			if d2 <= r2:
				set_px(x, y, c)
			elif feather and d2 <= r2 * 1.35:
				var t := 1.0 - (d2 - r2) / (r2 * 0.35)
				set_px(x, y, Color(c.r, c.g, c.b, c.a * clampf(t, 0.0, 1.0)))


func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for y in range(floori(cy - ry) - 1, ceili(cy + ry) + 2):
		for x in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
			var nx := (float(x) + 0.5 - cx) / rx
			var ny := (float(y) + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				set_px(x, y, c)


func ring(cx: float, cy: float, r: float, thickness: float, c: Color) -> void:
	var ro := r + thickness * 0.5
	var ri := maxf(r - thickness * 0.5, 0.0)
	for y in range(floori(cy - ro) - 1, ceili(cy + ro) + 2):
		for x in range(floori(cx - ro) - 1, ceili(cx + ro) + 2):
			var d := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length()
			if d >= ri and d <= ro:
				set_px(x, y, c)


func line(x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	var steps := maxi(int(maxf(absf(x1 - x0), absf(y1 - y0))), 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		set_px(int(floor(lerpf(x0, x1, t))), int(floor(lerpf(y0, y1, t))), c)


func blit_mirror_x(x: int, y: int, c: Color) -> void:
	## Билиateralная симметрия: пиксель и его зеркало по вертикали.
	set_px(x, y, c)
	set_px(grid - 1 - x, y, c)


func shade(c: Color, amount: float) -> Color:
	if amount >= 0.0:
		return c.lerp(Color(1, 1, 1), clampf(amount, 0.0, 1.0))
	return c.lerp(Color(0, 0, 0), clampf(-amount, 0.0, 1.0))


func draw(ci: CanvasItem, rect: Rect2) -> void:
	## Вывод в прямоугольник: целочисленная ячейка, отрезки по горизонтали.
	if _px.is_empty():
		return
	var cell := floorf(minf(rect.size.x, rect.size.y) / float(grid))
	if cell < 1.0:
		cell = 1.0
	var used := cell * float(grid)
	var origin := rect.position + (rect.size - Vector2(used, used)) * 0.5
	for y in grid:
		var run_start := -1
		var run_color := Color(0, 0, 0, 0)
		for x in grid + 1:
			var has := x < grid and _px.has(Vector2i(x, y))
			var col: Color = _px.get(Vector2i(x, y), Color(0, 0, 0, 0)) if has else Color(0, 0, 0, 0)
			if has and run_start < 0:
				run_start = x
				run_color = col
			elif run_start >= 0 and (not has or not col.is_equal_approx(run_color)):
				ci.draw_rect(Rect2(origin + Vector2(float(run_start) * cell, float(y) * cell),
					Vector2(float(x - run_start) * cell, cell)), run_color, true)
				run_start = -1
				if has:
					run_start = x
					run_color = col


func to_image() -> Image:
	var img := Image.create(grid, grid, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for key in _px:
		img.set_pixelv(key, _px[key])
	return img


func count() -> int:
	return _px.size()


## Заливка выпуклого многоугольника по горизонтальным сечениям.
## Заливка «по столбцам» даёт рваный силуэт на пиксельной сетке.
func fill_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	# У PackedFloat32Array в Godot 4.3 нет min()/max(), поэтому экстремумы
	# считаем вручную по исходным точкам.
	var y0 := int(floorf(points[0].y))
	var y1 := int(ceilf(points[0].y))
	for p in points:
		y0 = mini(y0, int(floorf(p.y)))
		y1 = maxi(y1, int(ceilf(p.y)))
	for y in range(y0, y1 + 1):
		var yc := float(y) + 0.5
		var xs := PackedFloat32Array()
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= yc and yc < b.y) or (b.y <= yc and yc < a.y):
				xs.append(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y))
		if xs.size() < 2:
			continue
		var lo := int(floorf(xs[0]))
		var hi := int(ceilf(xs[0]))
		for xv in xs:
			lo = mini(lo, int(floorf(xv)))
			hi = maxi(hi, int(ceilf(xv)))
		for x in range(lo, hi + 1):
			set_px(x, y, color)


## Проход подсветки: осветляет центр объекта, затухая к краю.
## Именно он даёт пиксельному объекту объём и отрывает его от фона —
## без него генератор выглядит как «нарисованный в пейнте».
func shade_highlight(center: Vector2, radius: float, color: Color,
		strength: float = 0.12, reach: float = 0.55) -> void:
	for y in grid:
		for x in grid:
			var key := Vector2i(x, y)
			if not _px.has(key):
				continue
			var col: Color = _px[key]
			if col.a <= 0.3:
				continue
			var d := Vector2(float(x) + 0.5 - center.x, float(y) + 0.5 - center.y).length() \
				/ maxf(radius, 1.0)
			if d < reach:
				_px[key] = col.lerp(color, strength * (1.0 - d / reach))


## Обводка: пиксель рядом с закрашенным, но сам пустой, получает цвет контура.
func outline(color: Color) -> void:
	var filled := {}
	for k in _px.keys():
		filled[k] = true
	for y in range(-1, grid + 1):
		for x in range(-1, grid + 1):
			if filled.has(Vector2i(x, y)):
				continue
			for o in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
				if filled.has(Vector2i(x, y) + o):
					if not filled.has(Vector2i(x, y)):
						set_px(x, y, color)
					break
