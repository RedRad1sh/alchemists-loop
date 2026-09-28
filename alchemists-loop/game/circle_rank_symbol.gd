extends Control
class_name CircleRankSymbol
# Символ-ранг «Огонёк очага» (§2.2): процедурный, 7 форм, без анимации в v1.

var level := 0

func setup(lvl: int) -> void:
	level = lvl
	custom_minimum_size = Vector2(64, 64)
	queue_redraw()

func _draw() -> void:
	if level < 1:
		return
	var rk := {}
	for r in Game.CIRCLE_RANKS:
		if int(r["level"]) == level:
			rk = r
	if rk.is_empty():
		return
	var c := size * 0.5
	var rr := minf(size.x, size.y) * 0.36
	var col := Color(String(rk["color"]))
	match String(rk["shape"]):
		"dot":
			draw_circle(c, rr * 0.30, col)
		"circle":
			draw_circle(c, rr * 0.55, col)
		"triangle":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rr),
				c + Vector2(rr * 0.87, rr * 0.5), c + Vector2(-rr * 0.87, rr * 0.5)]), col)
		"square":
			draw_rect(Rect2(c - Vector2(rr * 0.75, rr * 0.75), Vector2(rr * 1.5, rr * 1.5)), col)
		"diamond":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rr), c + Vector2(rr * 0.7, 0),
				c + Vector2(0, rr), c + Vector2(-rr * 0.7, 0)]), col)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var a := TAU * float(k) / 10.0 - PI / 2.0
				var rad := rr if k % 2 == 0 else rr * 0.42
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			draw_colored_polygon(pts, col)
		"flame":
			ElementGlyphs.draw(self, "fire", c, rr, col)
