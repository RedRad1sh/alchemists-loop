extends Node3D
class_name FurnitureItem
# Порт PlayerHouse/scripts/furniture_item.gd (см. план, Task 8, правило 3):
# одна кодовая дорога, yaw_basis → Basis.IDENTITY, ISO_ROTATION_DEG → локальная
# константа, без mirrored_xz/reflection_advanced/visible_faces_only/grade/
# effective_yaw_degrees/reflected-ветки; отражение — тот же меш под Node3D с
# scale = (1, -1, 1).

const ISO_ROTATION_DEG := Vector3(-35.264, 45.0, 0.0)
const BOX_SHADER := preload("res://assets/house/shaders/item_box.gdshader")
const REFLECTION_SHADER := preload("res://assets/house/shaders/item_reflection.gdshader")
const SHADOW_TEX_PATH := "res://assets/house/shadows/blob_soft.png"

const SPRITE_PRIORITY := 5
const REFLECTION_PRIORITY := -5
const SHADOW_PRIORITY := 1
const REFLECTION_OPACITY := 0.35
const SHADOW_OPACITY := 0.55
const GHOST_OPACITY := 0.55
const SHADOW_MARGIN := 0.22
const GHOST_OK_TINT := Color(0.45, 1.0, 0.5)
const GHOST_BAD_TINT := Color(1.0, 0.35, 0.3)
const SELECTED_TINT := Color(1.0, 0.92, 0.72)

var item_id := ""
var def := {}
var placement := {}
var _sprite: MeshInstance3D
var _reflection: Node3D
var _reflection_sprite: MeshInstance3D
var _shadow: MeshInstance3D
var _sprite_mat: ShaderMaterial
var _reflection_mat: ShaderMaterial
var _shadow_mat: StandardMaterial3D
var _box := Vector3.ONE
var _ghost := false
var _ghost_valid := true
var _selected := false


func setup(id: String, p: Dictionary) -> void:
	item_id = id
	def = HouseItems.get_item(id)
	placement = p.duplicate(true)
	_build()


func apply(p: Dictionary) -> void:
	placement = p.duplicate(true)
	_update_transform()


func set_ghost(on: bool, valid := true) -> void:
	_ghost = on
	_ghost_valid = valid
	_apply_visual_state()


func set_selected(on: bool) -> void:
	_selected = on
	_apply_visual_state()


func _build() -> void:
	_box = def.get("box", Vector3.ONE)
	var mesh := _build_projected_box_mesh(_geometry_size())
	_sprite = MeshInstance3D.new()
	_sprite.name = "Sprite"
	_sprite.mesh = mesh
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite_mat = ShaderMaterial.new()
	_sprite_mat.shader = BOX_SHADER
	_sprite_mat.render_priority = SPRITE_PRIORITY
	_sprite.material_override = _sprite_mat
	_set_projected_shader_parameters(_sprite_mat)
	add_child(_sprite)
	_reflection = Node3D.new()
	_reflection.name = "Reflection"
	_reflection.scale = Vector3(1.0, -1.0, 1.0)
	add_child(_reflection)
	_reflection_sprite = MeshInstance3D.new()
	_reflection_sprite.name = "ReflectionSprite"
	_reflection_sprite.mesh = mesh
	_reflection_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflection_mat = ShaderMaterial.new()
	_reflection_mat.shader = REFLECTION_SHADER
	_reflection_mat.render_priority = REFLECTION_PRIORITY
	_reflection_sprite.material_override = _reflection_mat
	_set_projected_shader_parameters(_reflection_mat)
	_reflection.add_child(_reflection_sprite)
	_shadow = MeshInstance3D.new()
	_shadow.name = "BlobShadow"
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.albedo_texture = load(SHADOW_TEX_PATH)
	_shadow_mat.render_priority = SHADOW_PRIORITY
	_shadow.material_override = _shadow_mat
	add_child(_shadow)
	_apply_visual_state()
	_update_transform()


