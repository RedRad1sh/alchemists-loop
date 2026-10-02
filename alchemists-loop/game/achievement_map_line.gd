extends "res://addons/medusa/resources/graph_lines/graph_line.gd"
class_name AchievementMapLine

@export var line_color: Color = Color("#526673")
@export var highlighted_line_color: Color = Color("#e8cf8b")
@export_range(1.0, 5.0, 0.25) var line_width: float = 2.0


func draw(canvas: Control, start: Vector2, end: Vector2, context: Dictionary = {}) -> void:
	var has_connection: bool = context.get("connection", false)
	var is_highlighted: bool = context.get("highlighted", false)
	var alpha := float(context.get("alpha", 1.0))
	
	if has_connection:
		# UI/UX: thicker, brighter lines for actual connections
		var color_to_draw := highlighted_line_color if is_highlighted else line_color
		color_to_draw.a *= alpha
		var width := line_width * (1.5 if is_highlighted else 1.2)
		canvas.draw_line(start, end, color_to_draw, width, true)
		
		# UI/UX: small dots along the connection for visual interest
		var mid := start.lerp(end, 0.33)
		var mid2 := start.lerp(end, 0.67)
		var dot_color := color_to_draw
		dot_color.a *= 0.7
		canvas.draw_circle(mid, 2.5, dot_color)
		canvas.draw_circle(mid2, 2.5, dot_color)
	else:
		# UI/UX: dotted/dashed lines for non-connections (visual hint of potential path)
		var color_to_draw := line_color
		color_to_draw.a *= alpha * 0.4  # Much more transparent
		var distance := start.distance_to(end)
		var dot_spacing := 8.0
		var num_dots := int(distance / dot_spacing)
		for i in range(num_dots):
			var t := float(i) / float(num_dots)
			var pos := start.lerp(end, t)
			canvas.draw_circle(pos, 1.5, color_to_draw)
