extends Control
class_name CircleRankSymbol
# Символ-ранг «Огонёк очага» (§2.2): процедурный, 7 форм, без анимации в v1.

var level := 0

func setup(lvl: int) -> void:
	level = lvl
	custom_minimum_size = Vector2(64, 64)
	queue_redraw()

## Толщина силуэта (спека крафта §A): тёмная нижняя грань и светлый верхний срез
## рисуются теми же контурами со сдвигом по вертикали, поэтому одна форма даёт
## «штампованную монету», а не плоскую заливку из пеинта.
const FACE_DY := -1.4
const SHADOWS := [
	[Vector2(2.0, 3.0), Color(0.05, 0.02, 0.01, 0.30)],
	[Vector2(1.3, 2.0), Color(0.05, 0.02, 0.01, 0.18)],
	[Vector2(0.7, 1.0), Color(0.05, 0.02, 0.01, 0.08)],
]
## Латунный обод: без него насыщенный символ ранга читается красным пятном на
## ореховой доске. Обод — металл палитры доски, не новый цвет.
const RIM_INK := Color(0.62, 0.45, 0.20)
const RIM_K := 1.16

func _draw() -> void:
	if level < 1:
		return
	var rk := {}
	for r in Game.CIRCLE_RANKS:
		if int(r["level"]) == level:
			rk = r
	if rk.is_empty():
		return
	var shape := String(rk["shape"])
	var col := Color(String(rk["color"]))
	for s in SHADOWS:
		_shape(shape, size * 0.5 + (s[0] as Vector2), s[1] as Color, RIM_K)
	var c := size * 0.5
	_shape(shape, c + Vector2(0.0, 0.8), RIM_INK, RIM_K)
	_shape(shape, c, col.darkened(0.45))
	_shape(shape, c + Vector2(0.0, FACE_DY - 1.0), col.lightened(0.32))
	_shape(shape, c + Vector2(0.0, FACE_DY), col)

## Одна отливка символа: центр `c`, чернила `col`, масштаб силуэта `mul`.
func _shape(shape: String, c: Vector2, col: Color, mul: float = 1.0) -> void:
	var rr := minf(size.x, size.y) * 0.36 * mul
	match shape:
		"dot":
			draw_circle(c, rr * 0.30, col)
		"circle":
			draw_circle(c, rr * 0.55, col)
		"triangle":
			draw_colored_polygon(_poly(c, [Vector2(0, -rr),
				Vector2(rr * 0.87, rr * 0.5), Vector2(-rr * 0.87, rr * 0.5)]), col)
		"square":
			draw_colored_polygon(_poly(c, [Vector2(-rr * 0.75, -rr * 0.75),
				Vector2(rr * 0.75, -rr * 0.75), Vector2(rr * 0.75, rr * 0.75),
				Vector2(-rr * 0.75, rr * 0.75)]), col)
		"diamond":
			draw_colored_polygon(_poly(c, [Vector2(0, -rr), Vector2(rr * 0.7, 0),
				Vector2(0, rr), Vector2(-rr * 0.7, 0)]), col)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var a := TAU * float(k) / 10.0 - PI / 2.0
				var rad := rr if k % 2 == 0 else rr * 0.42
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			draw_colored_polygon(pts, col)
		"flame":
			ElementGlyphs.draw(self, "fire", c, rr, col)

func _poly(c: Vector2, offs: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for o in offs:
		pts.append(c + (o as Vector2))
	return pts