# Единственный путь из двух вариантов reference-а: без reflected-ветки и mirror_basis.
static func _build_projected_box_mesh(box_size: Vector3) -> ArrayMesh:
	var iso_basis := Basis.from_euler(Vector3(
		deg_to_rad(ISO_ROTATION_DEG.x), deg_to_rad(ISO_ROTATION_DEG.y), 0.0))
	var h := box_size.y
	var hx := box_size.x * 0.5
	var hz := box_size.z * 0.5
	var corners := [
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz),
		Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
		Vector3(-hx, h, -hz), Vector3(hx, h, -hz),
		Vector3(hx, h, hz), Vector3(-hx, h, hz)]
	var screen_min := Vector2(1e30, 1e30)
	var screen_max := Vector2(-1e30, -1e30)
	for corner in corners:
		var screen_point := Vector2(corner.dot(iso_basis.x), corner.dot(iso_basis.y))
		screen_min.x = minf(screen_min.x, screen_point.x)
		screen_min.y = minf(screen_min.y, screen_point.y)
		screen_max.x = maxf(screen_max.x, screen_point.x)
		screen_max.y = maxf(screen_max.y, screen_point.y)
	var screen_width := maxf(screen_max.x - screen_min.x, 0.001)
	var screen_height := maxf(screen_max.y - screen_min.y, 0.001)
	# Три грани, которые видит изо-камера (верх и две передние стены).
	var faces := [[4, 5, 6, 7], [1, 2, 6, 5], [2, 3, 7, 6]]
	var triangle_order := [0, 1, 2, 0, 2, 3]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var projected_uvs := PackedVector2Array()
	for face in faces:
		var face_indices: Array = face
		for tri in range(0, triangle_order.size(), 3):
			var a: Vector3 = corners[face_indices[triangle_order[tri]]]
			var b: Vector3 = corners[face_indices[triangle_order[tri + 1]]]
			var c: Vector3 = corners[face_indices[triangle_order[tri + 2]]]
			var normal := (b - a).cross(c - a).normalized()
			for point in [a, b, c]:
				vertices.append(point)
				normals.append(normal)
				var screen_x: float = point.dot(iso_basis.x)
				var screen_y: float = point.dot(iso_basis.y)
				var tx := clampf((screen_x - screen_min.x) / screen_width, 0.0, 1.0)
				var ty := clampf((screen_max.y - screen_y) / screen_height, 0.0, 1.0)
				# UV2 — нормализованные экранные координаты силуэта; шейдер
				# отображает их в alpha-прямоугольник спрайта.
				projected_uvs.append(Vector2(tx, ty))
				uvs.append(Vector2(tx, ty))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = projected_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_projected_shader_parameters(mat: ShaderMaterial) -> void:
	var tex: Texture2D = load(String(def.get("sprite", "")))
	mat.set_shader_parameter("sprite_tex", tex)
	# Экранная нормализация уже запечена в UV2 (tx/ty в [0,1]), поэтому
	# проекционная рамка — единичный квадрат; alpha-прямоугольник — из каталога.
	mat.set_shader_parameter("projection_rect", Vector4(0.0, 0.0, 1.0, 1.0))
	var alpha: Rect2 = def.get("alpha", Rect2(0, 0, 512, 512))
	var tex_size := Vector2(512.0, 512.0)
	if tex != null:
		tex_size = tex.get_size()
	mat.set_shader_parameter("alpha_rect_uv", Vector4(
		alpha.position.x / maxf(tex_size.x, 1.0),
		alpha.position.y / maxf(tex_size.y, 1.0),
		alpha.end.x / maxf(tex_size.x, 1.0),
		alpha.end.y / maxf(tex_size.y, 1.0)))
	mat.set_shader_parameter("flip_x", bool(placement.get("flip", false)))


# Wall 0 (плоскость x = -ROOM_HALF) разворачивает box на 90°: вдоль стены
# лежит box.x, в глубину — box.z. Placement.clamp_record/footprint предполагают
# ровно этот разворот; в исходнике его делал yaw_basis, здесь — подмена осей.
func _geometry_size() -> Vector3:
	if int(placement.get("wall", -1)) == 0:
		return Vector3(_box.z, _box.y, _box.x)
	return _box


func _update_transform() -> void:
	var wall := int(placement.get("wall", -1))
	var y := 0.0
	if wall >= 0:
		y = float(placement.get("y", _box.y * 0.5)) - _box.y * 0.5
	position = Vector3(float(placement.get("x", 0.0)), y, float(placement.get("z", 0.0)))
	if _reflection != null:
		# Отражение зеркалит относительно world y = 0 (плоскость пола), а не
		# вокруг origin узла: для стенных предметов узел поднят над полом.
		_reflection.position = Vector3(0.0, -y, 0.0)
	_update_shadow()


func _update_shadow() -> void:
	if _shadow == null:
		return
	var wall := int(placement.get("wall", -1))
	var plane := PlaneMesh.new()
	if wall == 0:
		plane.size = Vector2(_box.y + SHADOW_MARGIN, _box.x + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3(0.0, 0.0, -90.0)
		_shadow.position = Vector3(0.01 - _box.z * 0.5, _box.y * 0.5, 0.0)
	elif wall == 1:
		plane.size = Vector2(_box.x + SHADOW_MARGIN, _box.y + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_shadow.position = Vector3(0.0, _box.y * 0.5, 0.01 - _box.z * 0.5)
	else:
		var fp := Placement.footprint(placement)
		plane.size = Vector2(fp.size.x + SHADOW_MARGIN, fp.size.y + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3.ZERO
		_shadow.position = Vector3(0.0, 0.01, 0.0)
	_shadow.mesh = plane


func _current_tint() -> Color:
	if _ghost:
		return GHOST_OK_TINT if _ghost_valid else GHOST_BAD_TINT
	if _selected:
		return SELECTED_TINT
	var base := String(def.get("tint", ""))
	return Color(base) if bool(def.get("reward", false)) and base != "" else Color.WHITE


func _apply_visual_state() -> void:
	var tint := _current_tint()
	var opacity := GHOST_OPACITY if _ghost else 1.0
	if _sprite_mat != null:
		_sprite_mat.set_shader_parameter("tint", tint)
		_sprite_mat.set_shader_parameter("opacity", opacity)
	if _reflection_mat != null:
		_reflection_mat.set_shader_parameter("tint", tint)
		_reflection_mat.set_shader_parameter("opacity", REFLECTION_OPACITY * opacity)
	if _shadow_mat != null:
		_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_OPACITY * opacity)
