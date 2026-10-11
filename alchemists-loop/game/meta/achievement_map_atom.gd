extends "res://addons/medusa/nodes/atom.gd"
class_name AchievementMapAtom

const Glyphs = preload("res://game/lab/element_glyphs.gd")

const MAP_LOCKED := 0
const MAP_AVAILABLE := 1
const MAP_UNLOCKED := 2

var achievement_id: String = ""
var glyph_key: String = "spark"
var caption: String = ""
var map_status := MAP_LOCKED
var glyph_tint: Color = Color("#d8d7ce")
var map_selected: bool = false:
	set(value):
		if map_selected == value:
			return
		map_selected = value
		queue_redraw()

var _caption_label: Label
var _mouse_pressed := false
var _screen_touch_pressed := false
var _screen_touch_index := -1
var _press_position := Vector2.ZERO
var _last_screen_touch_msec := -1000


func setup(node_id: String, glyph: String, node_caption: String, node_status: int) -> void:
	achievement_id = node_id
	glyph_key = glyph
	caption = node_caption
	set_map_status(node_status)
	radius = 22.0
	drag_input = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(72.0, 76.0)
	size = custom_minimum_size


func set_map_status(node_status: int) -> void:
	# Do not write Atom.status here: its UNLOCKED setter emits Medusa's
	# unlocked signal. The map is a view, not an unlock/purchase authority.
	map_status = node_status
	match node_status:
		MAP_UNLOCKED:
			color = Color("#705425")
			glyph_tint = Color("#fff0bd")
			if _caption_label != null:
				_caption_label.add_theme_color_override("font_color", Color("#f6d995"))
		MAP_AVAILABLE:
			color = Color("#145356")
			glyph_tint = Color("#c8fff0")
			if _caption_label != null:
				_caption_label.add_theme_color_override("font_color", Color("#8cf2d7"))
		_:
			color = Color("#252e3a")
			glyph_tint = Color("#9aa8b2")
			if _caption_label != null:
				_caption_label.add_theme_color_override("font_color", Color("#7e8d98"))
	queue_redraw()


func set_caption(value: String) -> void:
	caption = value
	if _caption_label != null:
		_caption_label.text = value


func _ready() -> void:
	super._ready()
	# The base Atom captures the press to begin dragging. This map has a custom
	# tap recognizer and lets ScreenDrag bubble to its ScrollContainer instead.
	drag_input = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(72.0, 76.0)
	size = custom_minimum_size
	pivot_offset = size / 2.0
	set_process(false)

	_caption_label = Label.new()
	_caption_label.name = "Milestone"
	_caption_label.text = caption
	_caption_label.position = Vector2(0.0, 56.0)
	_caption_label.size = Vector2(size.x, 18.0)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_size_override("font_size", 10)
	_caption_label.add_theme_color_override("font_color", Color("#b9c5ca"))
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_label)
	set_map_status(map_status)


func _draw() -> void:
	super._draw()
	var center := size / 2.0
	if map_status == MAP_AVAILABLE:
		draw_arc(center, radius + 3.5, 0.0, TAU, 48, Color("#e8c778"), 2.0, true)
	elif map_status == MAP_UNLOCKED:
		draw_arc(center, radius + 2.5, 0.0, TAU, 48, Color("#f3ce75"), 2.0, true)
	else:
		draw_arc(center, radius + 1.0, 0.0, TAU, 48, Color(0.48, 0.57, 0.64, 0.42), 1.0, true)
	if is_hovered:
		draw_arc(center, radius + 6.0, 0.0, TAU, 48, Color("#b2eee2"), 1.5, true)
	if map_selected:
		draw_arc(center, radius + 7.5, 0.0, TAU, 48, Color("#fff0b1"), 2.0, true)
	Glyphs.draw(self, glyph_key, center, radius * 0.58, glyph_tint)
	if map_status == MAP_UNLOCKED:
		var badge := center + Vector2(radius * 0.72, radius * 0.68)
		draw_circle(badge, 6.5, Color("#f3ce75"))
		draw_line(
			badge + Vector2(-3.0, 0.0), badge + Vector2(-0.7, 2.5), Color("#2f321f"), 1.8, true
		)
		draw_line(
			badge + Vector2(-0.7, 2.5), badge + Vector2(3.5, -2.5), Color("#2f321f"), 1.8, true
		)


func _has_point(point: Vector2) -> bool:
	# The full 72×76 cell is the touch target, including the milestone caption.
	return Rect2(Vector2.ZERO, size).has_point(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_screen_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_screen_touch_pressed = true
			_screen_touch_index = event.index
			_press_position = event.position
		else:
			if _screen_touch_pressed and event.index == _screen_touch_index:
				_finish_tap(event.position)
			_screen_touch_pressed = false
			_screen_touch_index = -1
	elif event is InputEventScreenDrag:
		if (
			_screen_touch_pressed
			and event.index == _screen_touch_index
			and event.position.distance_to(_press_position) > drag_threshold
		):
			_screen_touch_pressed = false
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		# Godot can also synthesize mouse events for the same touch. The screen
		# touch path above is authoritative so one tap never selects twice.
		if Time.get_ticks_msec() - _last_screen_touch_msec < 150:
			return
		if event.pressed:
			_mouse_pressed = true
			_press_position = event.position
		else:
			if _mouse_pressed:
				_finish_tap(event.position)
			_mouse_pressed = false
	elif event is InputEventMouseMotion:
		if _mouse_pressed and event.position.distance_to(_press_position) > drag_threshold:
			_mouse_pressed = false


func _finish_tap(release_position: Vector2) -> void:
	if release_position.distance_to(_press_position) <= drag_threshold:
		clicked.emit(self)


func _exit_tree() -> void:
	_mouse_pressed = false
	_screen_touch_pressed = false
	_screen_touch_index = -1
