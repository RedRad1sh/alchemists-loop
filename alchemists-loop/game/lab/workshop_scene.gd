extends Control
## Живая сцена Мастерской: станции линий висят над верстаком, нити от станций
## к латунной планке показывают состояние линии. Только отрисовка и выбор
## линии тапом; данные приходят из WorkshopView через set_stations().

signal station_pressed(index: int)

const Kit = preload("res://game/ui/menu_kit.gd")
const PLATE := "res://assets/ui/room/workshop_plate.png"
const BENCH := "res://assets/ui/room/prop_bench.png"
const RAIL := "res://assets/contracts/shelf_bar.png"
## Центр фона по высоте плиты: балка с крюками и фонарь (0.20..0.55).
const PLATE_FOCUS_V := 0.36
## Станции в долях сцены: I, II висят на цепях, III, IV — на кронштейнах.
const SPOTS := [Vector2(0.30, 0.32), Vector2(0.70, 0.32), Vector2(0.11, 0.70), Vector2(0.89, 0.70),
	Vector2(0.50, 0.26), Vector2(0.50, 0.50)]
const HANGING := [true, true, false, false, true, true]
## Гнездо планки для станции: такой порядок не даёт нитям пересекаться.
const SOCKETS := [1, 2, 0, 3, 1, 2]
const ROMAN := ["I", "II", "III", "IV", "V", "VI"]

var g: Game
var stations: Array = []
var selected := 0
var _orbs: Array = []
var _plate: Texture2D
var _bench: Texture2D
var _rail: Texture2D
var _ring: Texture2D
var _chain: Texture2D
var _lock: Texture2D
var _time := 0.0


func setup(game: Game) -> void:
	g = game
	name = "WorkshopScene"
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	custom_minimum_size = Vector2(0, 220)
	_plate = load(PLATE) as Texture2D
	_bench = load(BENCH) as Texture2D
	_rail = load(RAIL) as Texture2D
	_ring = Kit.texture("05b_rune_ring_hollow.png")
	_chain = Kit.texture("07_brass_chain_link.png")
	_lock = UIIcon.texture("lock")
	resized.connect(_on_resized)


static func roman(index: int) -> String:
	return ROMAN[index] if index < ROMAN.size() else str(index + 1)


## stations: [{status, target, frac, text}] по линиям, включая закрытые.
func set_stations(data: Array, selected_index: int) -> void:
	stations = data
	selected = selected_index
	while _orbs.size() < stations.size():
		_orbs.append({"node": null, "target": ""})
	for i in _orbs.size():
		var want := ""
		if i < stations.size():
			want = String(stations[i].get("target", ""))
		var slot: Dictionary = _orbs[i]
		if slot["target"] == want and (want.is_empty() or is_instance_valid(slot["node"])):
			continue
		if is_instance_valid(slot["node"]):
			(slot["node"] as Node).queue_free()
		slot["node"] = null
		slot["target"] = want
		if not want.is_empty() and is_instance_valid(g):
			var orb: Control = g._engine._mini_orb(want, 40)
			orb.name = "StationOrb_%d" % (i + 1)
			add_child(orb)
			slot["node"] = orb
	for i in mini(_orbs.size(), stations.size()):
		var node: Control = _orbs[i]["node"]
		if is_instance_valid(node):
			node.modulate = Color.WHITE if String(stations[i].get("status", "")) == "running" else Color(0.72, 0.68, 0.64)
	_place_orbs()
	queue_redraw()


func _on_resized() -> void:
	var want := roundf(clampf(size.x * 0.64, 210.0, 320.0))
	if absf(custom_minimum_size.y - want) > 0.5:
		custom_minimum_size.y = want
	_place_orbs()
	queue_redraw()


func _radius() -> float:
	return clampf(size.x * 0.066, 20.0, 34.0)


func _center(i: int) -> Vector2:
	var spot: Vector2 = SPOTS[mini(i, SPOTS.size() - 1)]
	return Vector2(spot.x * size.x, spot.y * size.y)


