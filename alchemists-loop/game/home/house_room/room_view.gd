extends SubViewportContainer
class_name RoomView

signal placement_requested(p: Dictionary)
signal hint(text: String)

const CAMERA_PITCH := -35.264
const CAMERA_YAW := 45.0
const ZOOM_MAX_FACTOR := 2.2
const SHADOWS_ENABLED := true
const SUBVIEWPORT_SCALE := 1.0

var built := false
var read_only := false
var placements: Array = []
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _room: Node3D
var _mirror: Node3D
var _room_aabb := AABB()
var _items_root: Node3D
var _items: Array = []
var _fit_size := 6.0
var _zoom := 1.0
var _target := Vector3.ZERO
var _tray_lift_px := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_2X
	# У SubViewport нет scale (правка брифа): в Godot 4 множитель 3D-разрешения —
	# scaling_3d_scale (1.0 = без изменения).
	_viewport.scaling_3d_scale = SUBVIEWPORT_SCALE
	add_child(_viewport)
	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0b0a09")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#ffe0b0")
	e.ambient_light_energy = 0.55
	env.environment = e
	_world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 0.35
	light.shadow_enabled = false
	_world.add_child(light)
	var scene := RoomBuilder.build(_world)
	if scene.is_empty():
		return
	_room = scene["room"]
	_mirror = scene["mirror"]
	_room_aabb = scene["aabb"]
	_items_root = Node3D.new()
	_items_root.name = "FurnitureRoot"
	_world.add_child(_items_root)
	_camera = Camera3D.new()
	_camera.name = "IsoCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.05
	_camera.far = 120.0
	_world.add_child(_camera)
	_camera.current = true
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_fit_size = _compute_fit()
	_zoom = 1.0
	_apply_camera()
	resized.connect(_on_resized)


func set_built(value: bool) -> void:
	built = value
	visible = true


func set_layout(list: Array) -> void:
	placements = list.duplicate(true)
	_rebuild_items()


func set_room_tint(wall: Color, floor: Color) -> void:
	RoomBuilder.tint_room(_room, wall, floor)
	if _mirror != null and _mirror.get_child_count() > 0:
		RoomBuilder.tint_room(_mirror.get_child(0), wall, floor)


func spirit_anchor() -> Vector3:
	return Vector3(-1.2, 1.15, 0.8)


func spirit_screen_pos() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(spirit_anchor())


func place_at_center(id: String) -> bool:
	if read_only or not built:
		return false
	var p := Placement.clamp_record({"id": id, "x": 0.0, "z": 0.0, "y": 0.0, "flip": false,
		"wall": int(HouseItems.get_item(id).get("wall_view", -1))})
	if not Placement.valid(p, placements):
		p = Placement.push_out(p, placements, -1)
	if not Placement.valid(p, placements):
		hint.emit("Здесь не помещается.")
		return false
	placement_requested.emit(p)
	return true


func _rebuild_items() -> void:
	for child in _items_root.get_children():
		child.queue_free()
	_items.clear()
	for raw in placements:
		var p: Dictionary = raw
		var node := FurnitureItem.new()
		node.setup(String(p["id"]), p)
		_items_root.add_child(node)
		_items.append(node)


func _compute_fit() -> float:
	if _room_aabb.size == Vector3.ZERO:
		return 6.5
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for i in 8:
		var v := _room_aabb.get_endpoint(i)
		var x := v.dot(basis.x)
		var y := v.dot(basis.y)
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
	var w := max_x - min_x
	var h := max_y - min_y
	var aspect := float(maxi(1, _viewport.size.x)) / float(maxi(1, _viewport.size.y))
	return maxf(w, h * aspect) * 1.10


func _apply_camera() -> void:
	if _camera == null:
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	_camera.transform = Transform3D(basis, _target + basis.z * 30.0)
	_camera.size = _fit_size * _zoom


func _on_resized() -> void:
	if _viewport == null:
		return
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_fit_size = _compute_fit()
	_apply_camera()
