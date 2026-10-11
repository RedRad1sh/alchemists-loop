extends Control
class_name VeinDrop
# Капля находки жилы: рисуется процедурно (без спрайтов, §1.5). Статусы:
# pending_server («Ждёт связи», полупрозрачная), registered (налитая, тап = влить),
# poured / auto_applied (галочка).

var drop_color := Color(0.6, 0.75, 0.9)
var status := "registered"

func setup(col: Color, st: String) -> void:
	drop_color = col
	status = st
	custom_minimum_size = Vector2(28, 34)
	queue_redraw()

func _draw() -> void:
	var c := size * Vector2(0.5, 0.55)
	var r := minf(size.x, size.y) * 0.38
	var a := 0.5 if status == "pending_server" else 0.95
	draw_circle(c + Vector2(0, r * 0.35), r, Color(drop_color.r, drop_color.g, drop_color.b, a))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.72, r * 0.18), c + Vector2(0, -r * 1.25),
		c + Vector2(r * 0.72, r * 0.18)]), Color(drop_color.r, drop_color.g, drop_color.b, a))
	if status == "poured" or status == "auto_applied":
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.9),
			c + Vector2(-r * 0.05, r * 1.4), c + Vector2(r * 0.8, r * 0.1)]),
			Color(0.55, 0.95, 0.6, 0.95), 2.4)