func _rail_rect() -> Rect2:
	var h := clampf(size.y * 0.045, 7.0, 12.0)
	return Rect2(size.x * 0.22, size.y * 0.89, size.x * 0.56, h)


func _socket(i: int) -> Vector2:
	var r := _rail_rect()
	var k: int = SOCKETS[mini(i, SOCKETS.size() - 1)]
	return Vector2(r.position.x + r.size.x * (0.14 + 0.24 * k), r.position.y + r.size.y * 0.5)


func _place_orbs() -> void:
	var r := _radius()
	for i in _orbs.size():
		var orb: Control = _orbs[i]["node"]
		if not is_instance_valid(orb):
			continue
		var d := roundf(r * 1.1)
		orb.custom_minimum_size = Vector2(d, d)
		orb.size = Vector2(d, d)
		orb.pivot_offset = Vector2(d, d) * 0.5
		orb.position = _center(i) - Vector2(d, d) * 0.5


## Цвет состояния линии — из палитры игры, без неоновых тонов.
static func status_color(status: String) -> Color:
	match status:
		"running":
			return UIStyle.MAGIC
		"waiting_ether":
			return UIStyle.BRASS_HI
		"waiting_ingredients", "waiting_recipe":
			return UIStyle.RUBY
		"waiting_inventory":
			return UIStyle.PLASTER_HI
		"paused_user", "idle", "empty":
			return UIStyle.TEXT_DIM
		_:
			return UIStyle.TEXT_MUTED


func _process(delta: float) -> void:
	if not is_visible_in_tree() or stations.is_empty():
		return
	_time += delta
	var animated := false
	for i in stations.size():
		var status := String(stations[i].get("status", ""))
		if status in ["running", "waiting_ingredients", "waiting_recipe"]:
			animated = true
		if i < _orbs.size() and is_instance_valid(_orbs[i]["node"]):
			var orb: Control = _orbs[i]["node"]
			orb.scale = Vector2.ONE * (1.0 + 0.03 * sin(_time * 2.6 + float(i))) if status == "running" else Vector2.ONE
			orb.modulate = Color.WHITE if status == "running" else Color(0.72, 0.68, 0.64)
	if animated:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_backdrop()
	var beam := Rect2(0.0, size.y * 0.05, size.x, clampf(size.y * 0.05, 9.0, 14.0))
	_draw_bench()
	var r := _radius()
	for i in stations.size():
		_draw_mount(i, r, beam.end.y)
	if _rail != null:
		draw_rect(Rect2(beam.position + Vector2(0, 3), beam.size), Color(UIStyle.INK, 0.6))
		draw_texture_rect(_rail, beam, false)
	for i in stations.size():
		_draw_thread(i, r)
	_draw_rail()
	for i in stations.size():
		_draw_station(i, r)
	# Сцена — окно в комнату: тонкая латунная кромка, без глянцевой рамки.
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), UIStyle.BRASS_DIM, false, 2.0)
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(UIStyle.INK, 0.6), false, 1.0)


func _draw_backdrop() -> void:
	if _plate == null:
		draw_rect(Rect2(Vector2.ZERO, size), UIStyle.WOOD_DEEP)
		return
	var tw := float(_plate.get_width())
	var th := float(_plate.get_height())
	var src_h := minf(th, tw * size.y / size.x)
	var src_y := clampf(th * PLATE_FOCUS_V - src_h * 0.5, 0.0, th - src_h)
	draw_texture_rect_region(_plate, Rect2(Vector2.ZERO, size), Rect2(0.0, src_y, tw, src_h),
		Color(0.6, 0.55, 0.5))
	# Низ уходит в тень, чтобы станции и нити читались поверх полок.
	var clear := Color(UIStyle.INK, 0.0)
	var dark := Color(UIStyle.INK, 0.7)
	var y0 := size.y * 0.5
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([clear, clear, dark, dark]))


