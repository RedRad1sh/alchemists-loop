extends RefCounted
class_name RoomBuilder

const ROOM_PATH := "res://assets/house/room/room_with_ceiling.glb"
const ROOM_OFFSET := Vector3(-23.24929, 0.0, -15.735065)
const ROOM_MIRROR_PRIORITY := -10


static func build(world: Node3D) -> Dictionary:
	var packed: PackedScene = load(ROOM_PATH)
	if packed == null:
		return {}
	var room := packed.instantiate() as Node3D
	room.name = "Room"
	room.position = ROOM_OFFSET
	world.add_child(room)
	_prepare_floor(room)
	var mirror := _build_mirror(room, world)
	return {"room": room, "mirror": mirror, "aabb": room_aabb(room)}


static func _prepare_floor(room: Node3D) -> void:
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not String(mi.name).to_lower().contains("floor"):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				# Правка 2: не пишем в кэшированный импорт GLB — дубликат материала
				# ложится per-instance оверрайдом, второй экземпляр комнаты чист.
				var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.render_priority = 0
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(i, dup)


static func _build_mirror(room: Node3D, world: Node3D) -> Node3D:
	var mirror := Node3D.new()
	mirror.name = "RoomMirror"
	mirror.scale = Vector3(1.0, -1.0, 1.0)
	world.add_child(mirror)
	var copy := room.duplicate() as Node3D
	copy.name = "RoomCopyMirroredUnderFloor"
	mirror.add_child(copy)
	# Копия сохраняет ROOM_OFFSET исходной комнаты: зеркало масштабирует её
	# вокруг y=0, где после смещения лежит пол. Обнуление position сдвинуло бы
	# копию в сырые координаты GLB и вывело из кадра.
	for node in copy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lower := String(mi.name).to_lower()
		if lower.contains("floor"):
			mi.visible = false
			continue
		if lower.contains("ceiling"):
			mi.visible = true
		var mesh := mi.mesh.duplicate(true) as Mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var dup := mat.duplicate() as BaseMaterial3D
			dup.cull_mode = BaseMaterial3D.CULL_DISABLED
			dup.render_priority = ROOM_MIRROR_PRIORITY
			mesh.surface_set_material(i, dup)
		mi.mesh = mesh
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).to_lower().contains("ceiling"):
			mi.visible = false
	return mirror


static func tint_room(room: Node3D, wall_tint: Color, floor_tint: Color) -> void:
	if room == null:
		return
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lower := String(mi.name).to_lower()
		var col := floor_tint if lower.contains("floor") else (wall_tint if lower.contains("wall") else Color.WHITE)
		if col == Color.WHITE:
			continue
		for i in mi.mesh.get_surface_count():
			# Правка 2: за основу берём активный материал (оверрайд _prepare_floor
			# несёт прозрачность пола), меняем только albedo, пишем оверрайдом —
			# surface_set_material трогал бы общий кэшированный ArrayMesh.
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var dup := mat.duplicate() as BaseMaterial3D
			dup.albedo_color = col
			mi.set_surface_override_material(i, dup)


static func room_aabb(room: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
