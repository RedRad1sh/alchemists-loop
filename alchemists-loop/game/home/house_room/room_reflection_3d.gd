class_name RoomReflection3D
extends Node3D
## Builds a live, upside-down 3D copy of the room under the floor.
##
## The source Room is duplicated at runtime. Its MeshInstance3D whose name
## contains "floor" is hidden, and the whole copy is mirrored around the floor
## pivot. Nothing is baked to a sprite yet: this node intentionally leaves the
## copy as ordinary 3D geometry so its alignment can be inspected first.
##
## Godot is Y-up, so the floor mirror is scale (1, -1, 1). This is the same
## operation as a Z-axis vertical flip in a Z-up package such as 3ds Max.

@export var source_room: NodePath = NodePath("../Room")
@export var enabled := true
## Off: the room model owns its own ceiling. The mirrored copy is a duplicate of
## the source Room, so any ceiling mesh the model carries reflects here by itself
## and a generated box would only cover it. Turn this back on to get the old
## solid-colour ceiling that earlier builds painted at the measured room top.
@export var ceiling_enabled := false
@export var ceiling_color := Color(0.30, 0.12, 0.055, 1.0)
@export var ceiling_thickness := 0.035
## A mesh belongs to the ceiling when its name contains this, the same rule the
## floor match above uses for the floor.
const CEILING_NAME_MATCH := "ceiling"
## The model's ceiling exists to be *reflected*: it is the surface the floor
## mirror has to show, and the only reason the reflection space was black. A roof
## over the room would hide the furniture from the isometric camera though, so the
## source mesh is switched off once the mirrored copy has been taken. Turn this off
## to let the model roof the room in both places.
@export var hide_source_ceiling := true
@export var add_missing_walls := true
@export var missing_wall_color := Color(0.0, 0.0, 0.0, 1.0)
## Extra thickness pulled inward from the missing room edges. It is
## intentionally larger than a structural wall because these are masks.
@export var missing_wall_thickness := 0.25
@export var missing_wall_extra_span := 0.8
@export var missing_wall_extra_height := 0.8
## Ниже -5 (отражения мебели): маска без depth test, иначе она закрашивает
## зеркальные боксы предметов у ближних стен.
@export var missing_wall_render_priority := -7
@export var render_priority := -10

## World-space footprint of the source room's floor, published after each build
## so the mirror planes can clip themselves to the room silhouette.
var measured_floor_bounds := AABB()

var _reflection_root: Node3D
var _room_copy: Node3D
var _ceiling: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	call_deferred("build_room_reflection_3d")


## Public rebuild entry point. Replace the Room model, then call this method
## if the scene is already running. The next normal run rebuilds automatically.
func build_room_reflection_3d() -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	await get_tree().process_frame
	var source := get_node_or_null(source_room) as Node3D
	if source == null:
		push_warning("Room reflection needs a source Room Node3D")
		return

	_remove_previous_copy()
	var bounds: Dictionary = _measure_room(source)
	var floor_bounds: AABB = bounds["floor"]
	var room_bounds: AABB = bounds["all"]
	if floor_bounds.size.x <= 0.001 or floor_bounds.size.z <= 0.001:
		push_warning("Room reflection could not measure a usable floor")
		measured_floor_bounds = AABB()
		return
	measured_floor_bounds = floor_bounds

	var floor_pivot := floor_bounds.get_center()
	floor_pivot.y = 0.0
	var room_top := room_bounds.position.y + room_bounds.size.y

	_reflection_root = Node3D.new()
	_reflection_root.name = "MirroredRoom3D"
	_reflection_root.global_transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(1.0, -1.0, 1.0)), floor_pivot)
	add_child(_reflection_root)

	# Keep the duplicate's original model transform, but express it relative
	# to the floor pivot. The parent's negative Y scale then mirrors every
	# vertex around that pivot while leaving X/Z positions unchanged.
	_room_copy = source.duplicate() as Node3D
	_room_copy.name = "RoomCopyMirroredUnderFloor"
	_reflection_root.add_child(_room_copy)
	var pivot_inverse := Transform3D(Basis.IDENTITY, -floor_pivot)
	_room_copy.transform = pivot_inverse * source.global_transform
	_prepare_room_copy(_room_copy)
	# After the duplicate, so the copy still carries the ceiling it was taken from.
	if hide_source_ceiling:
		_hide_source_ceiling(source)

	if ceiling_enabled:
		_add_generated_ceiling(floor_bounds, room_top, floor_pivot)
	if add_missing_walls:
		_add_missing_walls(floor_bounds, room_top, floor_pivot)
	print("Live 3D room reflection built; floor pivot = ", floor_pivot)


