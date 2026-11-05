extends Control
class_name RoomView

signal placement_requested(p: Dictionary)
signal hint(text: String)
signal placement_moved(index: int, p: Dictionary)
signal placement_removed(index: int)
signal selection_changed(index: int)
signal ghost_moved(p: Dictionary)
signal placement_reaction(valid: bool)
signal pointer_input(event: InputEvent)
signal placement_returned

const CAMERA_PITCH := -35.264
const CAMERA_YAW := 45.0
const ZOOM_MAX_FACTOR := 2.2
const SHADOWS_ENABLED := true
# Ограничиваем разрешение единственного полноэкранного 3D-слоя.
const MAX_RENDER_SCALE := 2.0
## Доля ширины ромба пола, которая обязана остаться в кадре при приближении под
## открытым лотком: за резать можно только боковые углы ромба, остальное
## добирается pan/zoom.
const MIN_TRAY_FIT := 0.85
# В ландшафте cover-доводка не срабатывает (полоса низкая), и комната остаётся
# вписанной вдвое меньшей пиксельной плотностью, чем в портрете: при открытом
# лотке приближаем на этот множитель, запас ромба пола это допускает.
const LAND_TRAY_ZOOM := 1.15
## Запас вокруг ромба площади расстановки: 3% вместо прежних 10% — комната
## обязана быть достаточно крупной, чтобы ставить мебель без лупы.
const FIT_MARGIN := 1.03
## Порт `WALL_RESNAP_MARGIN` из PlayerHouse: настенный предмет уезжает на
## противоположную стену, только когда курсор ушёл за угол по-настоящему.
const WALL_RESNAP_MARGIN := 0.25
## Подложка под комнатой: кадр вписан по ромбу пола, поэтому всё вокруг него
## было чистым цветом фона — та самая «чёрная пустота».
const BACKDROP_SIZE := 14.0
const BACKDROP_TINT := Color(0.145, 0.112, 0.084)
# У blob_soft.png чёрный RGB (в оригинале это декаль-тень), поэтому обычный
# albedo-мультипликатор дал бы снова чёрное: тон берётся из uniform, а из
# текстуры используется только альфа.
const BACKDROP_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.145, 0.112, 0.084, 1.0);
uniform sampler2D soft : filter_linear;
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = texture(soft, UV).a * tint.a;
}
"""

var built := false
var read_only := false:
	set(value):
		read_only = value
		if value and _touch != null:
			_touch.cancel()
var placements: Array = []
var _touch: TouchDrag
var _ghost_node: FurnitureItem
var _selected_idx := -1
# Граница закрытого лотка: возврат в эту полосу отменяет перенос.
var tray_return_y := INF
var _viewport: SubViewport
var _room_tex: TextureRect
# Отношение пикселей окна к пикселям лэйаута (design 540x960 -> окно). Все
# входные координаты приходят в единицах лэйаута, а камера мыслит пикселями
# вьюпорта, поэтому конвертация нужна на границах raycast/unproject.
var _px_scale := 1.0
var _world: Node3D
var _camera: Camera3D
var _room: Node3D
var _room_aabb := AABB()
var _items_root: Node3D
var _items: Array = []
var _blur: ReflectionBlur
var _backdrop: MeshInstance3D
var _fit_size := 6.0
var _zoom := 1.0
var _target := Vector3.ZERO
var _tray_lift_px := 0.0
var _tray_top_px := 0.0
# Фактическое смещение камеры в пикселях экрана: запрошенный лотком подъём,
# урезанный так, чтобы верх комнаты оставался на экране.
var _lift_px := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	# Свой World3D: иначе комната попапа и комната экрана живут в одном мире root,
	# и пол/матовое стекло одной комнаты перекрывают отражения мебели другой.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	# Разрешение 3D задаём сами: SubViewportContainer с stretch=true принудительно
	# держит вьюпорт равным размеру контрола в единицах лэйаута (540x960), и на
	# большом окне комната растягивается вверх — те самые «жёсткие пиксели».
	# TextureRect растягивает уже настоящий пиксельный кадр окна 1:1.
	_room_tex = TextureRect.new()
	_room_tex.name = "RoomTexture"
	_room_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_room_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_room_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_room_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room_tex.texture = _viewport.get_texture()
	add_child(_room_tex)
	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# Значения из PlayerHouse/scenes/main.tscn: комната unshaded, поэтому свет на
	# неё не влияет, а ambient обязан быть нейтрально-белым, а не оранжевым.
	# Фон при этом поднят с почти чёрного: в оригинале кадр целиком занят комнатой
	# с потолком и четырьмя стенами, у нас же над двумя стенами виден фон.
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1a1411")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 1.0, 1.0)
	e.ambient_light_energy = 1.0
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
	_room_aabb = scene["aabb"]
	# Пол в исходнике полупрозрачен (альфа текстуры нигде не доходит до 1, а пять
	# пятен вообще с нулевой альфой): под ним обязано лежать зеркало комнаты.
	var reflection := RoomReflection3D.new()
	reflection.name = "RoomReflection3D"
	_world.add_child(reflection)
	_add_backdrop()
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
	# Матовое стекло вместо резкого зеркала: именно оно режет зеркальный мир по
	# силуэту пола, поэтому за ближними рёбрами комнаты не остаётся серой полосы.
	var blur := ReflectionBlur.new()
	blur.name = "ReflectionBlur"
	_world.add_child(blur)
	_blur = blur
	_sync_viewport_size()
	_fit_size = _compute_fit()
	_zoom = 1.0
	_apply_camera()
	_touch = TouchDrag.new(self)
	resized.connect(_on_resized)
	visibility_changed.connect(_sync_rendering)
	_sync_rendering()
	_rebuild_items()


func _sync_rendering() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree() and _touch != null:
		_touch.cancel()


func set_built(value: bool) -> void:
	built = value
	if not built and _touch != null:
		_touch.cancel()


## Тёмный «ковёр» вокруг комнаты (пункт «чёрная пустота»): лежит ниже матового
## стекла отражений (приоритет -6 < -3) и на слое комнаты, поэтому зеркальная
## камера его не видит и двойного изображения не добавляет.
func _add_backdrop() -> void:
	var tex := load(FurnitureItem.SHADOW_TEX_PATH) as Texture2D
	if tex == null:
		return
	var shader := Shader.new()
	shader.code = BACKDROP_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("soft", tex)
	mat.set_shader_parameter("tint", BACKDROP_TINT)
	mat.render_priority = -6
	var plane := PlaneMesh.new()
	plane.size = Vector2(BACKDROP_SIZE, BACKDROP_SIZE)
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.mesh = plane
	_backdrop.material_override = mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.position = Vector3(0.0, -0.05, 0.0)
	_world.add_child(_backdrop)


## Набор отражающих узлов изменился: пересканировать матовое стекло сразу, иначе
## до следующего таймерного прохода новое отражение рисуется и в основном проходе.
func _refresh_reflections() -> void:
	if _blur != null and is_instance_valid(_blur):
		_blur.rescan_now()


func set_layout(list: Array) -> void:
	if placements == list:
		return
	if _touch != null:
		_touch.cancel()
	placements = list.duplicate(true)
	_sync_items()


## Разностная перестройка: полная переулка всех узлов на каждое изменение
## заставляла исчезать спрайт, отражение и тень на кадр — «мигают текстуры» при
## добавлении и удалении мебели. Заново собираем только при смены порядка id.
func _sync_items() -> void:
	if _items_root == null:
		return
	var shared := mini(_items.size(), placements.size())
	for i in shared:
		if String((_items[i] as FurnitureItem).item_id) != String((placements[i] as Dictionary)["id"]):
			_rebuild_items()
			_refresh_reflections()
			return
	for i in shared:
		(_items[i] as FurnitureItem).apply(placements[i])
	while _items.size() > placements.size():
		_drop_item_node(_items.pop_back() as Node)
	for i in range(shared, placements.size()):
		_add_item_node(placements[i])
	if _selected_idx >= _items.size():
		highlight(-1)
	_refresh_reflections()


func _add_item_node(p: Dictionary) -> void:
	var node := FurnitureItem.new()
	node.add_to_group("furniture")
	node.setup(String(p["id"]), p)
	_items_root.add_child(node)
	_items.append(node)


func _drop_item_node(node: Node) -> void:
	if node == null:
		return
	_items_root.remove_child(node)
	node.queue_free()


func set_room_tint(wall: Color, floor: Color, floor_mat := "planks", wall_mat := "timber") -> void:
	var f := DecorData.floor_mat(floor_mat)
	var w := DecorData.wall_mat(wall_mat)
	RoomBuilder.tint_room(_room, wall, floor, String(f["tex"]), String(w["left"]), String(w["right"]))
	var mirror := _world.get_node_or_null("RoomReflection3D") as RoomReflection3D if _world != null else null
	if mirror != null:
		mirror.sync_materials()


func spirit_anchor() -> Vector3:
	return Vector3(-1.2, 1.15, 0.8)


func spirit_screen_pos() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(spirit_anchor()) / _px_scale


func _gui_input(event: InputEvent) -> void:
	if _touch != null:
		_touch.gui_input(event)


func _input(event: InputEvent) -> void:
	if _touch == null or not is_visible_in_tree():
		return
	# Клавиша удаления из донора (Del/Backspace). Поле ввода имени в диалоге
	# Светика живёт поверх открытого дома, поэтому символы из него не должны
	# сносить выбранную мебель.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		if built and not read_only and _selected_idx >= 0 \
				and not get_viewport().gui_get_focus_owner() is LineEdit:
			remove_selected()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer_input.emit(event)
		if not _touch.capturing():
			return
		var local := make_input_local(event)
		_touch.gui_input(local)
		get_viewport().set_input_as_handled()


func begin_placement(id: String, at: Vector2, pointer := TouchDrag.NO_POINTER) -> void:
	if _touch != null:
		_touch.begin_from_tray(id, at, pointer)


func cancel_placement() -> void:
	if _touch != null:
		_touch.cancel()


func cancel_ghost() -> void:
	if _touch != null:
		_touch.cancel_ghost()


func raycast_floor(at: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	var dev := at * _px_scale
	var origin := _camera.project_ray_origin(dev)
	var dir := _camera.project_ray_normal(dev)
	if is_zero_approx(dir.y):
		return {}
	var t := -origin.y / dir.y
	var hit := origin + dir * t
	if t <= 0.0 or absf(hit.x) > Placement.ROOM_HALF or absf(hit.z) > Placement.ROOM_HALF:
		return {}
	return {"x": hit.x, "y": 0.0, "z": hit.z}


func raycast_wall(at: Vector2, current := -1) -> Dictionary:
	if _camera == null:
		return {}
	var dev := at * _px_scale
	var origin := _camera.project_ray_origin(dev)
	var dir := _camera.project_ray_normal(dev)
	if is_zero_approx(dir.y):
		return {}
	var t_floor := -origin.y / dir.y
	if t_floor <= 0.0:
		return {}
	# Порт `_wall_axis_for_cursor`: «лицо» выбирается по тому, к какой стене ближе
	# точка луча на ПОЛУ, а не по ближайшему пересечению луча с плоскостью стены.
	# Второй вариант на изо-камере переключал стену на одном пикселе от угла.
	var floor_pt := origin + dir * t_floor
	var wall := _wall_axis_for_cursor(Vector2(floor_pt.x, floor_pt.z), current)
	var component := dir.x if wall == 0 else dir.z
	if is_zero_approx(component):
		return {}
	var t := (-Placement.ROOM_HALF - (origin.x if wall == 0 else origin.z)) / component
	if t <= 0.0:
		return {}
	var hit := origin + dir * t
	var along := hit.z if wall == 0 else hit.x
	if absf(along) > Placement.ROOM_HALF or hit.y < 0.0 or hit.y > Placement.WALL_H:
		return {}
	return {"x": hit.x, "y": hit.y, "z": hit.z, "wall": wall}


## та же функция донора (`furniture_drag.gd:989-998`) в осях пола X/Z: ближайшая к
## курсору стена выигрывает только после запаса в `WALL_RESNAP_MARGIN`, поэтому
## предмет не перецепляется у самого угла. `current < 0` — чистое правило
## ближайшей стены (вызов без граба).
func _wall_axis_for_cursor(point: Vector2, current: int) -> int:
	var room_min := -Placement.ROOM_HALF
	var nearer := 0 if point.x - room_min <= point.y - room_min else 1
	if current < 0 or nearer == current:
		return nearer
	if (point[nearer] - room_min) + WALL_RESNAP_MARGIN < point[current] - room_min:
		return nearer
	return current


func pick_item(at: Vector2) -> int:
	if _camera == null:
		return -1
	var best := -1
	var depth := INF
	for i in _items.size():
		var node := _items[i] as FurnitureItem
		var aabb := node._sprite.mesh.get_aabb()
		# unproject отдаёт пиксели вьюпорта, а `at` приходит в единицах лэйаута.
		var rect := Rect2(_camera.unproject_position(node.to_global(aabb.position)) / _px_scale, Vector2.ZERO)
		for corner in 8:
			rect = rect.expand(_camera.unproject_position(node.to_global(aabb.get_endpoint(corner))) / _px_scale)
		if not rect.grow(8.0).has_point(at):
			continue
		var p: Dictionary = placements[i]
		var box: Vector3 = HouseItems.get_item(String(p["id"]))["box"]
		var center := Vector3(p["x"], float(p["y"]) if int(p["wall"]) >= 0 else box.y * 0.5, p["z"])
		var distance := -(_camera.global_transform.affine_inverse() * center).z
		if distance < depth:
			best = i
			depth = distance
	return best


func highlight(index: int) -> void:
	if _selected_idx >= 0 and _selected_idx < _items.size():
		(_items[_selected_idx] as FurnitureItem).set_selected(false)
	_selected_idx = index if index >= 0 and index < _items.size() else -1
	if _selected_idx >= 0:
		(_items[_selected_idx] as FurnitureItem).set_selected(true)
	if _touch != null:
		_touch.selected = _selected_idx
	selection_changed.emit(_selected_idx)


func selected_index() -> int:
	return _selected_idx


func show_ghost(p: Dictionary, valid: bool) -> void:
	if not built or p.is_empty():
		return
	if _ghost_node == null:
		_ghost_node = FurnitureItem.new()
		# Группа «furniture» — то, по чему ReflectionBlur находит отражения: без
		# неё зеркало призрака остаётся на слое основных спрайтов и рисуется
		# вторым, «под полом».
		_ghost_node.add_to_group("furniture")
		_ghost_node.setup(String(p["id"]), p)
		_items_root.add_child(_ghost_node)
		_refresh_reflections()
	else:
		_ghost_node.apply(p)
	_ghost_node.set_ghost(true, valid)
	ghost_moved.emit(p)


## Перенос двигает сам предмет, как в доноре, а не отдельный призрак: иначе под
## пальцем живёт копия, а настоящий предмет остаётся на месте — то самое
## «мерцание при передвижении».
func preview_move(index: int, p: Dictionary) -> void:
	if index < 0 or index >= _items.size() or index >= placements.size():
		return
	(_items[index] as FurnitureItem).apply(p)
	ghost_moved.emit(p)


## Отменённый перенос: запись в `placements` не менялась, а узел — менялся.
func restore_preview(index: int) -> void:
	if index < 0 or index >= _items.size() or index >= placements.size():
		return
	(_items[index] as FurnitureItem).apply(placements[index])


func clear_ghost() -> void:
	if is_instance_valid(_ghost_node):
		if _ghost_node.get_parent() != null:
			_ghost_node.get_parent().remove_child(_ghost_node)
		_ghost_node.queue_free()
	_ghost_node = null


func commit_placement(p: Dictionary) -> bool:
	if read_only or not built:
		return false
	var before := placements.size()
	placement_requested.emit(p.duplicate(true))
	# Home подтверждает приём синхронным set_layout; emit сам по себе не успех.
	var accepted := placements.size() > before
	placement_reaction.emit(accepted)
	return accepted


func commit_move(index: int, p: Dictionary) -> void:
	if read_only or not built or index < 0 or index >= placements.size():
		return
	var clean := Placement.snap_record(p)
	if not Placement.move_allowed(placements[index], clean, placements, index):
		return
	placements[index] = clean.duplicate(true)
	(_items[index] as FurnitureItem).apply(clean)
	placement_moved.emit(index, clean.duplicate(true))


func flip_selected() -> void:
	if read_only or not built or _selected_idx < 0:
		return
	var p := (placements[_selected_idx] as Dictionary).duplicate(true)
	if not bool(HouseItems.get_item(String(p["id"])).get("flip_ok", false)):
		return
	p["flip"] = not bool(p["flip"])
	commit_move(_selected_idx, p)


func remove_selected() -> void:
	if read_only or not built or _selected_idx < 0:
		return
	var index := _selected_idx
	cancel_placement()
	placements.remove_at(index)
	# Удаляем именно этот узел: переулка всех остальных на кадре пустого места
	# и есть «мигают текстуры».
	_drop_item_node(_items.pop_at(index) as Node)
	_refresh_reflections()
	placement_removed.emit(index)


func _rebuild_items() -> void:
	if _items_root == null:
		return
	for child in _items_root.get_children():
		_items_root.remove_child(child)
		child.queue_free()
	_items.clear()
	for raw in placements:
		var p: Dictionary = raw
		_add_item_node(p)
	_refresh_reflections()


func _compute_fit() -> float:
	if _room_aabb.size == Vector3.ZERO:
		return 6.5
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	var floor_box := _floor_box(basis)
	var aspect := float(maxi(1, _viewport.size.x)) / float(maxi(1, _viewport.size.y))
	return maxf(floor_box.size.x, floor_box.size.y * aspect) * FIT_MARGIN


## Ромб площади расстановки в координатах камеры: Rect2(min_x, min_y, w, h).
## Кадр считается по полу, а не по полному AABB комнаты: вид сверху вниз
## раздувает AABB верхними углами стен на 2,4 м, и «вписать всё» означает
## отъехать настолько, что комната становится меньше подушечки пальца.
## Пол — то, на что ставят мебель, он обязан влезать; стены могут выходить
## за край кадра.
func _floor_box(basis: Basis) -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for x in [-Placement.ROOM_HALF, Placement.ROOM_HALF]:
		for z in [-Placement.ROOM_HALF, Placement.ROOM_HALF]:
			var p := Vector3(x, 0.0, z)
			var cx := p.dot(basis.x)
			var cy := p.dot(basis.y)
			min_x = minf(min_x, cx)
			max_x = maxf(max_x, cx)
			min_y = minf(min_y, cy)
			max_y = maxf(max_y, cy)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


## Полный габарит комнаты (со стенами) в координатах камеры. Нужен только для
## того, чтобы оценить, какой высоты кадр заполняет полосу: пол для кадрирования
## берётся из `_floor_box()`, потому что стены за верхний край уходить вправе.
func _room_box(basis: Basis) -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for corner in 8:
		var p := _room_aabb.get_endpoint(corner)
		var cx := p.dot(basis.x)
		var cy := p.dot(basis.y)
		min_x = minf(min_x, cx)
		max_x = maxf(max_x, cx)
		min_y = minf(min_y, cy)
		max_y = maxf(max_y, cy)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


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
	var fit := _fit_size
	var floor_box := Rect2(0.0, 0.0, 0.0, 0.0)
	if _tray_top_px > 0.0:
		floor_box = _floor_box(basis)
		var available_height := size.y - _tray_lift_px * 2.0 - _tray_top_px
		# Если свободной полосы почти не осталось (split-screen, очень низкое
		# окно), пересчёт масштаба раздувает кадр до тысяч мировых единиц и
		# комната схлопывается в точку. В таком окне вписать комнату невозможно
		# в принципе, поэтому остаётся только обычный подъём.
		if available_height > size.y * 0.3:
			# Кадр = полоса между шапкой и лотком, а не весь экран: `cover` —
			# насколько приблизить, чтобы СТАНЫ заполнили полосу по высоте.
			# Минимум с обычным вписыванием означает «приближаем, но никогда не
			# отъезжаем дальше вписанной комнаты»: в ландшафте полоса низкая и
			# cover больше вписанного кадра, там остаётся вписывание; в portrait
			# полоса высокая, и комната уезжает ближе, а чёрные поля уходят.
			var cover := _room_box(basis).size.y * size.x / available_height * FIT_MARGIN
			var max_fit := _fit_size / (LAND_TRAY_ZOOM if size.x > size.y else 1.0)
			fit = clampf(minf(fit, cover), floor_box.size.x * MIN_TRAY_FIT, max_fit)
	_camera.size = fit / _zoom
	_lift_px = maxf(0.0, _tray_lift_px - _tray_top_px * 0.5)
	if _tray_top_px > 0.0:
		# Подъём центрирует комнату в свободной полосе, но при приближении комната
		# бывает выше полосы: полный подъём срезал бы верхнюю стену. Дальний угол
		# ПОЛА оставляем на экране — стены над ним вправе уйти за шапку.
		var world_per_px := _camera.size / maxf(1.0, size.x)
		var top_px := size.y * 0.5 - (floor_box.end.y - _target.dot(basis.y)) / world_per_px
		_lift_px = minf(_lift_px, maxf(0.0, top_px))
	# Комната обязана уезжать ВВЕРХ экрана, когда открыт лоток, поэтому камера
	# смещается вниз по собственной оси Y.
	var origin := _target - basis.y * _lift_offset() + basis.z * 30.0
	_camera.transform = Transform3D(basis, origin)


func effective_screen_scale() -> float:
	var w := get_window()
	if w == null:
		return 1.0
	var screen := w.get_final_transform() * get_global_transform_with_canvas()
	var factors := screen.get_scale().abs()
	return maxf(0.01, minf(factors.x, factors.y))


func _device_scale() -> float:
	return minf(effective_screen_scale(), MAX_RENDER_SCALE)


func _process(_delta: float) -> void:
	if is_visible_in_tree() and not is_equal_approx(_px_scale, _device_scale()):
		_on_resized()


func _sync_viewport_size() -> void:
	_px_scale = _device_scale()
	_viewport.size = Vector2i(
		maxi(1, int(round(size.x * _px_scale))),
		maxi(1, int(round(size.y * _px_scale))))


func _on_resized() -> void:
	if _viewport == null:
		return
	var before := _viewport.size
	_sync_viewport_size()
	if before == _viewport.size:
		return
	_fit_size = _compute_fit()
	_apply_camera()


func zoom_at(factor: float, local_pos: Vector2) -> void:
	if _camera == null:
		return
	var new_zoom := clampf(_zoom * factor, 1.0, ZOOM_MAX_FACTOR)
	factor = new_zoom / _zoom
	if is_equal_approx(factor, 1.0):
		return
	var vp := size
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
	var vp := size
	var k := _camera.size / maxf(1.0, vp.x)
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	_target += right * (-delta.x * k) + up * (delta.y * k)
	_clamp_target()
	_apply_camera()


func set_tray_lift(px: float, top_px := 0.0) -> void:
	if _camera == null:
		return
	_tray_lift_px = px
	_tray_top_px = top_px
	_apply_camera()


## Мировое смещение камеры вдоль её собственной оси Y под открытый лоток.
func _lift_offset() -> float:
	if _camera == null:
		return 0.0
	var vp := size
	return _lift_px * (_camera.size / maxf(1.0, vp.x))


func reset_camera() -> void:
	_zoom = 1.0
	_target = Vector3.ZERO
	# Подъём под лоток — часть состояния камеры: без сброса следующий вызов
	# set_tray_lift(420) оставил бы камеру там же, а тест возврата — зелёным.
	_tray_lift_px = 0.0
	_tray_top_px = 0.0
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
