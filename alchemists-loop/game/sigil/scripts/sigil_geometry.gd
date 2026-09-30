class_name SigilGeometry
extends RefCounted

## Чистая геометрия круга. Ни одного draw_* — только числа.
## Благодаря этому layout можно проверять тестами, а крафтовый UI может
## брать позиции слотов, ничего не рисуя.

static func polar(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * radius


static func regular_polygon(center: Vector2, radius: float, sides: int, offset: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(polar(center, radius, offset + TAU * float(i) / float(sides)))
	return pts


static func star_polygon(center: Vector2, r_outer: float, r_inner: float, points: int, offset: float = -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := r_outer if i % 2 == 0 else r_inner
		pts.append(polar(center, r, offset + PI * float(i) / float(points)))
	return pts


static func arc_points(center: Vector2, radius: float, a0: float, a1: float, segments: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		pts.append(polar(center, radius, lerpf(a0, a1, float(i) / float(segments))))
	return pts


static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() >= 2:
		out.append(out[0])
	return out


static func dashed_line(from: Vector2, to: Vector2, dash: float, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var delta := to - from
	var len := delta.length()
	if len < 0.001:
		return out
	var dir := delta / len
	var t := 0.0
	while t < len:
		var t2 := minf(t + dash, len)
		out.append(from + dir * t)
		out.append(from + dir * t2)
		t = t2 + gap
	return out


static func dashed_arc(center: Vector2, radius: float, a0: float, a1: float, segments: int, duty: float = 0.5) -> PackedVector2Array:
	## Дуга с разрывами. duty = доля сегмента «рисуем».
	var out := PackedVector2Array()
	var step := (a1 - a0) / float(segments)
	for i in segments:
		if fmod(float(i) / float(segments), 1.0) < duty:
			continue
		var s0 := a0 + step * float(i)
		var s1 := s0 + step * duty
		out.append(polar(center, radius, s0))
		out.append(polar(center, radius, s1))
	return out


static func chord(from_angle: float, to_angle: float, r_in: float, r_out: float, center: Vector2) -> PackedVector2Array:
	## Дуга-мостик между двумя секторами: внешняя дуга + две радиальные черты.
	var pts := PackedVector2Array()
	var s0 := minf(from_angle, to_angle)
	var s1 := maxf(from_angle, to_angle)
	for p in arc_points(center, r_out, s0, s1, 12):
		pts.append(p)
	pts.append(polar(center, r_in, s1))
	pts.append(polar(center, r_in, s0))
	return closed(pts)


static func rounded_rect_points(rect: Rect2, radius: float, segments: int = 4) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
	]
	for c in corners:
		var ctr: Vector2 = c[0]
		var a0: float = c[1]
		for p in arc_points(ctr, r, a0, a0 + PI * 0.5, segments):
			pts.append(p)
	return closed(pts)


static func rotate_about(points: PackedVector2Array, center: Vector2, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(center + (p - center).rotated(angle))
	return out


static func scale_about(points: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(center + (p - center) * factor)
	return out


static func spread_angles(count: int, total: int, offset: float) -> PackedFloat32Array:
	## Равномерно (с шагом, кратным total/count) распределяет count углов.
	## Слоты ингредиентов не слипаются в одной половине круга.
	var out := PackedFloat32Array()
	if count <= 0 or total <= 0:
		return out
	var step := int(floor(float(total) / float(count)))
	if step < 1:
		step = 1
	var start := (total - step * count) / 2
	for i in count:
		out.append(offset + TAU * float(start + step * i + step * 0.5) / float(total))
	return out


static func hash_points(points: PackedVector2Array) -> String:
	# У PackedFloat32Array в Godot 4.3 нет hex_encode(), поэтому строка
	# собирается вручную. Шаг 0.001 снимает дрожание от порядка сложения.
	var parts := PackedStringArray()
	for p in points:
		parts.append("%.3f,%.3f" % [snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
	return "|".join(parts)