## Compatibility name for scripts that used the previous prototype. It now
## rebuilds live 3D geometry and deliberately does not create a sprite.
func bake_room_reflection() -> void:
	build_room_reflection_3d()


func _remove_previous_copy() -> void:
	measured_floor_bounds = AABB()
	if is_instance_valid(_reflection_root):
		_reflection_root.queue_free()
	_reflection_root = null
	_room_copy = null
	_ceiling = null


func _prepare_room_copy(room_copy: Node3D) -> void:
	for node in room_copy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lower := String(mi.name).to_lower()
		if "floor" in lower:
			# The real transparent floor remains the only floor surface; the
			# copy must not paint a second, opaque one under it.
			mi.visible = false
			continue
		var original_mesh: Mesh = mi.mesh
		if original_mesh == null:
			continue
		if CEILING_NAME_MATCH in lower:
			# A rebuild takes its duplicate from a source whose ceiling is already
			# hidden, and `duplicate()` copies `visible` - without this the second
			# build would lose the ceiling from the mirror.
			mi.visible = true
		# Deep-copy the imported mesh/materials so changing culling and
		# priority here cannot modify the visible source Room.
		var copied_mesh := original_mesh.duplicate(true) as Mesh
		if copied_mesh == null:
			continue
		for surface in copied_mesh.get_surface_count():
			var original_material: Material = copied_mesh.surface_get_material(surface)
			var base_material := original_material as BaseMaterial3D
			if base_material == null:
				continue
			var copied_material := base_material.duplicate() as BaseMaterial3D
			if copied_material == null:
				continue
			# The camera views the underside of the mirrored room. Both
			# winding directions must be rendered.
			copied_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			copied_material.render_priority = render_priority
			copied_mesh.surface_set_material(surface, copied_material)
		mi.mesh = copied_mesh
		# Оверрайды (unshaded/tint от RoomBuilder) копируются вместе с узлом и
		# перекрыли бы материал меша приоритетом 0 - зеркало легло бы поверх
		# отражений мебели (-5). Переносим на них те же cull/priority.
		for surface in copied_mesh.get_surface_count():
			var override := mi.get_surface_override_material(surface) as BaseMaterial3D
			if override == null:
				continue
			var copied_override := override.duplicate() as BaseMaterial3D
			copied_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			copied_override.render_priority = render_priority
			mi.set_surface_override_material(surface, copied_override)


## Re-copies the source's current override materials (tint, wall texture) onto
## the mirrored copy; the build only snapshots them once.
func sync_materials() -> void:
	if not is_instance_valid(_room_copy):
		return
	var source := get_node_or_null(source_room) as Node3D
	if source == null:
		return
	for node in _room_copy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if "floor" in String(mi.name).to_lower():
			continue
		var src := source.get_node_or_null(_room_copy.get_path_to(mi)) as MeshInstance3D
		if src == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var override := src.get_surface_override_material(surface) as BaseMaterial3D
			if override == null:
				continue
			var copied := override.duplicate() as BaseMaterial3D
			copied.cull_mode = BaseMaterial3D.CULL_DISABLED
			copied.render_priority = render_priority
			mi.set_surface_override_material(surface, copied)


## Switches the room's own ceiling off for the camera. The mirrored copy is built
## from the source before this runs, so the reflection keeps it.
func _hide_source_ceiling(source: Node3D) -> void:
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if CEILING_NAME_MATCH in String(mi.name).to_lower():
			mi.visible = false