func _draw_bench() -> void:
	if _bench == null:
		return
	var h := size.y * 0.46
	var w := h * float(_bench.get_width()) / float(_bench.get_height())
	var rect := Rect2(size.x * 0.5 - w * 0.5, size.y * 0.99 - h, w, h)
	draw_texture_rect(_bench, rect, false, Color(0.82, 0.78, 0.74))


func _draw_rail() -> void:
	var r := _rail_rect()
	# Стойки держат планку: она не висит в воздухе.
	for x in [r.position.x + 6.0, r.end.x - 10.0]:
		draw_rect(Rect2(x, r.end.y, 4.0, size.y - r.end.y), UIStyle.WOOD_LIGHT)
		draw_rect(Rect2(x + 3.0, r.end.y, 1.0, size.y - r.end.y), Color(UIStyle.INK, 0.6))
	draw_rect(Rect2(r.position + Vector2(0, 2), r.size), Color(UIStyle.INK, 0.6))
	if _rail != null:
		draw_texture_rect(_rail, r, false)
	else:
		draw_rect(r, UIStyle.BRASS_DIM)
	for i in stations.size():
		var p := _socket(i)
		draw_circle(p, 5.0, UIStyle.INK)
		draw_arc(p, 5.0, 0.0, TAU, 16, UIStyle.BRASS, 1.5, true)
		var st_status := String(stations[i].get("status", ""))
		draw_circle(p, 2.5, Color(UIStyle.TEXT_MUTED, 0.6) if st_status == "locked" else status_color(st_status))


func _draw_chain(x: float, top: float, bottom: float, w: float) -> void:
	if _chain == null:
		draw_line(Vector2(x, top), Vector2(x, bottom), UIStyle.BRASS_DIM, 3.0)
		return
	var tw := float(_chain.get_width())
	var th := float(_chain.get_height())
	var seg := w * th / tw
	var y := top
	while y < bottom - 0.5:
		var h := minf(seg, bottom - y)
		draw_texture_rect_region(_chain, Rect2(x - w * 0.5, y, w, h), Rect2(0.0, 0.0, tw, th * h / seg))
		y += h


func _draw_mount(i: int, r: float, beam_bottom: float) -> void:
	var c := _center(i)
	if HANGING[mini(i, HANGING.size() - 1)]:
		_draw_chain(c.x, beam_bottom - 3.0, c.y - r * 0.9, clampf(r * 0.3, 6.0, 10.0))
		return
	# Настенный кронштейн: плечо от стены, укосина и короткий крюк.
	var left := c.x < size.x * 0.5
	var wall_x := 0.0 if left else size.x
	var arm_y := c.y - r - 9.0
	draw_line(Vector2(wall_x, arm_y + 2.0), Vector2(c.x, arm_y + 2.0), Color(UIStyle.INK, 0.6), 5.0)
	draw_line(Vector2(wall_x, arm_y), Vector2(c.x, arm_y), UIStyle.BRASS_DIM, 4.0)
	draw_line(Vector2(wall_x, arm_y - 1.0), Vector2(c.x, arm_y - 1.0), Color(UIStyle.BRASS, 0.55), 1.0)
	var brace := wall_x + (r * 0.8 if left else -r * 0.8)
	draw_line(Vector2(wall_x, arm_y + r * 0.8), Vector2(brace, arm_y), UIStyle.BRASS_DIM, 3.0)
	draw_line(Vector2(c.x, arm_y), Vector2(c.x, c.y - r * 0.9), UIStyle.BRASS_DIM, 3.0)


func _thread_points(i: int, r: float) -> Array:
	var c := _center(i)
	var left := c.x < size.x * 0.5
	var start := c + Vector2(r * 1.02 if left else -r * 1.02, r * 0.25)
	var end := _socket(i)
	var c1 := start + Vector2(r * 0.9 if left else -r * 0.9, size.y * 0.12)
	var c2 := end + Vector2(0.0, -size.y * 0.18)
	return [start, c1, c2, end]


