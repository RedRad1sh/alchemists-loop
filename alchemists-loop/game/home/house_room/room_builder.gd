extends RefCounted
class_name RoomBuilder

const ROOM_PATH := "res://assets/house/room/room_with_ceiling.glb"
const ROOM_OFFSET := Vector3(-23.24929, 0.0, -15.735065)
const DEFAULT_FLOOR_TEX := "res://assets/house/room/floor_planks.png"


static func build(world: Node3D) -> Dictionary:
	var packed: PackedScene = load(ROOM_PATH)
	if packed == null:
		return {}
	var room := packed.instantiate() as Node3D
	room.name = "Room"
	room.position = ROOM_OFFSET
	world.add_child(room)
	_unshade(room)
	_hide_ceiling(room)
	_prepare_floor(room)
	return {"room": room, "aabb": room_aabb(room)}


# Изо-камера смотрит сверху вниз: потолок закрыл бы комнату. В исходнике его
# прятал CeilingSetup (горячая клавиша), здесь он спрятан всегда.
static func _hide_ceiling(room: Node3D) -> void:
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).to_lower().contains("ceiling"):
			mi.visible = false


# Исходная комната экспортируется с KHR_materials_unlit и все её шейдеры идут
# render_mode unshaded: свет в кадре не участвует, цвет = albedo текстуры.
static func _unshade(room: Node3D) -> void:
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(i, dup)


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
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.render_priority = 0
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
				var planks := load(DEFAULT_FLOOR_TEX) as Texture2D
				if planks != null:
					dup.albedo_texture = planks
				mi.set_surface_override_material(i, dup)


## Пустой путь текстуры стен = родная текстура GLB. У пола родная текстура с
## пятью вставками плитки, поэтому по умолчанию он всегда досками.
static func tint_room(room: Node3D, wall_tint: Color, floor_tint: Color,
		floor_tex := DEFAULT_FLOOR_TEX, wall_left_tex := "", wall_right_tex := "") -> void:
	if room == null:
		return
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lower := String(mi.name).to_lower()
		var is_floor := lower.contains("floor")
		if not is_floor and not lower.contains("wall"):
			continue
		var col := floor_tint if is_floor else wall_tint
		for i in mi.mesh.get_surface_count():
			# Каждый раз от оригинала, не от прошлого tint-оверрайда. WHITE
			# восстанавливает albedo GLB; материал остаётся строго per-instance.
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var dup := mat.duplicate() as BaseMaterial3D
			dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if col != Color.WHITE:
				dup.albedo_color = col
			var tex_path := floor_tex if is_floor else _wall_tex_for(mat, wall_left_tex, wall_right_tex)
			if tex_path != "":
				var tex := load(tex_path) as Texture2D
				if tex != null:
					dup.albedo_texture = tex
			if is_floor:
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.render_priority = 0
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, dup)


# Имя меша не говорит, какая это развёртка (obj_wall_right_south несёт left_wall),
# поэтому сторона берётся из исходного материала GLB.
static func _wall_tex_for(mat: BaseMaterial3D, left: String, right: String) -> String:
	var key := mat.resource_name.to_lower()
	if mat.albedo_texture != null:
		key += " " + mat.albedo_texture.resource_path.to_lower()
	if key.contains("left"):
		return left
	if key.contains("right"):
		return right
	return ""


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