func _add_generated_ceiling(floor_bounds: AABB, room_top: float, floor_pivot: Vector3) -> void:
	_ceiling = MeshInstance3D.new()
	_ceiling.name = "GeneratedBrownCeiling"
	_ceiling.layers = 1
	var ceiling_mesh := BoxMesh.new()
	ceiling_mesh.size = Vector3(
		floor_bounds.size.x + 0.04,
		maxf(0.01, ceiling_thickness),
		floor_bounds.size.z + 0.04)
	_ceiling.mesh = ceiling_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = ceiling_color
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = render_priority
	_ceiling.material_override = material
	# This is local to the floor-pivot parent; its negative Y scale places it
	# at the matching depth below the real floor.
	_ceiling.position = Vector3(0.0, room_top - floor_pivot.y, 0.0)
	_reflection_root.add_child(_ceiling)


func _add_missing_walls(floor_bounds: AABB, room_top: float, floor_pivot: Vector3) -> void:
	var wall_height := maxf(0.01, room_top - floor_pivot.y)
	var mask_height := wall_height + missing_wall_extra_height
	var wall_x := floor_bounds.position.x + floor_bounds.size.x - floor_pivot.x
	var wall_z := floor_bounds.position.z + floor_bounds.size.z - floor_pivot.z
	# The imported room has walls on -X and -Z. These two black closure
	# walls occupy the missing +X and +Z sides before the parent mirror is
	# applied. Their thickness extends OUTWARD from the room edge, not inward
	# into the playable floor. They are deliberately fatter/taller than
	# structural walls so they mask the reflected open area instead of leaving
	# a thin leak at the edge.
	_add_missing_wall(
		"MissingWallPlusX",
		Vector3(wall_x + missing_wall_thickness * 0.5, mask_height * 0.5, 0.0),
		Vector3(missing_wall_thickness, mask_height,
			floor_bounds.size.z + missing_wall_extra_span))
	_add_missing_wall(
		"MissingWallPlusZ",
		Vector3(0.0, mask_height * 0.5, wall_z + missing_wall_thickness * 0.5),
		Vector3(floor_bounds.size.x + missing_wall_extra_span, mask_height,
			missing_wall_thickness))


func _add_missing_wall(node_name: String, position: Vector3, size: Vector3) -> void:
	var wall := MeshInstance3D.new()
	wall.name = node_name
	wall.layers = 1
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = size
	wall.mesh = wall_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = missing_wall_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	# Draw after the reflected room copy but before furniture reflections and
	# the transparent floor, making this an actual black mask.
	material.render_priority = missing_wall_render_priority
	wall.material_override = material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position = position
	_reflection_root.add_child(wall)


func _measure_room(room: Node3D) -> Dictionary:
	var all_bounds := AABB()
	var floor_bounds := AABB()
	var have_any := false
	var have_floor := false
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var bounds := _world_aabb(mi)
		if not have_any:
			all_bounds = bounds
			have_any = true
		else:
			all_bounds = all_bounds.merge(bounds)
		if "floor" in String(mi.name).to_lower():
			if not have_floor:
				floor_bounds = bounds
				have_floor = true
			else:
				floor_bounds = floor_bounds.merge(bounds)
	if not have_floor:
		floor_bounds = all_bounds
	return {"all": all_bounds, "floor": floor_bounds}


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var low := local.position
	var high := local.position + local.size
	var min_point := Vector3(1e30, 1e30, 1e30)
	var max_point := Vector3(-1e30, -1e30, -1e30)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var point := Vector3(
					low.x if ix == 0 else high.x,
					low.y if iy == 0 else high.y,
					low.z if iz == 0 else high.z)
				point = mi.global_transform * point
				min_point.x = minf(min_point.x, point.x)
				min_point.y = minf(min_point.y, point.y)
				min_point.z = minf(min_point.z, point.z)
				max_point.x = maxf(max_point.x, point.x)
				max_point.y = maxf(max_point.y, point.y)
				max_point.z = maxf(max_point.z, point.z)
	return AABB(min_point, max_point - min_point)
