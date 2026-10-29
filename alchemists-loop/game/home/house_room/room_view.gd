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
	# Порядок важен: `_lift_offset()` переводит пикселя лотка в мировые единицы
	# через текущий `_camera.size`, поэтому размер кадра обязан быть применён ДО
	# вычисления подъёма.
	# `_zoom > 1` = «крупнее»: в орто-проекции увеличение — это МЕНЬШИЙ size,
	# иначе `_zoom ∈ [1, 2.2]` только отдаляет камеру и приблизить комнату
	# невозможно (пинч Task 13 передаёт `d / _pinch_dist` > 1 на «растягивании»).
	_camera.size = _fit_size / _zoom
	# Комната обязана уезжать ВВЕРХ экрана, когда открыт лоток, поэтому камера
	# смещается вниз по собственной оси Y.
	var origin := _target - basis.y * _lift_offset() + basis.z * 30.0
	_camera.transform = Transform3D(basis, origin)


func _on_resized() -> void:
	if _viewport == null:
		return
	_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_fit_size = _compute_fit()
	_apply_camera()


func zoom_at(factor: float, local_pos: Vector2) -> void:
	if _camera == null:
		return
	var new_zoom := clampf(_zoom * factor, 1.0, ZOOM_MAX_FACTOR)
	factor = new_zoom / _zoom
	if is_equal_approx(factor, 1.0):
		return
	var vp := Vector2(_viewport.size)
	# KEEP_WIDTH: size задаёт ширину кадра в мировых единицах, поэтому
	# мировых единиц на пиксель = size / ширина (пиксели квадратные).
	var k := _camera.size / maxf(1.0, vp.x)
	var u := (local_pos.x - vp.x * 0.5) * k
	var v := -(local_pos.y - vp.y * 0.5) * k
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	# `factor > 1` означает «увеличить», а увеличение в орто-камере — это МЕНЬШИЙ
	# size, поэтому мировых единиц на пиксель становится factor раз меньше, и точка
	# под пальцем смещается от центра экрана на d / factor. Отсюда новый центр =
	# старый центр + d * (1 - 1/factor). Подъём лотка пересчитывается так же
	# (L_new = L_old / factor), поэтому вычитаемый член получает тот же множитель.
	# Точка под пальцем смещена от точки наблюдения `_target` на d минус подъём
	# лотка: подъём уводит камеру вниз по её собственной оси Y, поэтому центр
	# экрана лежит не в `_target`, а ниже него.
	_target += (right * u + up * v - up * _lift_offset()) * (1.0 - 1.0 / factor)
	_zoom = new_zoom
	_clamp_target()
	_apply_camera()


func pan_screen(delta: Vector2) -> void:
	if _camera == null:
		return
	var vp := Vector2(_viewport.size)
	var k := _camera.size / maxf(1.0, vp.x)
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	_target += right * (-delta.x * k) + up * (delta.y * k)
	_clamp_target()
	_apply_camera()


func set_tray_lift(px: float) -> void:
	if _camera == null:
		return
	# Объявление состояния, а не инкремент: подъём задаётся в пикселях и
	# пересчитывается из `_tray_lift_px` в `_apply_camera`. Повторный вызов
	# идемпотентен, закрытие лотка возвращает камеру ровно туда же, и кламп
	# точки наблюдения не может «съесть» часть подъёма безвозвратно.
	_tray_lift_px = px
	_apply_camera()


## Мировое смещение камеры вдоль её собственной оси Y под открытый лоток.
func _lift_offset() -> float:
	if _camera == null:
		return 0.0
	var vp := Vector2(_viewport.size)
	return _tray_lift_px * (_camera.size / maxf(1.0, vp.x))


func reset_camera() -> void:
	_zoom = 1.0
	_target = Vector3.ZERO
	# Подъём под лоток — часть состояния камеры: без сброса следующий вызов
	# set_tray_lift(420) оставил бы камеру там же, а тест возврата — зелёным.
	_tray_lift_px = 0.0
	_apply_camera()


func _clamp_target() -> void:
	_target.x = clampf(_target.x, -Placement.ROOM_HALF, Placement.ROOM_HALF)
	_target.z = clampf(_target.z, -Placement.ROOM_HALF, Placement.ROOM_HALF)
	# Пан идёт вдоль basis.y камеры (мировая Y ≈ cos(pitch) ≈ 0.816), поэтому без
	# ограничения по высоте непрерывный драг неограниченно уводит точку наблюдения
	# из кадра: x и z зажаты, а комната уезжает по вертикали и не возвращается.
	# Границы — AABB комнаты, выросший на ROOM_HALF со всех сторон. На подъём
	# лотка кламп не влияет: он применяется к `_target`, а подъём добавывается
	# после клампа в `_apply_camera`.
	_target.y = clampf(_target.y, -Placement.ROOM_HALF, Placement.WALL_H + Placement.ROOM_HALF)
