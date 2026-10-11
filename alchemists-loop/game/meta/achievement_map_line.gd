extends "res://addons/medusa/resources/graph_lines/graph_line.gd"
class_name AchievementMapLine

@export var line_color: Color = Color("#526673")
@export var highlighted_line_color: Color = Color("#e8cf8b")
@export_range(1.0, 5.0, 0.25) var line_width: float = 2.0


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	if not context.get("connection", true):
		return
	var color_to_draw := highlighted_line_color if context.get("highlighted", false) else line_color
	color_to_draw.a *= float(context.get("alpha", 1.0))
	canvas.draw_line(start, end, color_to_draw, line_width, true)
	canvas.draw_circle(start.lerp(end, 0.5), 2.0, color_to_draw)