func _draw_thread(i: int, r: float) -> void:
	var status := String(stations[i].get("status", ""))
	if status == "locked":
		return
	var col := status_color(status)
	var pts := _thread_points(i, r)
	var alpha := 0.85
	if status in ["waiting_ingredients", "waiting_recipe"]:
		alpha = 0.5 + 0.4 * (0.5 + 0.5 * sin(_time * 3.5))
	elif status in ["empty", "idle", "paused_user"]:
		alpha = 0.55
	var steps := 30
	for k in steps + 1:
		var p: Vector2 = (pts[0] as Vector2).bezier_interpolate(pts[1], pts[2], pts[3], float(k) / float(steps))
		draw_circle(p, 3.0, Color(UIStyle.INK, 0.8))
		draw_circle(p, 2.0, Color(col, alpha))
	if status == "running":
		var t := fmod(_time * 0.4 + float(i) * 0.31, 1.0)
		var p: Vector2 = (pts[0] as Vector2).bezier_interpolate(pts[1], pts[2], pts[3], t)
		draw_circle(p, 3.4, Color(UIStyle.INK, 0.6))
		draw_circle(p, 2.4, UIStyle.PAPER_HI)


func _draw_station(i: int, r: float) -> void:
	var st: Dictionary = stations[i]
	var c := _center(i)
	var status := String(st.get("status", ""))
	var col := status_color(status)
	var locked := status == "locked"
	draw_circle(c, r * 0.95, Color(UIStyle.INK, 0.85))
	if _ring != null:
		var d := r * 2.3
		draw_texture_rect(_ring, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false,
			Color(0.5, 0.46, 0.42) if locked else Color(0.95, 0.92, 0.88))
	var frac := clampf(float(st.get("frac", 0.0)), 0.0, 1.0)
	if not locked and not String(st.get("target", "")).is_empty():
		draw_arc(c, r * 0.8, 0.0, TAU, 40, Color(UIStyle.INK, 0.8), 3.0, true)
		if frac > 0.0:
			draw_arc(c, r * 0.8, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, col, 3.0, true)
	if locked and _lock != null:
		var s := r * 0.75
		draw_texture_rect(_lock, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, UIStyle.TEXT_MUTED)
	if i == selected and not locked:
		draw_arc(c, r * 1.22, 0.0, TAU, 48, Color(UIStyle.BRASS_HI, 0.9), 2.0, true)
	_draw_plaque(c + Vector2(0.0, r * 1.2 + 4.0), String(st.get("text", roman(i))), col, i == selected and not locked)


func _draw_plaque(top_center: Vector2, text: String, accent: Color, active: bool) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var fs := 13 if size.x < 400.0 else 14
	# На узкой сцене подпись закрытой линии — только номер: имя ранга
	# наезжало на соседние станции.
	if size.x < 380.0 and accent == status_color("locked"):
		text = text.get_slice(" · ", 0)
	var shown := atr(text)
	var tw := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 20.0
	var h := float(fs) + 9.0
	var x := clampf(top_center.x - w * 0.5, 4.0, size.x - w - 4.0)
	var rect := Rect2(x, top_center.y, w, h)
	draw_rect(rect, Color(UIStyle.INK, 0.9))
	draw_rect(rect, UIStyle.BRASS_HI if active else UIStyle.BRASS_DIM, false, 1.0)
	draw_circle(Vector2(rect.position.x + 7.5, rect.get_center().y), 2.5, accent)
	draw_string(font, Vector2(rect.position.x + 13.0, rect.position.y + h - 6.0), shown,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.PAPER_HI if active else UIStyle.CREAM)


func station_at(p: Vector2) -> int:
	var r := _radius()
	for i in stations.size():
		if p.distance_to(_center(i)) <= r + 16.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = mb.position
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		pos = touch.position
	else:
		return
	var hit := station_at(pos)
	if hit >= 0:
		station_pressed.emit(hit)
		accept_event()
