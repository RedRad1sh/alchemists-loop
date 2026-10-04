class_name TarotIcon
extends Control

## Иконка-таро для кнопки Аркана Сигилов. Процедурная, а не глиф: в Manrope
## нет ✦/⚡, на устройстве они рисуются квадратиком.

const LINE := Color(0.93, 0.80, 0.45, 0.95)
const CORNER := 4.0
const SEGMENTS := 8


## Замкнутая полилиния скруглённого прямоугольника: четыре дуги по углам.
## Углы обходятся против часовой в экранных координатах (y вниз), поэтому
## стартовые углы PI, 3PI/2, 0, PI/2 дают непрерывную линию без разрывов.
static func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	var centers := [
		Vector2(x0 + r, y0 + r), Vector2(x1 - r, y0 + r),
		Vector2(x1 - r, y1 - r), Vector2(x0 + r, y1 - r),
	]
	var starts := [PI, PI * 1.5, 0.0, PI * 0.5]
	for i in 4:
		var c: Vector2 = centers[i]
		var a0: float = starts[i]
		for s in SEGMENTS + 1:
			var a := a0 + (PI * 0.5) * float(s) / float(SEGMENTS)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	return pts


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-1.0)
	draw_polyline(_rounded_rect_points(rect, CORNER), LINE, 1.5, true)

	var c := rect.get_center()
	var rad := minf(rect.size.x, rect.size.y) * 0.5
	draw_arc(c, rad * 0.30, 0.0, TAU, 40, LINE, 1.5, true)

	# Восьмиконечная звезда: чередование внешнего и внутреннего радиуса.
	var star := PackedVector2Array()
	var outer := rad * 0.22
	var inner := outer * 0.34
	for i in 16:
		var a := TAU * float(i) / 16.0 - PI * 0.5
		var rr := outer if i % 2 == 0 else inner
		star.append(c + Vector2(cos(a), sin(a)) * rr)
	star.append(star[0])
	draw_polyline(star, LINE, 1.2, true)
